#!/usr/bin/env python3
"""Generate a Sparkle appcast without rewriting previously published entries."""

import argparse
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from urllib.parse import quote, unquote, urlsplit
import xml.etree.ElementTree as ET
import zipfile


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
VERSION = f"{{{SPARKLE_NS}}}version"
SHORT_VERSION = f"{{{SPARKLE_NS}}}shortVersionString"
ED_SIGNATURE = f"{{{SPARKLE_NS}}}edSignature"
SIGNING_BLOCK = re.compile(
    rb"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\n\Z"
)
ARCHIVE_NAME = re.compile(r"zStats-(\d+\.\d+\.\d+)-([1-9]\d*)\.zip\Z")


class PreparationError(ValueError):
    pass


TRANSACTION_FILE = "transaction.json"
TRANSACTION_SCHEMA = 1


def _signed_xml(path):
    data = Path(path).read_bytes()
    match = SIGNING_BLOCK.search(data)
    if match is None:
        raise PreparationError(f"Appcast is not signed: {path}")
    try:
        signature = base64.b64decode(match.group(1), validate=True)
    except ValueError as error:
        raise PreparationError(f"Appcast has an invalid signing block: {path}") from error
    if len(signature) != 64 or int(match.group(2)) != match.start():
        raise PreparationError(f"Appcast has an invalid signing block: {path}")
    try:
        root = ET.fromstring(data[:match.start()])
    except ET.ParseError as error:
        raise PreparationError(f"Appcast is malformed: {path}: {error}") from error
    return data, root


def _normalized_element(element):
    return (
        element.tag,
        tuple(sorted(element.attrib.items())),
        (element.text or "").strip(),
        tuple(_normalized_element(child) for child in element),
    )


def _items(root, source):
    if root.tag != "rss":
        raise PreparationError(f"Appcast root is not rss: {source}")
    channels = root.findall("channel")
    if len(channels) != 1:
        raise PreparationError(f"Appcast must contain one channel: {source}")

    result = {}
    for item in channels[0].findall("item"):
        version_node = item.find(VERSION)
        short_version_node = item.find(SHORT_VERSION)
        enclosures = item.findall("enclosure")
        if (
            version_node is None
            or not (version_node.text or "").strip()
            or short_version_node is None
            or not (short_version_node.text or "").strip()
            or len(enclosures) != 1
        ):
            raise PreparationError(f"Appcast item is missing version metadata: {source}")
        enclosure = enclosures[0]
        required = ("url", "length", "type", ED_SIGNATURE)
        if any(not enclosure.get(attribute) for attribute in required):
            raise PreparationError(f"Appcast item is missing enclosure metadata: {source}")
        try:
            if int(enclosure.get("length")) < 0:
                raise ValueError
        except ValueError as error:
            raise PreparationError(f"Appcast item has an invalid enclosure length: {source}") from error
        url = urlsplit(enclosure.get("url"))
        if url.scheme != "https" or not url.netloc or url.username or url.password or url.fragment:
            raise PreparationError(f"Appcast item has an invalid enclosure URL: {source}")
        try:
            enclosure_signature = base64.b64decode(enclosure.get(ED_SIGNATURE), validate=True)
        except ValueError as error:
            raise PreparationError(f"Appcast item has an invalid enclosure signature: {source}") from error
        if len(enclosure_signature) != 64:
            raise PreparationError(f"Appcast item has an invalid enclosure signature: {source}")
        version = version_node.text.strip()
        if version in result:
            raise PreparationError(f"Appcast contains duplicate version {version}: {source}")
        result[version] = {
            "url": enclosure.get("url"),
            "signature": enclosure.get(ED_SIGNATURE),
            "length": int(enclosure.get("length")),
            "short_version": short_version_node.text.strip(),
            "item": _normalized_element(item),
        }
    if not result:
        raise PreparationError(f"Appcast contains no update items: {source}")
    return result


