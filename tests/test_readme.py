"""Verifies every link in the README resolves to something real.

The README previously pointed at bare relative paths like `releases` and
`releases/latest`. GitHub resolves those against the current blob path, so they
landed on /blob/main/releases and 404'd. The Releases page lives at a repository
URL, not a file path, so those links have to be absolute.

Run with:  python3 -m unittest discover -s tests
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"

REPO_URL = "https://github.com/taylordrew4u2/dictype"

# [text](target) — ignores images, which are written as ![text](target).
LINK = re.compile(r"(?<!!)\[(?P<text>[^\]]*)\]\((?P<target>[^)\s]+)(?:\s+\"[^\"]*\")?\)")


def links():
    body = README.read_text(encoding="utf-8")
    return [(m.group("text"), m.group("target")) for m in LINK.finditer(body)]


class TestReadmeLinks(unittest.TestCase):

    def setUp(self):
        self.assertTrue(README.is_file(), "README.md is missing")
        self.links = links()
        self.assertTrue(self.links, "no markdown links found — the regex or README changed")

    def test_relative_links_point_at_files_that_exist(self):
        broken = []
        for text, target in self.links:
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            path = (ROOT / target.split("#", 1)[0]).resolve()
            if not path.exists():
                broken.append(f"[{text}]({target})")
        self.assertEqual(broken, [], f"README links point at missing paths: {broken}")

    def test_no_bare_relative_release_links(self):
        # These are the exact links that used to 404.
        bad = [
            f"[{text}]({target})"
            for text, target in self.links
            if target in ("releases", "releases/latest", "releases/latest/download")
            or target.startswith("releases/")
        ]
        self.assertEqual(
            bad,
            [],
            f"release links must be absolute repository URLs, found: {bad}",
        )

    def test_releases_page_is_linked_absolutely(self):
        targets = [t for _, t in self.links]
        self.assertTrue(
            any(t.startswith(f"{REPO_URL}/releases") for t in targets),
            "README should link to the Releases page with an absolute URL",
        )

    def test_dmg_download_link_is_present_and_absolute(self):
        targets = [t for _, t in self.links]
        self.assertTrue(
            any("DicType.dmg" in t and t.startswith("https://") for t in targets),
            "README should offer an absolute direct download link for DicType.dmg",
        )

    def test_license_link_resolves(self):
        targets = {text.lower(): target for text, target in self.links}
        self.assertIn("license", targets, "README should link to the licence")
        target = targets["license"]
        if not target.startswith("http"):
            self.assertTrue(
                (ROOT / target).exists(),
                f"LICENSE link points at {target}, which does not exist",
            )


class TestReadmeClaims(unittest.TestCase):
    """The README should not promise things the build does not do."""

    def setUp(self):
        self.body = README.read_text(encoding="utf-8")

    def test_does_not_claim_the_build_avoids_swift(self):
        # The app is ~850 lines of Swift and SwiftUI; it cannot be built without
        # the Swift compiler.
        lowered = self.body.lower()
        for claim in (
            "no longer depends on swift",
            "no longer requires swift",
            "does not require swift",
        ):
            self.assertNotIn(claim, lowered, f"README still claims: {claim!r}")

    def test_does_not_promise_unsigned_builds_are_warning_free(self):
        # Only notarized builds avoid the Gatekeeper prompt.
        self.assertNotIn("No security warnings, no right-clicking, no terminal", self.body)

    def test_documents_the_quarantine_workaround(self):
        self.assertIn("com.apple.quarantine", self.body)

    def test_references_the_real_build_entry_points(self):
        self.assertIn("build-dmg.sh", self.body)
        self.assertNotIn("python3 build.py", self.body)

    def test_mentions_that_full_xcode_is_not_required(self):
        self.assertIn("xcode-select --install", self.body)


if __name__ == "__main__":
    unittest.main()
