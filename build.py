#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP_NAME = "DicType"
OUT_DIR = ROOT / "build"
DIST_DIR = OUT_DIR / "dist"


def run(cmd, cwd=ROOT):
    print("$", " ".join(cmd))
    completed = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if completed.returncode != 0:
        sys.stderr.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    return completed.stdout


def main():
    shutil.rmtree(OUT_DIR, ignore_errors=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    bundle_dir = DIST_DIR / f"{APP_NAME}.app"
    bundle_dir.mkdir(parents=True, exist_ok=True)
    (bundle_dir / "Contents").mkdir(exist_ok=True)
    (bundle_dir / "Contents" / "MacOS").mkdir(exist_ok=True)
    (bundle_dir / "Contents" / "Resources").mkdir(exist_ok=True)

    script_path = ROOT / "DicType" / "Sources" / "DicType" / "DicTypeApp.swift"
    if not script_path.exists():
        raise SystemExit("Expected Swift source tree not found")

    with open(bundle_dir / "Contents" / "Info.plist", "w", encoding="utf-8") as fh:
        fh.write("""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n  <key>CFBundleExecutable</key>\n  <string>DicType</string>\n  <key>CFBundleIdentifier</key>\n  <string>com.example.dictype</string>\n  <key>CFBundleName</key>\n  <string>DicType</string>\n  <key>CFBundlePackageType</key>\n  <string>APPL</string>\n</dict>\n</plist>\n""")

    with open(bundle_dir / "Contents" / "PkgInfo", "w", encoding="utf-8") as fh:
        fh.write("APPL????")

    wrapper = DIST_DIR / APP_NAME
    wrapper.write_text("#!/usr/bin/env python3\nprint('DicType placeholder build')\n", encoding="utf-8")
    wrapper.chmod(0o755)

    print(f"Built {bundle_dir}")


if __name__ == "__main__":
    main()
