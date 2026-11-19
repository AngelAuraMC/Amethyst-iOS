"""Reject incomplete CI packages before uploading downloadable artifacts."""

import argparse
from pathlib import Path
import plistlib
import sys
import zipfile


APP = "Payload/AngelAuraAmethyst.app/"
HELPER = APP + "PlugIns/AmethystJITHelper.appex/"
FRAMEWORK = APP + "Frameworks/StikJIT.framework/"
PAIRING = APP + "Frameworks/AmethystPairing.framework/"
PLATFORMS = ("ios", "tvos", "iossimulator", "tvossimulator")


def require_file(archive, name):
    try:
        info = archive.getinfo(name)
    except KeyError:
        raise ValueError(f"Missing {name}") from None
    if info.file_size == 0 or info.is_dir():
        raise ValueError(f"Empty file: {name}")


def verify_archive(path, *, builtin_jit, slimmed, expected_bundle_id=None):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if any(part.endswith(".dSYM") for name in names for part in name.split("/")):
            raise ValueError("Package contains build-only dSYM debug symbols")
        host = plistlib.loads(archive.read(APP + "Info.plist"))
        if expected_bundle_id is not None and host.get("CFBundleIdentifier") != expected_bundle_id:
            raise ValueError(f"Host CFBundleIdentifier must be {expected_bundle_id!r}, "
                             f"got {host.get('CFBundleIdentifier')!r}")
        require_file(archive, APP + host["CFBundleExecutable"])
        if slimmed:
            if any(name.startswith(APP + "java_runtimes/") for name in names):
                raise ValueError("Slimmed package contains Java runtimes")
        else:
            for version in (8, 17, 21, 25):
                require_file(archive, APP + f"java_runtimes/java-{version}-openjdk/release")

        if not builtin_jit:
            if any(name.startswith((HELPER, FRAMEWORK, PAIRING)) for name in names):
                raise ValueError("Non-iOS package contains the iOS JIT helper or framework")
            return

        require_file(archive, HELPER + "Info.plist")
        helper = plistlib.loads(archive.read(HELPER + "Info.plist"))
        expected = {
            "CFBundleIdentifier": host["CFBundleIdentifier"] + ".JITHelper",
            "CFBundleShortVersionString": host["CFBundleShortVersionString"],
            "CFBundleVersion": host["CFBundleVersion"],
            "CFBundlePackageType": "XPC!",
        }
        for key, value in expected.items():
            if helper.get(key) != value:
                raise ValueError(f"Helper {key} must be {value!r}, got {helper.get(key)!r}")
        extension = helper.get("NSExtension", {})
        if (extension.get("NSExtensionPointIdentifier") != "com.apple.ar.viewer"
                or extension.get("NSExtensionPrincipalClass") != "AmethystJITHelperHandler"):
            raise ValueError("Incorrect JIT extension entry point")
        require_file(archive, HELPER + helper["CFBundleExecutable"])
        require_file(archive, FRAMEWORK + "Info.plist")
        require_file(archive, FRAMEWORK + "StikJIT")
        framework = plistlib.loads(archive.read(FRAMEWORK + "Info.plist"))
        if framework.get("AmethystJITMemoryFix") != "full-width-v1":
            raise ValueError("StikJIT framework is missing the full-width JIT memory fix")
        require_file(archive, PAIRING + "Info.plist")
        require_file(archive, PAIRING + "AmethystPairing")
        pairing = plistlib.loads(archive.read(PAIRING + "Info.plist"))
        if pairing.get("CFBundleIdentifier") != host["CFBundleIdentifier"] + ".Pairing":
            raise ValueError("Pairing framework CFBundleIdentifier does not match the host")
        if ("_remotepairing-pairable-host._tcp" not in host.get("NSBonjourServices", [])
                or "audio" not in host.get("UIBackgroundModes", [])):
            raise ValueError("On-device pairing requires Bonjour and background audio declarations")


def verify_packages(directory, platform, *, expected_bundle_id=None):
    suffixes = [".ipa"] if platform != "tvos" else []
    if platform in ("ios", "tvos"):
        suffixes.append("-trollstore.tipa")
    for slimmed in (False, True):
        bundle = "org.angelauramc.amethyst" + (".slimmed" if slimmed else "")
        for suffix in suffixes:
            pattern = f"{bundle}-*-{platform}{suffix}"
            paths = list(directory.glob(pattern))
            if len(paths) != 1:
                raise ValueError(f"Expected one {pattern}, found {len(paths)}")
            verify_archive(paths[0], builtin_jit=platform == "ios", slimmed=slimmed,
                           expected_bundle_id=expected_bundle_id)
            print(f"Verified {paths[0].name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=PLATFORMS)
    parser.add_argument("--artifacts", type=Path, default=Path("artifacts"))
    parser.add_argument("--bundle-id", help="Required host bundle identifier for every package")
    args = parser.parse_args()
    try:
        verify_packages(args.artifacts, args.platform, expected_bundle_id=args.bundle_id)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"Package validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
