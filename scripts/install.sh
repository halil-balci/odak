#!/usr/bin/env bash
# Builds Odak from source and installs it. Usage: scripts/install.sh
# Safe to re-run: it replaces an existing install. Built on this Mac, so macOS shows no Gatekeeper prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "the Odak app needs macOS. On Windows/Linux use the browser extension in chrome-extension/ (see AGENTS.md)."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "Odak needs macOS 14 (Sonoma) or later; this Mac has $(sw_vers -productVersion)."
# Swift comes with Xcode or Apple's Command Line Tools. /usr/bin/swift exists even without them,
# so check xcode-select instead of running swift (which would just pop up the install dialog and fail).
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Swift is not installed. Opening Apple's Command Line Tools installer;"
    echo "click Install in the dialog that appears (download takes a few minutes)."
    xcode-select --install >/dev/null 2>&1 || true
    for _ in $(seq 360); do   # wait up to 60 minutes
        xcode-select -p >/dev/null 2>&1 && break
        sleep 10
    done
    xcode-select -p >/dev/null 2>&1 || fail "Command Line Tools are still not installed. Finish the installer, then run this script again."
fi
swift_version="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9]*\).*/\1/p' | head -1)"
(( ${swift_version:-0} >= 6 )) || fail "Odak needs Swift 6 or later (found: ${swift_version:-none}). Update Xcode or the Command Line Tools in System Settings › General › Software Update, then run this script again."

scripts/build-app.sh

# /Applications when writable, otherwise the per-user Applications folder (no sudo needed).
DEST=/Applications
[[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
osascript -e 'quit app "Odak"' >/dev/null 2>&1 || true
rm -rf "$DEST/Odak.app"
cp -R build/Odak.app "$DEST/"

# Register the app so "Read with Odak" shows up in the Services / right-click menu.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Odak.app" 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true
open "$DEST/Odak.app"

cat <<EOF

Odak is installed in $DEST and running.
- Select text in any app, right-click › Services › Read with Odak.
  If it is missing: System Settings › Keyboard › Keyboard Shortcuts… › Services › Text › enable "Read with Odak".
- Optional browser extension: chrome://extensions › Developer mode › Load unpacked › choose
  $(pwd)/chrome-extension
EOF
