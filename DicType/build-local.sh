#!/usr/bin/env bash
#
# Builds DicType.app as a local development bundle.
# This standalone script does not require Xcode or a signing certificate.
# Use SIGN_BUILD=1 to apply an optional ad-hoc signature.
#
#   bash build-local.sh
#   SIGN_BUILD=1 bash build-local.sh
#
set -euo pipefail

APP_NAME="DicType"
BUNDLE="${APP_NAME}.app"
BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RESET=$'\033[0m'

say()  { printf "%s%s%s\n" "$BOLD" "$1" "$RESET"; }
note() { printf "%s%s%s\n" "$DIM" "$1" "$RESET"; }
die()  { printf "Error: %s\n" "$1" >&2; exit 1; }

# --- checks ------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
command -v swift >/dev/null 2>&1 || die "Swift not found. Install a Swift toolchain from swift.org or Xcode."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MACOS_MAJOR >= 13 )) || die "macOS 13 or newer required. Found $(sw_vers -productVersion)."

# --- build -------------------------------------------------------------------
say "Compiling..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
[[ -x "$BIN" ]] || die "Build produced no binary."

# --- assemble bundle ---------------------------------------------------------
say "Assembling ${BUNDLE}..."
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

cp "$BIN" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.svg "${BUNDLE}/Contents/Resources/AppIcon.svg"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# --- sign --------------------------------------------------------------------
if [[ "${SIGN_BUILD:-0}" == "1" ]]; then
  if command -v codesign >/dev/null 2>&1; then
    say "Signing (ad-hoc)..."
    if ! codesign --force --deep --sign - "$BUNDLE" 2>/dev/null; then
      note "codesign failed; continuing unsigned."
    fi
  else
    note "codesign not found; continuing unsigned."
  fi
else
  note "Skipping codesign; build remains unsigned."
fi

# --- done --------------------------------------------------------------------
printf "\n%s%s built.%s\n\n" "$GREEN$BOLD" "$BUNDLE" "$RESET"

cat <<EOS
Next:

  1. Drag ${BUNDLE} into your Applications folder.
  2. Double-click it. The app walks you through the rest.

To share it, zip the bundle and attach it to a GitHub release:

  ditto -c -k --keepParent ${BUNDLE} ${APP_NAME}.zip

EOS

read -r -p "Open the folder now? [y/N] " reply
[[ "${reply:-N}" =~ ^[Yy]$ ]] && open .
exit 0
