#!/bin/bash
set -euo pipefail
INPUT_IPA="${1:-Input.ipa}"
OUTPUT_IPA="raptor.ipa"
DYLIB="Tweak/.theos/obj/raptor.dylib"
if [ ! -f "$Tweak/.theos/obj/raptor.dylib" ]; then DYLIB="obj/raptor.dylib"; fi
cd "$(dirname "$0")/.."
echo "[1/5] Building dylib..."
make -C Tweak clean all
DYLIB="$(find Tweak/.theos/obj -name "*.dylib" | head -n 1)"
[ -z "$DYLIB" ] && { echo "no dylib"; exit 1; }
WORKDIR="$(mktemp -d)"; echo "[2/5] Extracting $INPUT_IPA -> $WORKDIR"
unzip -q "$INPUT_IPA" -d "$WORKDIR"
APP="$(ls -d "$WORKDIR"/Payload/*.app | head -n 1)"
BIN="$APP/$(basename "$APP" .app)"; [ ! -f "$BIN" ] && BIN="$APP/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Info.plist")"
mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/raptor.dylib"
if command -v insert_dylib >/dev/null; then insert_dylib --strip-codesig --inplace "@executable_path/Frameworks/raptor.dylib" "$BIN"; else python3 Tweak/inject_dylib.py "$BIN" "$APP/Frameworks/raptor.dylib"; fi
for fw in "$APP/Frameworks/"*.dylib; do [ -f "$fw" ] && codesign --force --sign - "$fw" || true; done
codesign --force --sign - "$BIN"
zip -r -q "$OUTPUT_IPA" -C "$WORKDIR" Payload/
echo "[5/5] -> $OUTPUT_IPA"

