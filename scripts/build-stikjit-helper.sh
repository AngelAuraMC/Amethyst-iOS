#!/bin/bash
set -euo pipefail

mode="$1"
source_dir="$2"
work_dir="$3"
sdk_path="${4:-}"
configuration="${5:-Debug}"

version=2.0.1
revision=b3e01a30ded4cd0b27cf1b6bd42f123bbdf49c3a
checksum=c0aa8df8b65998cc16d45130d004ca0e1f2ae6b6a0c737486bd832a8d4dd390a
cache_dir="$source_dir/depends/stikjit/$version"
upstream="$work_dir/StikJIT-source"
framework="$work_dir/StikJIT.xcarchive/Products/Library/Frameworks/StikJIT.framework"
helper="$work_dir/AmethystJITHelper.appex"
app="$work_dir/AngelAuraAmethyst.app"

case "$mode" in
    build)
        rm -rf "$helper"
        mkdir -p "$cache_dir" "$helper"
        archive="$cache_dir/StikJIT-source.tar.gz"
        if [ ! -f "$archive" ]; then
            curl --fail --location --retry 3 \
                "https://codeload.github.com/StikDebug/StikJIT/tar.gz/$revision" \
                --output "$archive.part"
            mv "$archive.part" "$archive"
        fi
        actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
        if [ "$actual" != "$checksum" ]; then
            echo "StikJIT archive checksum mismatch. Remove $archive and retry." >&2
            exit 1
        fi
        rm -rf "$upstream" "$work_dir/StikJIT.xcarchive"
        mkdir -p "$upstream"
        tar -xz -C "$upstream" --strip-components=1 < "$archive"
        # MPL-2.0 replacements are kept in-tree, so the exact modified source
        # remains available with each Amethyst revision.
        cp "$source_dir/JITHelper/StikJIT/"*.swift "$upstream/Sources/"
        (
            cd "$upstream"
            xcodegen generate
            xcodebuild -quiet archive -project StikJIT.xcodeproj -scheme StikJIT \
                -configuration Release -destination 'generic/platform=iOS' \
                -archivePath "$work_dir/StikJIT" \
                SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
                CODE_SIGNING_ALLOWED=NO APPLICATION_EXTENSION_API_ONLY=YES
        )
        plutil -insert AmethystJITMemoryFix -string full-width-v1 "$framework/Info.plist"
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
            -o "$work_dir/AmethystJITHelper"
        # swiftc -g also emits a sibling dSYM. Keep build outputs outside the
        # extension so recursive signing never encounters its MH_DSYM binary.
        mv -f "$work_dir/AmethystJITHelper" "$helper/AmethystJITHelper"
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
        rm -rf "$app/PlugIns/AmethystJITHelper.appex"
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
