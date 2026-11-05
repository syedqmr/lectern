#!/bin/bash
# Builds Lectern and wraps the binary in a proper .app bundle.
# A bundle with an Info.plist is required: macOS will not show the microphone
# or speech-recognition permission prompts for a bare command-line binary.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Lectern"

APP="build/Lectern.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lectern"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature (no hardened runtime, so no audio-input entitlement is needed).
codesign --force --sign - "$APP"

echo ""
echo "Built: $(pwd)/$APP"
echo "Run:   open \"$APP\""
