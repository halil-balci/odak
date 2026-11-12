#!/usr/bin/env bash
# Builds build/Odak.app. Usage: scripts/build-app.sh [--zip | --release]
#   (no flag)  ad-hoc signed app, fine for running on this Mac
#   --zip      also creates build/Odak.zip
#   --release  maintainers only: Developer ID signs, notarizes and staples, then zips.
#              Needs a "Developer ID Application" identity in the keychain and a notarytool
#              keychain profile (env NOTARY_PROFILE, default "odak-notary"; SIGN_IDENTITY overrides the identity).
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"
case "$MODE" in ""|--zip|--release) ;; *) echo "usage: $0 [--zip | --release]" >&2; exit 2 ;; esac

APP=build/Odak.app

# Universal binary when the toolchain supports it, otherwise native arch.
if swift build -c release --arch arm64 --arch x86_64; then
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Odak"
else
    echo "warning: universal build failed, building for $(uname -m) only" >&2
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/Odak"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Odak"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

codesign --force --deep -s - "$APP"
codesign -v "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Odak"))"

make_zip() {
    rm -f build/Odak.zip
    ditto -c -k --norsrc --noextattr --keepParent "$APP" build/Odak.zip
}

if [[ "$MODE" == "--release" ]]; then
    IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
    PROFILE="${NOTARY_PROFILE:-odak-notary}"
    [[ -n "$IDENTITY" ]] || { echo "error: no 'Developer ID Application' identity in the keychain" >&2; exit 1; }
    echo "Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP"
    codesign --verify --strict "$APP"
    make_zip
    # --wait returns 0 even when Apple rejects the build, so check the status explicitly.
    RESULT="$(xcrun notarytool submit build/Odak.zip --keychain-profile "$PROFILE" --wait)"
    echo "$RESULT"
    if ! grep -q "status: Accepted" <<<"$RESULT"; then
        ID="$(awk '/^ *id:/ {print $2; exit}' <<<"$RESULT")"
        echo "error: notarization failed; see: xcrun notarytool log $ID --keychain-profile $PROFILE" >&2
        exit 1
    fi
    xcrun stapler staple "$APP"
    make_zip  # re-zip so the shipped app carries the stapled ticket
    spctl -a -t install -vv "$APP"
    echo "Created notarized build/Odak.zip"
elif [[ "$MODE" == "--zip" ]]; then
    make_zip
    echo "Created build/Odak.zip"
fi
