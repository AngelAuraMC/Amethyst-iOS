#!/bin/bash
set -euo pipefail

mode="$1"
source_dir="$2"
work_dir="$3"
sdk_path="${4:-}"
configuration="${5:-Debug}"

version=2.0.1
checksum=c376687326a785f5ed1da8caca08adc709b56919019dd751bca059b92b175d95
cache_dir="$source_dir/depends/stikjit/$version"
framework="$cache_dir/StikJIT.xcframework/ios-arm64/StikJIT.framework"
helper="$work_dir/AmethystJITHelper.appex"
app="$work_dir/AngelAuraAmethyst.app"

case "$mode" in
    build)
        mkdir -p "$cache_dir" "$helper"
        archive="$cache_dir/StikJIT.xcframework.zip"
        if [ ! -f "$archive" ]; then
            curl --fail --location --retry 3 \
                "https://github.com/StikDebug/StikJIT/releases/download/$version/StikJIT.xcframework.zip" \
                --output "$archive.part"
            mv "$archive.part" "$archive"
        fi
        actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
        if [ "$actual" != "$checksum" ]; then
            echo "StikJIT archive checksum mismatch. Remove $archive and retry." >&2
            exit 1
        fi
        unzip -oq "$archive" -d "$cache_dir"
        xcrun --sdk iphoneos clang -target arm64-apple-ios17.4 \
            -isysroot "$sdk_path" -fobjc-arc -fapplication-extension \
            -c "$source_dir/JITHelper/main.m" -o "$work_dir/AmethystJITHelper-main.o"
        optimization=(-Onone -g)
        if [ "$configuration" = Release ]; then optimization=(-O); fi
        xcrun --sdk iphoneos swiftc -sdk "$sdk_path" -target arm64-apple-ios17.4 \
            -swift-version 5 -application-extension -parse-as-library -emit-executable \
            "${optimization[@]}" -F "$(dirname "$framework")" \
            -framework StikJIT -framework UIKit \
            -Xlinker -rpath -Xlinker @executable_path/../../Frameworks \
            -Xlinker -rpath -Xlinker /usr/lib/swift \
            "$source_dir/JITHelper/AmethystJITHelper.swift" "$work_dir/AmethystJITHelper-main.o" \
            -o "$helper/AmethystJITHelper"
        cp "$source_dir/JITHelper/Info.plist" "$helper/Info.plist"
        bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$app/Info.plist")"
        plutil -replace CFBundleIdentifier -string "$bundle_id.JITHelper" "$helper/Info.plist"
        for key in CFBundleShortVersionString CFBundleVersion; do
            value="$(plutil -extract "$key" raw -o - "$app/Info.plist")"
            plutil -replace "$key" -string "$value" "$helper/Info.plist"
        done
        ;;
    embed)
        mkdir -p "$app/PlugIns" "$app/Frameworks"
        cp -R "$helper" "$app/PlugIns/"
        # Keep the framework in the host's Frameworks directory, where
        # SideStore and AltStore discover it for re-signing.
        cp -R "$framework" "$app/Frameworks/"
        xcrun swift-stdlib-tool --copy --platform iphoneos \
            --scan-executable "$app/PlugIns/AmethystJITHelper.appex/AmethystJITHelper" \
            --scan-folder "$app/Frameworks/StikJIT.framework" \
            --destination "$app/Frameworks"
        ;;
    *) echo "Usage: $0 build|embed SOURCE_DIR WORK_DIR [SDK_PATH] [Debug|Release]" >&2; exit 2 ;;
esac
