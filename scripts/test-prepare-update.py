#!/usr/bin/env python3
import base64
import copy
import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.parse import quote
import xml.etree.ElementTree as ET


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


class FakeGenerator:
    def __init__(self):
        self.generated = []
        self.commands = []
        self.verified = []
        self.change_prior_url = False

    def __call__(self, command, cwd):
        self.commands.append(command)
        if "--verify" in command:
            verified_path = Path(command[-1] if command[-1].endswith(".xml") else command[-2])
            if verified_path.suffix == ".xml":
                module._signed_xml(verified_path)
            else:
                expected = base64.b64encode(hashlib.sha512(verified_path.read_bytes()).digest()).decode()
                if command[-1] != expected:
                    raise AssertionError("archive signature does not match")
            self.verified.append(verified_path.read_bytes())
            return
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
        self.generator = self.directory / "generate_appcast"
        self.generator.touch()
        self.verifier = self.directory / "sign_update"
        self.verifier.touch()
        self.appcast = self.directory / "appcast.xml"
        self.fake = FakeGenerator()

    def tearDown(self):
        self.temporary.cleanup()

    def prepare(self, archive, prefix):
        module.prepare_update(
            self.generator,
            self.verifier,
            "test-account",
            prefix,
            archive,
            self.appcast,
            run_command=self.fake,
        )

    def archive(self, name, contents):
        path = self.directory / name
        path.write_bytes(contents)
        return path

    def items(self):
        _, root = module._signed_xml(self.appcast)
        return module._items(root, self.appcast)

    def test_two_releases_keep_first_tag_url_and_metadata(self):
        first = self.archive("zStats-1.0.0-10.zip", b"release-a")
        self.prepare(first, "https://github.com/owner/zStats/releases/download/v1.0.0/")
        first_item = self.items()["10"]

        second = self.archive("zStats-1.1.0-11.zip", b"release-b")
        self.prepare(second, "https://github.com/owner/zStats/releases/download/v1.1.0/")
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
        self.prepare(self.archive("zStats-2.0.0-20.zip", b"twenty"), prefix)
        self.prepare(self.archive("zStats-2.1.0-21.zip", b"twenty-one"), prefix)
        self.assertEqual(
            {item["url"] for item in self.items().values()},
            {
                prefix + "zStats-2.0.0-20.zip",
                prefix + "zStats-2.1.0-21.zip",
            },
        )

    def test_generated_signed_bytes_are_published_without_post_edit(self):
        archive = self.archive("zStats-3.0.0-30.zip", b"thirty")
        self.prepare(archive, "https://example.com/v3.0.0/")
        self.assertEqual(self.appcast.read_bytes(), self.fake.generated[-1])
        self.assertEqual(self.appcast.read_bytes(), self.fake.verified[-1])
        module._signed_xml(self.appcast)

    def test_malformed_prior_feed_fails_without_replacing_it(self):
        original = signed_bytes(b"<rss><channel>")
        self.appcast.write_bytes(original)
        archive = self.archive("zStats-4.0.0-40.zip", b"forty")
        with self.assertRaises(module.PreparationError):
            self.prepare(archive, "https://example.com/v4.0.0/")
        self.assertEqual(self.appcast.read_bytes(), original)
        self.assertEqual(self.fake.commands, [])

    def test_missing_prior_enclosure_metadata_fails_without_replacing_it(self):
        root = empty_feed()
        item = add_item(root, "50", "5.0", "https://example.com/v5.0/old.zip", 3)
        del item.find("enclosure").attrib[module.ED_SIGNATURE]
        original = signed_bytes(ET.tostring(root, encoding="utf-8"))
        self.appcast.write_bytes(original)
        archive = self.archive("zStats-5.1.0-51.zip", b"fifty-one")
        with self.assertRaises(module.PreparationError):
            self.prepare(archive, "https://example.com/v5.1.0/")
        self.assertEqual(self.appcast.read_bytes(), original)
        self.assertEqual(self.fake.commands, [])

    def test_generator_cannot_change_a_prior_item(self):
        self.prepare(
            self.archive("zStats-6.0.0-60.zip", b"sixty"),
            "https://example.com/v6.0.0/",
        )
        original = self.appcast.read_bytes()
        self.fake.change_prior_url = True
        with self.assertRaises(module.PreparationError):
            self.prepare(
                self.archive("zStats-6.1.0-61.zip", b"sixty-one"),
                "https://example.com/v6.1.0/",
            )
        self.assertEqual(self.appcast.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