def _default_run(command, cwd):
    subprocess.run(command, cwd=cwd, check=True)


def _sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@contextmanager
def _exclusive_lock(output_directory):
    lock_path = output_directory / ".prepare-update.lock"
    descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise PreparationError("Another update preparation is already running") from error
        yield
    finally:
        os.close(descriptor)


def _write_transaction(workspace, metadata):
    temporary = workspace / f".{TRANSACTION_FILE}.tmp"
    with temporary.open("w", encoding="utf-8") as stream:
        stream.write(json.dumps(metadata, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, workspace / TRANSACTION_FILE)
    directory_descriptor = os.open(workspace, os.O_RDONLY)
    try:
        os.fsync(directory_descriptor)
    finally:
        os.close(directory_descriptor)


def _remove_workspace(workspace, output_directory, prefix):
    if workspace.parent != output_directory or not workspace.name.startswith(prefix):
        raise PreparationError(f"Refusing to remove unexpected transaction workspace: {workspace}")
    shutil.rmtree(workspace)


def _bundle_metadata(info, source):
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise PreparationError(f"Invalid CFBundleShortVersionString in {source}")
    if not isinstance(build, str) or not re.fullmatch(r"[1-9]\d*", build):
        raise PreparationError(f"Invalid CFBundleVersion in {source}")
    return version, build


def _app_bundle_metadata(app):
    info_path = app / "Contents" / "Info.plist"
    try:
        with info_path.open("rb") as stream:
            return _bundle_metadata(plistlib.load(stream), info_path)
    except (OSError, plistlib.InvalidFileException) as error:
        raise PreparationError(f"Unable to read application metadata: {info_path}") from error


def _archive_bundle_metadata(archive):
    try:
        with zipfile.ZipFile(archive) as zipped:
            info_paths = [
                name for name in zipped.namelist()
                if (
                    len(Path(name).parts) == 3
                    and Path(name).parts[0].endswith(".app")
                    and Path(name).parts[1:] == ("Contents", "Info.plist")
                )
            ]
            if len(info_paths) != 1:
                raise PreparationError(f"Archive must contain one application Info.plist: {archive}")
            return _bundle_metadata(plistlib.loads(zipped.read(info_paths[0])), archive)
    except (OSError, KeyError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        raise PreparationError(f"Unable to read archive metadata: {archive}") from error


def _validate_build_history(candidate_version, candidate_build, archive, appcast, previous_items):
    archive_match = ARCHIVE_NAME.fullmatch(archive.name)
    if archive_match.groups() != (candidate_version, candidate_build):
        raise PreparationError("Candidate archive name does not match the application version and build")

    retained_names = set()
    known_builds = []
    for feed_build, item in previous_items.items():
        if not re.fullmatch(r"[1-9]\d*", feed_build):
            raise PreparationError(f"Prior feed has an invalid build number: {feed_build!r}")
        archive_name = Path(unquote(urlsplit(item["url"]).path)).name
        retained_archive = archive.parent / archive_name
        name_match = ARCHIVE_NAME.fullmatch(archive_name)
        if name_match is None:
            raise PreparationError(f"Prior archive has an unexpected name: {archive_name}")
        retained_version, retained_build = _archive_bundle_metadata(retained_archive)
        if (
            name_match.groups() != (retained_version, retained_build)
            or feed_build != retained_build
            or item["short_version"] != retained_version
        ):
            raise PreparationError(f"Prior release metadata is inconsistent: {archive_name}")
        retained_names.add(archive_name)
        known_builds.append(int(retained_build))

    local_names = {path.name for path in archive.parent.glob("zStats-*.zip") if path.is_file()}
    if local_names != retained_names:
        source = appcast if appcast.exists() else archive.parent
        raise PreparationError(f"Retained release history is incomplete or inconsistent: {source}")
    if known_builds and int(candidate_build) <= max(known_builds):
        raise PreparationError(
            f"CFBundleVersion {candidate_build} must be greater than prior build {max(known_builds)}"
        )


def _verify_archives(items, directory, verifier, account, runner):
    for version, item in items.items():
        archive_name = Path(unquote(urlsplit(item["url"]).path)).name
        local_archive = directory / archive_name
        if not archive_name or not local_archive.is_file():
            raise PreparationError(f"Archive for prior version {version} is missing: {local_archive}")
        if local_archive.stat().st_size != item["length"]:
            raise PreparationError(f"Archive length for prior version {version} has changed")
        runner(
            [
                str(verifier), "--verify", "--account", account,
                str(local_archive), item["signature"],
            ],
            directory,
        )


def _validate_generated(staged_appcast, archive, download_url_prefix, previous_items):
    archive_match = ARCHIVE_NAME.fullmatch(archive.name)
    expected_short_version, expected_build = archive_match.groups()
    _, generated_root = _signed_xml(staged_appcast)
    generated_items = _items(generated_root, staged_appcast)
    for version, prior in previous_items.items():
        current = generated_items.get(version)
        if current is None:
            raise PreparationError(f"Sparkle generator removed prior version {version}")
        if current["item"] != prior["item"]:
            raise PreparationError(f"Sparkle generator changed prior version {version}")

    new_versions = set(generated_items) - set(previous_items)
    if new_versions != {expected_build}:
        raise PreparationError("Generated appcast must add exactly one update version")
    new_item = generated_items[expected_build]
    expected_url = download_url_prefix + quote(archive.name)
    if new_item["url"] != expected_url:
        raise PreparationError(f"New update URL is {new_item['url']!r}; expected {expected_url!r}")
    if new_item["short_version"] != expected_short_version:
        raise PreparationError("New update display version does not match its archive name")
    if new_item["length"] != archive.stat().st_size:
        raise PreparationError("New update length does not match its archive")
    return new_item


def _finish_transaction(
    workspace, metadata, archive, appcast, verifier, account, download_url_prefix,
    previous_items, runner, replace, after_archive_promoted=None, after_feed_promoted=None,
):
    staged_archive = workspace / archive.name
    staged_appcast = workspace / "appcast.xml"
    archive_is_final = archive.is_file() and _sha256(archive) == metadata["archive_sha256"]
    feed_is_final = appcast.is_file() and _sha256(appcast) == metadata["feed_sha256"]
    if archive_is_final and feed_is_final:
        _remove_workspace(workspace, archive.parent, metadata["workspace_prefix"])
        return
    if archive.is_file() and not archive_is_final:
        raise PreparationError(f"Final archive conflicts with interrupted transaction: {archive}")
    if appcast.is_file() and feed_is_final and not archive_is_final:
        raise PreparationError("Prepared feed exists without its matching archive")

    candidate_archive = archive if archive_is_final else staged_archive
    if not candidate_archive.is_file() or _sha256(candidate_archive) != metadata["archive_sha256"]:
        raise PreparationError("Interrupted transaction archive is missing or changed")
    if not staged_appcast.is_file() or _sha256(staged_appcast) != metadata["feed_sha256"]:
        raise PreparationError("Interrupted transaction feed is missing or changed")

    new_item = _validate_generated(staged_appcast, candidate_archive, download_url_prefix, previous_items)
    runner(
        [str(verifier), "--verify", "--account", account, str(candidate_archive), new_item["signature"]],
        candidate_archive.parent,
    )
    runner([str(verifier), "--verify", "--account", account, str(staged_appcast)], workspace)

    promoted_here = False
    try:
        if not archive_is_final:
            replace(staged_archive, archive)
            promoted_here = True
            metadata["state"] = "archive-promoted"
            _write_transaction(workspace, metadata)
        if after_archive_promoted is not None:
            after_archive_promoted()
        replace(staged_appcast, appcast)
        if after_feed_promoted is not None:
            after_feed_promoted()
    except Exception:
        if appcast.is_file() and _sha256(appcast) == metadata["feed_sha256"]:
            _remove_workspace(workspace, archive.parent, metadata["workspace_prefix"])
            return
        if (promoted_here or archive_is_final) and archive.is_file() and _sha256(archive) == metadata["archive_sha256"]:
            try:
                os.replace(archive, staged_archive)
            except OSError:
                pass
        raise

    _remove_workspace(workspace, archive.parent, metadata["workspace_prefix"])


def _recover_transaction(
    archive, appcast, verifier, account, download_url_prefix, previous_items,
    runner, replace, after_archive_promoted=None, after_feed_promoted=None,
):
    prefix = f".prepare-update-{archive.name}-"
    workspaces = [path for path in archive.parent.glob(f"{prefix}*") if path.is_dir()]
    if len(workspaces) > 1:
        raise PreparationError(f"Multiple interrupted transactions exist for {archive.name}")
    if not workspaces:
        return False
    if appcast.exists():
        runner([str(verifier), "--verify", "--account", account, str(appcast)], appcast.parent)
        _verify_archives(previous_items, appcast.parent, verifier, account, runner)
    workspace = workspaces[0]
    transaction_path = workspace / TRANSACTION_FILE
    try:
        metadata = json.loads(transaction_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PreparationError(f"Interrupted transaction metadata is unreadable: {workspace}") from error
    expected = {
        "schema": TRANSACTION_SCHEMA,
        "archive_name": archive.name,
        "appcast_name": appcast.name,
        "download_url_prefix": download_url_prefix,
        "workspace_prefix": prefix,
    }
    if any(metadata.get(key) != value for key, value in expected.items()):
        raise PreparationError(f"Interrupted transaction metadata does not match this release: {workspace}")
    if metadata.get("state") == "building":
        if archive.exists():
            raise PreparationError("Incomplete transaction unexpectedly has a final archive")
        _remove_workspace(workspace, archive.parent, prefix)
        return False
    for field in ("archive_sha256", "feed_sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", metadata.get(field, "")):
            raise PreparationError(f"Interrupted transaction metadata is incomplete: {workspace}")
    _finish_transaction(
        workspace, metadata, archive, appcast, verifier, account, download_url_prefix,
        previous_items, runner, replace, after_archive_promoted, after_feed_promoted,
    )
    return True


def prepare_update(
    generator, verifier, archiver, app, account, download_url_prefix, archive, appcast,
    run_command=None, replace=os.replace, after_archive_promoted=None, after_feed_promoted=None,
):
    prefix = urlsplit(download_url_prefix)
    if (
        prefix.scheme != "https"
        or not prefix.netloc
        or prefix.username
        or prefix.password
        or prefix.query
        or prefix.fragment
        or not download_url_prefix.endswith("/")
    ):
        raise PreparationError("Download URL prefix must be an HTTPS directory URL ending in /")

    generator = Path(generator)
    verifier = Path(verifier)
    archiver = Path(archiver)
    app = Path(app)
    archive = Path(archive)
    appcast = Path(appcast)
    if not generator.is_file():
        raise PreparationError(f"Sparkle generator does not exist: {generator}")
    if not verifier.is_file():
        raise PreparationError(f"Sparkle verifier does not exist: {verifier}")
    if not archiver.is_file():
        raise PreparationError(f"Archive tool does not exist: {archiver}")
    if not app.exists():
        raise PreparationError(f"Application does not exist: {app}")
    candidate_version, candidate_build = _app_bundle_metadata(app)
    if archive.suffix != ".zip":
        raise PreparationError(f"Update archive is not a ZIP: {archive}")
    archive_match = ARCHIVE_NAME.fullmatch(archive.name)
    if archive_match is None:
        raise PreparationError(f"Update archive has an unexpected name: {archive.name}")
    if archive_match.groups() != (candidate_version, candidate_build):
        raise PreparationError("Candidate archive name does not match the application version and build")
    if archive.parent != appcast.parent:
        raise PreparationError("Update archive and appcast must use the same output directory")

    runner = run_command or _default_run
    archive.parent.mkdir(parents=True, exist_ok=True)
    with _exclusive_lock(archive.parent):
        previous_data = None
        previous_items = {}
        if appcast.exists():
            previous_data, previous_root = _signed_xml(appcast)
            previous_items = _items(previous_root, appcast)

        if _recover_transaction(
            archive, appcast, verifier, account, download_url_prefix, previous_items,
            runner, replace, after_archive_promoted, after_feed_promoted,
        ):
            return
        _validate_build_history(
            candidate_version, candidate_build, archive, appcast, previous_items,
        )
        if appcast.exists():
            runner([str(verifier), "--verify", "--account", account, str(appcast)], appcast.parent)
            _verify_archives(previous_items, appcast.parent, verifier, account, runner)
        if archive.exists():
            raise PreparationError(f"Archive already exists; use a new build number: {archive}")

        prefix = f".prepare-update-{archive.name}-"
        workspace = Path(tempfile.mkdtemp(prefix=prefix, dir=archive.parent))
        metadata = {
            "schema": TRANSACTION_SCHEMA,
            "state": "building",
            "archive_name": archive.name,
            "appcast_name": appcast.name,
            "download_url_prefix": download_url_prefix,
            "workspace_prefix": prefix,
        }
        try:
            _write_transaction(workspace, metadata)
        except Exception:
            if workspace.exists():
                _remove_workspace(workspace, archive.parent, prefix)
            raise
        try:
            staged_archive = workspace / archive.name
            staged_appcast = workspace / "appcast.xml"
            runner(
                [str(archiver), "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(staged_archive)],
                workspace,
            )
            if not staged_archive.is_file():
                raise PreparationError("Archive tool did not create the update ZIP")
            if previous_data is not None:
                staged_appcast.write_bytes(previous_data)
            runner(
                [
                    str(generator), "--account", account,
                    "--download-url-prefix", download_url_prefix,
                    "--maximum-versions", "0", "--maximum-deltas", "0",
                    "--embed-release-notes", "-o", str(staged_appcast), str(workspace),
                ],
                workspace,
            )
            if not staged_appcast.is_file():
                raise PreparationError("Sparkle generator did not create appcast.xml")
            new_item = _validate_generated(staged_appcast, staged_archive, download_url_prefix, previous_items)
            runner(
                [str(verifier), "--verify", "--account", account, str(staged_archive), new_item["signature"]],
                workspace,
            )
            runner([str(verifier), "--verify", "--account", account, str(staged_appcast)], workspace)
            metadata.update({
                "state": "prepared",
                "archive_sha256": _sha256(staged_archive),
                "feed_sha256": _sha256(staged_appcast),
            })
            _write_transaction(workspace, metadata)
            _finish_transaction(
                workspace, metadata, archive, appcast, verifier, account, download_url_prefix,
                previous_items, runner, replace, after_archive_promoted, after_feed_promoted,
            )
        except Exception:
            if workspace.exists() and not archive.exists():
                _remove_workspace(workspace, archive.parent, prefix)
            raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generator", required=True)
    parser.add_argument("--verifier", required=True)
    parser.add_argument("--archiver", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--account", required=True)
    parser.add_argument("--download-url-prefix", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--appcast", required=True)
    args = parser.parse_args()
    try:
        prepare_update(
            args.generator,
            args.verifier,
            args.archiver,
            args.app,
            args.account,
            args.download_url_prefix,
            args.archive,
            args.appcast,
        )
    except (OSError, subprocess.CalledProcessError, PreparationError) as error:
        parser.exit(1, f"Unable to prepare update: {error}\n")


if __name__ == "__main__":
    main()
