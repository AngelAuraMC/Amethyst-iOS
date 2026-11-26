#!/usr/bin/env python3
"""Cross-platform build & isolated-subprocess runner for gl4es116 C tests."""

import argparse
import concurrent.futures
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

FULL_SUITES = [
    "tier1_mem_low",
    "tier1_mem_medium",
    "tier1_mem_high",
    "tier1_mem_auto",
    "tier1_mem_budget",
    "tier1_trim",
    "tier1_leaks",
    "tier1_caps",
    "tier1_fpe_cache",
    "tier1_fpe_invariants",
    "tier1_ibo_stream",
    "tier1_draw_upload",
    "tier2_bounds",
    "tier3_pairwise",
    "tier4_village_low",
    "tier4_village_high",
    "tier4_multicontext",
]

SMOKE_SUITES = [
    "tier1_leaks",
    "tier1_fpe_invariants",
    "tier1_ibo_stream",
    "tier2_bounds",
    "tier3_pairwise",
]


def parse_gl_src(repo_root: Path) -> list[Path]:
    cmake_file = repo_root / "Natives/external/gl4es_116/src/CMakeLists.txt"
    txt = cmake_file.read_text(encoding="utf-8")
    m = re.search(r"SET\s*\(\s*GL_SRC(.*?)\)", txt, re.S)
    if not m:
        raise RuntimeError(f"Could not parse GL_SRC from {cmake_file}")
    src_root = repo_root / "Natives/external/gl4es_116/src"
    files = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if "${CMAKE_CURRENT_SOURCE_DIR}/" in line:
            rel = line.split("${CMAKE_CURRENT_SOURCE_DIR}/", 1)[1]
            files.append(src_root / rel)
    files.append(src_root / "glx/hardext.c")
    return files


def default_build_dir(repo_root: Path) -> Path:
    env_dir = os.environ.get("GL4ES_TEST_BUILD_DIR")
    if env_dir:
        return Path(env_dir)
    if os.name == "nt":
        local_app = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData/Local")
        return Path(local_app) / "amethyst_gl4es116_c_build"
    return Path(os.environ.get("TMPDIR", "/tmp")) / "amethyst_gl4es116_c_build"


