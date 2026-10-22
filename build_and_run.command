#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# Finder does not inherit the terminal's Homebrew paths.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

CHECK_ONLY=0
case "${1:-}" in
    --check) CHECK_ONLY=1 ;;
    --help|-h)
        cat <<'HELP'
Usage: ./build_and_run.command [--check]

Build, package, sign, install and launch Amethyst on an iPhone or iPad.
--check validates the configuration without building or installing.

Environment variables:
  DEVICE_UDID          Device UDID, identifier or name.
  PROVISIONING_PROFILE Path to a .mobileprovision file (defaults to the app's profile).
  TEAM_ID              Apple team ID; read from the profile if omitted.
  SIGN_IDENTITY        SHA-1 or name of a certificate included in the profile.
  BUNDLE_ID            App identifier; preserves the current package's identifier.
  BUILD_VERSION        Build version; increments automatically.
  BUILD_TAG            Build tag; increments automatically.
  BOOTJDK              JDK 8 bin directory used to compile Java.
  DEPENDENCIES_DIR     Directory containing iOS Java runtimes 8, 17, 21 and 25.
  RENDERER_LIB_DIR     Directory containing built MobileGlues and SPIRV-Cross libraries.
  LAUNCH_AFTER_INSTALL 0 to install without launching the app (default: 1).
  START_STOPPED        1 to launch suspended for LLDB attachment (default: 0).

In a worktree, dependencies and the profile are reused from the primary
checkout when unavailable locally. The app is built from this branch.
HELP
        exit 0 ;;
    "") ;;
    *) printf 'Unknown argument: %s. Use --help.\n' "$1" >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'Use ./build_and_run.command [--check].\n' >&2
    exit 1
fi

trap 'status=$?; printf "The workflow failed at line %s (exit code %s).\n" "$LINENO" "$status" >&2; exit "$status"' ERR
for tool in python3 cmake make security codesign xcrun git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$tool" >&2
        exit 1
    fi
done

APP="$ROOT/artifacts/Payload/AngelAuraAmethyst.app"
COMMON_DIR="$(git rev-parse --git-common-dir)"
PRIMARY_ROOT="$(cd "$COMMON_DIR/.." && pwd)"
PRIMARY_APP="$PRIMARY_ROOT/artifacts/Payload/AngelAuraAmethyst.app"
CURRENT_INFO="$APP/Info.plist"
[[ -f "$CURRENT_INFO" ]] || CURRENT_INFO="$PRIMARY_APP/Info.plist"
DEFAULT_PROFILE="$APP/embedded.mobileprovision"
[[ -f "$DEFAULT_PROFILE" ]] || DEFAULT_PROFILE="$PRIMARY_APP/embedded.mobileprovision"
PROFILE_SOURCE="${PROVISIONING_PROFILE:-$DEFAULT_PROFILE}"
DEFAULT_DEPENDENCIES="$ROOT/depends"
[[ -d "$DEFAULT_DEPENDENCIES" ]] || DEFAULT_DEPENDENCIES="$PRIMARY_ROOT/depends"
DEPENDENCIES_DIR="${DEPENDENCIES_DIR:-$DEFAULT_DEPENDENCIES}"
DEFAULT_RENDERER="$ROOT/Natives/build"
if [[ ! -f "$DEFAULT_RENDERER/libmobileglues.dylib" && -f "$PRIMARY_ROOT/Natives/build/libmobileglues.dylib" ]]; then
    DEFAULT_RENDERER="$PRIMARY_ROOT/Natives/build"
fi
RENDERER_LIB_DIR_OVERRIDE="${RENDERER_LIB_DIR:-}"
RENDERER_LIB_DIR="${RENDERER_LIB_DIR:-$DEFAULT_RENDERER}"
if [[ ! -f "$PROFILE_SOURCE" ]]; then
    printf 'Profile not found: %s. Set PROVISIONING_PROFILE to its path.\n' "$PROFILE_SOURCE" >&2
    exit 1
