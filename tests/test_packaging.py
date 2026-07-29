"""Checks on the things that decide whether the shipped DMG actually works.

These run anywhere, including Linux, because they only inspect repository
contents. The macOS-only checks — that the binary compiles, is universal, is
signed, and that the DMG mounts with a draggable layout — live in the CI
workflow, which runs on a real macOS runner.

Run with:  python3 -m unittest discover -s tests
"""

import plistlib
import re
import stat
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DICTYPE = ROOT / "DicType"
RESOURCES = DICTYPE / "Resources"


class TestBundleMetadata(unittest.TestCase):
    """Info.plist decides whether a hand-assembled bundle launches at all."""

    def setUp(self):
        self.plist_path = RESOURCES / "Info.plist"
        self.assertTrue(self.plist_path.is_file(), "Info.plist is missing")
        with open(self.plist_path, "rb") as fh:
            self.plist = plistlib.load(fh)

    def test_required_keys_present(self):
        for key in (
            "CFBundleName",
            "CFBundleIdentifier",
            "CFBundleExecutable",
            "CFBundlePackageType",
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "LSMinimumSystemVersion",
        ):
            self.assertIn(key, self.plist, f"Info.plist is missing {key}")

    def test_principal_class_is_set(self):
        # Without NSPrincipalClass, AppKit does not know what to instantiate as
        # the application object in a bundle assembled by hand rather than Xcode.
        self.assertEqual(self.plist.get("NSPrincipalClass"), "NSApplication")

    def test_executable_name_matches_the_binary_the_build_copies(self):
        self.assertEqual(self.plist["CFBundleExecutable"], "DicType")

    def test_usage_descriptions_present(self):
        # macOS terminates the app instead of prompting if these are absent.
        self.assertIn("NSMicrophoneUsageDescription", self.plist)
        self.assertIn("NSSpeechRecognitionUsageDescription", self.plist)
        for key in ("NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"):
            self.assertTrue(self.plist[key].strip(), f"{key} is empty")

    def test_minimum_system_version_matches_package_swift(self):
        package = (DICTYPE / "Package.swift").read_text(encoding="utf-8")
        self.assertIn(".macOS(.v13)", package)
        self.assertEqual(self.plist["LSMinimumSystemVersion"], "13.0")

    def test_entitlements_parse(self):
        path = RESOURCES / "DicType.entitlements"
        self.assertTrue(path.is_file(), "entitlements file is missing")
        with open(path, "rb") as fh:
            entitlements = plistlib.load(fh)
        self.assertIn("com.apple.security.device.audio-input", entitlements)


class TestAppIcon(unittest.TestCase):
    """macOS cannot read SVG icons; CFBundleIconFile must resolve to an .icns."""

    def test_icns_exists(self):
        self.assertTrue(
            (RESOURCES / "AppIcon.icns").is_file(),
            "AppIcon.icns is missing — regenerate it with: python3 tools/make-icon.py",
        )

    def test_icon_file_key_resolves_to_the_icns(self):
        with open(RESOURCES / "Info.plist", "rb") as fh:
            plist = plistlib.load(fh)
        name = plist["CFBundleIconFile"]
        # CFBundleIconFile may be given with or without the extension.
        stem = name[:-5] if name.endswith(".icns") else name
        self.assertTrue((RESOURCES / f"{stem}.icns").is_file())

    def test_icns_is_a_wellformed_container(self):
        data = (RESOURCES / "AppIcon.icns").read_bytes()
        self.assertEqual(data[:4], b"icns", "not an icns file")
        declared = struct.unpack(">I", data[4:8])[0]
        self.assertEqual(declared, len(data), "icns length header disagrees with file size")

        offset, types = 8, []
        while offset < len(data):
            ostype = data[offset:offset + 4]
            length = struct.unpack(">I", data[offset + 4:offset + 8])[0]
            self.assertGreaterEqual(length, 8, "icns entry shorter than its own header")
            payload = data[offset + 8:offset + length]
            self.assertEqual(payload[:8], b"\x89PNG\r\n\x1a\n", f"{ostype!r} is not a PNG")
            types.append(ostype)
            offset += length
        self.assertEqual(offset, len(data), "trailing bytes after the last icns entry")

        # Retina Dock and Finder sizes. Without the large representations the
        # icon renders blurry or falls back to the generic application icon.
        for required in (b"ic07", b"ic08", b"ic09", b"ic10"):
            self.assertIn(required, types, f"icns is missing the {required.decode()} size")


