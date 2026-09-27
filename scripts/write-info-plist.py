#!/usr/bin/env python3
"""Build public bundle metadata; signing secrets never belong in this file."""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import urlsplit


def bundle_info(config, environ):
    version = environ.get("ZSTATS_VERSION", str(config["version"]))
    build = environ.get("ZSTATS_BUILD_NUMBER", str(config["build"]))
    feed = environ.get("ZSTATS_UPDATE_FEED_URL", config.get("feedURL", ""))
    key = environ.get("ZSTATS_UPDATE_PUBLIC_KEY", config.get("publicEDKey", ""))
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must have three numeric components (for example 0.1.0).")
    if not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("Build number must be a positive integer, increased for each release.")
    if bool(feed) != bool(key):
        raise ValueError("Configure both the update feed URL and public Ed25519 key, or leave both empty.")
    if feed:
        url = urlsplit(feed)
        if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment or any(c.isspace() for c in feed):
            raise ValueError("Update feed must be an HTTPS URL without credentials or a fragment.")
        try:
            valid_key = len(base64.b64decode(key, validate=True)) == 32
        except ValueError:
            valid_key = False
        if not valid_key:
            raise ValueError("Public Ed25519 key must be a base64-encoded 32-byte key.")
    info = {
        "CFBundleName": "zStats", "CFBundleDisplayName": "zStats",
        "CFBundleIdentifier": "dev.zach.zStats", "CFBundleExecutable": "zStats",
        "CFBundleIconFile": "zStats", "CFBundleIconName": "zStats",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
        "CFBundleVersion": build, "LSMinimumSystemVersion": "26.0",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "zStats — local system monitoring",
        # Opt in through About; never install an update without the user choosing it.
        "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False,
        "SUAllowsAutomaticUpdates": False, "SUEnableSystemProfiling": False,
        "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True,
    }
    if feed:
        info.update(SUFeedURL=feed, SUPublicEDKey=key)
    return info


if __name__ == "__main__":
    try:
        config = json.loads(Path("config/release.json").read_text())
        info = bundle_info(config, os.environ)
        with open(sys.argv[1], "wb") as output:
            plistlib.dump(info, output)
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
