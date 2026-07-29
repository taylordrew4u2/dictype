#!/usr/bin/env bash
#
# Builds DicType.app — a real, double-clickable Mac application.
# You only need to run this once. Afterwards you can drag the app
# to Applications and forget the terminal exists.
#
#   bash build-app.sh
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

command -v swift >/dev/null 2>&1 || die "Swift not found. Run: xcode-select --install"

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
# Ad-hoc signature. Free, and gives the app a stable identity so macOS
# remembers its permissions instead of re-asking after every launch.

say "Signing (ad-hoc)..."
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null \
  || note "codesign unavailable; continuing unsigned."

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
