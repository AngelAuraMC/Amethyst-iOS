"""Exercise helper packaging without requiring an Apple toolchain or network."""

import json
import io
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import tarfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash") or (r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else None)
SHA256 = "c0aa8df8b65998cc16d45130d004ca0e1f2ae6b6a0c737486bd832a8d4dd390a"

# These doubles emulate tool outputs, not compilation. Real cp/tar execute so
# extension layout and metadata failures remain visible to the tests.
TOOL = r'''
import json, os, pathlib, plistlib, shutil, sys
tool, *args = sys.argv[1:]
with open(os.environ["STIKJIT_TEST_LOG"], "a", encoding="utf-8") as log:
    log.write(json.dumps([tool, *args]) + "\n")
if tool == "shasum":
    print(os.environ["STIKJIT_TEST_SHA"] + "  " + args[-1])
elif tool == "curl":
    shutil.copyfile(os.environ["STIKJIT_TEST_ARCHIVE"], args[args.index("--output") + 1])
elif tool == "plutil":
    path = pathlib.Path(args[-1])
    data = plistlib.loads(path.read_bytes())
    if args[0] == "-extract":
        print(data[args[1]])
    else:
        data[args[1]] = args[args.index("-string") + 1]
        path.write_bytes(plistlib.dumps(data))
elif tool == "xcodebuild":
    archive = pathlib.Path(args[args.index("-archivePath") + 1] + ".xcarchive")
    framework = archive / "Products/Library/Frameworks/StikJIT.framework"
    framework.mkdir(parents=True)
    (framework / "StikJIT").write_bytes(b"framework fixture")
    (framework / "universal.js").write_text("fixture script")
    (framework / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "StikJIT"}))
elif tool == "xcrun":
    if "swift-stdlib-tool" in args:
        destination = pathlib.Path(args[args.index("--destination") + 1])
        (destination / "libswiftCore.dylib").write_bytes(b"swift runtime fixture")
    else:
        output = pathlib.Path(args[args.index("-o") + 1])
        output.write_bytes(b"compiled helper fixture")
        if "swiftc" in args and "-g" in args:
            dwarf = pathlib.Path(str(output) + ".dSYM") / "Contents/Resources/DWARF"
            dwarf.mkdir(parents=True, exist_ok=True)
            (dwarf / output.name).write_bytes(b"non-loadable MH_DSYM fixture")
'''


