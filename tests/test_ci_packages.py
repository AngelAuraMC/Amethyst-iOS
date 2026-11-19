"""Check CI rejects archives that SideStore cannot install with built-in JIT."""

from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("verify_ci_packages", ROOT / "scripts/verify-ci-packages.py")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class CIPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="amethyst-ci-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def fixture(self, *, builtin_jit=True, slimmed=False, bundle_id="dev.example.amethyst"):
        host = {
            "CFBundleIdentifier": bundle_id,
            "CFBundleExecutable": "AngelAuraAmethyst",
            "CFBundleVersion": "527",
            "CFBundleShortVersionString": "2.3.4",
        }
        files = {
            VERIFY.APP + "Info.plist": plistlib.dumps(host),
            VERIFY.APP + "AngelAuraAmethyst": b"host fixture",
        }
        if not slimmed:
            for version in (8, 17, 21, 25):
                files[VERIFY.APP + f"java_runtimes/java-{version}-openjdk/release"] = b"runtime fixture"
        if builtin_jit:
            helper = plistlib.loads((ROOT / "JITHelper/Info.plist").read_bytes())
            for key in ("CFBundleVersion", "CFBundleShortVersionString"):
                helper[key] = host[key]
            helper["CFBundleIdentifier"] = host["CFBundleIdentifier"] + ".JITHelper"
            files.update({
                VERIFY.HELPER + "Info.plist": plistlib.dumps(helper),
                VERIFY.HELPER + "AmethystJITHelper": b"helper fixture",
                VERIFY.FRAMEWORK + "Info.plist": plistlib.dumps({"CFBundleExecutable": "StikJIT"}),
                VERIFY.FRAMEWORK + "StikJIT": b"framework fixture",
            })
        return files

    def write_archive(self, files, name="fixture.ipa"):
        path = self.directory / name
        with zipfile.ZipFile(path, "w") as archive:
            for member, contents in files.items():
                archive.writestr(member, contents)
        return path

    def test_all_platform_package_sets(self):
        bundle_id = "org.angelauramc.amethyst.95J8WZ4TN8"
        for platform in VERIFY.PLATFORMS:
            with self.subTest(platform=platform):
                suffixes = (".ipa", "-trollstore.tipa") if platform == "ios" else (
                    ("-trollstore.tipa",) if platform == "tvos" else (".ipa",))
                for slimmed in (False, True):
                    bundle = "org.angelauramc.amethyst" + (".slimmed" if slimmed else "")
                    for suffix in suffixes:
                        self.write_archive(self.fixture(builtin_jit=platform == "ios", slimmed=slimmed,
                                                        bundle_id=bundle_id),
                            f"{bundle}-1.0-{platform}{suffix}")
                with redirect_stdout(io.StringIO()):
                    VERIFY.verify_packages(self.directory, platform, expected_bundle_id=bundle_id)

    def test_changed_installation_identifier_is_rejected(self):
        for builtin_jit in (False, True):
            for slimmed in (False, True):
                with self.subTest(builtin_jit=builtin_jit, slimmed=slimmed):
                    files = self.fixture(builtin_jit=builtin_jit, slimmed=slimmed,
                                         bundle_id="org.angelauramc.amethyst")
                    with self.assertRaisesRegex(ValueError, "Host CFBundleIdentifier"):
                        VERIFY.verify_archive(self.write_archive(files), builtin_jit=builtin_jit,
                            slimmed=slimmed, expected_bundle_id="org.angelauramc.amethyst.95J8WZ4TN8")

    def test_missing_or_empty_helper_files_are_rejected(self):
        for member in (VERIFY.HELPER + "Info.plist", VERIFY.HELPER + "AmethystJITHelper",
                       VERIFY.FRAMEWORK + "Info.plist", VERIFY.FRAMEWORK + "StikJIT"):
            for empty in (False, True):
                with self.subTest(member=member, empty=empty):
                    files = self.fixture()
                    if empty:
                        files[member] = b""
                    else:
                        del files[member]
                    with self.assertRaisesRegex(ValueError, "Missing|Empty"):
                        VERIFY.verify_archive(self.write_archive(files), builtin_jit=True, slimmed=False)

    def test_stale_extension_metadata_is_rejected(self):
        for key in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString"):
            with self.subTest(key=key):
                files = self.fixture()
                helper = plistlib.loads(files[VERIFY.HELPER + "Info.plist"])
                helper[key] = "stale"
                files[VERIFY.HELPER + "Info.plist"] = plistlib.dumps(helper)
                with self.assertRaisesRegex(ValueError, key):
                    VERIFY.verify_archive(self.write_archive(files), builtin_jit=True, slimmed=False)

    def test_wrong_runtime_variant_is_rejected(self):
        for slimmed in (False, True):
            with self.subTest(slimmed=slimmed):
                with self.assertRaisesRegex(ValueError, "runtimes|java_runtimes"):
                    VERIFY.verify_archive(self.write_archive(self.fixture(slimmed=not slimmed)),
                        builtin_jit=True, slimmed=slimmed)

    def test_non_ios_package_cannot_contain_ios_helper(self):
        with self.assertRaisesRegex(ValueError, "Non-iOS"):
            VERIFY.verify_archive(self.write_archive(self.fixture()), builtin_jit=False, slimmed=False)

    def test_missing_build_outputs_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Expected one"):
            VERIFY.verify_packages(self.directory, "ios")

    def test_debug_symbols_cannot_be_embedded_in_extension(self):
        files = self.fixture()
        files[VERIFY.HELPER + "AmethystJITHelper.dSYM/Contents/Resources/DWARF/AmethystJITHelper"] = b"debug fixture"
        with self.assertRaisesRegex(ValueError, "dSYM"):
            VERIFY.verify_archive(self.write_archive(files), builtin_jit=True, slimmed=False)


if __name__ == "__main__":
    unittest.main()
