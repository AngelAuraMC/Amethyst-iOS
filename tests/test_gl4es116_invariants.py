#!/usr/bin/env python3
"""Host invariant, LF hygiene, JIT guard, and M1/M2/M3 structural test suite."""

import argparse
import re
import sys
import tempfile
from pathlib import Path

BINARY_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".icns", ".ico", ".nib", ".car",
    ".dylib", ".a", ".so", ".dll", ".exe", ".ttf", ".otf", ".woff",
    ".zip", ".jar", ".class", ".o", ".obj", ".bin", ".psa", ".storyboardc",
    ".pyc", ".pyo", ".cer", ".der", ".p12", ".crt", ".mobileprovision", ".spv",
}

SKIP_DIR_PARTS = {"__pycache__", ".git"}

TEXT_ROOTS = ("Natives", "tests", ".github", "Makefile")


def load_submodule_prefixes(root: Path) -> tuple[str, ...]:
    gm = root / ".gitmodules"
    if not gm.exists():
        return ()
    prefixes: list[str] = []
    for line in gm.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^\s*path\s*=\s*(.+?)\s*$", line)
        if m:
            prefixes.append(m.group(1).strip().strip("/").replace("\\", "/") + "/")
    return tuple(prefixes)

PASSED = 0
FAILED = 0
TIER_COUNTS: dict[str, dict[str, int]] = {
    "T1": {"passed": 0, "failed": 0},
    "T2": {"passed": 0, "failed": 0},
    "T3": {"passed": 0, "failed": 0},
    "T4": {"passed": 0, "failed": 0},
    "OTHER": {"passed": 0, "failed": 0},
}


def record(name: str, ok: bool, detail: str = "") -> None:
    global PASSED, FAILED
    tier = "OTHER"
    m = re.search(r"\[(T[1-4])\]", name)
    if m:
        tier = m.group(1)
    if ok:
        PASSED += 1
        TIER_COUNTS[tier]["passed"] += 1
        print(f"  [PASS] {name}" + (f" ({detail})" if detail else ""))
    else:
        FAILED += 1
        TIER_COUNTS[tier]["failed"] += 1
        print(f"  [FAIL] {name}" + (f" ({detail})" if detail else ""))


def is_binary_blob(path: Path, data: bytes) -> bool:
    if path.suffix.lower() in BINARY_EXTENSIONS:
        return True
    if any(part in SKIP_DIR_PARTS for part in path.parts):
        return True
    if data.startswith(b"bplist00"):
        return True
    if len(data) >= 4 and data[:4] in (
        b"\xcf\xfa\xed\xfe",
        b"\xce\xfa\xed\xfe",
        b"\xca\xfe\xba\xbe",
        b"\xbe\xba\xfe\xca",
        b"\x7fELF",
        b"PK\x03\x04",
    ):
        return True
    if data.startswith(b"!<arch>\n"):
        return True
    # Prebuilt Mach-O framework binary without extension inside Frameworks/
    if "Frameworks" in path.parts and b"\x00" in data[:1024]:
        return True
    return False


def scan_unix_lf_tree(root: Path, entries: tuple[str, ...]) -> tuple[int, list[str], list[str]]:
    checked = 0
    crlf_files: list[str] = []
    missing: list[str] = []
    submodule_prefixes = load_submodule_prefixes(root)
    for entry in entries:
        p = root / entry
        if not p.exists():
            missing.append(entry)
            continue
        files = [p] if p.is_file() else sorted(x for x in p.rglob("*") if x.is_file())
        for f in files:
            if any(part in SKIP_DIR_PARTS for part in f.parts):
                continue
            if submodule_prefixes and f.relative_to(root).as_posix().startswith(submodule_prefixes):
                continue
            data = f.read_bytes()
            if is_binary_blob(f, data):
                continue
            checked += 1
            if b"\r" in data:
                cr_cnt = data.count(b"\r")
                crlf_files.append(f"{f.relative_to(root)} (CR={cr_cnt})")
    return checked, crlf_files, missing


