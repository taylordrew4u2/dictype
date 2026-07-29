#!/usr/bin/env bash
#
# build.sh — compile DicType and assemble DicType.app.
#
# Xcode.app is NOT required. The Apple Command Line Tools provide the Swift
# compiler and the macOS SDK, and that is all this script uses:
#
#     xcode-select --install
#
# Usage:
#     bash build.sh
#
# Environment:
#     SIGN_IDENTITY   Signing identity. Defaults to "-" (ad-hoc). Set to a
#                     "Developer ID Application: ..." string for a real one.
#     HARDENED        1 to sign with the hardened runtime and entitlements.
#                     Only meaningful with a real Developer ID identity.
#     APP_VERSION     Overrides CFBundleShortVersionString in the built bundle.
#     BUILD_NUMBER    Overrides CFBundleVersion in the built bundle.
#     UNIVERSAL       1 (default) builds arm64 + x86_64. 0 builds native only.
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="DicType"
BUNDLE="${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
HARDENED="${HARDENED:-0}"
UNIVERSAL="${UNIVERSAL:-1}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
say()  { printf "%s▸ %s%s\n" "$BOLD" "$1" "$RESET"; }
note() { printf "%s  %s%s\n" "$DIM" "$1" "$RESET"; }
die()  { printf "\nError: %s\n" "$1" >&2; exit 1; }

# --- environment checks ------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only — DicType links against AppKit, AVFoundation and Speech."

if ! command -v swift >/dev/null 2>&1; then
  die "The Swift compiler was not found.

       Install the Apple Command Line Tools (this is not Xcode; it is a
       much smaller download and needs no Apple ID):

           xcode-select --install

       If you would rather not build at all, download the prebuilt
       DicType.dmg from the Releases page instead."
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MACOS_MAJOR >= 13 )) || die "macOS 13 Ventura or newer required. Found $(sw_vers -productVersion)."

# --- compile -----------------------------------------------------------------

# Multiple --arch flags make SwiftPM emit a universal binary, so one DMG runs
# natively on both Apple Silicon and Intel.
#
# macOS still ships bash 3.2, where expanding an empty array under `set -u`
# aborts the script. ${arr[@]+"${arr[@]}"} expands to nothing when the array is
# empty and to the quoted elements otherwise, on both 3.2 and modern bash.
ARCH_FLAGS=()
if [[ "$UNIVERSAL" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

say "Compiling release binary"
if ! swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}; then
  if (( ${#ARCH_FLAGS[@]} > 0 )); then
    note "Universal build failed; retrying for this machine's architecture only."
    ARCH_FLAGS=()
    swift build -c release || die "Compilation failed."
  else
    die "Compilation failed."
  fi
fi

# --show-bin-path must be given the same flags as the build, or it reports the
# wrong directory for a universal build.
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
BIN="${BIN_DIR}/${APP_NAME}"
[[ -x "$BIN" ]] || die "Build produced no binary at ${BIN}."

if command -v lipo >/dev/null 2>&1; then
  note "architectures: $(lipo -archs "$BIN" 2>/dev/null || echo unknown)"
fi

# --- assemble the bundle -----------------------------------------------------

say "Assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

cp "$BIN" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# CFBundleIconFile points at AppIcon, which macOS resolves to AppIcon.icns.
# The SVG is the source artwork and is not readable by macOS at runtime.
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
else
  die "Resources/AppIcon.icns is missing. Regenerate it with: python3 tools/make-icon.py"
fi

if [[ -n "${APP_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" \
    "${BUNDLE}/Contents/Info.plist"
  note "version: ${APP_VERSION}"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" \
    "${BUNDLE}/Contents/Info.plist"
fi

# --- sign --------------------------------------------------------------------

# Signing is mandatory, not optional. macOS keys Accessibility and Microphone
# grants to the bundle's code signature; an unsigned bundle is identified only
# by its path, so the permissions the user grants do not reliably stick.
# An ad-hoc signature ("-") needs no certificate and no Apple account.
command -v codesign >/dev/null 2>&1 || die "codesign not found. Install the Command Line Tools: xcode-select --install"

CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$HARDENED" == "1" ]]; then
  say "Signing with the hardened runtime"
  CODESIGN_ARGS+=(--options runtime --timestamp --entitlements Resources/DicType.entitlements)
elif [[ "$SIGN_IDENTITY" == "-" ]]; then
  say "Signing (ad-hoc)"
  note "no certificate needed; gives the app a stable identity for permissions"
else
  say "Signing as ${SIGN_IDENTITY}"
fi

codesign "${CODESIGN_ARGS[@]}" "$BUNDLE"
codesign --verify --strict "$BUNDLE" || die "Signature verification failed."

printf "\n%s%s✓ %s built%s\n" "$GREEN" "$BOLD" "$BUNDLE" "$RESET"
note "$(cd "$(dirname "$BUNDLE")" && pwd)/${BUNDLE}"
