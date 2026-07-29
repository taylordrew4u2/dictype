#!/usr/bin/env bash
#
# Builds DicType.app and packages it into a drag-to-Applications DMG.
# This is a standalone local packaging script. It does not require Xcode.
# Use SIGN_BUILD=1 to apply an optional ad-hoc signature to the app.
#
#   bash build-dmg.sh
#   SIGN_BUILD=1 bash build-dmg.sh
#
set -euo pipefail

APP_NAME="DicType"
BUNDLE="${APP_NAME}.app"
DMG="${APP_NAME}.dmg"
BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RESET=$'\033[0m'

say()  { printf "%s%s%s\n" "$BOLD" "$1" "$RESET"; }
note() { printf "%s%s%s\n" "$DIM" "$1" "$RESET"; }
die()  { printf "Error: %s\n" "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
command -v swift >/dev/null 2>&1 || die "Swift not found. Install a Swift toolchain from swift.org or Xcode."
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MACOS_MAJOR >= 13 )) || die "macOS 13 or newer required. Found $(sw_vers -productVersion)."

say "Compiling..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
[[ -x "$BIN" ]] || die "Build produced no binary."

say "Assembling ${BUNDLE}..."
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$BIN" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.svg "${BUNDLE}/Contents/Resources/AppIcon.svg"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

if [[ "${SIGN_BUILD:-0}" == "1" ]]; then
  if command -v codesign >/dev/null 2>&1; then
    say "Signing ${BUNDLE} (ad-hoc)..."
    if ! codesign --force --deep --sign - "$BUNDLE" 2>/dev/null; then
      note "codesign failed; continuing with unsigned app."
    fi
  else
    note "codesign not found; continuing with unsigned app."
  fi
fi

say "Building ${DMG}..."
rm -f "$DMG"
STAGING="$(mktemp -d)"
mkdir -p "$STAGING/$APP_NAME"
cp -R "$BUNDLE" "$STAGING/$APP_NAME/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING" \
               -ov -format UDZO \
               "$DMG" >/dev/null
rm -rf "$STAGING"

printf "\n%s%s built.%s\n" "$GREEN$BOLD" "$DMG" "$RESET"
cat <<EOS
Next:

  1. Open ${DMG}.
  2. Drag ${APP_NAME} into Applications.

EOS

exit 0
