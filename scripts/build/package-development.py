#!/usr/bin/env python3
"""Package this checkout's launcher with prepared iOS Java runtimes."""
import argparse
import pathlib
import plistlib
import shutil
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--bundle-id", required=True)
parser.add_argument("--build-version", required=True)
parser.add_argument("--build-tag", required=True)
parser.add_argument("--runtime-dir", type=pathlib.Path, required=True)
parser.add_argument("--renderer-dir", type=pathlib.Path, required=True)
args = parser.parse_args()

root = pathlib.Path(__file__).resolve().parents[2]
native = root / "Natives/build"
resources = root / "Natives/resources"
app = root / "artifacts/Payload/AngelAuraAmethyst.app"
libraries = {
    **{name: native / name for name in (
        "libAmethystAccountJNI.dylib", "libAFNetworking.dylib", "libtinygl4angle.dylib")},
    **{name: args.renderer_dir / name for name in (
        "libmobileglues.dylib", "libspirv-cross-c-shared.0.dylib")},
}
jars = [root / "JavaApp/build" / (directory.name + ".jar")
        for directory in (root / "JavaApp/src").iterdir() if directory.is_dir()]
required = [native / "AngelAuraAmethyst.app/AngelAuraAmethyst",
            native / "AngelAuraAmethyst.app/Info.plist", native / "libawt_xawt.dylib",
            native / "assets/Assets.car", *libraries.values(), *jars]
required += [args.runtime_dir / f"java-{version}-openjdk/release"
             for version in (8, 17, 21, 25)]
missing = [str(path) for path in required if not path.is_file()]
if missing:
    parser.error("Missing build inputs:\n" + "\n".join(missing))

app.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix=".amethyst-package-", dir=app.parent) as temporary:
    staged = pathlib.Path(temporary) / app.name
    shutil.copytree(native / app.name, staged, symlinks=True)
    shutil.copytree(resources, staged, dirs_exist_ok=True, symlinks=True)
    shutil.copytree(native / "assets", staged, dirs_exist_ok=True)
    shutil.copytree(resources / "en.lproj/LaunchScreen.storyboardc",
                    staged / "Base.lproj/LaunchScreen.storyboardc", dirs_exist_ok=True)
    (staged / "libs").mkdir(exist_ok=True)
    for source in (root / "JavaApp/libs/others").iterdir():
        if source.is_file():
            shutil.copy2(source, staged / "libs" / source.name)
    for source in jars:
        shutil.copy2(source, staged / "libs" / source.name)
    for suffix in ("", "17"):
        shutil.copytree(root / f"JavaApp/libs/caciocavallo{suffix}",
                        staged / f"libs_caciocavallo{suffix}", dirs_exist_ok=True)
    for name, source in libraries.items():
        shutil.copy2(source, staged / "Frameworks" / name)
    for version in (8, 17, 21, 25):
        runtime = staged / f"java_runtimes/java-{version}-openjdk"
        shutil.copytree(args.runtime_dir / runtime.name, runtime, symlinks=True)
        for name in ("bin", "man", "include", "legal", "jre", "ASSEMBLY_EXCEPTION",
                     "LICENSE", "THIRD_PARTY_README", "lib/ct.sym", "lib/jspawnhelper",
                     "lib/libjsig.dylib", "lib/src.zip", "lib/tools.jar"):
            item = runtime / name
            if item.is_symlink():
                item.unlink()
            elif item.is_dir():
                shutil.rmtree(item)
            elif item.exists():
                item.unlink()
        shutil.copy2(native / "libawt_xawt.dylib", runtime / "lib")
    info_path = staged / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleIdentifier=args.bundle_id, CFBundleVersion=args.build_version,
                AmethystBuildTag=args.build_tag, UIDeviceFamily=[1, 2])
    info_path.write_bytes(plistlib.dumps(info))
    if app.exists():
        shutil.rmtree(app)
    staged.rename(app)
print(app)
