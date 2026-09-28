#!/usr/bin/env python3
import base64
import copy
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest import mock
from urllib.parse import quote
import xml.etree.ElementTree as ET
import zipfile


sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("prepare_update", Path(__file__).with_name("prepare-update.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

ET.register_namespace("sparkle", module.SPARKLE_NS)


def signed_bytes(xml_bytes):
    signature = base64.b64encode(hashlib.sha512(xml_bytes).digest()).decode()
    return xml_bytes + (
        f"<!-- sparkle-signatures:\nedSignature: {signature}\n"
        f"length: {len(xml_bytes)}\n-->\n"
    ).encode()


def empty_feed():
    root = ET.Element("rss", {"version": "2.0"})
    ET.SubElement(root, "channel")
    return root


def add_item(root, version, short_version, url, length, signature=None):
    channel = root.find("channel")
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = short_version
    ET.SubElement(item, module.VERSION).text = version
    ET.SubElement(item, module.SHORT_VERSION).text = short_version
    ET.SubElement(item, "enclosure", {
        "url": url,
        "length": str(length),
        "type": "application/octet-stream",
        module.ED_SIGNATURE: signature or base64.b64encode(bytes([int(version) % 251]) * 64).decode(),
    })
    return item


class SimulatedInterruption(BaseException):
    pass


class FakeTools:
    def __init__(self, archiver):
        self.archiver = str(archiver)
        self.generated = []
        self.commands = []
        self.verified = []
        self.change_prior_url = False
        self.failure = None

    def __call__(self, command, cwd):
        self.commands.append(command)
        if command[0] == self.archiver:
            if self.failure == "archive":
                raise OSError("injected archive failure")
            app = Path(command[-2])
            with zipfile.ZipFile(command[-1], "w") as zipped:
                for path in app.rglob("*"):
                    if path.is_file():
                        zipped.write(path, f"{app.name}/{path.relative_to(app)}")
            return
        if "--verify" in command:
            verified_path = Path(command[-1] if command[-1].endswith(".xml") else command[-2])
            if self.failure == "feed" and verified_path.suffix == ".xml":
                raise OSError("injected feed verification failure")
            if self.failure == "signature" and verified_path.name == "zStats-7.1.0-71.zip":
                raise OSError("injected signature failure")
            if verified_path.suffix == ".xml":
                module._signed_xml(verified_path)
            else:
                expected = base64.b64encode(hashlib.sha512(verified_path.read_bytes()).digest()).decode()
                if command[-1] != expected:
                    raise AssertionError("archive signature does not match")
            self.verified.append(verified_path.read_bytes())
            return
        if self.failure == "generator":
            raise OSError("injected generator failure")
        cwd = Path(cwd)
        archives = list(cwd.glob("*.zip"))
        if len(archives) != 1:
            raise AssertionError(f"expected one staged archive, got {archives}")
        archive = archives[0]
        output = Path(command[command.index("-o") + 1])
        prefix = command[command.index("--download-url-prefix") + 1]
        if output.exists():
            _, root = module._signed_xml(output)
            root = copy.deepcopy(root)
        else:
            root = empty_feed()
        if self.change_prior_url:
            root.find("channel/item/enclosure").set("url", "https://example.com/changed.zip")
        parts = archive.stem.rsplit("-", 2)
        short_version, version = parts[-2], parts[-1]
        add_item(
            root,
            version,
            short_version,
            prefix + quote(archive.name),
            archive.stat().st_size,
            base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode(),
        )
        generated = signed_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))
        output.write_bytes(generated)
        self.generated.append(generated)


class PrepareUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.output = self.directory / "updates"
        self.output.mkdir()
        self.generator = self.directory / "generate_appcast"
        self.generator.touch()
        self.verifier = self.directory / "sign_update"
        self.verifier.touch()
        self.archiver = self.directory / "ditto"
        self.archiver.touch()
        self.app = self.directory / "zStats.app"
        self.app.mkdir()
        nested_info = self.app / "Contents" / "Frameworks" / "Sparkle.framework" / "Updater.app" / "Contents" / "Info.plist"
        nested_info.parent.mkdir(parents=True)
        with nested_info.open("wb") as stream:
            plistlib.dump({"CFBundleShortVersionString": "2.10.0", "CFBundleVersion": "2100"}, stream)
        self.appcast = self.output / "appcast.xml"
        self.fake = FakeTools(self.archiver)

    def tearDown(self):
        self.temporary.cleanup()

    def prepare(self, name, contents, prefix, app_version=None, app_build=None, **kwargs):
        name_match = module.ARCHIVE_NAME.fullmatch(name)
        name_version, name_build = name_match.groups()
        info_path = self.app / "Contents" / "Info.plist"
        info_path.parent.mkdir(parents=True, exist_ok=True)
        with info_path.open("wb") as stream:
            plistlib.dump({
                "CFBundleShortVersionString": app_version or name_version,
                "CFBundleVersion": app_build or name_build,
            }, stream)
        (self.app / "payload").write_bytes(contents)
        archive = self.output / name
        module.prepare_update(
            self.generator,
            self.verifier,
            self.archiver,
            self.app,
            "test-account",
            prefix,
            archive,
            self.appcast,
            run_command=self.fake,
            **kwargs,
        )
        return archive

    def items(self):
        _, root = module._signed_xml(self.appcast)
        return module._items(root, self.appcast)

    def test_two_releases_keep_first_tag_url_and_metadata(self):
        self.prepare(
            "zStats-1.0.0-10.zip", b"release-a",
            "https://github.com/owner/zStats/releases/download/v1.0.0/",
        )
        first_item = self.items()["10"]

        self.prepare(
            "zStats-1.1.0-11.zip", b"release-b",
            "https://github.com/owner/zStats/releases/download/v1.1.0/",
        )
        items = self.items()

        self.assertEqual(items["10"], first_item)
        self.assertEqual(
            items["10"]["url"],
            "https://github.com/owner/zStats/releases/download/v1.0.0/zStats-1.0.0-10.zip",
        )
        self.assertEqual(
            items["11"]["url"],
            "https://github.com/owner/zStats/releases/download/v1.1.0/zStats-1.1.0-11.zip",
        )
        generation = next(command for command in reversed(self.fake.commands) if "--maximum-versions" in command)
        self.assertIn("--maximum-versions", generation)
        self.assertEqual(
            generation[generation.index("--maximum-versions") + 1],
            "0",
        )

    def test_stable_download_prefix_is_supported(self):
        prefix = "https://updates.example.com/downloads/"
        self.prepare("zStats-2.0.0-20.zip", b"twenty", prefix)
        self.prepare("zStats-2.1.0-21.zip", b"twenty-one", prefix)
        self.assertEqual(
            {item["url"] for item in self.items().values()},
            {
                prefix + "zStats-2.0.0-20.zip",
                prefix + "zStats-2.1.0-21.zip",
            },
        )

    def test_generated_signed_bytes_are_published_without_post_edit(self):
        self.prepare("zStats-3.0.0-30.zip", b"thirty", "https://example.com/v3.0.0/")
        self.assertEqual(self.appcast.read_bytes(), self.fake.generated[-1])
        self.assertEqual(self.appcast.read_bytes(), self.fake.verified[-1])
        module._signed_xml(self.appcast)

    def test_malformed_prior_feed_fails_without_replacing_it(self):
        original = signed_bytes(b"<rss><channel>")
        self.appcast.write_bytes(original)
        with self.assertRaises(module.PreparationError):
            self.prepare("zStats-4.0.0-40.zip", b"forty", "https://example.com/v4.0.0/")
        self.assertEqual(self.appcast.read_bytes(), original)
        self.assertEqual(self.fake.commands, [])

    def test_missing_prior_enclosure_metadata_fails_without_replacing_it(self):
        root = empty_feed()
        item = add_item(root, "50", "5.0", "https://example.com/v5.0/old.zip", 3)
        del item.find("enclosure").attrib[module.ED_SIGNATURE]
        original = signed_bytes(ET.tostring(root, encoding="utf-8"))
        self.appcast.write_bytes(original)
        with self.assertRaises(module.PreparationError):
            self.prepare("zStats-5.1.0-51.zip", b"fifty-one", "https://example.com/v5.1.0/")
        self.assertEqual(self.appcast.read_bytes(), original)
        self.assertEqual(self.fake.commands, [])

    def test_generator_cannot_change_a_prior_item(self):
        self.prepare("zStats-6.0.0-60.zip", b"sixty", "https://example.com/v6.0.0/")
        original = self.appcast.read_bytes()
        self.fake.change_prior_url = True
        with self.assertRaises(module.PreparationError):
            self.prepare(
                "zStats-6.1.0-61.zip", b"sixty-one",
                "https://example.com/v6.1.0/",
            )
        self.assertEqual(self.appcast.read_bytes(), original)

    def test_prepromotion_failures_leave_old_artifacts_and_allow_retry(self):
        first = self.prepare("zStats-7.0.0-70.zip", b"seventy", "https://example.com/v7.0.0/")
        original_feed = self.appcast.read_bytes()
        original_archive = first.read_bytes()
        for failure in ("archive", "generator", "signature"):
            with self.subTest(failure=failure):
                self.fake.failure = failure
                target = self.output / "zStats-7.1.0-71.zip"
                with self.assertRaises(OSError):
                    self.prepare(target.name, b"seventy-one", "https://example.com/v7.1.0/")
                self.assertFalse(target.exists())
                self.assertEqual(self.appcast.read_bytes(), original_feed)
                self.assertEqual(first.read_bytes(), original_archive)
                self.assertEqual(list(self.output.glob(".prepare-update-*.zip-*")), [])
        self.fake.failure = None
        self.prepare("zStats-7.1.0-71.zip", b"seventy-one", "https://example.com/v7.1.0/")

    def test_promotion_failure_rolls_back_and_same_build_retries(self):
        self.prepare("zStats-8.0.0-80.zip", b"eighty", "https://example.com/v8.0.0/")
        original_feed = self.appcast.read_bytes()
        target = self.output / "zStats-8.1.0-81.zip"

        def fail_feed(source, destination):
            if Path(destination) == self.appcast:
                raise OSError("injected feed promotion failure")
            os.replace(source, destination)

        with self.assertRaises(OSError):
            self.prepare(
                target.name, b"eighty-one", "https://example.com/v8.1.0/",
                replace=fail_feed,
            )
        self.assertFalse(target.exists())
        self.assertEqual(self.appcast.read_bytes(), original_feed)
        self.prepare(target.name, b"eighty-one", "https://example.com/v8.1.0/")
        self.assertTrue(target.exists())

    def test_interrupted_promotion_recovers_without_regenerating(self):
        self.prepare("zStats-9.0.0-90.zip", b"ninety", "https://example.com/v9.0.0/")
        old_feed = self.appcast.read_bytes()
        target = self.output / "zStats-9.1.0-91.zip"

        def interrupt():
            raise SimulatedInterruption()

        with self.assertRaises(SimulatedInterruption):
            self.prepare(
                target.name, b"ninety-one", "https://example.com/v9.1.0/",
                after_archive_promoted=interrupt,
            )
        self.assertTrue(target.exists())
        self.assertEqual(self.appcast.read_bytes(), old_feed)
        generated_count = len(self.fake.generated)
        self.prepare(target.name, b"ignored-on-recovery", "https://example.com/v9.1.0/")
        self.assertEqual(len(self.fake.generated), generated_count)
        self.assertIn("91", self.items())
        self.assertEqual(list(self.output.glob(".prepare-update-*.zip-*")), [])

    def test_interrupted_recovery_reverifies_retained_archive(self):
        retained = self.prepare("zStats-12.0.0-120.zip", b"one twenty", "https://example.com/v12.0.0/")
        old_feed = self.appcast.read_bytes()

        def interrupt():
            raise SimulatedInterruption()

        with self.assertRaises(SimulatedInterruption):
            self.prepare(
                "zStats-12.1.0-121.zip", b"one twenty-one", "https://example.com/v12.1.0/",
                after_archive_promoted=interrupt,
            )
        retained_bytes = bytearray(retained.read_bytes())
        retained_bytes[len(retained_bytes) // 2] ^= 1
        retained.write_bytes(retained_bytes)
        with self.assertRaises(AssertionError):
            self.prepare(
                "zStats-12.1.0-121.zip", b"retry", "https://example.com/v12.1.0/",
            )
        self.assertEqual(self.appcast.read_bytes(), old_feed)
        self.assertTrue((self.output / "zStats-12.1.0-121.zip").exists())
        self.assertEqual(len(list(self.output.glob(".prepare-update-zStats-12.1.0-121.zip-*"))), 1)

    def test_completed_but_uncleaned_recovery_reverifies_feed_and_archives(self):
        self.prepare("zStats-13.0.0-130.zip", b"one thirty", "https://example.com/v13.0.0/")

        def interrupt():
            raise SimulatedInterruption()

        with self.assertRaises(SimulatedInterruption):
            self.prepare(
                "zStats-13.1.0-131.zip", b"one thirty-one", "https://example.com/v13.1.0/",
                after_feed_promoted=interrupt,
            )
        workspace_pattern = ".prepare-update-zStats-13.1.0-131.zip-*"
        self.assertEqual(len(list(self.output.glob(workspace_pattern))), 1)
        self.fake.failure = "feed"
        with self.assertRaises(OSError):
            self.prepare("zStats-13.1.0-131.zip", b"retry", "https://example.com/v13.1.0/")
        self.assertEqual(len(list(self.output.glob(workspace_pattern))), 1)
        self.fake.failure = None
        verified_before = len(self.fake.verified)
        self.prepare("zStats-13.1.0-131.zip", b"retry", "https://example.com/v13.1.0/")
        verified = self.fake.verified[verified_before:]
        self.assertIn(self.appcast.read_bytes(), verified)
        self.assertIn((self.output / "zStats-13.0.0-130.zip").read_bytes(), verified)
        self.assertIn((self.output / "zStats-13.1.0-131.zip").read_bytes(), verified)
        self.assertEqual(list(self.output.glob(workspace_pattern)), [])

    def test_pending_transaction_rejects_app_filename_mismatch_before_recovery(self):
        self.prepare("zStats-14.0.0-140.zip", b"one forty", "https://example.com/v14.0.0/")
        old_feed = self.appcast.read_bytes()

        def interrupt():
            raise SimulatedInterruption()

        with self.assertRaises(SimulatedInterruption):
            self.prepare(
                "zStats-14.1.0-141.zip", b"one forty-one", "https://example.com/v14.1.0/",
                after_archive_promoted=interrupt,
            )
        tool_calls = len(self.fake.commands)
        with self.assertRaises(module.PreparationError):
            self.prepare(
                "zStats-14.1.0-141.zip", b"mismatch", "https://example.com/v14.1.0/",
                app_build="140",
            )
        self.assertEqual(len(self.fake.commands), tool_calls)
        self.assertEqual(self.appcast.read_bytes(), old_feed)
        self.assertTrue((self.output / "zStats-14.1.0-141.zip").exists())
        self.prepare("zStats-14.1.0-141.zip", b"retry", "https://example.com/v14.1.0/")
        self.assertIn("141", self.items())

    def test_completed_duplicate_is_refused(self):
        name = "zStats-10.0.0-100.zip"
        self.prepare(name, b"one hundred", "https://example.com/v10.0.0/")
        with self.assertRaises(module.PreparationError):
            self.prepare(name, b"different", "https://example.com/v10.0.0/")

    def test_concurrent_writer_is_refused_and_lock_releases(self):
        with module._exclusive_lock(self.output):
            with self.assertRaises(module.PreparationError):
                self.prepare("zStats-11.0.0-110.zip", b"locked", "https://example.com/v11.0.0/")
        self.prepare("zStats-11.0.0-110.zip", b"unlocked", "https://example.com/v11.0.0/")

    def test_reused_and_decreasing_builds_fail_before_packaging(self):
        self.prepare("zStats-1.0.0-10.zip", b"ten", "https://example.com/v1.0.0/")
        archiver_calls = sum(command[0] == str(self.archiver) for command in self.fake.commands)
        tool_calls = len(self.fake.commands)
        for name in ("zStats-2.0.0-10.zip", "zStats-3.0.0-9.zip"):
            with self.subTest(name=name), self.assertRaises(module.PreparationError):
                self.prepare(name, b"rejected", "https://example.com/rejected/")
            self.assertFalse((self.output / name).exists())
            self.assertEqual(
                sum(command[0] == str(self.archiver) for command in self.fake.commands),
                archiver_calls,
            )
            self.assertEqual(len(self.fake.commands), tool_calls)

        accepted = self.prepare("zStats-2.0.0-11.zip", b"eleven", "https://example.com/v2.0.0/")
        self.assertTrue(accepted.exists())

    def test_candidate_filename_cannot_hide_its_actual_bundle_build(self):
        self.prepare("zStats-1.0.0-10.zip", b"ten", "https://example.com/v1.0.0/")
        archiver_calls = sum(command[0] == str(self.archiver) for command in self.fake.commands)
        tool_calls = len(self.fake.commands)
        with self.assertRaises(module.PreparationError):
            self.prepare(
                "zStats-2.0.0-11.zip", b"renamed", "https://example.com/v2.0.0/",
                app_build="10",
            )
        self.assertEqual(
            sum(command[0] == str(self.archiver) for command in self.fake.commands),
            archiver_calls,
        )
        self.assertEqual(len(self.fake.commands), tool_calls)

    def test_malformed_or_inconsistent_retained_metadata_fails_closed(self):
        archive = self.prepare("zStats-1.0.0-10.zip", b"ten", "https://example.com/v1.0.0/")
        original_feed = self.appcast.read_bytes()
        archive.write_bytes(b"not a zip")
        with self.assertRaises(module.PreparationError):
            self.prepare("zStats-2.0.0-11.zip", b"eleven", "https://example.com/v2.0.0/")
        self.assertEqual(self.appcast.read_bytes(), original_feed)

    def test_feed_and_retained_archive_builds_must_agree(self):
        self.prepare("zStats-1.0.0-10.zip", b"ten", "https://example.com/v1.0.0/")
        _, root = module._signed_xml(self.appcast)
        root.find(f"channel/item/{module.VERSION}").text = "12"
        inconsistent = signed_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))
        self.appcast.write_bytes(inconsistent)
        with self.assertRaises(module.PreparationError):
            self.prepare("zStats-2.0.0-13.zip", b"thirteen", "https://example.com/v2.0.0/")
        self.assertEqual(self.appcast.read_bytes(), inconsistent)

    def test_empty_history_accepts_a_large_positive_build(self):
        large_build = "99999999999999999999999999999999999999"
        archive = self.prepare(
            f"zStats-1.0.0-{large_build}.zip", b"large",
            "https://example.com/v1.0.0/",
        )
        self.assertTrue(archive.exists())
        self.assertIn(large_build, self.items())

    def test_retained_archive_without_feed_is_rejected(self):
        orphan = self.output / "zStats-1.0.0-10.zip"
        orphan.write_bytes(b"orphan")
        with self.assertRaises(module.PreparationError):
            self.prepare("zStats-2.0.0-11.zip", b"eleven", "https://example.com/v2.0.0/")
        self.assertTrue(orphan.exists())

    def test_initial_transaction_metadata_failure_removes_owned_workspace(self):
        with mock.patch.object(module, "_write_transaction", side_effect=OSError("injected metadata failure")):
            with self.assertRaises(OSError):
                self.prepare("zStats-1.0.0-10.zip", b"ten", "https://example.com/v1.0.0/")
        self.assertEqual(list(self.output.glob(".prepare-update-*.zip-*")), [])

    def test_unknown_nonempty_transaction_workspace_is_preserved(self):
        name = "zStats-1.0.0-10.zip"
        workspace = self.output / f".prepare-update-{name}-unknown"
        workspace.mkdir()
        (workspace / "user-notes").write_text("preserve", encoding="utf-8")
        with self.assertRaises(module.PreparationError):
            self.prepare(name, b"ten", "https://example.com/v1.0.0/")
        self.assertEqual((workspace / "user-notes").read_text(encoding="utf-8"), "preserve")


if __name__ == "__main__":
    unittest.main()
