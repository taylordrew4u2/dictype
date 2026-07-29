#!/usr/bin/env bash
#
# build-dmg.sh — build DicType.app and package it into a drag-to-Applications DMG.
#
# Xcode.app is NOT required; the Command Line Tools are enough. See build.sh.
#
# Usage:
#     bash build-dmg.sh
#
# Environment is passed straight through to build.sh (SIGN_IDENTITY, HARDENED,
# APP_VERSION, BUILD_NUMBER, UNIVERSAL). OUTPUT_DIR sets where the DMG lands.
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="DicType"
BUNDLE="${APP_NAME}.app"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
DMG="${OUTPUT_DIR}/${APP_NAME}.dmg"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
say()  { printf "%s▸ %s%s\n" "$BOLD" "$1" "$RESET"; }
note() { printf "%s  %s%s\n" "$DIM" "$1" "$RESET"; }
die()  { printf "\nError: %s\n" "$1" >&2; exit 1; }

command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found. This script only runs on macOS."

bash build.sh

[[ -d "$BUNDLE" ]] || die "${BUNDLE} was not produced."

say "Building ${APP_NAME}.dmg"
mkdir -p "$OUTPUT_DIR"
rm -f "$DMG"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# The app and the Applications symlink both sit at the root of the disk image.
# Nesting the app inside a subfolder — as this script previously did — means the
# user opens the DMG and sees a folder instead of something they can drag across.
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING" \
               -fs HFS+ \
               -ov -format UDZO \
               "$DMG" >/dev/null

[[ -f "$DMG" ]] || die "DMG was not created."

if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
  say "Signing disk image"
  codesign --force --sign "${SIGN_IDENTITY}" "$DMG"
fi

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
printf "\n%s%s✓ %s built (%s)%s\n\n" "$GREEN" "$BOLD" "$DMG" "$SIZE" "$RESET"

cat <<EOS
Install it:

  1. Open ${DMG}
  2. Drag ${APP_NAME} onto the Applications shortcut
  3. Launch DicType from Applications

This build is ad-hoc signed, not notarised by Apple. macOS quarantines files
downloaded from the internet, so a DMG built here and then transferred to
another Mac needs the quarantine flag cleared once:

  xattr -dr com.apple.quarantine /Applications/${BUNDLE}

A DMG you built and opened on this machine is not quarantined and needs no
such step.
EOS
