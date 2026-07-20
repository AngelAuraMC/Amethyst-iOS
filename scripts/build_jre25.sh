#!/usr/bin/env bash
# Downloads our iOS-built OpenJDK 25 from the vibecodest/Amethyst-iOS release
# (built by .github/workflows/build-ios-jdk25.yml from OpenJDK source +
# scripts/jdk25_ios_fixups.py — actual iOS-targeted compile, not retag).
#
# Earlier revision retagged macOS Adoptium binaries; that approach didn't work
# because OpenJDK has macOS-specific code paths that fail at iOS runtime.
# This version uses a real iOS-targeted build.

set -euo pipefail

JRE_URL="${JRE_URL:-https://assets.angelauramc.dev/openjdk/ios-arm64/jre25-ios-aarch64.zip}"
DEST_DIR="${DEST_DIR:-$(cd "$(dirname "$0")/.." && pwd)/depends/java-25-openjdk}"
WORK_DIR="${WORK_DIR:-$(mktemp -d -t jre25-XXXXXX)}"

if [ -f "$DEST_DIR/release" ] && [ -f "$DEST_DIR/lib/server/libjvm.dylib" ]; then
    echo "[jre25] $DEST_DIR already present, skipping download"
    exit 0
fi

echo "[jre25] downloading iOS-built OpenJDK 25 from release..."
echo "[jre25]   $JRE_URL"
curl -L --fail -o "$WORK_DIR/jre25.tar.xz" "$JRE_URL"

mkdir -p "$DEST_DIR"
echo "[jre25] extracting to $DEST_DIR..."
tar xf "$WORK_DIR/jre25.tar.xz" -C "$DEST_DIR"

# Sanity check: libjvm.dylib must exist and be tagged iOS.
JVM="$DEST_DIR/lib/server/libjvm.dylib"
JLI="$DEST_DIR/lib/libjli.dylib"
for required in "$JVM" "$JLI"; do
    if [ ! -f "$required" ]; then
        echo "[jre25] ERROR: required dylib missing: $required"
        find "$DEST_DIR" -name "libjvm*.dylib" -o -name "libjli*.dylib" 2>/dev/null
        exit 1
    fi
done

# Verify it's an iOS Mach-O (not macOS retag).
if vtool -show "$JVM" 2>/dev/null | grep -q "platform IOS"; then
    echo "[jre25] confirmed: libjvm.dylib has platform IOS"
else
    echo "[jre25] WARNING: libjvm.dylib is not tagged as iOS. vtool output:"
    vtool -show "$JVM" || true
fi

rm -rf "$WORK_DIR"
echo "[jre25] done. Final size:"
du -sh "$DEST_DIR"