fi
for required in scripts/build/package-development.py scripts/build/sign-development.py \
    Natives/external/AFNetworking/AFNetworking/AFSecurityPolicy.m \
    Natives/external/DBNumberedSlider/Classes/DBNumberedSlider.m \
    Natives/external/fishhook/fishhook.c Natives/external/UnzipKit/UnzipKit.h; do
    if [[ ! -f "$required" ]]; then
        printf 'Missing dependency: %s. Initialize the submodules and prepare the UnzipKit headers.\n' "$required" >&2
        exit 1
    fi
done
for version in 8 17 21 25; do
    if [[ ! -f "$DEPENDENCIES_DIR/java-$version-openjdk/release" ]]; then
        printf 'Missing iOS Java %s runtime in %s. Set DEPENDENCIES_DIR.\n' "$version" "$DEPENDENCIES_DIR" >&2
        exit 1
    fi
done
if [[ ! -f "$RENDERER_LIB_DIR/libmobileglues.dylib" || ! -f "$RENDERER_LIB_DIR/libspirv-cross-c-shared.0.dylib" ]]; then
    if [[ -n "${RENDERER_LIB_DIR_OVERRIDE:-}" ]]; then
        printf 'The renderer libraries are incomplete.\n' >&2
        exit 1
    fi
    RENDERER_LIB_DIR="$ROOT/Natives/build"
    if [[ ! -f Natives/external/MobileGlues/src/main/cpp/CMakeLists.txt || ! -f Natives/external/MobileGlues/src/main/cpp/libraries/ios/libspirv-cross-c-shared.0.dylib ]]; then
        printf 'MobileGlues is missing. Initialize its submodules recursively or set RENDERER_LIB_DIR.\n' >&2
        exit 1
    fi
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/amethyst-build.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
# Packaging replaces APP, including its embedded profile. Save it first.
cp "$PROFILE_SOURCE" "$TEMP_DIR/development.mobileprovision"
security cms -D -i "$TEMP_DIR/development.mobileprovision" -o "$TEMP_DIR/profile.plist"
security find-identity -v -p codesigning > "$TEMP_DIR/identities.txt"
xcrun devicectl --timeout 30 list devices --json-output "$TEMP_DIR/devices.json" >/dev/null

python3 - "$TEMP_DIR" "$CURRENT_INFO" <<'PY'
import datetime
import fnmatch
import hashlib
import json
import os
import pathlib
import plistlib
import re
import sys

work = pathlib.Path(sys.argv[1])
profile = plistlib.loads((work / "profile.plist").read_bytes())
current_path = pathlib.Path(sys.argv[2])
current = plistlib.loads(current_path.read_bytes()) if current_path.exists() else {}

def fail(message):
    sys.exit(message)

teams = profile.get("TeamIdentifier", [])
team = os.environ.get("TEAM_ID") or (teams[0] if teams else "")
if not team or team not in teams:
    fail("TEAM_ID does not match the provisioning profile's team.")
expiration = profile.get("ExpirationDate")
if not expiration or expiration <= datetime.datetime.utcnow():
    fail("The provisioning profile has expired; use a valid profile.")
entitlements = dict(profile.get("Entitlements", {}))
if not entitlements.get("get-task-allow"):
    fail("A development profile with get-task-allow is required to launch and debug.")

allowed_id = entitlements.get("application-identifier", "")
prefix, separator, profile_bundle = allowed_id.partition(".")
bundle_id = os.environ.get("BUNDLE_ID") or current.get("CFBundleIdentifier")
if not bundle_id:
    bundle_id = profile_bundle if "*" not in profile_bundle else "org.angelauramc.amethyst"
if not separator or not fnmatch.fnmatchcase(prefix + "." + bundle_id, allowed_id):
    fail(f"The profile does not allow BUNDLE_ID={bundle_id}. Use a profile compatible with the app.")

# Certificate names need not contain TeamIdentifier. Match the profile's DER
# certificates to identities with a private key available in the keychain.
certificates = {hashlib.sha1(cert).hexdigest().upper()
                for cert in profile.get("DeveloperCertificates", [])}
identities = re.findall(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"',
                        (work / "identities.txt").read_text(), re.MULTILINE)
requested_identity = os.environ.get("SIGN_IDENTITY", "")
matches = [(sha.upper(), name) for sha, name in identities
           if sha.upper() in certificates
           and (not requested_identity or requested_identity.upper() == sha.upper()
                or requested_identity == name)]
