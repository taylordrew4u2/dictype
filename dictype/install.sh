#!/usr/bin/env bash
set -euo pipefail

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
INSTALL_DIR="/usr/local/bin"

say() { printf "%s%s%s\n" "$BOLD" "$1" "$RESET"; }
note() { printf "%s%s%s\n" "$DIM" "$1" "$RESET"; }
die() { printf "Error: %s\n" "$1" >&2; exit 1; }

# 1. Environment checks -------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."

if ! command -v swift >/dev/null 2>&1; then
  die "Swift not found. Install Xcode Command Line Tools first:
       xcode-select --install"
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( MACOS_MAJOR < 13 )); then
  die "macOS 13 or newer required. Found $(sw_vers -productVersion)."
fi

# 2. Build --------------------------------------------------------------------

say "Building dictype..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/dictype"
[[ -x "$BIN_PATH" ]] || die "Build produced no binary."

# 3. Install ------------------------------------------------------------------

say "Installing to $INSTALL_DIR..."
if [[ -w "$INSTALL_DIR" ]]; then
  install -m 755 "$BIN_PATH" "$INSTALL_DIR/dictype"
else
  note "Administrator password required to write to $INSTALL_DIR."
  sudo install -m 755 "$BIN_PATH" "$INSTALL_DIR/dictype"
fi

say "Installed: $INSTALL_DIR/dictype"

# 4. Permissions --------------------------------------------------------------

cat <<'EOS'

────────────────────────────────────────────────────────────
ONE-TIME PERMISSIONS

dictype runs inside your terminal, so macOS assigns the
permissions to the terminal app itself (Terminal or iTerm).

Add your terminal app to all three lists:

  1. Microphone
  2. Speech Recognition
  3. Accessibility

Quit and reopen your terminal afterward, or the permissions
will not take effect.
────────────────────────────────────────────────────────────

EOS

read -r -p "Open those Settings panes now? [y/N] " reply
if [[ "${reply:-N}" =~ ^[Yy]$ ]]; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
  sleep 1
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
  sleep 1
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi

say "Done. Run it with:  dictype"
