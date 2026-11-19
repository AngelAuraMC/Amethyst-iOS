"""Run the real native packet/batch implementation on the macOS CI host."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SWIFTC = shutil.which("swiftc")
NODE = shutil.which("node")


@unittest.skipUnless(SWIFTC, "Swift compiler required; exercised on macOS CI")
class StikJITMemoryTests(unittest.TestCase):
    def test_full_width_addresses_and_failures(self):
        with tempfile.TemporaryDirectory(prefix="amethyst-jit-memory-") as temp:
            executable = str(Path(temp) / "jit-memory-tests")
            build = subprocess.run([SWIFTC, str(ROOT / "JITHelper/StikJIT/JITMemory.swift"),
                                    str(ROOT / "tests/stikjit_memory_tests.swift"), "-o", executable],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([executable], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


@unittest.skipUnless(NODE, "Node.js required for Universal JIT protocol tests")
class UniversalJITTests(unittest.TestCase):
    def test_failed_preparation_cannot_return_or_detach(self):
        run = subprocess.run([NODE, str(ROOT / "tests/universal_jit_tests.js")],
                             capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
