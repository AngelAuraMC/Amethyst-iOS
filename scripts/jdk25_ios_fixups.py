#!/usr/bin/env python3
"""Apply iOS fixups to OpenJDK 25 source that the JDK 21 patch couldn't.

The JDK 21 iOS base patch (patches/jre_21/ios/1_jdk21u_ios.diff) applies
mostly clean to JDK 25 source, but ~14 hunks reject because OpenJDK source
moved between 21 and 25. This script finishes the job by applying targeted
text replacements for each rejected hunk.

Idempotent — safe to re-run. Reports skip/ok/warn for each file.

Usage: python3 jdk25_ios_fixups.py [/path/to/openjdk-25]
"""
import sys, os
from pathlib import Path

JDK = Path(sys.argv[1] if len(sys.argv) > 1 else 'openjdk-25')
os.chdir(JDK)

ok = warn = skip = 0


def patch(path, transformations, replace_all=False):
    """Apply (old_text, new_text) tuples to file. Each transformation is
    independent — reports per file at end. If replace_all=True, every
    occurrence of `old` is replaced (use for patterns that recur in the
    same file like nmethod.cpp's many `(this)` write sites)."""
    global ok, warn, skip
    p = Path(path)
    if not p.exists():
        print(f"  [WARN] missing file: {path}")
        warn += 1
        return
    s = original = p.read_text()
    file_status = []
    for label, old, new in transformations:
        if new in s and old not in s:
            file_status.append(f"skip:{label}")
            continue
        if old in s:
            n = s.count(old) if replace_all else 1
            s = s.replace(old, new) if replace_all else s.replace(old, new, 1)
            file_status.append(f"ok:{label}({n}x)" if replace_all else f"ok:{label}")
        else:
            file_status.append(f"WARN:{label}")
    if s != original:
        p.write_text(s)
    statuses = ", ".join(file_status)
    print(f"  {path}: {statuses}")
    if "WARN:" in statuses:
        warn += 1
    elif "ok:" in statuses:
        ok += 1
    else:
        skip += 1


# 1. flags-ldflags.m4 — comment out OS_LDFLAGS for iOS (keeping JDK 25's
#    -Wl,-reproducible suffix which JDK 21 didn't have)
patch('make/autoconf/flags-ldflags.m4', [
    ("comment-os-ldflags",
     '    OS_LDFLAGS="-mmacosx-version-min=$MACOSX_VERSION_MIN -Wl,-reproducible"',
     '    #OS_LDFLAGS="-mmacosx-version-min=$MACOSX_VERSION_MIN -Wl,-reproducible"'),
])

# 2. MakeBase.gmk — original hunk just removes a blank line. Cosmetic, skip.

# 3. LauncherCommon.gmk — JDK 25 moved per-launcher LIBS into individual
#    module Lib.gmk files, so the Cocoa→Foundation swap that was here in
#    JDK 21 is now handled by the individual module patches below. Skip.

