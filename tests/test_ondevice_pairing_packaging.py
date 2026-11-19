"""Check pairing framework integrity checks and its independently signable layout."""

import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

from test_stikjit_packaging import BASH, ROOT


TOOL = r'''
import os, pathlib, sys
tool, *args = sys.argv[1:]
if tool == "curl":
    pathlib.Path(args[args.index("--output") + 1]).write_bytes(b"download fixture")
elif tool == "shasum":
    expected = ("696286794e8cf1c18a91d4dab5046cef4d9bae352f5e7a1ad33fbc0ba30d7ab4"
        if args[-1].endswith("idevice.h") else
        "4db23fe1d342927b9480bb9a8577f219994365621dc28aa0018e23ea1990ecc8")
    print(("0" * 64 if os.environ.get("PAIRING_TEST_CORRUPT") else expected) + "  " + args[-1])
elif tool == "xcrun":
    pathlib.Path(args[args.index("-o") + 1]).write_bytes(b"compiled pairing fixture")
'''


@unittest.skipUnless(BASH, "Bash is required for packaging smoke tests")
class OnDevicePairingPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="amethyst-pairing-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source with spaces"
        self.work = self.root / "Natives/build"
        self.app = self.work / "AngelAuraAmethyst.app"
        self.app.mkdir(parents=True)
        (self.app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.angelauramc.amethyst.95J8WZ4TN8",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0"}))
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        (self.bin / "tool.py").write_text(TOOL, encoding="utf-8")
        # Use the same Python interpreter for the real plist-writing build step.
        for name in ("curl", "shasum", "xcrun", "python3"):
            command = ('exec "$PAIRING_TEST_PYTHON" "$@"' if name == "python3" else
                'exec "$PAIRING_TEST_PYTHON" "$PAIRING_TEST_TOOL" ' + name + ' "$@"')
            stub = self.bin / name
            stub.write_text("#!/bin/bash\n" + command + "\n", encoding="utf-8")
            stub.chmod(0o755)
        import sys
        path = self.bin.as_posix()
        if os.name == "nt":
            path = "/" + path[0].lower() + path[2:]
        self.env = dict(os.environ, PAIRING_TEST_BIN=path,
            PAIRING_TEST_PYTHON=Path(sys.executable).as_posix(),
            PAIRING_TEST_TOOL=(self.bin / "tool.py").as_posix(), MSYS_NO_PATHCONV="1")

    def run_script(self, mode):
        return subprocess.run([BASH, "-c", 'export PATH="$PAIRING_TEST_BIN:$PATH"; exec bash "$@"', "--",
            (ROOT / "scripts/build-ondevice-pairing.sh").as_posix(), mode, self.root.as_posix(),
            self.work.as_posix(), "/fake SDK", "Debug"], env=self.env,
            capture_output=True, text=True, timeout=30)

    def test_build_and_embed_keep_framework_signable_and_match_host(self):
        for mode in ("build", "embed"):
            result = self.run_script(mode)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        framework = self.app / "Frameworks/AmethystPairing.framework"
        info = plistlib.loads((framework / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "org.angelauramc.amethyst.95J8WZ4TN8.Pairing")
        self.assertEqual(info["CFBundleVersion"], "1")
        self.assertEqual(info["CFBundleExecutable"], "AmethystPairing")
        self.assertEqual((framework / "AmethystPairing").read_bytes(), b"compiled pairing fixture")
        self.assertFalse(any(p.name.endswith(".dSYM") for p in framework.rglob("*")))

    def test_corrupt_dependency_is_rejected_before_framework_build(self):
        self.env["PAIRING_TEST_CORRUPT"] = "1"
        result = self.run_script("build")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr)
        self.assertFalse((self.work / "AmethystPairing.framework").exists())

    def test_embedding_requires_a_built_framework(self):
        self.assertNotEqual(self.run_script("embed").returncode, 0)


if __name__ == "__main__":
    unittest.main()