def build_with_zig(repo_root: Path, build_dir: Path, pre_m1_smoke: bool) -> Path:
    gl4es_mem_h = repo_root / "Natives/external/gl4es_116/src/gl/gl4es_mem.h"
    if not pre_m1_smoke and not gl4es_mem_h.exists():
        raise FileNotFoundError(
            f"Missing required M1 contract header: {gl4es_mem_h}. "
            "Pass --pre-m1-smoke only for pre-M1 smoke testing."
        )

    obj_dir = build_dir / "obj"
    obj_dir.mkdir(parents=True, exist_ok=True)
    exe_path = build_dir / ("gl4es116_test_harness_smoke.exe" if pre_m1_smoke else "gl4es116_test_harness.exe")

    gl_srcs = parse_gl_src(repo_root)
    harness_srcs = [
        repo_root / "tests/mock_gles2.c",
        repo_root / "tests/win_alloc_shim.c",
        repo_root / "tests/gl4es116_test_harness.c",
    ]
    all_srcs = gl_srcs + harness_srcs

    cflags = [
        "-std=gnu11",
        "-O1",
        "-g",
        "-fsanitize=undefined",
        "-fno-omit-frame-pointer",
        "-DSTATICLIB=1",
        "-DDEFAULT_ES=2",
        "-DNOX11=1",
        "-DNOEGL=1",
        "-DEGL_NO_X11=1",
        "-DNO_GBM=1",
        "-DNO_LOADER=1",
        "-DNO_INIT_CONSTRUCTOR=1",
        "-Wno-pointer-sign",
        "-Wno-dangling-else",
        "-Wno-deprecated-declarations",
        "-Wno-date-time",
        f"-I{repo_root / 'Natives/external/gl4es_116/include'}",
        f"-I{repo_root / 'Natives/external/gl4es_116/src/gl'}",
        f"-I{repo_root / 'Natives/external/gl4es_116/src/glx'}",
        f"-I{repo_root / 'Natives/external/gl4es_116/src/util'}",
        f"-I{repo_root / 'tests'}",
    ]
    win_shim_h = repo_root / "tests/win_alloc_shim.h"
    if os.name == "nt":
        cflags.append("-DWIN_ALLOC_SHIM_WRAP=1")
    if pre_m1_smoke:
        cflags.append("-DGL4ES_PRE_M1_SMOKE=1")

    def compile_one(src: Path) -> Path:
        rel = src.relative_to(repo_root)
        suffix = ".smoke.o" if (pre_m1_smoke and src.name == "gl4es116_test_harness.c") else ".o"
        obj = obj_dir / (str(rel).replace("\\", "_").replace("/", "_") + suffix)
        newest_dep = src.stat().st_mtime
        if os.name == "nt" and win_shim_h.exists():
            newest_dep = max(newest_dep, win_shim_h.stat().st_mtime)
        need_build = not obj.exists() or obj.stat().st_mtime < newest_dep
        if src in harness_srcs:
            need_build = True
        if need_build:
            tu_cflags = list(cflags)
            if os.name == "nt" and src.name != "win_alloc_shim.c":
                tu_cflags.extend(["-include", str(win_shim_h)])
            cmd = [sys.executable, "-m", "ziglang", "cc", "-c", *tu_cflags, str(src), "-o", str(obj)]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                raise RuntimeError(f"Compile failed for {rel}:\n{res.stdout}\n{res.stderr}")
        return obj

    workers = min(8, os.cpu_count() or 4)
    print(f"Building gl4es116 C harness ({len(all_srcs)} TUs, workers={workers}, smoke={pre_m1_smoke})...", flush=True)
    objs: list[Path] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(compile_one, s) for s in all_srcs]
        for fut in futures:
            objs.append(fut.result())

    link_cmd = [
        sys.executable, "-m", "ziglang", "cc",
        "-fsanitize=undefined",
        *[str(o) for o in objs],
        "-lm", "-lpthread",
        "-o", str(exe_path),
    ]
    res = subprocess.run(link_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Link failed:\n{res.stdout}\n{res.stderr}")
    return exe_path


def build_with_cmake(repo_root: Path, build_dir: Path, pre_m1_smoke: bool) -> Path:
    build_dir.mkdir(parents=True, exist_ok=True)
    cmake_cmd = [
        "cmake",
        "-S", str(repo_root / "tests"),
        "-B", str(build_dir),
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
        "-DENABLE_SANITIZERS=ON",
        f"-DGL4ES_PRE_M1_SMOKE={'ON' if pre_m1_smoke else 'OFF'}",
    ]
    subprocess.run(cmake_cmd, check=True)
    subprocess.run(["cmake", "--build", str(build_dir), "-j4"], check=True)
    exe = build_dir / "bin/gl4es116_test_harness"
    if not exe.exists():
        exe = build_dir / "gl4es116_test_harness"
    return exe


def main() -> int:
    parser = argparse.ArgumentParser(description="Build & run gl4es116 opaque-box C E2E suites")
    parser.add_argument("--pre-m1-smoke", action="store_true",
                        help="Run only pre-M1 core smoke suites without gl4es_mem.h")
    parser.add_argument("--suite", help="Run only one named suite")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    build_dir = default_build_dir(repo_root)

    try:
        if os.name == "nt":
            exe_path = build_with_zig(repo_root, build_dir, args.pre_m1_smoke)
        else:
            if shutil.which("cmake"):
                exe_path = build_with_cmake(repo_root, build_dir, args.pre_m1_smoke)
            else:
                exe_path = build_with_zig(repo_root, build_dir, args.pre_m1_smoke)
    except Exception as exc:
        print(f"BUILD ERROR: {exc}", file=sys.stderr)
        return 1

    suites = [args.suite] if args.suite else (SMOKE_SUITES if args.pre_m1_smoke else FULL_SUITES)
    psa_dir = build_dir / "psa"
    if psa_dir.exists():
        shutil.rmtree(psa_dir, ignore_errors=True)
    psa_dir.mkdir(parents=True, exist_ok=True)

    passed_suites = 0
    failed_suites = 0
    total_checks_passed = 0
    total_checks_failed = 0
    metrics_by_profile: dict[str, dict[str, float]] = {}

    for suite in suites:
        env = os.environ.copy()
        env["LIBGL_PSA_FOLDER"] = str(psa_dir)
        env["LIBGL_NOBANNER"] = "1"
        env["AMETHYST_GL4ES_ERROR_TRACE"] = "0"
        env["LIBGL_BEGINEND"] = "1"
        if platform.system() == "Linux":
            env.setdefault("ASAN_OPTIONS", "detect_leaks=1")

        try:
            res = subprocess.run([str(exe_path), "--suite", suite], env=env, capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired as exc:
            failed_suites += 1
            total_checks_failed += 1
            print(f"  [SUITE FAIL] {suite} timed out after 60s")
            if exc.stdout:
                print(exc.stdout, end="")
            if exc.stderr:
                print(exc.stderr, end="", file=sys.stderr)
            continue
        print(res.stdout, end="")
        if res.stderr:
            print(res.stderr, end="", file=sys.stderr)

        m = re.search(r"(\d+)\s+PASSED,\s+(\d+)\s+FAILED", res.stdout)
        if m:
            total_checks_passed += int(m.group(1))
            total_checks_failed += int(m.group(2))

        for line in res.stdout.splitlines():
            if line.startswith("METRIC "):
                kv: dict[str, str] = {}
                for part in line.split()[1:]:
                    if "=" in part:
                        k, v = part.split("=", 1)
                        kv[k] = v
                prof = kv.get("profile")
                if prof:
                    metrics_by_profile[prof] = {
                        k: float(v) for k, v in kv.items() if k != "profile"
                    }

        if res.returncode == 0:
            passed_suites += 1
        else:
            failed_suites += 1
            print(f"  [SUITE FAIL] {suite} exited with {res.returncode}")

    if not args.suite and not args.pre_m1_smoke:
        print("\n=== Cross-Profile Comparison (tier4_village_low vs tier4_village_high) ===")
        low_m = metrics_by_profile.get("low")
        high_m = metrics_by_profile.get("high")
        if not low_m or not high_m:
            failed_suites += 1
            total_checks_failed += 1
            print("  [FAIL] Missing METRIC output from tier4_village_low or tier4_village_high")
        else:
            cmp_checks = [
                (low_m["budget_bytes"] < high_m["budget_bytes"],
                 f"low budget_bytes ({low_m['budget_bytes']:.0f}) < high ({high_m['budget_bytes']:.0f})"),
                (low_m["fpe_cache_max_entries"] < high_m["fpe_cache_max_entries"],
                 f"low fpe_cache_max_entries ({low_m['fpe_cache_max_entries']:.0f}) < high ({high_m['fpe_cache_max_entries']:.0f})"),
                (low_m["psa_max_entries"] < high_m["psa_max_entries"],
                 f"low psa_max_entries ({low_m['psa_max_entries']:.0f}) < high ({high_m['psa_max_entries']:.0f})"),
                (low_m["psa_max_bytes"] < high_m["psa_max_bytes"],
                 f"low psa_max_bytes ({low_m['psa_max_bytes']:.0f}) < high ({high_m['psa_max_bytes']:.0f})"),
                (low_m["fpe_cache_entries"] <= 192.0 < high_m["fpe_cache_entries"] <= 1024.0,
                 f"low fpe_cache_entries ({low_m['fpe_cache_entries']:.0f}) <= 192 < high ({high_m['fpe_cache_entries']:.0f}) <= 1024"),
                (low_m["peak_scratch_bytes"] <= low_m["budget_bytes"]
                 and low_m["peak_scratch_bytes"] <= low_m["color_scratch_cap"]
                 and low_m["peak_scratch_bytes"] < high_m["peak_scratch_bytes"],
                 f"low peak_scratch_bytes ({low_m['peak_scratch_bytes']:.0f}) <= low color_scratch_cap ({low_m['color_scratch_cap']:.0f}) & < high ({high_m['peak_scratch_bytes']:.0f})"),
                (low_m["max_batch_ms"] < 2000.0 and high_m["max_batch_ms"] < 2000.0,
                 f"max_batch_ms within stall bound (low={low_m['max_batch_ms']:.2f}ms, high={high_m['max_batch_ms']:.2f}ms)"),
            ]
            for ok, msg in cmp_checks:
                if ok:
                    total_checks_passed += 1
                    print(f"  [PASS] {msg}")
                else:
                    total_checks_failed += 1
                    failed_suites += 1
                    print(f"  [FAIL] {msg}")

    print(
        f"\n=== C HARNESS SUMMARY: {passed_suites}/{len(suites)} SUITES PASSED, "
        f"{total_checks_passed} CHECKS PASSED, {total_checks_failed} CHECKS FAILED ==="
    )
    return 0 if failed_suites == 0 and total_checks_failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
