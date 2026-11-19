#!/bin/bash
set -euo pipefail

mode="$1"
source_dir="$2"
work_dir="$3"
sdk_path="${4:-}"
configuration="${5:-Debug}"

# MIT idevice FFI, pinned to the same header and static library used by StikDebug.
revision=7a80dfce28eeb501faca6498d1746949ac921e74
cache="$source_dir/depends/ondevice-pairing/$revision"
framework="$work_dir/AmethystPairing.framework"
app="$work_dir/AngelAuraAmethyst.app"

case "$mode" in
    build)
        mkdir -p "$cache"
        for name in idevice.h libidevice_ffi.a; do
            if [ "$name" = idevice.h ]; then
                expected=696286794e8cf1c18a91d4dab5046cef4d9bae352f5e7a1ad33fbc0ba30d7ab4
            else
                expected=4db23fe1d342927b9480bb9a8577f219994365621dc28aa0018e23ea1990ecc8
            fi
            if [ ! -f "$cache/$name" ]; then
                curl --fail --location --retry 3 \
                    "https://raw.githubusercontent.com/StikDebug/StikDebug/$revision/StikDebug/idevice/$name" \
                    --output "$cache/$name.part"
                mv "$cache/$name.part" "$cache/$name"
            fi
            actual="$(shasum -a 256 "$cache/$name" | cut -d ' ' -f 1)"
            if [ "$actual" != "$expected" ]; then
                echo "On-device pairing $name checksum mismatch." >&2
                exit 1
            fi
        done
        rm -rf "$framework"
        mkdir -p "$framework"
        optimization=-O0
        if [ "$configuration" = Release ]; then optimization=-O2; fi
        xcrun --sdk iphoneos clang -target arm64-apple-ios17.4 -isysroot "$sdk_path" \
            -fobjc-arc -fblocks "$optimization" -dynamiclib -Wl,-dead_strip \
            -I "$cache" "$source_dir/JITPairing/AmethystPairing.m" "$cache/libidevice_ffi.a" \
            -framework Foundation -framework UIKit -framework AVFoundation \
            -framework UserNotifications -framework Security -framework SystemConfiguration \
            -liconv -lresolv -lz \
            -install_name @rpath/AmethystPairing.framework/AmethystPairing \
            -o "$framework/AmethystPairing"
        python3 - "$framework/Info.plist" "$app/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
host = plistlib.loads(Path(sys.argv[2]).read_bytes())
info = {
    "CFBundleIdentifier": host["CFBundleIdentifier"] + ".Pairing",
    "CFBundleExecutable": "AmethystPairing",
    "CFBundleName": "AmethystPairing",
    "CFBundlePackageType": "FMWK",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleVersion": host["CFBundleVersion"],
    "CFBundleShortVersionString": host["CFBundleShortVersionString"],
    "MinimumOSVersion": "17.4",
}
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
        ;;
    embed)
        mkdir -p "$app/Frameworks"
        rm -rf "$app/Frameworks/AmethystPairing.framework"
        cp -R "$framework" "$app/Frameworks/"
        ;;
    *) echo "Usage: $0 build|embed SOURCE_DIR WORK_DIR [SDK_PATH] [Debug|Release]" >&2; exit 2 ;;
esac
