#!/usr/bin/env python3
"""Sign every native library, framework and the development launcher."""
import argparse
import pathlib
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--identity", required=True)
parser.add_argument("--profile", type=pathlib.Path, required=True)
parser.add_argument("--entitlements", type=pathlib.Path, required=True,
                    help="Entitlements derived from the selected development profile")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
app = root / "artifacts/Payload/AngelAuraAmethyst.app"
shutil.copy2(args.profile, app / "embedded.mobileprovision")
magic = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
def sign(path, entitlements=None):
    cmd = ["codesign", "--force", "--sign", args.identity, "--timestamp=none", "--generate-entitlement-der"]
    if entitlements:
        cmd += ["--entitlements", str(entitlements)]
    subprocess.run(cmd + [str(path)], check=True)
for path in app.rglob("*"):
    if path.is_file() and not path.is_symlink() and path.name != "AngelAuraAmethyst":
        with path.open("rb") as stream:
            if stream.read(4) in magic:
                sign(path)
for framework in sorted(app.rglob("*.framework"), key=lambda p: len(p.parts), reverse=True):
    sign(framework)
sign(app, args.entitlements)
subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)
print("All native libraries and launcher verified")