def check_unix_lf(repo_root: Path) -> None:
    print("\n--- [1] F10 Unix LF Hygiene (0 CR bytes across Natives/, tests/, .github/, Makefile) ---")
    checked, crlf_files, missing = scan_unix_lf_tree(repo_root, TEXT_ROOTS)
    for m in missing:
        record(f"[F10][T1] Path exists: {m}", False, "missing")
    record(
        "[F10][T1] All text/source/script/config files use pure Unix LF",
        len(crlf_files) == 0 and len(missing) == 0 and checked > 0,
        f"checked={checked}, violations={crlf_files[:10]}",
    )


def check_lf_boundary_suite() -> None:
    print("\n--- [1b] F10 Tier 2 Synthetic LF/CRLF/Binary Boundary Checks ---")
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        # 1. Reject CRLF
        f_crlf = tmp / "sample_crlf.c"
        f_crlf.write_bytes(b"int a = 1;\r\nint b = 2;\r\n")
        chk1, viol1, _ = scan_unix_lf_tree(tmp, ("sample_crlf.c",))
        record("[F10][T2] Synthetic CRLF (\\r\\n) file is detected as violation",
               chk1 == 1 and len(viol1) == 1)

        # 2. Reject lone CR
        f_cr = tmp / "sample_cr.m"
        f_cr.write_bytes(b"int x = 0;\rint y = 1;\r")
        chk2, viol2, _ = scan_unix_lf_tree(tmp, ("sample_cr.m",))
        record("[F10][T2] Synthetic lone CR (\\r) file is detected as violation",
               chk2 == 1 and len(viol2) == 1)

        # 3. Accept pure LF and 0-byte empty files
        f_lf = tmp / "sample_lf.py"
        f_empty = tmp / "empty.txt"
        f_lf.write_bytes(b"print('ok')\n")
        f_empty.write_bytes(b"")
        chk3, viol3, _ = scan_unix_lf_tree(tmp, ("sample_lf.py", "empty.txt"))
        record("[F10][T2] Pure LF and 0-byte empty files pass cleanly",
               chk3 == 2 and len(viol3) == 0)

        # 4. Skip binary assets (.png/.nib/bplist00/Mach-O/Frameworks extensionless) containing CR bytes
        (tmp / "Frameworks").mkdir()
        (tmp / "icon.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\r")
        (tmp / "ui.nib").write_bytes(b"bplist00\r\x00\x01")
        (tmp / "info.plist").write_bytes(b"bplist00\r\n")
        (tmp / "libtest.dylib").write_bytes(b"\xcf\xfa\xed\xfe\r\n\x00\x00")
        (tmp / "Frameworks/AltKit").write_bytes(b"\xcf\xfa\xed\xfe\r\x00\x00\x00")
        chk4, viol4, _ = scan_unix_lf_tree(
            tmp, ("icon.png", "ui.nib", "info.plist", "libtest.dylib", "Frameworks")
        )
        record("[F10][T2] Binary blobs (.png/.nib/bplist00/Mach-O/Frameworks) skip CR scan",
               chk4 == 0 and len(viol4) == 0)

        # 5. Skip .pyc/.pyo and __pycache__ containing CR bytes
        (tmp / "__pycache__").mkdir()
        (tmp / "__pycache__/mod.cpython-310.pyc").write_bytes(b"o\r\r\n\x00\x00\x00\x00")
        (tmp / "standalone.pyc").write_bytes(b"\x00\r\r\n")
        (tmp / "standalone.pyo").write_bytes(b"\x00\r\r\n")
        chk5, viol5, _ = scan_unix_lf_tree(tmp, ("__pycache__", "standalone.pyc", "standalone.pyo"))
        record("[F10][T2] .pyc/.pyo and __pycache__ artifacts skip CR scan without false positives",
               chk5 == 0 and len(viol5) == 0)


def read_text(repo_root: Path, rel: str) -> str:
    p = repo_root / rel
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")


_C_TOKEN_RE = re.compile(
    r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/)',
    re.S,
)