if not matches:
    fail("No valid certificate with a private key matches the profile. "
         "Check Keychain, PROVISIONING_PROFILE and SIGN_IDENTITY.")
identity = matches[0][0]

devices = json.loads((work / "devices.json").read_text())["result"]["devices"]
devices = [d for d in devices
           if d.get("hardwareProperties", {}).get("platform") == "iOS"
           and d.get("hardwareProperties", {}).get("deviceType", "").lower() in ("ipad", "iphone")
           and d.get("hardwareProperties", {}).get("reality") == "physical"]
requested_device = os.environ.get("DEVICE_UDID", "")
if requested_device:
    def identifiers(device):
        connection = device.get("connectionProperties", {})
        return [device["identifier"], device.get("hardwareProperties", {}).get("udid", ""),
                device.get("deviceProperties", {}).get("name", "")] + \
               connection.get("potentialHostnames", []) + connection.get("localHostnames", [])
    matches = [d for d in devices if requested_device.casefold() in
               [value.casefold() for value in identifiers(d)]]
else:
    connected = [d for d in devices
                 if d.get("connectionProperties", {}).get("tunnelState") == "connected"]
    # CoreDevice opens tunnels on demand, including for attached USB devices.
    wired = [d for d in devices
             if d.get("connectionProperties", {}).get("transportType") == "wired"]
    paired = [d for d in devices
              if d.get("connectionProperties", {}).get("pairingState") == "paired"]
    matches = wired or connected or paired
if len(matches) != 1:
    available = ", ".join(f'{d.get("deviceProperties", {}).get("name", "iOS")} ({d["identifier"]})'
                          for d in (matches or devices)) or "none"
    fail(f"Unable to select a single iPhone or iPad. Devices: {available}. "
         "Connect the device or set DEVICE_UDID.")
device = matches[0]
if device.get("deviceProperties", {}).get("developerModeStatus") != "enabled":
    fail("Enable Developer Mode on the device before installing.")
if device.get("hardwareProperties", {}).get("udid") not in profile.get("ProvisionedDevices", []):
    fail("The device is not included in the profile. Register it and renew the profile.")

def increment(value):
    match = re.fullmatch(r"(.*?)(\d+)", value)
    return match[1] + str(int(match[2]) + 1) if match else value + ".1"

config = dict(TEAM_ID=team, BUNDLE_ID=bundle_id, SIGN_IDENTITY=identity,
              DEVICE_UDID=device["identifier"],
              DEVICE_NAME=device.get("deviceProperties", {}).get("name", "iOS"),
              BUILD_VERSION=os.environ.get("BUILD_VERSION") or increment(current.get("CFBundleVersion", "1.0.0")),
              BUILD_TAG=os.environ.get("BUILD_TAG") or increment(current.get("AmethystBuildTag", "modrinth-ios.0")))
entitlements["application-identifier"] = prefix + "." + bundle_id
(work / "entitlements.plist").write_bytes(plistlib.dumps(entitlements))
(work / "config.plist").write_bytes(plistlib.dumps(config))
PY

TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :TEAM_ID' "$TEMP_DIR/config.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$TEMP_DIR/config.plist")"
SIGN_IDENTITY="$(/usr/libexec/PlistBuddy -c 'Print :SIGN_IDENTITY' "$TEMP_DIR/config.plist")"
DEVICE_UDID="$(/usr/libexec/PlistBuddy -c 'Print :DEVICE_UDID' "$TEMP_DIR/config.plist")"
DEVICE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :DEVICE_NAME' "$TEMP_DIR/config.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :BUILD_VERSION' "$TEMP_DIR/config.plist")"
BUILD_TAG="$(/usr/libexec/PlistBuddy -c 'Print :BUILD_TAG' "$TEMP_DIR/config.plist")"

if [[ -z "${BOOTJDK:-}" ]]; then
    if [[ -x "$DEPENDENCIES_DIR/jdk8u504-b01/Contents/Home/bin/javac" ]]; then
        BOOTJDK="$DEPENDENCIES_DIR/jdk8u504-b01/Contents/Home/bin"
    else
        BOOTJDK="$(/usr/libexec/java_home -v 1.8)/bin"
    fi
