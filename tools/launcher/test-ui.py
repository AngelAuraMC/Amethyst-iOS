#!/usr/bin/env python3
"""Exercise the production launcher navigation and skin loader in an isolated simulator."""
import argparse
import json
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
NATIVES = ROOT / "Natives"
BUNDLE = "org.amethyst.launcher-tests"


def command(*args, timeout=60):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=timeout).strip()


def sim(*args, timeout=60):
    return command("xcrun", "simctl", *args, timeout=timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="iPad Air 11-inch (M3)")
    parser.add_argument("--landscape", action="store_true")
    parser.add_argument("--baseline-ref", default="origin/main", help="Git ref containing the previous launcher implementation")
    parser.add_argument("--dependency-root", type=Path, default=ROOT, help="Checkout with the pinned AFNetworking submodule initialized")
    parser.add_argument("--baseline", action="store_true", help="Reproduce the previous empty sidebar item and clipped title")
    parser.add_argument("--output", type=Path, default=ROOT / "evidence/launcher-account")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    device = None
    with tempfile.TemporaryDirectory(prefix="amethyst-launcher-") as temporary:
        app = Path(temporary) / "LauncherTests.app"
        app.mkdir()
        arch = "arm64" if platform.machine() == "arm64" else "x86_64"
        sources = [Path(__file__).with_name("ui-test.m"), NATIVES / "LauncherMenuViewController.m", NATIVES / "LauncherSplitViewController.m", NATIVES / "AccountListViewController.m", NATIVES / "PLAccountSkin.m"]
        if args.baseline:
            original = Path(temporary) / "LauncherMenuViewController.m"
            original.write_text(command("git", "show", args.baseline_ref + ":Natives/LauncherMenuViewController.m"))
            sources[1] = original
        af = args.dependency_root.resolve() / "Natives/external/AFNetworking"
        sources += [af / "AFNetworking" / name for name in ("AFSecurityPolicy.m", "AFHTTPSessionManager.m", "AFURLRequestSerialization.m", "AFURLSessionManager.m", "AFNetworkReachabilityManager.m", "AFURLResponseSerialization.m")]
        sources += [af / "UIKit+AFNetworking" / name for name in ("AFAutoPurgingImageCache.m", "AFImageDownloader.m", "UIImageView+AFNetworking.m", "UIButton+AFNetworking.m")]
        compiler = ["xcrun", "--sdk", "iphonesimulator", "clang", "-target", f"{arch}-apple-ios14.0-simulator", "-fobjc-arc", "-fcommon", "-Wno-incomplete-implementation", "-Wno-objc-property-implementation"]
        if args.baseline:
            compiler.append("-DLAUNCHER_BASELINE=1")
        compiler += [part for name in ("UIKit", "Foundation", "CoreGraphics", "QuartzCore", "Security", "SystemConfiguration", "MobileCoreServices", "AuthenticationServices") for part in ("-framework", name)]
        compiler += [part for directory in (NATIVES, af / "AFNetworking", af / "UIKit+AFNetworking", NATIVES / "external/AltKit", NATIVES / "external/UnzipKit") for part in ("-I", str(directory))]
        command(*(compiler + [str(source) for source in sources] + ["-o", str(app / "LauncherTests")]))
        print("Launcher harness compiled", flush=True)
        with (app / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "LauncherTests", "CFBundleName": "Launcher Tests", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1", "MinimumOSVersion": "14.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {}, "UIRequiresFullScreen": True, "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft" if args.landscape else "UIInterfaceOrientationPortrait"]}, file)
        for name in ("DefaultAccount", "AppLogo", "MenuProfiles", "MenuNews", "MenuSettings", "IconAdd", "MenuCustomControls", "MenuInstallJar"):
            folder = NATIVES / "Assets.xcassets" / f"{name}.imageset"
            files = json.loads((folder / "Contents.json").read_text())["images"]
            filename = next((item["filename"] for item in files if "filename" in item), None)
            if filename:
                shutil.copyfile(folder / filename, app / (name + Path(filename).suffix))
        for language in ("en", "es"):
            target = app / f"{language}.lproj"
            target.mkdir()
            shutil.copyfile(NATIVES / "resources" / f"{language}.lproj/Localizable.strings", target / "Localizable.strings")
        runtime = next(item["identifier"] for item in json.loads(sim("list", "runtimes", "--json"))["runtimes"] if item.get("isAvailable") and ".iOS-" in item["identifier"])
        device_type = next(item["identifier"] for item in json.loads(sim("list", "devicetypes", "--json"))["devicetypes"] if item["name"] == args.device)
        try:
            device = sim("create", "Amethyst Launcher tests", device_type, runtime)
            sim("boot", device)
            sim("bootstatus", device, "-b", timeout=180)
            sim("install", device, str(app))
            sim("launch", device, BUNDLE, "-AppleLanguages", "(es)", "-AppleLocale", "es_ES")
            container = Path(sim("get_app_container", device, BUNDLE, "data"))
            report = container / "Documents/ui-test.json"
            deadline = time.monotonic() + 35
            while not report.exists() and time.monotonic() < deadline:
                time.sleep(0.1)
            if not report.exists():
                sim("io", device, "screenshot", str(output / "failure.png"))
                raise RuntimeError("Launcher tests produced no report")
            result = json.loads(report.read_text())
            for image in (container / "Documents").glob("*.png"):
                shutil.copyfile(image, output / image.name)
            result.update(runtime=runtime, device=device_type, baseline=args.baseline)
            (output / "ui-test.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
            sim("io", device, "screenshot", str(output / "launcher.png"))
            print(json.dumps(result, ensure_ascii=False, indent=2))
            if not result["passed"]:
                raise RuntimeError(result["failure"])
        finally:
            if device:
                subprocess.run(["xcrun", "simctl", "shutdown", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
                subprocess.run(["xcrun", "simctl", "delete", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.output)
