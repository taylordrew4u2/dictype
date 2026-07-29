#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, staple and package DicType for public
# distribution. Maintainer only; requires an Apple Developer Program membership.
#
# Most people do not need this. `bash build-dmg.sh` produces a working,
# ad-hoc-signed DMG with no certificate and no Apple account. This script only
# adds Apple notarization, which is what removes the Gatekeeper warning for
# people downloading the DMG from the internet.
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

cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="DicType"
BUNDLE="${APP_NAME}.app"
OUTPUT_DIR="${OUTPUT_DIR:-../assets}"
DMG="${OUTPUT_DIR}/${APP_NAME}.dmg"
ZIP="${OUTPUT_DIR}/${APP_NAME}.zip"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-dictype}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
say()  { printf "\n%s▸ %s%s\n" "$BOLD" "$1" "$RESET"; }
note() { printf "%s  %s%s\n" "$DIM" "$1" "$RESET"; }
die()  { printf "\nError: %s\n" "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
command -v swift >/dev/null 2>&1 || die "Swift not found. Run: xcode-select --install"
command -v xcrun >/dev/null 2>&1 || die "Command Line Tools not found. Run: xcode-select --install"
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found. Run: xcode-select --install"

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
       Then rerun, or set DEV_ID=\"Developer ID Application: Your Name (TEAMID)\".

       If you only want a DMG for yourself, use build-dmg.sh instead — it
       needs no certificate."

note "$IDENTITY"

# --- 2. verify notary credentials --------------------------------------------

say "Checking notarization credentials"

if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  die "No stored credentials under profile '$KEYCHAIN_PROFILE'.
       Run this once:
         xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\
           --apple-id \"you@example.com\" \\
           --team-id \"YOURTEAMID\" \\
           --password \"app-specific-password\""
fi
note "profile '$KEYCHAIN_PROFILE' is valid"

# --- 3. build and sign with the hardened runtime -----------------------------

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG" "$ZIP"

SIGN_IDENTITY="$IDENTITY" HARDENED=1 bash build.sh

# --- 4. notarize the app -----------------------------------------------------

say "Submitting app for notarization (this usually takes 1–5 minutes)"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

xcrun notarytool submit "$ZIP" \
      --keychain-profile "$KEYCHAIN_PROFILE" \
      --wait

say "Stapling ticket to app"
xcrun stapler staple "$BUNDLE"
rm -f "$ZIP"

# --- 5. build the DMG --------------------------------------------------------

say "Building drag-to-install disk image"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# App and Applications symlink both live at the root of the image so the user
# can drag one onto the other the moment the DMG opens.
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING" \
               -fs HFS+ \
               -ov -format UDZO \
               "$DMG" >/dev/null

[[ -f "$DMG" ]] || die "DMG was not created."

say "Signing disk image"
codesign --force --sign "$IDENTITY" "$DMG"

say "Submitting disk image for notarization"
xcrun notarytool submit "$DMG" \
      --keychain-profile "$KEYCHAIN_PROFILE" \
      --wait

say "Stapling ticket to disk image"
xcrun stapler staple "$DMG"

# --- 6. verify ---------------------------------------------------------------

say "Verifying Gatekeeper acceptance"
spctl --assess --type execute --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/  /'

# --- 7. ship-ready zip for GitHub Releases -----------------------------------

ditto -c -k --keepParent "$BUNDLE" "$ZIP"

printf "\n%s%s✓ Release ready%s\n\n" "$GREEN" "$BOLD" "$RESET"
cat <<EOS
  ${DMG}   drag-to-Applications installer
  ${ZIP}   plain app archive

Attach both to a GitHub release:

  gh release create v1.1.0 ${DMG} ${ZIP} \\
     --title "DicType 1.1.0" \\
     --notes "Speak, and watch it type."

Both are notarized. Users double-click. No right-click, no warnings.
EOS