fi
if [[ ! -x "$BOOTJDK/javac" || ! -x "$BOOTJDK/jar" ]]; then
    printf 'BOOTJDK must point to a JDK 8 bin directory: %s\n' "$BOOTJDK" >&2
    exit 1
fi
if [[ "$("$BOOTJDK/javac" -version 2>&1)" != 'javac 1.8.'* ]]; then
    printf 'The Java build requires JDK 8. Set BOOTJDK to its bin directory.\n' >&2
    exit 1
fi

printf 'Amethyst %s (%s) → %s\nTeam: %s · Bundle: %s\n' "$BUILD_VERSION" "$BUILD_TAG" "$DEVICE_NAME" "$TEAM_ID" "$BUNDLE_ID"
printf 'Runtimes: %s\nRenderer: %s\n' "$DEPENDENCIES_DIR" "$RENDERER_LIB_DIR"
if [[ "$CHECK_ONLY" == "1" ]]; then
    printf 'Development configuration is valid. No build or installation was performed.\n'
    exit 0
fi

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CMAKE_OPTIONS=(-DCMAKE_BUILD_TYPE=Debug -DCMAKE_CROSSCOMPILING=true
    -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=aarch64
    "-DCMAKE_OSX_SYSROOT=$SDK_PATH" -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 '-DCMAKE_C_FLAGS=-arch arm64')
cmake -S Natives -B Natives/build "${CMAKE_OPTIONS[@]}" \
    "-DCONFIG_BRANCH=$(git branch --show-current)" \
    "-DCONFIG_COMMIT=$(git rev-parse --short HEAD)" -DCONFIG_RELEASE=0
cmake --build Natives/build --target AngelAuraAmethyst awt_xawt AmethystAccountJNI tinygl4angle
if [[ ! -f "$RENDERER_LIB_DIR/libmobileglues.dylib" || ! -f "$RENDERER_LIB_DIR/libspirv-cross-c-shared.0.dylib" ]]; then
    cmake -S Natives/external/MobileGlues/src/main/cpp -B Natives/build/mobileglues \
        "${CMAKE_OPTIONS[@]}" -DMACOS=1
    cmake --build Natives/build/mobileglues --target mobileglues
    cp Natives/build/mobileglues/libmobileglues.dylib "$RENDERER_LIB_DIR/"
    cp Natives/external/MobileGlues/src/main/cpp/libraries/ios/libspirv-cross-c-shared.0.dylib "$RENDERER_LIB_DIR/"
fi
make -C JavaApp BOOTJDK="$BOOTJDK"
mkdir -p Natives/build/assets
xcrun actool Natives/Assets.xcassets --compile Natives/build/assets \
    --platform iphoneos --minimum-deployment-target 14.0 \
    --app-icon AppIcon-Light --output-partial-info-plist /dev/null

python3 scripts/build/package-development.py \
    --bundle-id "$BUNDLE_ID" --build-version "$BUILD_VERSION" --build-tag "$BUILD_TAG" \
    --runtime-dir "$DEPENDENCIES_DIR" --renderer-dir "$RENDERER_LIB_DIR"
python3 scripts/build/sign-development.py \
    --identity "$SIGN_IDENTITY" --profile "$TEMP_DIR/development.mobileprovision" \
    --entitlements "$TEMP_DIR/entitlements.plist"

xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
if [[ "${LAUNCH_AFTER_INSTALL:-1}" != "0" ]]; then
    LAUNCH_OPTIONS=(--terminate-existing)
    if [[ "${START_STOPPED:-0}" == "1" ]]; then
        LAUNCH_OPTIONS+=(--start-stopped)
    fi
    xcrun devicectl device process launch --device "$DEVICE_UDID" "${LAUNCH_OPTIONS[@]}" "$BUNDLE_ID"
    if [[ "${START_STOPPED:-0}" == "1" ]]; then
        printf 'Amethyst is suspended. Attach LLDB to continue and enable JIT.\n'
    else
        printf 'Amethyst is running. Attach LLDB and enable JIT for Minecraft; keep the debugger attached.\n'
    fi
else
    printf 'Amethyst is installed; launch was skipped.\n'
fi
