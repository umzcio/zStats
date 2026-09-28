#!/usr/bin/env python3
"""Generate a Sparkle appcast without rewriting previously published entries."""

import argparse
import base64
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import quote, unquote, urlsplit
import xml.etree.ElementTree as ET


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


def prepare_update(generator, verifier, account, download_url_prefix, archive, appcast, run_command=None):
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
    archive = Path(archive)
    appcast = Path(appcast)
    if not generator.is_file():
        raise PreparationError(f"Sparkle generator does not exist: {generator}")
    if not verifier.is_file():
        raise PreparationError(f"Sparkle verifier does not exist: {verifier}")
    if not archive.is_file() or archive.suffix != ".zip":
        raise PreparationError(f"Update archive does not exist or is not a ZIP: {archive}")
    archive_match = ARCHIVE_NAME.fullmatch(archive.name)
    if archive_match is None:
        raise PreparationError(f"Update archive has an unexpected name: {archive.name}")
    expected_short_version, expected_build = archive_match.groups()
    if archive.parent != appcast.parent:
        raise PreparationError("Update archive and appcast must use the same output directory")

    runner = run_command or _default_run
    previous_data = None
    previous_items = {}
    if appcast.exists():
        previous_data, previous_root = _signed_xml(appcast)
        previous_items = _items(previous_root, appcast)
        runner([str(verifier), "--verify", "--account", account, str(appcast)], appcast.parent)
        _verify_archives(previous_items, appcast.parent, verifier, account, runner)

    with tempfile.TemporaryDirectory(prefix=".prepare-update-", dir=appcast.parent) as staging_name:
        staging = Path(staging_name)
        staged_archive = staging / archive.name
        staged_appcast = staging / "appcast.xml"
        shutil.copy2(archive, staged_archive)
        if previous_data is not None:
            staged_appcast.write_bytes(previous_data)

        command = [
            str(generator),
            "--account", account,
            "--download-url-prefix", download_url_prefix,
            "--maximum-versions", "0",
            "--maximum-deltas", "0",
            "--embed-release-notes",
            "-o", str(staged_appcast),
            str(staging),
        ]
        runner(command, staging)
        if not staged_appcast.is_file():
            raise PreparationError("Sparkle generator did not create appcast.xml")

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
            raise PreparationError(
                f"New update URL is {new_item['url']!r}; expected {expected_url!r}"
            )
        if new_item["short_version"] != expected_short_version:
            raise PreparationError("New update display version does not match its archive name")
        if new_item["length"] != archive.stat().st_size:
            raise PreparationError("New update length does not match its archive")

        runner(
            [
                str(verifier), "--verify", "--account", account,
                str(archive), new_item["signature"],
            ],
            archive.parent,
        )
        runner([str(verifier), "--verify", "--account", account, str(staged_appcast)], staging)
        os.replace(staged_appcast, appcast)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generator", required=True)
    parser.add_argument("--verifier", required=True)
    parser.add_argument("--account", required=True)
    parser.add_argument("--download-url-prefix", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--appcast", required=True)
    args = parser.parse_args()
    try:
        prepare_update(
            args.generator,
            args.verifier,
            args.account,
            args.download_url_prefix,
            args.archive,
            args.appcast,
        )
    except (OSError, subprocess.CalledProcessError, PreparationError) as error:
        parser.exit(1, f"Unable to prepare update: {error}\n")


if __name__ == "__main__":
    main()
