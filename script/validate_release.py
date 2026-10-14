#!/usr/bin/env python3
"""Validate version, updater configuration, and generated release feed before publishing."""

import base64
import pathlib
import plistlib
import sys
import xml.etree.ElementTree as ET


def validate_bundle(app, version, build, public_key):
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    expected = {
        "CFBundleIdentifier": "local.lhg.Periodic",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": "26.0",
        "SUFeedURL": "https://github.com/occva/Periodic/releases/latest/download/appcast.xml",
        "SUPublicEDKey": public_key,
        "SUEnableInstallerLauncherService": True,
        "SUVerifyUpdateBeforeExtraction": True,
        "SURequireSignedFeed": True,
        "SUSignedFeedFailureExpirationInterval": 0,
        "SUEnableAutomaticChecks": False,
        "SUAutomaticallyUpdate": False,
        "SUEnableSystemProfiling": False,
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"{key} mismatch: expected {value!r}, got {info.get(key)!r}")
    if len(base64.b64decode(public_key, validate=True)) != 32:
        raise ValueError("Sparkle public key must be 32 bytes.")
    framework = app / "Contents/Frameworks/Sparkle.framework"
    for relative in ["Sparkle", "XPCServices/Installer.xpc", "Autoupdate", "Updater.app"]:
        if not (framework / relative).exists():
            raise ValueError("Missing Sparkle component: " + relative)


def validate_appcast(feed, dmg, version, build):
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    items = ET.parse(feed).findall("./channel/item")
    matches = [
        item for item in items
        if item.findtext(namespace + "version") == build
    ]
    if len(matches) != 1:
        raise ValueError("Appcast must contain exactly one item for the current build.")
    item = matches[0]
    if item.findtext(namespace + "shortVersionString") != version:
        raise ValueError("Appcast marketing version does not match.")
    if item.findtext(namespace + "minimumSystemVersion") != "26.0":
        raise ValueError("Appcast must require macOS 26.0.")
    if item.findtext(namespace + "hardwareRequirements") != "arm64":
        raise ValueError("Appcast must require Apple silicon (arm64).")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Appcast has no update archive.")
    expected_url = f"https://github.com/occva/Periodic/releases/download/v{version}/{dmg.name}"
    if enclosure.get("url") != expected_url:
        raise ValueError("Appcast download URL does not match the release asset.")
    if int(enclosure.get("length", "0")) != dmg.stat().st_size:
        raise ValueError("Appcast archive length does not match.")
    signature = enclosure.get(namespace + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Appcast is missing a valid EdDSA signature.")


def validate_next_build(feed, build):
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    versions = [
        item.findtext(namespace + "version", "")
        for item in ET.parse(feed).findall("./channel/item")
    ]
    if not versions or any(not version.isdecimal() for version in versions):
        raise ValueError("Previous official feed has no valid numeric build numbers.")
    previous_build = max(int(version) for version in versions)
    if int(build) <= previous_build:
        raise ValueError(f"Build {build} must be greater than published build {previous_build}.")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--next-build":
        validate_next_build(pathlib.Path(sys.argv[2]), sys.argv[3])
        print("Build number is greater than the previous official release.")
        return
    if len(sys.argv) not in (5, 7):
        raise SystemExit("usage: validate_release.py APP VERSION BUILD PUBLIC_KEY [APPCAST DMG]")
    app, version, build, public_key = sys.argv[1:5]
    validate_bundle(pathlib.Path(app), version, build, public_key)
    if len(sys.argv) == 7:
        validate_appcast(pathlib.Path(sys.argv[5]), pathlib.Path(sys.argv[6]), version, build)
    print(f"Release metadata verified: {version} ({build})")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, ET.ParseError, plistlib.InvalidFileException) as error:
        raise SystemExit(str(error)) from error