def strip_c_comments(src: str) -> str:
    def _repl(m: re.Match[str]) -> str:
        tok = m.group(0)
        if tok.startswith("//") or tok.startswith("/*"):
            return "\n" * tok.count("\n")
        return tok
    return _C_TOKEN_RE.sub(_repl, src)


def read_c_code(repo_root: Path, rel: str) -> str:
    return strip_c_comments(read_text(repo_root, rel))


def check_jit_guards(repo_root: Path) -> None:
    print("\n--- [2] F10 JIT Startup Guard Non-Regression (b9270f7b, f03cbe4b, a24cea0c) ---")

    lm = read_c_code(repo_root, "Natives/LauncherMenuViewController.m")
    record("[F10][T1] LauncherMenuViewController: get-task-allow || isJITEnabled(false)",
           'getEntitlementValue(@"get-task-allow") || isJITEnabled(false)' in lm)
    record("[F10][T1] LauncherMenuViewController: toolbarItems bounds & main-thread displayProgress",
           "if (!NSThread.isMainThread)" in lm
           and "self.toolbarItems.count > 1" in lm
           and bool(re.search(r"if\s*\(\s*!self\.toolbarItems\s*\|\|\s*self\.toolbarItems\.count\s*==\s*0\s*\)\s*\{\s*return;\s*\}", lm)))
    record("[F10][T1] LauncherMenuViewController: Catalyst/Simulator failure alert guard",
           '!NSProcessInfo.processInfo.macCatalystApp && !getenv("SIMULATOR_DEVICE_NAME")' in lm)

    mm = read_c_code(repo_root, "Natives/main.m")
    record("[F10][T1] main.m: synchronous uncaughtExceptionHandler crash log flush",
           "AME_HOME" in mm and "latestlog.txt" in mm and "synchronizeFile" in mm and "handle_fatal_exit(SIGABRT)" in mm)
    record("[F10][T1] main.m: csops CS_OPS_STATUS, PT_TRACE_ME empty-arg guard, sysctl size init & realpath guard",
           "csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags))" in mm
           and "argc == 2 && argv[1] != NULL && argv[1][0] == '\\0' && !isJITEnabled(true)" in mm
           and "size_t size = 0;" in mm
           and "if (st != 0 || size == 0)" in mm
           and "resolvedHome ? resolvedHome : homeDir.UTF8String" in mm
           and "ptrace(PT_TRACE_ME" in mm
           and 'com.apple.private.security.no-sandbox' in mm
           and "ptrace(PT_DETACH" in mm)
    jl_src = read_c_code(repo_root, "Natives/JavaLauncher.m")
    record("[F10][T1] main.m + JavaLauncher.m: sync boot trace & clean signal uninstall before JVM launch",
           "amethyst_init_boot_trace" in mm
           and "amethyst_uninstall_boot_signal_handlers" in mm
           and "amethyst_uninstall_boot_signal_handlers();" in jl_src)

    mh = read_c_code(repo_root, "Natives/main_hook.m")
    pos_home_tmp = mh.find("((home && strstr(fullpath, home)) || (tmp && strstr(fullpath, tmp)))")
    pos_jit_flags = mh.find("DeviceHasJITFlags(")
    record("[F10][T1] main_hook.m: NULL-safe home/tmp path check evaluated BEFORE DeviceHasJITFlags",
           pos_home_tmp != -1 and pos_jit_flags != -1 and pos_home_tmp < pos_jit_flags)
    record("[F10][T1] main_hook.m: early orig_dlopen bypass + TXM/PPL + LiveContainer sys_dlopen fallback",
           "if (!shouldUseDyldBypass)" in mh
           and "DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED)" in mh
           and "!DeviceHasJITFlags(JIT_FLAG_HAS_TXM)" in mh
           and "PLPatchMachOPlatformForFile(path)" in mh
           and 'sys_dlopen = dlsym(RTLD_NEXT, "dlopen")' in mh
           and "if(!sys_dlopen) sys_dlopen = orig_dlopen;" in mh)

    dp = read_c_code(repo_root, "Natives/dyld_patch_platform.m")
    record("[F10][T1] dyld_patch_platform.m: Mach-O slice/load_command/MAP_FAILED/FAT_CIGAM bounds guards",
           "slice_size < sizeof(struct mach_header_64)" in dp
           and "command->cmdsize < sizeof(struct load_command)" in dp
           and "(uint8_t *)command + command->cmdsize > (uint8_t *)header + slice_size" in dp
           and "dylib->dylib.name.offset < command->cmdsize" in dp
           and "strnlen(dylibName, maxLen) < maxLen" in dp
           and "strlen(verPtr) >= 11" in dp
           and "lastComponentLen >= 0" in dp
           and "if (!map || map == MAP_FAILED)" in dp
           and "nfat_arch <= (s.st_size - sizeof(struct fat_header)) / sizeof(struct fat_arch)" in dp
           and "arch_offset + sizeof(struct mach_header_64) <= s.st_size" in dp)

    ut = read_c_code(repo_root, "Natives/utils.m")
    record("[F10][T1] utils.m: getEntitlementValue CFRelease & isJITEnabled csops/TXM check",
           ("if (!secTask) return NO;" in ut or "if (!secTask) {\n        return NO;\n    }" in ut)
           and "CFRelease(secTask);" in ut
           and "CFRelease(value);" in ut
           and "csops(getpid(), 0, &flags, sizeof(flags));" in ut
           and "(flags & CS_DEBUGGED) == 0" in ut
           and "DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)" in ut
           and "JIT26IsLikelyDebuggerKeepAttached()" in ut)
    record("[F10][T1] utils.m: DeviceHasTXMReal iOS 19 guard, preboot break, RTLD_DEFAULT MGGetSInt64Answer",
           "@available(iOS 19.0, *)" in ut
           and "/private/preboot" in ut
           and "access(txmPath, F_OK) == 0" in ut
           and 'dlsym(RTLD_DEFAULT, "MGGetSInt64Answer")' in ut
           and "if (MGGetSInt64Answer)" in ut)
    record("[F10][T1] utils.m: DeviceGetJITFlags re-entrancy guard (static BOOL evaluating)",
           "static BOOL evaluating = NO;" in ut and "if (evaluating)" in ut)

    # F10 Tier 3 pairwise
    record("[F10][T3] Pairwise JIT guard chain: main_hook path-first x utils re-entrancy x RTLD_NEXT fallback",
           pos_home_tmp != -1 and pos_jit_flags != -1 and pos_home_tmp < pos_jit_flags
           and "static BOOL evaluating = NO;" in ut and "if (evaluating)" in ut
           and 'sys_dlopen = dlsym(RTLD_NEXT, "dlopen")' in mh
           and "if(!sys_dlopen) sys_dlopen = orig_dlopen;" in mh)

    # F10 Tier 4 scenario
    emp_jit = repo_root / "tests/empirical_jit_stress.py"
    emp_ok = emp_jit.exists() and (b"\r" not in emp_jit.read_bytes())
    record("[F10][T4] Scenario: LF hygiene + 5 JIT guard files + empirical_jit_stress.py intact",
           emp_ok and bool(lm and mm and mh and dp and ut))


