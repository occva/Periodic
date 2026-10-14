import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET


MODULE_PATH = Path(__file__).resolve().parents[2] / "script/validate_release.py"
SPEC = importlib.util.spec_from_file_location("validate_release", MODULE_PATH)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.app = root / "Periodic.app"
        self.info_path = self.app / "Contents/Info.plist"
        self.info_path.parent.mkdir(parents=True)
        self.public_key = base64.b64encode(bytes(range(32))).decode()
        self.info = {
            "CFBundleIdentifier": "local.lhg.Periodic",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "26.0",
            "SUFeedURL": "https://github.com/occva/Periodic/releases/latest/download/appcast.xml",
            "SUPublicEDKey": self.public_key,
            "SUEnableInstallerLauncherService": True,
            "SUVerifyUpdateBeforeExtraction": True,
            "SURequireSignedFeed": True,
            "SUSignedFeedFailureExpirationInterval": 0,
            "SUEnableAutomaticChecks": False,
            "SUAutomaticallyUpdate": False,
            "SUEnableSystemProfiling": False,
        }
        self.write_info()
        framework = self.app / "Contents/Frameworks/Sparkle.framework"
        for relative in ["Sparkle", "XPCServices/Installer.xpc", "Autoupdate", "Updater.app"]:
            (framework / relative).mkdir(parents=True)
        self.dmg = root / "Periodic-1.0.0.dmg"
        self.dmg.write_bytes(b"release archive")
        self.feed = root / "appcast.xml"
        self.signature = base64.b64encode(bytes(range(64))).decode()
        self.write_feed()

    def write_info(self):
        with self.info_path.open("wb") as output:
            plistlib.dump(self.info, output)

    def write_feed(self, **overrides):
        attributes = {
            "url": "https://github.com/occva/Periodic/releases/download/v1.0.0/Periodic-1.0.0.dmg",
            "length": str(self.dmg.stat().st_size),
            "sparkle:edSignature": self.signature,
        }
        attributes.update(overrides)
        attributes_text = " ".join(f'{key}="{value}"' for key, value in attributes.items())
        self.feed.write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            "<channel><item><sparkle:version>1</sparkle:version>"
            "<sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>"
            "<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>"
            "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"
            f"<enclosure {attributes_text}/></item></channel></rss>"
        )

    def test_accepts_consistent_bundle_and_feed(self):
        release.validate_bundle(self.app, "1.0.0", "1", self.public_key)
        release.validate_appcast(self.feed, self.dmg, "1.0.0", "1")

    def test_rejects_version_key_and_privacy_mismatches(self):
        for key, value in [
            ("CFBundleVersion", "2"),
            ("SUPublicEDKey", base64.b64encode(b"x" * 32).decode()),
            ("SUEnableSystemProfiling", True),
            ("SURequireSignedFeed", False),
        ]:
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = value
                self.write_info()
                with self.assertRaises(ValueError):
                    release.validate_bundle(self.app, "1.0.0", "1", self.public_key)
                self.info[key] = original

    def test_rejects_missing_installer(self):
        installer = self.app / "Contents/Frameworks/Sparkle.framework/XPCServices/Installer.xpc"
        installer.rmdir()
        with self.assertRaisesRegex(ValueError, "Missing Sparkle component"):
            release.validate_bundle(self.app, "1.0.0", "1", self.public_key)

    def test_rejects_incorrect_download_url_archive_size_or_signature(self):
        for attributes in [
            {"url": "https://example.com/Periodic.dmg"},
            {"length": "1"},
            {"sparkle:edSignature": ""},
            {"sparkle:edSignature": base64.b64encode(b"x" * 32).decode()},
        ]:
            with self.subTest(attributes=attributes):
                self.write_feed(**attributes)
                with self.assertRaises(ValueError):
                    release.validate_appcast(self.feed, self.dmg, "1.0.0", "1")

    def test_rejects_changed_archive_size_after_feed_generation(self):
        self.dmg.write_bytes(b"changed archive content")
        with self.assertRaisesRegex(ValueError, "length"):
            release.validate_appcast(self.feed, self.dmg, "1.0.0", "1")

    def test_rejects_duplicate_builds_or_wrong_system_requirement(self):
        tree = ET.parse(self.feed)
        channel = tree.find("channel")
        channel.append(ET.fromstring(ET.tostring(channel.find("item"))))
        tree.write(self.feed)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            release.validate_appcast(self.feed, self.dmg, "1.0.0", "1")
        self.write_feed()
        self.feed.write_text(self.feed.read_text().replace(">26.0<", ">12.0<"))
        with self.assertRaisesRegex(ValueError, "macOS 26.0"):
            release.validate_appcast(self.feed, self.dmg, "1.0.0", "1")

    def test_requires_increasing_build_number(self):
        release.validate_next_build(self.feed, "2")
        for build in ["0", "1"]:
            with self.subTest(build=build):
                with self.assertRaisesRegex(ValueError, "greater than"):
                    release.validate_next_build(self.feed, build)

    def test_rejects_missing_or_incorrect_hardware_requirement(self):
        for replacement in ["", "<sparkle:hardwareRequirements>x86_64</sparkle:hardwareRequirements>"]:
            with self.subTest(replacement=replacement):
                self.write_feed()
                self.feed.write_text(self.feed.read_text().replace(
                    "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>",
                    replacement
                ))
                with self.assertRaisesRegex(ValueError, "Apple silicon"):
                    release.validate_appcast(self.feed, self.dmg, "1.0.0", "1")

    def test_rejects_previous_feed_without_numeric_build_number(self):
        for version in ["", "1.0.0"]:
            with self.subTest(version=version):
                self.write_feed()
                self.feed.write_text(self.feed.read_text().replace(
                    "<sparkle:version>1</sparkle:version>",
                    f"<sparkle:version>{version}</sparkle:version>"
                ))
                with self.assertRaisesRegex(ValueError, "numeric"):
                    release.validate_next_build(self.feed, "2")


if __name__ == "__main__":
    unittest.main()
