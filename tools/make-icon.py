#!/usr/bin/env python3
"""Render DicType/Resources/AppIcon.svg into a multi-resolution AppIcon.icns.

macOS cannot read SVG icons. CFBundleIconFile resolves to an .icns file, so the
SVG has to be rasterised into the sizes the Finder, Dock and app switcher ask
for and packed into an .icns container.

The generated .icns is committed to the repository, so building the app does not
require this script or its dependencies. Run it only when the SVG changes:

    pip install cairosvg
    python3 tools/make-icon.py

On macOS you can equivalently produce the same file with `iconutil` from an
.iconset directory; this script exists so the icon can also be regenerated on
Linux, where `iconutil` and `sips` are unavailable.
"""

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "DicType" / "Resources" / "AppIcon.svg"
ICNS = ROOT / "DicType" / "Resources" / "AppIcon.icns"

# OSType -> pixel size. These are the PNG-encoded icon types; every one of them
# stores a plain PNG payload, which is what `iconutil` emits for a modern
# .iconset. Types are ordered small to large so the file mirrors Apple's layout.
ENTRIES = [
    (b"icp4", 16),    # 16x16
    (b"icp5", 32),    # 16x16@2x / 32x32
    (b"ic11", 32),    # 16x16@2x
    (b"ic12", 64),    # 32x32@2x
    (b"ic07", 128),   # 128x128
    (b"ic13", 256),   # 128x128@2x
    (b"ic08", 256),   # 256x256
    (b"ic14", 512),   # 256x256@2x
    (b"ic09", 512),   # 512x512
    (b"ic10", 1024),  # 512x512@2x
]


def render(size: int) -> bytes:
    import cairosvg

    return cairosvg.svg2png(
        url=str(SVG),
        output_width=size,
        output_height=size,
    )


def build() -> bytes:
    # Render each distinct size once; several OSTypes share a pixel size.
    cache: dict[int, bytes] = {}
    body = b""
    for ostype, size in ENTRIES:
        if size not in cache:
            cache[size] = render(size)
        png = cache[size]
        body += ostype + struct.pack(">I", len(png) + 8) + png

    return b"icns" + struct.pack(">I", len(body) + 8) + body


def main() -> int:
    if not SVG.exists():
        print(f"error: {SVG} not found", file=sys.stderr)
        return 1

    try:
        import cairosvg  # noqa: F401
    except ImportError:
        print(
            "error: cairosvg is required to regenerate the icon.\n"
            "       pip install cairosvg",
            file=sys.stderr,
        )
        return 1

    data = build()
    ICNS.write_bytes(data)
    print(f"Wrote {ICNS.relative_to(ROOT)} ({len(data):,} bytes, "
          f"{len(ENTRIES)} representations)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