@unittest.skipUnless(BASH, "Bash is required for packaging smoke tests")
class StikJITPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="amethyst-stikjit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source with spaces"
        self.work = self.root / "Natives" / "build"
        self.app = self.work / "AngelAuraAmethyst.app"
        self.app.mkdir(parents=True)
        shutil.copytree(ROOT / "JITHelper", self.root / "JITHelper")
        host = {
            "CFBundleIdentifier": "dev.example.amethyst.RENAMED",
            "CFBundleShortVersionString": "2.3.4",
            "CFBundleVersion": "527",
        }
        (self.app / "Info.plist").write_bytes(plistlib.dumps(host))
        self.archive = Path(self.temp.name) / "source-fixture.tar.gz"
        with tarfile.open(self.archive, "w:gz") as archive:
            for name, contents in [("project.yml", b"fixture project"),
                                   ("Sources/ScriptRunner.swift", b"unpatched upstream fixture")]:
                info = tarfile.TarInfo("StikJIT-fixture/" + name)
                info.size = len(contents)
                archive.addfile(info, io.BytesIO(contents))
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        tool = self.bin / "tool.py"
        tool.write_text(TOOL, encoding="utf-8")
        for name in ["xcrun", "xcodegen", "xcodebuild", "plutil", "shasum", "curl"]:
            stub = self.bin / name
            stub.write_text('#!/bin/bash\nexec "$STIKJIT_TEST_PYTHON" "$STIKJIT_TEST_TOOL" ' + name + ' "$@"\n', encoding="utf-8")
            stub.chmod(0o755)
        self.log = self.bin / "calls.jsonl"
        test_bin = self.bin.as_posix()
        if os.name == "nt":
            test_bin = "/" + test_bin[0].lower() + test_bin[2:]
        self.env = dict(os.environ,
            STIKJIT_TEST_BIN=test_bin,
            STIKJIT_TEST_PYTHON=Path(sys.executable).as_posix(),
            STIKJIT_TEST_TOOL=tool.as_posix(),
            STIKJIT_TEST_LOG=self.log.as_posix(),
            STIKJIT_TEST_ARCHIVE=self.archive.as_posix(),
            STIKJIT_TEST_SHA=SHA256,
            MSYS_NO_PATHCONV="1")

    def run_script(self, mode, configuration="Debug"):
        wrapper = 'export PATH="$STIKJIT_TEST_BIN:$PATH"; test "$(command -v curl)" = "$STIKJIT_TEST_BIN/curl" || exit 99; exec bash "$@"'
        return subprocess.run([BASH, "-c", wrapper, "--", (ROOT / "scripts/build-stikjit-helper.sh").as_posix(),
            mode, self.root.as_posix(), self.work.as_posix(), "/fake iPhoneOS.sdk", configuration],
            env=self.env, capture_output=True, text=True, timeout=30)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text(encoding="utf-8").splitlines()]

    def test_build_and_embed_preserve_signable_layout_and_metadata(self):
        for mode in ["build", "embed"]:
            result = self.run_script(mode)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        helper = self.app / "PlugIns/AmethystJITHelper.appex"
        info = plistlib.loads((helper / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "dev.example.amethyst.RENAMED.JITHelper")
        self.assertEqual(info["CFBundleShortVersionString"], "2.3.4")
        self.assertEqual(info["CFBundleVersion"], "527")
        self.assertEqual(info["MinimumOSVersion"], "17.4")
        self.assertEqual(info["NSExtension"]["NSExtensionPrincipalClass"], "AmethystJITHelperHandler")
        self.assertEqual(info["NSExtension"]["NSExtensionPointIdentifier"], "com.apple.ar.viewer")
        self.assertTrue((helper / "AmethystJITHelper").is_file())
        self.assertTrue((self.work / "AmethystJITHelper.dSYM/Contents/Resources/DWARF/AmethystJITHelper").is_file())
        self.assertFalse(any(path.name.endswith(".dSYM") for path in self.app.rglob("*")))
        self.assertEqual((self.app / "Frameworks/StikJIT.framework/StikJIT").read_bytes(), b"framework fixture")
        framework_info = plistlib.loads((self.app / "Frameworks/StikJIT.framework/Info.plist").read_bytes())
        self.assertEqual(framework_info["AmethystJITMemoryFix"], "full-width-v1")
        self.assertTrue((self.app / "Frameworks/libswiftCore.dylib").is_file())
        self.assertFalse((helper / "Frameworks").exists())
        swift = next(call for call in self.calls() if "swiftc" in call)
        self.assertIn("@executable_path/../../Frameworks", swift)
        self.assertIn("arm64-apple-ios17.4", swift)
        self.assertIn("-application-extension", swift)
        self.assertIn("-Onone", swift)
        download = next(call for call in self.calls() if call[0] == "curl")
        self.assertIn("https://codeload.github.com/StikDebug/StikJIT/tar.gz/b3e01a30ded4cd0b27cf1b6bd42f123bbdf49c3a", download)
        # Prove the source actually compiled is the patched implementation.
        for name in ("ScriptRunner.swift", "JITMemory.swift"):
            self.assertEqual((self.work / "StikJIT-source/Sources" / name).read_bytes(),
                             (ROOT / "JITHelper/StikJIT" / name).read_bytes())
        build = next(call for call in self.calls() if call[0] == "xcodebuild")
        self.assertIn("APPLICATION_EXTENSION_API_ONLY=YES", build)

    def test_corrupted_archive_is_rejected_before_extraction_or_compilation(self):
        self.env["STIKJIT_TEST_SHA"] = "0" * 64
        result = self.run_script("build")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr)
        self.assertFalse(any(call[0] in ("xcodegen", "xcodebuild", "xcrun") for call in self.calls()))
        self.assertFalse((self.work / "StikJIT-source").exists())

    def test_cached_archive_is_still_verified_and_release_uses_optimization(self):
        result = self.run_script("build")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_script("build", "Release")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(sum(call[0] == "curl" for call in calls), 1)
        self.assertEqual(sum(call[0] == "shasum" for call in calls), 2)
        swift = [call for call in calls if "swiftc" in call][-1]
        self.assertIn("-O", swift)
        self.assertNotIn("-Onone", swift)

    def test_embed_fails_if_helper_was_not_built(self):
        result = self.run_script("embed")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.app / "PlugIns/AmethystJITHelper.appex").exists())


if __name__ == "__main__":
    unittest.main()