# 4. java.base/Lib.gmk — (a) add CFNetwork to libnet, (b) skip libosxsecurity
patch('make/modules/java.base/Lib.gmk', [
    ("libnet-add-cfnetwork",
     "    LIBS_macosx := \\\n        -framework CoreFoundation \\\n        -framework CoreServices, \\\n))\n\nTARGETS += $(BUILD_LIBNET)",
     "    LIBS_macosx := \\\n        -framework CoreFoundation \\\n        -framework CoreServices \\\n        -framework CFNetwork, \\\n))\n\nTARGETS += $(BUILD_LIBNET)"),
    ("skip-libosxsecurity-on-ios",
     "ifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  ## Build libosxsecurity",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  ## Build libosxsecurity"),
])

# 5. java.base/lib/CoreLibraries.gmk — libjli: ApplicationServices+Cocoa → Foundation
patch('make/modules/java.base/lib/CoreLibraries.gmk', [
    ("libjli-foundation-only",
     "    LIBS_macosx := \\\n        -framework ApplicationServices \\\n        -framework Cocoa \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib comctl32.lib user32.lib, \\",
     "    LIBS_macosx := \\\n        -framework Foundation \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib comctl32.lib user32.lib, \\"),
])

# 6. java.desktop/Lib.gmk — (a) AudioUnit → AVFoundation in libjsound,
#    (b) skip libosxapp on iOS
patch('make/modules/java.desktop/Lib.gmk', [
    ("libjsound-avfoundation",
     "      LIBS_macosx := \\\n          -framework AudioToolbox \\\n          -framework AudioUnit \\\n          -framework CoreAudio \\",
     "      LIBS_macosx := \\\n          -framework AudioToolbox \\\n          -framework AVFoundation \\\n          -framework CoreAudio \\"),
    ("skip-libosxapp-on-ios",
     "ifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  # Build libosxapp",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  # Build libosxapp"),
])

# 7. java.instrument/Lib.gmk — libinstrument: ApplicationServices+Cocoa → Foundation
patch('make/modules/java.instrument/Lib.gmk', [
    ("libinstrument-foundation-only",
     "    LIBS_macosx := \\\n        -framework ApplicationServices \\\n        -framework Cocoa \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib, \\",
     "    LIBS_macosx := \\\n        -framework Foundation \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib, \\"),
])

# 8. java.security.jgss/Lib.gmk — skip libosxkrb5 on iOS
patch('make/modules/java.security.jgss/Lib.gmk', [
    ("skip-libosxkrb5-on-ios",
     "  ifeq ($(call isTargetOs, macosx), true)\n    ############################################################################\n    ## Build libosxkrb5",
     "  ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n    ############################################################################\n    ## Build libosxkrb5"),
])

# 9. jdk.hotspot.agent/Lib.gmk — skip building libsaproc on iOS (was libsa
#    in JDK 21, renamed to libsaproc in JDK 25; see SetupJdkLibrary block name)
patch('make/modules/jdk.hotspot.agent/Lib.gmk', [
    ("skip-libsaproc-target",
     "TARGETS += $(BUILD_LIBSAPROC)",
     "#TARGETS += $(BUILD_LIBSAPROC)  # disabled for iOS"),
])

# 10. jdk.jpackage/Lib.gmk — applauncher: Cocoa → Foundation
patch('make/modules/jdk.jpackage/Lib.gmk', [
    ("jpackage-applauncher-foundation",
     "    LIBS_macosx := -framework Cocoa, \\",
     "    LIBS_macosx := -framework Foundation, \\"),
])

# 11. signals_posix.cpp — add includes for os_bsd.hpp + sys/mman.h
patch('src/hotspot/os/posix/signals_posix.cpp', [
    ("add-os-bsd-include",
     '#include "utilities/vmError.hpp"\n\n#include <signal.h>',
     '#include "utilities/vmError.hpp"\n#include "os_bsd.hpp"\n\n#include <signal.h>\n#include <sys/mman.h>'),
])

# 13. memMapPrinter_macosx.cpp — uses <mach/mach_vm.h> which iOS SDK marks
#     "unsupported". Wrap the entire macOS body in an extra iOS guard, then
#     append an iOS stub so the linker still resolves
#     MemMapPrinter::pd_print_all_mappings called from shared NMT code.
def patch_memmapprinter():
    p = Path('src/hotspot/os/bsd/memMapPrinter_macosx.cpp')
    if not p.exists():
        print(f"  [WARN] missing file: {p}")
        return
    s = original = p.read_text()
    if 'TARGET_OS_IPHONE' in s:
        print(f"  {p}: skip (already patched)")
        return
    # Replace top guard
    s = s.replace(
        "#if defined(__APPLE__)\n\n#include \"nmt/memMapPrinter.hpp\"",
        "#include <TargetConditionals.h>\n#if defined(__APPLE__) && !TARGET_OS_IPHONE\n\n#include \"nmt/memMapPrinter.hpp\"",
        1,
    )
    # Append iOS stub at end of file
    stub = (
        "\n\n#if defined(__APPLE__) && TARGET_OS_IPHONE\n"
        "// iOS stub: NMT memory-map printing requires <mach/mach_vm.h> which the\n"
        "// iOS SDK marks unsupported. Provide an empty implementation so the\n"
        "// shared NMT module's call resolves at link time.\n"
        "#include \"nmt/memMapPrinter.hpp\"\n"
        "void MemMapPrinter::pd_print_all_mappings(const MappingPrintSession&) {}\n"
        "#endif\n"
    )
    s = s + stub
    if s != original:
        p.write_text(s)
        print(f"  {p}: ok:guard-and-stub-on-ios")
        global ok
        ok += 1
patch_memmapprinter()

# 12. icache_bsd_aarch64.hpp — wrap __clear_cache with iOS-compatible version
#     using sys_icache_invalidate. JDK 25 has `initialize(int phase)` (vs
#     plain `initialize()` in JDK 21), so context is slightly different.
patch('src/hotspot/os_cpu/bsd_aarch64/icache_bsd_aarch64.hpp', [
    ("ios-clear-cache-wrapper",
     "  static void initialize(int phase);\n  static void invalidate_word(address addr) {\n    __clear_cache((char *)addr, (char *)(addr + 4));\n  }\n  static void invalidate_range(address start, int nbytes) {\n    __clear_cache((char *)start, (char *)(start + nbytes));\n  }",
     "  static void initialize(int phase);\n#if defined(__APPLE__) && defined(__arm64__)\n  static void __clear_cache_(void *start, void *end) {\n    sys_icache_invalidate(start, (char *)end - (char *)start);\n  }\n#else\n  #define __clear_cache_ __clear_cache\n#endif\n  static void invalidate_word(address addr) {\n    __clear_cache_((char *)addr, (char *)(addr + 4));\n  }\n  static void invalidate_range(address start, int nbytes) {\n    __clear_cache_((char *)start, (char *)(start + nbytes));\n  }"),
])

# 14. AwtLibraries.gmk — JDK 25 renamed Awt2dLibraries.gmk to AwtLibraries.gmk.
#     The libjawt source for macOS lives in src/java.desktop/macosx which
#     6_buildjdk.sh moves to macosx_NOTIOS at build time, so SetupJdkLibrary
#     fails with "No sources found for BUILD_LIBJAWT". Wrap the SetupJdkLibrary
#     call AND the TARGETS line in a macosx_NOTIOS guard so iOS skips libjawt
#     entirely (Pojav iOS uses GLFW + LWJGL directly, no AWT needed).
def patch_awtlibraries():
    p = Path('make/modules/java.desktop/lib/AwtLibraries.gmk')
    if not p.exists():
        print(f"  [WARN] missing file: {p}")
        return
    s = original = p.read_text()
    if 'libjawt disabled for iOS' in s:
        print(f"  {p}: skip (already patched)")
        return
    old_block = (
        "$(eval $(call SetupJdkLibrary, BUILD_LIBJAWT, \\\n"
        "    NAME := jawt, \\\n"
        "    EXCLUDE_SRC_PATTERNS := $(LIBJAWT_EXCLUDE_SRC_PATTERNS), \\\n"
        "    OPTIMIZATION := LOW, \\\n"
        "    CFLAGS := $(LIBJAWT_CFLAGS), \\\n"
        "    CFLAGS_windows := -EHsc -DUNICODE -D_UNICODE, \\\n"
        "    CXXFLAGS_windows := -EHsc -DUNICODE -D_UNICODE, \\\n"
        "    DISABLED_WARNINGS_clang_jawt.m := sign-compare, \\\n"
        "    EXTRA_HEADER_DIRS := $(LIBJAWT_EXTRA_HEADER_DIRS), \\\n"
        "    LDFLAGS_windows := $(LDFLAGS_CXX_JDK), \\\n"
        "    LDFLAGS_macosx := -Wl$(COMMA)-rpath$(COMMA)@loader_path, \\\n"
        "    JDK_LIBS_unix := $(LIBJAWT_JDK_LIBS_unix), \\\n"
        "    JDK_LIBS_windows := libawt, \\\n"
        "    JDK_LIBS_macosx := libawt_lwawt, \\\n"
        "    LIBS_macosx := -framework Cocoa, \\\n"
        "    LIBS_windows := advapi32.lib $(LIBJAWT_LIBS_windows), \\\n"
        "))\n"
        "\n"
        "TARGETS += $(BUILD_LIBJAWT)"
    )
    if old_block not in s:
        print(f"  {p}: WARN libjawt block not found verbatim")
        global warn
        warn += 1
        return
    new_block = (
        "# libjawt disabled for iOS — no AWT support, src/java.desktop/macosx moved out\n"
        "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n"
        + old_block + "\n"
        "endif"
    )
    s = s.replace(old_block, new_block, 1)
    p.write_text(s)
    print(f"  {p}: ok:guard-libjawt-on-ios")
    global ok
    ok += 1
patch_awtlibraries()

# 15. ClientLibraries.gmk — JDK 25's libosxui block also depends on
#     src/java.desktop/macosx sources (Metal shaders + AquaFileView etc.)
#     which we move to macosx_NOTIOS. Skip the entire macosx libosxui block
#     by changing its outer ifeq to macosx_NOTIOS.
patch('make/modules/java.desktop/lib/ClientLibraries.gmk', [
    ("skip-libosxui-on-ios",
     "TARGETS += $(BUILD_LIBFONTMANAGER)\n\nifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  ## Build libosxui",
     "TARGETS += $(BUILD_LIBFONTMANAGER)\n\nifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  ## Build libosxui"),
    # libfontmanager's macOS variant pulled libawt_lwawt; on iOS we only have
    # libawt_headless (libawt_lwawt is skipped). JDK 21 patch did the same swap.
    ("libfontmanager-headless-on-ios",
     "    JDK_LIBS_macosx := libawt_lwawt, \\",
     "    JDK_LIBS_macosx := libawt_headless, \\"),
])

# 16. AwtLibraries.gmk — port the JDK 21 patch's libawt/lwawt iOS strategy:
#     (a) BUILD_LIBAWT links macOS frameworks (ApplicationServices, Cocoa,
#         OpenGL, JavaRuntimeSupport) that don't exist on iOS — change
#         LIBS_macosx to LIBS_macosx_NOTIOS so iOS gets an empty link list.
#     (b) The libawt_excludeFiles macosx ifeq excludes initIDs/img_colors
#         only on real macOS (the iOS build needs them in libawt_headless).
#     (c) libawt_headless is gated off for windows+macosx — flip the guard
#         to macosx_NOTIOS so it builds on iOS instead.
#     (d) BUILD_LIBAWT_LWAWT is the AppKit-using path; skip entirely on iOS
#         since src/java.desktop/macosx is moved out and libosxapp doesn't
#         exist on iOS.
patch('make/modules/java.desktop/lib/AwtLibraries.gmk', [
    ("libawt-exclude-files-macosx-only-real-mac",
     "ifeq ($(call isTargetOs, macosx), true)\n  LIBAWT_EXCLUDE_FILES += initIDs.c img_colors.c\nendif",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  LIBAWT_EXCLUDE_FILES += initIDs.c img_colors.c\nendif"),
    ("libawt-libs-macosx-not-ios",
     "    LIBS_aix := $(LIBDL), \\\n    LIBS_macosx := \\\n        -framework ApplicationServices \\\n        -framework AudioToolbox \\\n        -framework Cocoa \\\n        -framework JavaRuntimeSupport \\\n        -framework Metal \\\n        -framework OpenGL, \\",
     "    LIBS_aix := $(LIBDL), \\\n    LIBS_macosx_NOTIOS := \\\n        -framework ApplicationServices \\\n        -framework AudioToolbox \\\n        -framework Cocoa \\\n        -framework JavaRuntimeSupport \\\n        -framework Metal \\\n        -framework OpenGL, \\"),
    ("libawt-headless-build-on-ios",
     "# Mac and Windows only use the native AWT lib, do not build libawt_headless\nifeq ($(call isTargetOs, windows macosx), false)",
     "# Mac and Windows only use the native AWT lib, do not build libawt_headless\n# (iOS gets libawt_headless because we skip the Cocoa-using libawt_lwawt)\nifeq ($(call isTargetOs, windows macosx_NOTIOS), false)"),
    ("skip-libawt-lwawt-on-ios",
     "ifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  ## Build libawt_lwawt",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  ## Build libawt_lwawt"),
])

# 17. JDK 21 patch swapped pthread_jit_write_protect_np() for jit_write_protect()
#     defined in tcg-apple-jit.h, which uses APRR (Apple's old W^X mechanism).
#     APRR is disabled on iPhone 17 / iOS 26 / A19 Pro (TXM hardware enforcement
#     replaced it). On these devices jit_write_protect() reads
#     _COMM_PAGE_APRR_SUPPORT, gets 0, and returns as a no-op — JIT pages
#     never transition to executable, SIGBUS at first call_stub.
#
#     crystall1ne's build doesn't hit this because they ALSO have patch 2
#     (mirror_mapping) which handles W^X via dual virtual mappings, making
#     jit_write_protect's no-op irrelevant.
#
#     Without porting full mirror_mapping (Phase 2 work), substitute the
#     standard Apple API pthread_jit_write_protect_np() back in. It works
#     correctly on iOS 26 + TXM when the process holds JIT entitlement
#     (StikDebug provides this). Also include <pthread.h> for the prototype.
# 17. atomic.hpp needs `#include "os_bsd.hpp"` so mirror_w / mirror_x macros
#     are visible. The mirror_mapping patch's hunk for this file rejected
#     because JDK 25 has additional includes (utilities/checkedCast.hpp)
#     that shifted the context. Add the include manually.
patch('src/hotspot/share/runtime/atomic.hpp', [
    ("add-os-bsd-include-for-mirror-macros",
     "#include \"utilities/macros.hpp\"\n\n#include <type_traits>",
     "#include \"utilities/macros.hpp\"\n\n#ifdef __APPLE__\n#include \"os_bsd.hpp\"\n#endif\n\n#include <type_traits>"),
])

# 18. JDK 25 packs nmethod flags into a single uint8_t bit-field declaration
#     for memory savings. mirror_w_set(_x) expands to *mirror_w(&(_x)) which
#     takes the address of _x — illegal in C++ for bit-fields. The
#     mirror_mapping patch's set_load_reported / set_is_unlinked /
#     set_has_flushed_dependencies hunks apply textually but break compile:
#       nmethod.hpp:880:53: error: address of bit-field requested
#     Convert the 8 :1 bit-fields into 8 separate uint8_t fields (cost: 7
#     extra bytes per nmethod, negligible against typical nmethod sizes).
#     ALL fields in the group are split — even the ones not currently wrapped
#     in mirror_w_set — so the declaration stays consistent and future patches
#     can wrap any of them without re-tripping the bit-field error.
patch('src/hotspot/share/code/nmethod.hpp', [
    ("split-nmethod-flag-bitfields",
     "  uint8_t _has_unsafe_access:1,        // May fault due to unsafe access.\n"
     "          _has_method_handle_invokes:1,// Has this method MethodHandle invokes?\n"
     "          _has_wide_vectors:1,         // Preserve wide vectors at safepoints\n"
     "          _has_monitors:1,             // Fastpath monitor detection for continuations\n"
     "          _has_scoped_access:1,        // used by for shared scope closure (scopedMemoryAccess.cpp)\n"
     "          _has_flushed_dependencies:1, // Used for maintenance of dependencies (under CodeCache_lock)\n"
     "          _is_unlinked:1,              // mark during class unloading\n"
     "          _load_reported:1;            // used by jvmti to track if an event has been posted for this nmethod",
     "  uint8_t _has_unsafe_access;        // May fault due to unsafe access.\n"
     "  uint8_t _has_method_handle_invokes;// Has this method MethodHandle invokes?\n"
     "  uint8_t _has_wide_vectors;         // Preserve wide vectors at safepoints\n"
     "  uint8_t _has_monitors;             // Fastpath monitor detection for continuations\n"
     "  uint8_t _has_scoped_access;        // used by for shared scope closure (scopedMemoryAccess.cpp)\n"
     "  uint8_t _has_flushed_dependencies; // Used for maintenance of dependencies (under CodeCache_lock)\n"
     "  uint8_t _is_unlinked;              // mark during class unloading\n"
     "  uint8_t _load_reported;            // used by jvmti to track if an event has been posted for this nmethod"),
    # Multi-line setters that the JDK 21 mirror_mapping patch couldn't place
    # because JDK 25 changed the signatures (e.g. set_has_flushed_dependencies
    # now takes `bool z` and stores `z` instead of literal 1).
    ("set-has-flushed-dependencies-mirror-w-set",
     "    assert(!has_flushed_dependencies(), \"should only happen once\");\n    _has_flushed_dependencies = z;",
     "    assert(!has_flushed_dependencies(), \"should only happen once\");\n    mirror_w_set(_has_flushed_dependencies) = z;"),
    ("set-is-unlinked-mirror-w-set",
     "     assert(!_is_unlinked, \"already unlinked\");\n      _is_unlinked = true;",
     "     assert(!_is_unlinked, \"already unlinked\");\n      mirror_w_set(_is_unlinked) = true;"),
    # The other 5 setters that write directly to (now byte-sized) flag fields
    # without mirror_w_set. v5 confirmed this SIGBUSes inside ciEnv::register_method
    # at +0x5fc when the JIT compiler does `nm->set_has_unsafe_access(...)` etc.
    # nmethod returned from new_nmethod is mirror_x (the JDK 21 hunk
    # `nm = mirror_x(nm);` DID apply via git apply), so writes through `this`
    # need explicit mirror_w_set on iOS 26+TXM where mirror_w/x are different
    # virtual mappings (vs APRR-based JDK 21 path where they were one RWX page).
    ("set-has-unsafe-access-mirror-w-set",
     "  void  set_has_unsafe_access(bool z)             { _has_unsafe_access = z; }",
     "  void  set_has_unsafe_access(bool z)             { mirror_w_set(_has_unsafe_access) = z; }"),
    ("set-has-monitors-mirror-w-set",
     "  void  set_has_monitors(bool z)                  { _has_monitors = z; }",
     "  void  set_has_monitors(bool z)                  { mirror_w_set(_has_monitors) = z; }"),
    ("set-has-scoped-access-mirror-w-set",
     "  void  set_has_scoped_access(bool z)             { _has_scoped_access = z; }",
     "  void  set_has_scoped_access(bool z)             { mirror_w_set(_has_scoped_access) = z; }"),
    ("set-has-method-handle-invokes-mirror-w-set",
     "  void  set_has_method_handle_invokes(bool z)     { _has_method_handle_invokes = z; }",
     "  void  set_has_method_handle_invokes(bool z)     { mirror_w_set(_has_method_handle_invokes) = z; }"),
    ("set-has-wide-vectors-mirror-w-set",
     "  void  set_has_wide_vectors(bool z)              { _has_wide_vectors = z; }",
     "  void  set_has_wide_vectors(bool z)              { mirror_w_set(_has_wide_vectors) = z; }"),
    # Other inline setters that write nmethod fields directly. set_method is
    # called from register_method right after make_in_use, set_osr_link is
    # called by add_osr_nmethod for OSR compiles, set_gc_data is called by GC.
    ("set-method-mirror-w-set",
     "  void set_method(Method* method) { _method = method; }",
     "  void set_method(Method* method) { mirror_w_set(_method) = method; }"),
    ("set-osr-link-mirror-w-set",
     "  void     set_osr_link(nmethod *n) { _osr_link = n; }",
     "  void     set_osr_link(nmethod *n) { mirror_w_set(_osr_link) = n; }"),
])

# 29. nmethod.cpp Atomic ops + direct field writes that fault when `this`
#     is mirror_x. The JDK 21 hunk inserts `nm = mirror_x(nm);` in new_nmethod,
#     so every method call on `nm` ends up with `this` = mirror_x. Any
#     `Atomic::store(&_field, val)` or `_field = val` inside such methods
#     writes via mirror_x → BUS_ADRALN on iOS 26 + TXM.
#
#     v6 fixed register_method's setters (set_has_*, try_transition's _state).
#     v7 testing exposed nmethod::purge crashing at `_immutable_data = blob_end();`
#     (libjvm.dylib+0x8529d8). Same shape applies to *all* Atomic ops on
#     nmethod fields and all post-construction direct field writes — wrap them
#     comprehensively here so we don't whack-a-mole one site at a time.
#
#     mirror_w is idempotent on already-W addresses (returns input unchanged),
#     so wrapping `&_field` is safe whether `this` is mirror_w or mirror_x.
patch('src/hotspot/share/code/nmethod.cpp', [
    # try_transition's _state store (kept here for documentation; my earlier
    # fixup already added this exact pair so it'll skip)
    ("try-transition-atomic-store-mirror-w",
     "  Atomic::store(&_state, new_state);",
     "  Atomic::store(mirror_w(&_state), new_state);"),
    # nmethod::purge writes _immutable_data after free
    ("purge-immutable-data-mirror-w-set",
     "    _immutable_data = blob_end(); // Valid not null address",
     "    mirror_w_set(_immutable_data) = blob_end(); // Valid not null address"),
    # set_deoptimized_done's atomic store
    ("set-deoptimized-done-mirror-w",
     "    Atomic::store(&_deoptimization_status, deoptimize_done);",
     "    Atomic::store(mirror_w(&_deoptimization_status), deoptimize_done);"),
    # mark_as_maybe_on_stack — GC marks epoch
    ("mark-on-stack-gc-epoch-mirror-w",
     "  Atomic::store(&_gc_epoch, CodeCache::gc_epoch());",
     "  Atomic::store(mirror_w(&_gc_epoch), CodeCache::gc_epoch());"),
    # clear_unloading_state — GC clears unloading state
    ("clear-unloading-state-mirror-w",
     "  Atomic::store(&_is_unloading_state, state);",
     "  Atomic::store(mirror_w(&_is_unloading_state), state);"),
    # is_unloading state CAS (set_unloading_state-like path)
    ("is-unloading-cmpxchg-mirror-w",
     "Atomic::cmpxchg(&_is_unloading_state, state, new_state, memory_order_relaxed);",
     "Atomic::cmpxchg(mirror_w(&_is_unloading_state), state, new_state, memory_order_relaxed);"),
    # finalize_relocations creates _compiled_ic_data array
    ("compiled-ic-data-mirror-w-set",
     "    _compiled_ic_data = new CompiledICData[virtual_call_data.length()];",
     "    mirror_w_set(_compiled_ic_data) = new CompiledICData[virtual_call_data.length()];"),
    # oops_do_mark_link write
    ("oops-do-mark-link-mirror-w-set",
     "  _oops_do_mark_link = mark_link(old_head, claim_strong_done_tag);",
     "  mirror_w_set(_oops_do_mark_link) = mark_link(old_head, claim_strong_done_tag);"),
], replace_all=True)

# 30. nmethod.cpp Atomic::cmpxchg on _exception_cache — appears in
#     add_exception_cache_entry and clean_exception_cache. There are 3 sites
#     all matching `Atomic::cmpxchg(&_exception_cache, X, Y)` with different
#     args; replace_all of just the address part is the cleanest.
patch('src/hotspot/share/code/nmethod.cpp', [
    ("exception-cache-cmpxchg-addr-mirror-w",
     "Atomic::cmpxchg(&_exception_cache,",
     "Atomic::cmpxchg(mirror_w(&_exception_cache),"),
    # oops_do_mark_link cmpxchg has 4 sites with different args, replace_all
    # of the address part covers all of them.
    ("oops-do-mark-link-cmpxchg-addr-mirror-w",
     "Atomic::cmpxchg(&_oops_do_mark_link,",
     "Atomic::cmpxchg(mirror_w(&_oops_do_mark_link),"),
], replace_all=True)

# 31. CodeBlob::purge — same problem class. The base class purge runs after
#     nmethod::purge calls `CodeBlob::purge();`, with `this` still mirror_x'd.
#     Four direct field writes need mirror_w_set. _oop_maps was already
#     wrapped via the JDK 21 hunk that applied (the line is now
#     `mirror_w_set(_oop_maps) = nullptr;`); the other three (_mutable_data,
#     _mutable_data_size, _relocation_size) were not.
patch('src/hotspot/share/code/codeBlob.cpp', [
    ("codeblob-purge-mutable-data-mirror-w-set",
     "    _mutable_data = blob_end(); // Valid not null address\n"
     "    _mutable_data_size = 0;\n"
     "    _relocation_size = 0;",
     "    mirror_w_set(_mutable_data) = blob_end(); // Valid not null address\n"
     "    mirror_w_set(_mutable_data_size) = 0;\n"
     "    mirror_w_set(_relocation_size) = 0;"),
])

# 32. CodeBlob::set_oop_maps — assigns either a built ImmutableOopMapSet
#     pointer or nullptr to _oop_maps. Called from nmethod ctor body and
#     other places. The two assignments need mirror_w_set.
patch('src/hotspot/share/code/codeBlob.cpp', [
    ("codeblob-set-oop-maps-build-mirror-w-set",
     "    _oop_maps = ImmutableOopMapSet::build_from(p);",
     "    mirror_w_set(_oop_maps) = ImmutableOopMapSet::build_from(p);"),
    ("codeblob-set-oop-maps-null-mirror-w-set",
     "  } else {\n"
     "    _oop_maps = nullptr;\n"
     "  }",
     "  } else {\n"
     "    mirror_w_set(_oop_maps) = nullptr;\n"
     "  }"),
])

# 33. CodeBlob::purge has a SECOND _oop_maps write that fixup #31 missed:
#     after `delete _oop_maps`, it sets `_oop_maps = nullptr`. v8 confirmed
#     this is the next SIGBUS site (purge+0x2a0, after the +0x268 fix).
#     Multi-line match with the `delete _oop_maps;` before, since the same
#     `_oop_maps = nullptr;` line also appears in set_oop_maps and
#     prepare_for_archiving_impl with different surroundings.
patch('src/hotspot/share/code/codeBlob.cpp', [
    ("codeblob-purge-oop-maps-null-mirror-w-set",
     "  if (_oop_maps != nullptr) {\n"
     "    delete _oop_maps;\n"
     "    _oop_maps = nullptr;\n"
     "  }",
     "  if (_oop_maps != nullptr) {\n"
     "    delete _oop_maps;\n"
     "    mirror_w_set(_oop_maps) = nullptr;\n"
     "  }"),
])

# 34. CodeBlob::prepare_for_archiving_impl writes _oop_maps and _mutable_data
#     to nullptr. Called during CDS archive creation — unlikely to fire
#     during normal Minecraft runtime, but wrap for defensive safety.
patch('src/hotspot/share/code/codeBlob.cpp', [
    ("codeblob-prepare-for-archiving-mirror-w-set",
     "void CodeBlob::prepare_for_archiving_impl() {\n"
     "  set_name(nullptr);\n"
     "  _oop_maps = nullptr;\n"
     "  _mutable_data = nullptr;",
     "void CodeBlob::prepare_for_archiving_impl() {\n"
     "  set_name(nullptr);\n"
     "  mirror_w_set(_oop_maps) = nullptr;\n"
     "  mirror_w_set(_mutable_data) = nullptr;"),
])

# 35. nmethod::purge JVMCI_ONLY(_metadata_size = 0). v9 disassembly of the
#     v9 SIGBUS at nmethod::purge+0x2a0 = `strh wzr, [x20, #0xbe]` confirmed
#     this is the crashing site — uint16_t zero-store at offset 0xbe of
#     nmethod. INCLUDE_JVMCI is enabled in our build (default for server VM
#     on aarch64), so the JVMCI_ONLY line DOES compile. The unwrapped store
#     hits RX → BUS_ADRALN.
patch('src/hotspot/share/code/nmethod.cpp', [
    ("purge-jvmci-metadata-size-mirror-w-set",
     "  JVMCI_ONLY( _metadata_size = 0; )",
     "  JVMCI_ONLY( mirror_w_set(_metadata_size) = 0; )"),
])

# 19. codeBlob.cpp: 3 hunks the JDK 21 mirror_mapping patch couldn't place
#     because JDK 25 changed BufferBlob/AdapterBlob constructor signatures
#     (CodeBlobKind enum added) and operator-new arg list. Surgical replacements:
#     - BufferBlob::create(name, CodeBuffer*) — `cb = mirror_w(cb)` before new,
#       `return mirror_x(blob)` instead of `return blob`
#     - AdapterBlob::create — same shape
#     - BufferBlob::operator new — wrap CodeCache::allocate result in mirror_w
patch('src/hotspot/share/code/codeBlob.cpp', [
    ("bufferblob-create-mirror-w",
     "    MutexLocker mu(CodeCache_lock, Mutex::_no_safepoint_check_flag);\n"
     "    blob = new (size) BufferBlob(name, CodeBlobKind::Buffer, cb, size);\n"
     "  }\n"
     "  // Track memory usage statistic after releasing CodeCache_lock\n"
     "  MemoryService::track_code_cache_memory_usage();\n"
     "\n"
     "  return blob;\n"
     "}\n"
     "\n"
     "void* BufferBlob::operator new(size_t s, unsigned size) throw() {\n"
     "  return CodeCache::allocate(size, CodeBlobType::NonNMethod);\n"
     "}",
     "    MutexLocker mu(CodeCache_lock, Mutex::_no_safepoint_check_flag);\n"
     "    cb = mirror_w(cb);\n"
     "    blob = new (size) BufferBlob(name, CodeBlobKind::Buffer, cb, size);\n"
     "  }\n"
     "  // Track memory usage statistic after releasing CodeCache_lock\n"
     "  MemoryService::track_code_cache_memory_usage();\n"
     "\n"
     "  return mirror_x(blob);\n"
     "}\n"
     "\n"
     "void* BufferBlob::operator new(size_t s, unsigned size) throw() {\n"
     "  return mirror_w(CodeCache::allocate(size, CodeBlobType::NonNMethod));\n"
     "}"),
    ("adapterblob-create-mirror-w",
     "    MutexLocker mu(CodeCache_lock, Mutex::_no_safepoint_check_flag);\n"
     "    blob = new (size) AdapterBlob(size, cb);\n"
     "  }\n"
     "  // Track memory usage statistic after releasing CodeCache_lock\n"
     "  MemoryService::track_code_cache_memory_usage();\n"
     "\n"
     "  return blob;\n"
     "}",
     "    MutexLocker mu(CodeCache_lock, Mutex::_no_safepoint_check_flag);\n"
     "    cb = mirror_w(cb);\n"
     "    blob = new (size) AdapterBlob(size, cb);\n"
     "  }\n"
     "  // Track memory usage statistic after releasing CodeCache_lock\n"
     "  MemoryService::track_code_cache_memory_usage();\n"
     "\n"
     "  return mirror_x(blob);\n"
     "}"),
])

# 20. heap.hpp — CRITICAL: HeapBlock header writes that go through the X-only
#     mirror cause SIGBUS at CodeHeap::allocate during VM init (the very first
#     stub allocation). v3 confirmed this: SIGBUS at libjvm.dylib+0x48cbbc
#     in CodeHeap::allocate+0x16c, called from BufferBlob::create →
#     CodeCache::allocate → CodeHeap::allocate, faulting on the freshly-mapped
#     code-cache page. Wrap _header._length / _header._used writes in mirror_w.
#     JDK 25's set_length uses checked_cast<uint32_t>(length) (JDK 21 had bare
#     length) so the patch text needed adjustment.
patch('src/hotspot/share/memory/heap.hpp', [
    ("heapblock-set-length-mirror-w",
     "    _header._length = checked_cast<uint32_t>(length);",
     "    mirror_w(&_header)->_length = checked_cast<uint32_t>(length);"),
    ("heapblock-set-used-mirror-w",
     "  void set_used()                                { _header._used = true; }",
     "  void set_used()                                { mirror_w(&_header)->_used = true; }"),
    ("heapblock-set-free-mirror-w",
     "  void set_free()                                { _header._used = false; }",
     "  void set_free()                                { mirror_w(&_header)->_used = false; }"),
])

# 21. codeBlob.hpp — header_begin + adjust_size. JDK 25 has fewer fields in
#     adjust_size (only _size and _data_offset; JDK 21 had four). header_begin
#     returns mirror_x(this) so all derived address methods (content_end,
#     code_end, data_begin) inherit the X-mirror automatically.
patch('src/hotspot/share/code/codeBlob.hpp', [
    ("header-begin-mirror-x",
     "address    header_begin() const             { return (address)    this; }",
     "address    header_begin() const             { return (address)    mirror_x(this); }"),
    ("adjust-size-mirror-w-set",
     "  void adjust_size(size_t used) {\n"
     "    _size = (int)used;\n"
     "    _data_offset = _size;\n"
     "  }",
     "  void adjust_size(size_t used) {\n"
     "    mirror_w_set(_size) = (int)used;\n"
     "    mirror_w_set(_data_offset) = _size;\n"
     "  }"),
])

# 22. nmethod.cpp — wrap `this` in mirror_x at every code-cache write/dispatch
#     site. The JDK 21 mirror_mapping hunks use big multi-line context that
#     doesn't fit JDK 25's reorganized constructors. Every callsite is the
#     same conceptual change though, so use replace_all on each pattern.
#     12 substitutions total across 9 distinct patterns.
patch('src/hotspot/share/code/nmethod.cpp', [
    ("copy-code-and-locs-to-this",
     "code_buffer->copy_code_and_locs_to(this)",
     "code_buffer->copy_code_and_locs_to(mirror_x(this))"),
    ("copy-values-to-this",
     "code_buffer->copy_values_to(this)",
     "code_buffer->copy_values_to(mirror_x(this))"),
    ("debug-info-copy-to-this",
     "debug_info->copy_to(this)",
     "debug_info->copy_to(mirror_x(this))"),
    ("dependencies-copy-to-this",
     "dependencies->copy_to(this)",
     "dependencies->copy_to(mirror_x(this))"),
    ("handler-table-copy-to-this",
     "handler_table->copy_to(this)",
     "handler_table->copy_to(mirror_x(this))"),
    ("nul-chk-table-copy-to-this",
     "nul_chk_table->copy_to(this)",
     "nul_chk_table->copy_to(mirror_x(this))"),
    ("register-nmethod-this",
     "Universe::heap()->register_nmethod(this)",
     "Universe::heap()->register_nmethod(mirror_x(this))"),
    ("verify-nmethod-this",
     "Universe::heap()->verify_nmethod(this)",
     "Universe::heap()->verify_nmethod(mirror_x(this))"),
    ("codecache-commit-this",
     "CodeCache::commit(this)",
     "CodeCache::commit(mirror_x(this))"),
], replace_all=True)

# 23. codeBuffer.cpp — three sites the JDK 21 mirror_mapping patch couldn't
#     place on JDK 25:
#     a) expand() zaps the OLD buffer's _total_start (in code cache). Without
#        mirror_w the debug-only fill_to_bytes writes to RX → SIGBUS. JDK 25
#        also renamed `debug_only` → `DEBUG_ONLY` (uppercase macro).
#     b) AsmRemarks::clear and ::share write _remarks (a CodeBlob member, in
#        code cache). JDK 25 added `_remarks != nullptr &&` to the check, so
#        the surrounding context differs from the JDK 21 hunk.
#     c) Same pattern for DbgStrings::_strings.
patch('src/hotspot/share/asm/codeBuffer.cpp', [
    ("expand-zap-mirror-w",
     "DEBUG_ONLY(Copy::fill_to_bytes(bxp->_total_start, bxp->_total_size,",
     "DEBUG_ONLY(Copy::fill_to_bytes(mirror_w(bxp->_total_start), bxp->_total_size,"),
    ("asmremarks-share-mirror-w-set",
     "void AsmRemarks::share(const AsmRemarks &src) {\n"
     "  precond(_remarks == nullptr || is_empty());\n"
     "  clear();\n"
     "  _remarks = src._remarks->reuse();\n"
     "}",
     "void AsmRemarks::share(const AsmRemarks &src) {\n"
     "  precond(_remarks == nullptr || is_empty());\n"
     "  clear();\n"
     "  mirror_w_set(_remarks) = src._remarks->reuse();\n"
     "}"),
    ("asmremarks-clear-mirror-w-set",
     "  if (_remarks != nullptr && _remarks->clear() == 0) {\n"
     "    delete _remarks;\n"
     "  }\n"
     "  _remarks = nullptr;",
     "  if (_remarks != nullptr && _remarks->clear() == 0) {\n"
     "    delete _remarks;\n"
     "  }\n"
     "  mirror_w_set(_remarks) = nullptr;"),
    ("dbgstrings-share-mirror-w-set",
     "void DbgStrings::share(const DbgStrings &src) {\n"
     "  precond(_strings == nullptr || is_empty());\n"
     "  clear();\n"
     "  _strings = src._strings->reuse();\n"
     "}",
     "void DbgStrings::share(const DbgStrings &src) {\n"
     "  precond(_strings == nullptr || is_empty());\n"
     "  clear();\n"
     "  mirror_w_set(_strings) = src._strings->reuse();\n"
     "}"),
    ("dbgstrings-clear-mirror-w-set",
     "  if (_strings != nullptr && _strings->clear() == 0) {\n"
     "    delete _strings;\n"
     "  }\n"
     "  _strings = nullptr;",
     "  if (_strings != nullptr && _strings->clear() == 0) {\n"
     "    delete _strings;\n"
     "  }\n"
     "  mirror_w_set(_strings) = nullptr;"),
])

# 24. stubs.cpp — _stub_buffer holds the start of the stub region inside a
#     BufferBlob. JDK 21 wrapped `blob->content_begin()`; JDK 25 first aligns
#     the address into a local `aligned_start` and stores that. Wrap the
#     stored value in mirror_x so StubQueue uses the X-mirror to read out
#     stub bodies for execution.
patch('src/hotspot/share/code/stubs.cpp', [
    ("stub-buffer-mirror-x",
     "_stub_buffer     = aligned_start;",
     "_stub_buffer     = mirror_x(aligned_start);"),
])

# 25. dependencies.cpp — Dependencies::copy_to(nmethod*) writes the dependency
#     table into the nmethod's body region. JDK 25 uses memcpy instead of
#     JDK 21's Copy::disjoint_words. The destination `beg` is in code cache,
#     so wrap in mirror_w.
patch('src/hotspot/share/code/dependencies.cpp', [
    ("dependencies-copy-to-mirror-w",
     "(void)memcpy(beg, content_bytes(), size_in_bytes());",
     "(void)memcpy(mirror_w(beg), content_bytes(), size_in_bytes());"),
])

# 26. deoptimization.cpp — DeoptimizationScope::mark writes the deopt
#     generation counter onto an nmethod field. JDK 21 named the parameter
#     `cm` (CompiledMethod*); JDK 25 renamed to `nm` (nmethod*). Same mirror_w
#     treatment, just different variable name.
patch('src/hotspot/share/runtime/deoptimization.cpp', [
    ("deopt-mark-generation-mirror-w",
     "  nm->_deoptimization_generation = DeoptimizationScope::_active_deopt_gen;",
     "  mirror_w(nm)->_deoptimization_generation = DeoptimizationScope::_active_deopt_gen;"),
])

# 27. codeBlob.cpp operator new wraps for the OTHER code-cache CodeBlob
#     subclasses (BufferBlob is already wrapped in fixup #19). v4 SIGBUS'd
#     here:
#       SIGBUS at pc=..., si_addr=0x14fef2e08 (BUS_ADRALN)
#       V  CodeBlob::CodeBlob(name,kind,CodeBuffer*,size,...)+0x40
#       V  RuntimeStub::new_runtime_stub+0x1a0
#       V  SharedRuntime::generate_throw_exception+0x38c
#       V  SharedRuntime::generate_initial_stubs+0x18
#       V  init_globals+0x60
#     RuntimeStub::operator new returned the raw CodeCache::allocate result
#     (X-only mirror), so placement-new at that address tried to write the
#     CodeBlob's member init list through RX → BUS_ADRALN. JDK 25 simplified
#     RuntimeStub::operator new to a single-line `return CodeCache::allocate`
#     (no `if (!p) fatal` like JDK 21), and added `bool alloc_fail_is_fatal`
#     to SingletonBlob's signature. The JDK 21 mirror_mapping hunks for both
#     don't match JDK 25 verbatim. Same need for VtableBlob (3rd arg
#     `handle_alloc_failure` added in JDK 25) and UpcallStub (new in JDK 25).
patch('src/hotspot/share/code/codeBlob.cpp', [
    ("runtimestub-operator-new-mirror-w",
     "void* RuntimeStub::operator new(size_t s, unsigned size) throw() {\n"
     "  return CodeCache::allocate(size, CodeBlobType::NonNMethod);\n"
     "}",
     "void* RuntimeStub::operator new(size_t s, unsigned size) throw() {\n"
     "  return mirror_w(CodeCache::allocate(size, CodeBlobType::NonNMethod));\n"
     "}"),
    ("singletonblob-operator-new-mirror-w",
     "void* SingletonBlob::operator new(size_t s, unsigned size, bool alloc_fail_is_fatal) throw() {\n"
     "  void* p = CodeCache::allocate(size, CodeBlobType::NonNMethod);\n"
     "  if (alloc_fail_is_fatal && !p) fatal(\"Initial size of CodeCache is too small\");\n"
     "  return p;\n"
     "}",
     "void* SingletonBlob::operator new(size_t s, unsigned size, bool alloc_fail_is_fatal) throw() {\n"
     "  void* p = CodeCache::allocate(size, CodeBlobType::NonNMethod);\n"
     "  if (alloc_fail_is_fatal && !p) fatal(\"Initial size of CodeCache is too small\");\n"
     "  return mirror_w(p);\n"
     "}"),
    ("vtableblob-operator-new-mirror-w",
     "  return CodeCache::allocate(size, CodeBlobType::NonNMethod, false /* handle_alloc_failure */);\n"
     "}",
     "  return mirror_w(CodeCache::allocate(size, CodeBlobType::NonNMethod, false /* handle_alloc_failure */));\n"
     "}"),
    ("upcallstub-operator-new-mirror-w",
     "void* UpcallStub::operator new(size_t s, unsigned size) throw() {\n"
     "  return CodeCache::allocate(size, CodeBlobType::NonNMethod);\n"
     "}",
     "void* UpcallStub::operator new(size_t s, unsigned size) throw() {\n"
     "  return mirror_w(CodeCache::allocate(size, CodeBlobType::NonNMethod));\n"
     "}"),
])

# 28. nmethod.cpp operator new wraps. Both overloads return raw CodeCache
#     pointers. Once JIT compilation starts, nmethod::operator new is called
#     to allocate compiled-method bodies in code cache. Without mirror_w,
#     placement-new constructor writes to RX → BUS_ADRALN, identical to the
#     v4 RuntimeStub failure. Wrap both overloads now so v5 makes it past
#     not just initial stubs but also the first JIT compile.
patch('src/hotspot/share/code/nmethod.cpp', [
    ("nmethod-operator-new-1-mirror-w",
     "void* nmethod::operator new(size_t size, int nmethod_size, int comp_level) throw () {\n"
     "  return CodeCache::allocate(nmethod_size, CodeCache::get_code_blob_type(comp_level));\n"
     "}",
     "void* nmethod::operator new(size_t size, int nmethod_size, int comp_level) throw () {\n"
     "  return mirror_w(CodeCache::allocate(nmethod_size, CodeCache::get_code_blob_type(comp_level)));\n"
     "}"),
    ("nmethod-operator-new-2-mirror-w",
     "  void* return_value = CodeCache::allocate(nmethod_size, CodeBlobType::MethodNonProfiled);\n"
     "  if (return_value != nullptr || !allow_NonNMethod_space) return return_value;\n"
     "  // Try NonNMethod or give up.\n"
     "  return CodeCache::allocate(nmethod_size, CodeBlobType::NonNMethod);",
     "  void* return_value = CodeCache::allocate(nmethod_size, CodeBlobType::MethodNonProfiled);\n"
     "  if (return_value != nullptr || !allow_NonNMethod_space) return mirror_w(return_value);\n"
     "  // Try NonNMethod or give up.\n"
     "  return mirror_w(CodeCache::allocate(nmethod_size, CodeBlobType::NonNMethod));"),
])

# NOTE: pthread_jit_write_protect_np is marked "unavailable: not available on iOS"
# in the iOS SDK headers, AND it shares the underlying APRR mechanism with
# tcg-apple-jit.h's jit_write_protect — both no-op on TXM devices like iPhone 17.
# Phase 2 ports the mirror_mapping HotSpot patch which uses vm_remap dual
# mappings instead — that's the only proven JIT path on iOS 26 + TXM.

print(f"\nfixups: ok={ok} skip={skip} warn={warn}")
# Don't exit non-zero on WARN — apply_rejs.py + patch -F 100 may have already
# applied the same change in a slightly different form (e.g. base patch's
# `ifeq (false, true)` vs fixup's `macosx_NOTIOS`). Both achieve the iOS skip,
# the file just doesn't have the fixup's expected `old` text anymore. Workflow
# also wraps this script in `|| echo` for a second layer of defense.
sys.exit(0)
