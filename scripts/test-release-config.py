#!/usr/bin/env python3
import base64
import importlib.util
from pathlib import Path
import plistlib
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("release_config", Path(__file__).with_name("write-info-plist.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseConfigTests(unittest.TestCase):
    def setUp(self):
        self.config = {"version": "0.1.0", "build": 3, "feedURL": "", "publicEDKey": ""}
        self.key = base64.b64encode(bytes(range(32))).decode()

    def test_local_build_is_inactive_and_opt_in(self):
        info = module.bundle_info(self.config, {})
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)
        self.assertFalse(info["SUEnableAutomaticChecks"])
        self.assertFalse(info["SUAllowsAutomaticUpdates"])
        self.assertEqual(info["LSMinimumSystemVersion"], "26.0")

    def test_release_overrides_and_plist_round_trip(self):
        info = module.bundle_info({**self.config, "updatesEnabled": True}, {
            "ZSTATS_VERSION": "1.2.3", "ZSTATS_BUILD_NUMBER": "42",
            "ZSTATS_UPDATE_FEED_URL": "https://example.com/appcast.xml?a=1&b=2",
            "ZSTATS_UPDATE_PUBLIC_KEY": self.key,
        })
        self.assertEqual(plistlib.loads(plistlib.dumps(info)), info)
        self.assertEqual(info["CFBundleVersion"], "42")
        self.assertEqual(info["CFBundleShortVersionString"], "1.2.3")
        self.assertTrue(info["SURequireSignedFeed"])
        self.assertTrue(info["SUVerifyUpdateBeforeExtraction"])

    def test_prepared_private_build_does_not_expose_update_feed(self):
        prepared = {**self.config, "feedURL": "https://github.com/umzcio/zStats/releases/latest/download/appcast.xml", "publicEDKey": self.key, "updatesEnabled": False}
        info = module.bundle_info(prepared, {})
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)
        public_info = module.bundle_info({**prepared, "updatesEnabled": True}, {})
        self.assertEqual(public_info["SUFeedURL"], prepared["feedURL"])
        self.assertEqual(public_info["SUPublicEDKey"], self.key)

    def test_updates_require_explicit_boolean_and_complete_configuration(self):
        for invalid in ["false", "true", 1, None]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                module.bundle_info({**self.config, "updatesEnabled": invalid}, {})
        with self.assertRaises(ValueError):
            module.bundle_info({**self.config, "updatesEnabled": True}, {})

    def test_partial_configuration_fails(self):
        for partial in [{"feedURL": "https://example.com/appcast.xml"}, {"publicEDKey": self.key}]:
            with self.subTest(partial=partial), self.assertRaises(ValueError):
                module.bundle_info({**self.config, **partial}, {})

    def test_invalid_feed_or_key_fails(self):
        for feed in ["http://example.com/appcast.xml", "https:///", "file:///tmp/a", "https://u:p@example.com/a", "https://example.com/a#b", "https://example.com/a b"]:
            with self.subTest(feed=feed), self.assertRaises(ValueError):
                module.bundle_info({**self.config, "feedURL": feed, "publicEDKey": self.key}, {})
        for key in ["invalid", base64.b64encode(bytes(31)).decode()]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.bundle_info({**self.config, "feedURL": "https://example.com/a", "publicEDKey": key}, {})

    def test_invalid_version_or_build_fails(self):
        for field, value in [("version", "1.0-beta"), ("build", 0), ("build", "../bad"), ("build", "1.2")]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                module.bundle_info({**self.config, field: value}, {})


if __name__ == "__main__":
    unittest.main()