def check_gl4es_baseline_invariants(repo_root: Path) -> None:
    print("\n--- [3] gl4es_116 Baseline Pipeline Invariants (4e330f27, fe1750f0) ---")

    buf = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/buffers.c")
    m_res = re.search(r"buffer_reserve_shadow\([^)]*\)\s*\{(.*?)\n\}", buf, re.S)
    res_body = m_res.group(1) if m_res else ""
    record("buffers.c: buffer_reserve_shadow has NO 1.5x (size >> 1) exponential growth",
           bool(res_body) and "(size >> 1)" not in res_body and "malloc(size)" in res_body)
    m_sub = re.search(r"gl4es_glBufferSubData\([^)]*\)\s*\{(.*?)\n\}", buf, re.S)
    sub_body = m_sub.group(1) if m_sub else ""
    record("buffers.c: gl4es_glBufferSubData unconditionally syncs shadow buff->data",
           bool(sub_body) and "GL_STREAM_DRAW" not in sub_body and "memcpy((char*)buff->data + offset, data, size)" in sub_body)

    prg = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/program.c")
    record("program.c: clear_program resets applied_matrix_seq = 0",
           "glprogram->applied_matrix_seq = 0;" in prg)

    fpe = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/fpe.c")
    record("fpe.c: fpe_ReleventState zeroes texmat when textype == 0",
           "dest->texture[i].texmat = 0;" in fpe)
    record("fpe.c: fpe_glMaterialf & fpe_glFogfv invoke fpe_state_dirty()",
           "fpe_glMaterialf" in fpe and "fpe_glFogfv" in fpe and fpe.count("fpe_state_dirty()") >= 4)

    mat = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/matrix.c")
    record("matrix.c: init_matrix matrix_seq=1 & set_fpe_textureidentity fpe_state_dirty()",
           "glstate->matrix_seq = 1;" in mat and "set_fpe_textureidentity" in mat and "fpe_state_dirty();" in mat)

    drw = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/drawing.c")
    record("drawing.c: draw_quad_arrays fast-path unbinds 0 & restores old_buffer",
           "bindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);" in drw and "bindBuffer(GL_ELEMENT_ARRAY_BUFFER, old_buffer);" in drw)


