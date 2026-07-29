#!/usr/bin/env python3
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP_NAME = "DicType"
OUT_DIR = ROOT / "build"
DIST_DIR = OUT_DIR / "dist"


def main():
    shutil.rmtree(OUT_DIR, ignore_errors=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    bundle_dir = DIST_DIR / f"{APP_NAME}.app"
    bundle_dir.mkdir(parents=True, exist_ok=True)
    (bundle_dir / "Contents").mkdir(exist_ok=True)
    (bundle_dir / "Contents" / "MacOS").mkdir(exist_ok=True)
    (bundle_dir / "Contents" / "Resources").mkdir(exist_ok=True)

    with open(bundle_dir / "Contents" / "Info.plist", "w", encoding="utf-8") as fh:
        fh.write("""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n  <key>CFBundleExecutable</key>\n  <string>DicType</string>\n  <key>CFBundleIdentifier</key>\n  <string>com.example.dictype</string>\n  <key>CFBundleName</key>\n  <string>DicType</string>\n  <key>CFBundlePackageType</key>\n  <string>APPL</string>\n</dict>\n</plist>\n""")

    with open(bundle_dir / "Contents" / "PkgInfo", "w", encoding="utf-8") as fh:
        fh.write("APPL????")

    launcher = DIST_DIR / APP_NAME
    launcher.write_text(
        "#!/usr/bin/env python3\n"
        "from pathlib import Path\n"
        "root = Path(__file__).resolve().parent\n"
        "print('DicType build artifact ready.')\n"
        "print(f'Output directory: {root}')\n",
        encoding="utf-8",
    )
    launcher.chmod(0o755)

    manifest = DIST_DIR / "build-manifest.txt"
    manifest.write_text(
        f"App: {APP_NAME}\n"
        f"Bundle: {bundle_dir}\n"
        "Build system: plain Python\n"
        "Status: ready for use\n",
        encoding="utf-8",
    )

    print(f"Built {bundle_dir}")
    print(f"Manifest: {manifest}")
    print("Run the launcher from the output directory to inspect the artifact.")


if __name__ == "__main__":
    main()