class TestBuildScripts(unittest.TestCase):

    SCRIPTS = ("build.sh", "build-dmg.sh", "release.sh")

    def read(self, name):
        return (DICTYPE / name).read_text(encoding="utf-8")

    def test_scripts_exist_and_are_executable(self):
        for name in self.SCRIPTS:
            path = DICTYPE / name
            self.assertTrue(path.is_file(), f"{name} is missing")
            self.assertTrue(
                path.stat().st_mode & stat.S_IXUSR,
                f"{name} is not executable",
            )

    def test_placebo_build_is_gone(self):
        # The old build.py emitted an .app with an empty MacOS directory and a
        # Python stub that printed a message. It could never launch.
        self.assertFalse((ROOT / "build.py").exists(), "the placebo build.py is back")

    def test_no_duplicate_or_dead_scripts(self):
        for name in ("build-app.sh", "build-local.sh", "build-release.sh"):
            self.assertFalse(
                (DICTYPE / name).exists(),
                f"{name} was a duplicate or a dead stub and should stay deleted",
            )

    def test_scripts_are_non_interactive(self):
        # `read -p` under `set -euo pipefail` returns non-zero on a closed stdin,
        # so a successful build would exit with a failure status in CI.
        for name in self.SCRIPTS:
            self.assertNotRegex(
                self.read(name),
                r"^\s*read\s+-",
                f"{name} blocks on interactive input",
            )

    def test_signing_is_not_opt_in(self):
        # Permission grants are keyed to the code signature, so signing has to
        # happen by default rather than behind SIGN_BUILD=1.
        body = self.read("build.sh")
        self.assertNotIn("SIGN_BUILD", body, "signing is gated behind an opt-in flag again")
        self.assertIn("codesign", body)
        self.assertIn('SIGN_IDENTITY:--', body, "build.sh should default to an ad-hoc signature")

    def test_dmg_layout_is_flat(self):
        # The app and the Applications symlink must both be at the image root.
        # Copying into "$STAGING/$APP_NAME/" nests the app inside a folder and
        # leaves the user with nothing to drag.
        body = self.read("build-dmg.sh")
        self.assertIn('cp -R "$BUNDLE" "$STAGING/"', body)
        self.assertIn('ln -s /Applications "$STAGING/Applications"', body)
        self.assertNotIn('mkdir -p "$STAGING/$APP_NAME"', body)

    def test_release_script_uses_the_same_flat_layout(self):
        body = self.read("release.sh")
        self.assertIn('cp -R "$BUNDLE" "$STAGING/"', body)
        self.assertNotIn('mkdir -p "$STAGING/$APP_NAME"', body)

    def test_build_script_requires_the_icon(self):
        self.assertIn("AppIcon.icns", self.read("build.sh"))

    def test_scripts_point_at_the_command_line_tools_not_xcode(self):
        # The Command Line Tools are enough; the previous wording sent people to
        # install all of Xcode. build-dmg.sh delegates the toolchain check to
        # build.sh, so only the scripts that check for `swift` need the hint.
        for name in ("build.sh", "release.sh"):
            body = self.read(name)
            self.assertIn("swift", body)
            self.assertIn(
                "xcode-select --install",
                body,
                f"{name} should tell the user to install the Command Line Tools",
            )

    def test_no_script_tells_the_user_to_install_xcode_itself(self):
        for name in self.SCRIPTS:
            self.assertNotIn(
                "swift.org or Xcode",
                self.read(name),
                f"{name} still sends people to install full Xcode",
            )


class TestWorkflows(unittest.TestCase):
    """Without CI producing a DMG, the Releases page has nothing to download."""

    WORKFLOWS = ROOT / ".github" / "workflows"

    def test_workflows_exist(self):
        self.assertTrue((self.WORKFLOWS / "ci.yml").is_file(), "ci.yml is missing")
        self.assertTrue((self.WORKFLOWS / "release.yml").is_file(), "release.yml is missing")

    def test_release_workflow_builds_and_uploads_a_dmg(self):
        body = (self.WORKFLOWS / "release.yml").read_text(encoding="utf-8")
        self.assertIn("macos-14", body, "the DMG has to be built on a macOS runner")
        self.assertIn("build-dmg.sh", body)
        self.assertIn("gh release upload", body)
        self.assertIn("DicType.dmg", body)
        self.assertIn("contents: write", body, "uploading assets needs write permission")

    def test_release_workflow_can_be_run_by_hand(self):
        # Needed to attach a DMG to a release that was published without one.
        body = (self.WORKFLOWS / "release.yml").read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch", body)

    def test_ci_verifies_the_bundle_rather_than_just_building_it(self):
        body = (self.WORKFLOWS / "ci.yml").read_text(encoding="utf-8")
        self.assertIn("codesign --verify", body)
        self.assertIn("hdiutil attach", body)
        self.assertIn("Contents/MacOS/DicType", body)


class TestSwiftSources(unittest.TestCase):

    def test_package_target_path_matches_the_sources(self):
        package = (DICTYPE / "Package.swift").read_text(encoding="utf-8")
        match = re.search(r'path:\s*"([^"]+)"', package)
        self.assertIsNotNone(match, "Package.swift declares no target path")
        self.assertTrue((DICTYPE / match.group(1)).is_dir())

    def test_entry_point_is_not_named_main_swift(self):
        # SwiftPM treats main.swift as top-level code, which conflicts with the
        # @main attribute the SwiftUI App type uses.
        sources = DICTYPE / "Sources" / "DicType"
        self.assertFalse((sources / "main.swift").exists())
        entry = (sources / "DicTypeApp.swift").read_text(encoding="utf-8")
        self.assertIn("@main", entry)


if __name__ == "__main__":
    unittest.main()