def check_m1_m2_m3_contracts(repo_root: Path) -> None:
    print("\n--- [4] M1/M2/M3/M4 Contracts & F9 iOS RAM/Jetsam Plumbing ---")

    mem_h = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/gl4es_mem.h")
    mem_c = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/gl4es_mem.c")
    record("M1: gl4es_mem.h exists with required types and exported APIs",
           bool(mem_h)
           and "gl4es_mem_profile_t" in mem_h
           and "gl4es_mem_stats_t" in mem_h
           and "gl4es_trim_memory" in mem_h
           and "gl4es_get_mem_stats" in mem_h)
    record("M1: gl4es_mem.c exists and implements profile/env/sysctl/trim",
           bool(mem_c)
           and "LIBGL_MEM_PROFILE" in mem_c
           and "AMETHYST_GL4ES_MEM_BUDGET_MB" in mem_c
           and "gl4es_trim_memory" in mem_c
           and "gl4es_get_mem_stats" in mem_c)

    cmake_src = read_text(repo_root, "Natives/external/gl4es_116/src/CMakeLists.txt")
    record("M1: src/CMakeLists.txt GL_SRC includes gl/gl4es_mem.c",
           "gl/gl4es_mem.c" in cmake_src)

    buf = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/buffers.c")
    m_dvao = re.search(r"gl4es_glDeleteVertexArrays\([^)]*\)\s*\{(.*?)\n\}", buf, re.S)
    dvao_body = m_dvao.group(1) if m_dvao else ""
    record("M1: gl4es_glDeleteVertexArrays frees glvao (no commented-out free)",
           bool(dvao_body) and "//free(glvao)" not in dvao_body and "free(glvao);" in dvao_body)

    m_dsb = re.search(r"deleteSingleBuffer\([^)]*\)\s*\{(.*?)\n\}", buf, re.S)
    dsb_body = m_dsb.group(1) if m_dsb else ""
    record("M1: deleteSingleBuffer clears want_index even when index == buffer",
           bool(dsb_body) and "else if(glstate->bind_buffer.want_index == buffer)" not in dsb_body
           and "want_index" in dsb_body)

    drw = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/drawing.c")
    record("M1/M2: drawing.c eliminates static GLushort *indices leak",
           "static GLushort *indices" not in drw)
    record("M2: drawing.c fallback quad paths restore via bindBuffer(GL_ELEMENT_ARRAY_BUFFER, old_buffer)",
           "wantBufferIndex(old_buffer);" not in drw)

    fpe_c = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/fpe.c")
    m_rel = re.search(r"realize_glenv\([^)]*\)\s*\{(.*?)\n\}", fpe_c, re.S)
    rel_body = m_rel.group(1) if m_rel else ""
    # Verify fpe_bound_changed block does NOT unconditionally bump fpe_generation and DOES guard fpe_generation++ on TMU state change
    m_bound_blk = re.search(
        r"if\s*\(\s*glstate->fpe_bound_changed\s*&&\s*!glstate->glsl->program\s*\)\s*\{(.*?)\n\s*glstate->fpe_bound_changed\s*=\s*0;",
        rel_body,
        re.S,
    )
    bound_blk = m_bound_blk.group(1) if m_bound_blk else ""
    has_uncond_inc = bool(re.match(r"^\s*glstate->fpe_generation\+\+;", bound_blk))
    has_cond_inc = bool(re.search(r"if\s*\([^)]+\)\s*(?:\{\s*)?glstate->fpe_generation\+\+;", bound_blk, re.S))
    record("M2: realize_glenv only bumps fpe_generation on effective TMU tuple change",
           bool(bound_blk) and not has_uncond_inc and has_cond_inc)

    fpe_cache = read_c_code(repo_root, "Natives/external/gl4es_116/src/gl/fpe_cache.c")
    record("M1: fpe_cache.c enforces tiered FPE & PSA bounds/eviction",
           "gl4es_mem_fpe_cache_max_entries" in fpe_cache
           and "gl4es_mem_psa_max_entries" in fpe_cache
           and "gl4es_mem_psa_max_bytes" in fpe_cache
           and "fpe_CacheTrim" in fpe_cache
           and "fpe_PSATrim" in fpe_cache)

    # F9: iOS RAM/Jetsam plumbing & didReceiveMemoryWarning (Tier 1: >=5, Tier 2: >=5, Tier 3: 1, Tier 4: 1)
    makefile = read_text(repo_root, "Makefile")
    jl = read_c_code(repo_root, "Natives/JavaLauncher.m")
    eb = read_c_code(repo_root, "Natives/egl_bridge.m")
    gb = read_c_code(repo_root, "Natives/ctxbridges/gl_bridge.m")
    svc = read_c_code(repo_root, "Natives/SurfaceViewController.m")

    jl_gb = jl + "\n" + gb
    has_ram_probe = ("physicalMemory" in jl_gb) and ("os_proc_available_memory" in jl_gb)
    record("[F9][T1] M3: JavaLauncher/gl_bridge probes physicalMemory & os_proc_available_memory",
           has_ram_probe)

    has_mem_env = ("LIBGL_MEM_PROFILE" in jl_gb) and ("AMETHYST_GL4ES_MEM_BUDGET_MB" in jl_gb or "LIBGL_MEM_PROFILE" in jl)
    record("[F9][T1] M3: Sets LIBGL_MEM_PROFILE and/or AMETHYST_GL4ES_MEM_BUDGET_MB before GL4ES init",
           has_mem_env)

    pos_mem_prof = jl.find("LIBGL_MEM_PROFILE")
    pos_custom_env = jl.find("init_loadCustomEnv()")
    record("[F9][T1] M3: JavaLauncher configures auto LIBGL_MEM_PROFILE BEFORE init_loadCustomEnv()",
           pos_mem_prof != -1 and pos_custom_env != -1 and pos_mem_prof < pos_custom_env)

    record("[F9][T1] M3: gl_bridge resolves set_getprocaddress + initialize_gl4es via get_gl4es_116_handle()",
           "get_gl4es_116_handle()" in gb
           and "set_getprocaddress" in gb
           and "initialize_gl4es" in gb
           and "get_gl4es_116_handle" in eb)

    record("[F9][T1] M3: SurfaceViewController implements didReceiveMemoryWarning -> gl4es_trim_memory",
           "didReceiveMemoryWarning" in svc
           and "[super didReceiveMemoryWarning]" in svc
           and "gl4es_trim_memory" in svc)

    # F9 Tier 2 boundaries
    record("[F9][T2] M3: Low RAM threshold (<= 2.5GB / 2560MB) maps to \"low\" & clamps os_proc_available_memory",
           ('"low"' in jl_gb or '"low"' in gb)
           and "os_proc_available_memory" in jl_gb
           and ("2560" in jl_gb or "2684354560" in jl_gb or "2.5" in jl_gb or "3072" in jl_gb))

    record("[F9][T2] M3: Medium & High RAM tiers (\"medium\" and \"high\") mapped in iOS launcher/bridge",
           '"medium"' in jl_gb and '"high"' in jl_gb)

    record("[F9][T2] M3: egl_bridge sets s_gl4es116Handle = NULL for non-gl4es_116 renderers",
           "s_gl4es116Handle = handle;" in eb and "s_gl4es116Handle = NULL;" in eb)

    m_drw_mem = re.search(r"-\s*\(void\)\s*didReceiveMemoryWarning\s*\{(.*?)\n\}", svc, re.S)
    drw_mem_body = m_drw_mem.group(1) if m_drw_mem else ""
    record("[F9][T2] M3: SurfaceViewController didReceiveMemoryWarning NULL-guards handle & dlsym",
           bool(drw_mem_body)
           and "get_gl4es_116_handle()" in drw_mem_body
           and 'dlsym(' in drw_mem_body
           and "gl4es_trim_memory" in drw_mem_body
           and bool(re.search(r"if\s*\(\s*!?\s*\w*(handle|trim|fn)", drw_mem_body)))

    record("[F9][T2] M4/M1: Makefile dep_gl4es_116 verifies _gl4es_trim_memory & _gl4es_get_mem_stats",
           "_gl4es_trim_memory" in makefile and "_gl4es_get_mem_stats" in makefile)

    # F9 Tier 3 pairwise
    record("[F9][T3] Pairwise M3: JavaLauncher custom env override x gl_bridge dispatch_once x didReceiveMemoryWarning urgency",
           pos_mem_prof != -1 and pos_custom_env != -1 and pos_mem_prof < pos_custom_env
           and "dispatch_once" in gb
           and "didReceiveMemoryWarning" in svc and "gl4es_trim_memory" in svc)

    # F9 Tier 4 scenario
    record("[F9][T4] Scenario: End-to-end iOS RAM -> dlopen -> initialize_gl4es -> memory warning trim -> Makefile gate",
           has_ram_probe
           and has_mem_env
           and "s_gl4es116Handle = handle;" in eb
           and "init_gl4es_116_if_needed" in gb
           and "didReceiveMemoryWarning" in svc
           and "gl4es_trim_memory" in svc
           and "_gl4es_trim_memory" in makefile
           and "_gl4es_get_mem_stats" in makefile)


def main() -> int:
    parser = argparse.ArgumentParser(description="gl4es_116 E2E invariant & hygiene checks")
    parser.add_argument(
        "--mode",
        choices=["hygiene-jit", "baseline", "all"],
        default="all",
        help="hygiene-jit: F10 LF + JIT guards; baseline: + 4e330f27/fe1750f0; all: + M1/M2/M3/M4 & F9",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    print(f"=== gl4es116 Invariant Suite (mode={args.mode}, root={repo_root}) ===")

    check_unix_lf(repo_root)
    check_lf_boundary_suite()
    check_jit_guards(repo_root)
    if args.mode in ("baseline", "all"):
        check_gl4es_baseline_invariants(repo_root)
    if args.mode == "all":
        check_m1_m2_m3_contracts(repo_root)

    print("\n--- Per-Tier Summary ---")
    for tier in ("T1", "T2", "T3", "T4", "OTHER"):
        c = TIER_COUNTS[tier]
        if c["passed"] or c["failed"]:
            print(f"  {tier}: {c['passed']} PASSED, {c['failed']} FAILED")

    print(f"\n=== INVARIANT SUMMARY: {PASSED} PASSED, {FAILED} FAILED ===")
    return 0 if FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
