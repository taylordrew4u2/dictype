#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, staple, and package DicType for distribution.
#
# One-time setup (see README):
#   1. Create a "Developer ID Application" certificate and install it in your keychain.
#   2. Store notarization credentials once:
#        xcrun notarytool store-credentials "dictype" \
#          --apple-id "you@example.com" \
#          --team-id "ABCDE12345" \
#          --password "abcd-efgh-ijkl-mnop"     # app-specific password
#
# Then, every release:
#   bash release.sh
#
set -euo pipefail

APP_NAME="DicType"
BUNDLE="${APP_NAME}.app"
ASSETS_DIR="${ASSETS_DIR:-../assets}"
DMG="${ASSETS_DIR}/${APP_NAME}.dmg"
ZIP="${ASSETS_DIR}/${APP_NAME}.zip"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-dictype}"
VOLUME_NAME="${APP_NAME}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
say()  { printf "\n%s▸ %s%s\n" "$BOLD" "$1" "$RESET"; }
note() { printf "%s  %s%s\n" "$DIM" "$1" "$RESET"; }
warn() { printf "%s  %s%s\n" "$YELLOW" "$1" "$RESET"; }
die()  { printf "\nError: %s\n" "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
command -v swift >/dev/null 2>&1 || die "Swift not found. Run: xcode-select --install"
command -v xcrun >/dev/null 2>&1 || die "Xcode command line tools not found."
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found. Install Xcode Command Line Tools."

# --- 1. locate signing identity ----------------------------------------------

say "Locating Developer ID certificate"

if [[ -n "${DEV_ID:-}" ]]; then
  IDENTITY="$DEV_ID"
else
  IDENTITY="$(security find-identity -v -p codesigning \
              | grep "Developer ID Application" \
              | head -n 1 \
              | sed -E 's/.*"(.+)".*/\1/')" || true
fi

[[ -n "${IDENTITY:-}" ]] || die "No 'Developer ID Application' certificate found.
       Create one at developer.apple.com/account/resources/certificates
       or via Xcode > Settings > Accounts > Manage Certificates.
       Then rerun, or set DEV_ID=\"Developer ID Application: Your Name (TEAMID)\"."

note "$IDENTITY"

# --- 2. verify notary credentials --------------------------------------------

say "Checking notarization credentials"

if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" \
     >/dev/null 2>&1; then
  die "No stored credentials under profile '$KEYCHAIN_PROFILE'.
       Run this once:
         xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\
           --apple-id \"you@example.com\" \\
           --team-id \"YOURTEAMID\" \\
           --password \"app-specific-password\""
fi
note "profile '$KEYCHAIN_PROFILE' is valid"

# --- 3. build ----------------------------------------------------------------

say "Compiling release binary"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
[[ -x "$BIN" ]] || die "Build produced no binary."

say "Assembling ${BUNDLE}"
mkdir -p "$ASSETS_DIR"
rm -rf "$BUNDLE" "$DMG" "$ZIP"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$BIN" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.svg "${BUNDLE}/Contents/Resources/AppIcon.svg"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# --- 4. sign with hardened runtime -------------------------------------------

say "Signing with hardened runtime"
codesign --force --options runtime --timestamp \
         --entitlements Resources/DicType.entitlements \
         --sign "$IDENTITY" \
         "$BUNDLE"

codesign --verify --strict --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/  /'

# --- 5. notarize the app -----------------------------------------------------

say "Submitting app for notarization (this usually takes 1–5 minutes)"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

xcrun notarytool submit "$ZIP" \
      --keychain-profile "$KEYCHAIN_PROFILE" \
      --wait

say "Stapling ticket to app"
xcrun stapler staple "$BUNDLE"
rm -f "$ZIP"

# --- 6. build the DMG --------------------------------------------------------

say "Building drag-to-install disk image"
STAGING="$(mktemp -d)"
mkdir -p "$STAGING/$APP_NAME"
cp -R "$BUNDLE" "$STAGING/$APP_NAME/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$VOLUME_NAME" \
               -srcfolder "$STAGING" \
               -ov -format UDZO \
               "$DMG" >/dev/null
rm -rf "$STAGING"

[[ -f "$DMG" ]] || die "DMG was not created."

say "Signing disk image"
codesign --force --sign "$IDENTITY" "$DMG"

say "Submitting disk image for notarization"
xcrun notarytool submit "$DMG" \
      --keychain-profile "$KEYCHAIN_PROFILE" \
      --wait

say "Stapling ticket to disk image"
xcrun stapler staple "$DMG"

# --- 7. verify ---------------------------------------------------------------

say "Verifying Gatekeeper acceptance"
spctl --assess --type execute --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/  /'

# --- 8. ship-ready zip for GitHub Releases -----------------------------------

ditto -c -k --keepParent "$BUNDLE" "$ZIP"

printf "\n%s%s✓ Release ready%s\n\n" "$GREEN" "$BOLD" "$RESET"
cat <<EOS
  ${DMG}   drag-to-Applications installer
  ${ZIP}   plain app archive

Attach both to a GitHub release:

  gh release create v1.0.0 ${DMG} ${ZIP} \\
     --title "DicType 1.0.0" \\
     --notes "Speak, and watch it type."

Both are notarized. Users double-click. No right-click, no warnings.
EOS
