#include <mach/mach.h>
#include <mach/task.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#include <mach/mach.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "utils.h"
#include "ZinkConfig.h"

#import "ios_uikit_bridge.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "PLLogOutputView.h"
#import "PLProfiles.h"

#define fm NSFileManager.defaultManager

extern char **environ;

BOOL validateVirtualMemorySpace(size_t size) {
    size <<= 20; // convert to MB
    void *map = mmap(0, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    // check if process successfully maps and unmaps a contiguous range
    if(map == MAP_FAILED || munmap(map, size) != 0)
        return NO;
    return YES;
}

void init_loadDefaultEnv() {
    /* Define default env */

    // Silent Caciocavallo NPE error in locating Android-only lib
    setenv("LD_LIBRARY_PATH", "", 1);

    // Ignore mipmap for performance(?) seems does not affect iOS
    //setenv("LIBGL_MIPMAP", "3", 1);

    // Disable overloaded functions hack for Minecraft 1.17+
    setenv("LIBGL_NOINTOVLHACK", "1", 1);

    // Fix white color on banner and sheep, since GL4ES 1.1.5
    setenv("LIBGL_NORMALIZE", "1", 1);

    // Override OpenGL version to 4.1 for Zink
    setenv("MESA_GL_VERSION_OVERRIDE", "4.1", 1);

    // Suppress [mvk-info] log spam (swapchain creation, etc.)
    setenv("MVK_CONFIG_LOG_LEVEL", "2", 1);

    // Runs JVM in a separate thread
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);
}

void init_loadCustomEnv() {
    NSString *envvars = getPrefObject(@"java.env_variables");
    if (envvars == nil) return;
    NSLog(@"[JavaLauncher] Reading custom environment variables");
    for (NSString *line in [envvars componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        if (![line containsString:@"="]) {
            NSLog(@"[JavaLauncher] Warning: skipped empty value custom env variable: %@", line);
            continue;
        }
        NSRange range = [line rangeOfString:@"="];
        NSString *key = [line substringToIndex:range.location];
        NSString *value = [line substringFromIndex:range.location+range.length];
        setenv(key.UTF8String, value.UTF8String, 1);
        NSLog(@"[JavaLauncher] Added custom env variable: %@", line);
    }
}

void init_loadMobileGluesConfig() {
    NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
    BOOL usesMobileGlues = [renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES] ||
        [renderer isEqualToString:@"auto"] ||
        [renderer isEqualToString:@ RENDERER_NAME_VULKAN];

    if (!usesMobileGlues) {
        return;
    }

    NSString *mgDirPath = [NSString stringWithFormat:@"%s/MG", getenv("POJAV_HOME")];
    setenv("MG_DIR_PATH", mgDirPath.UTF8String, 1);

    NSMutableDictionary *config = [NSMutableDictionary dictionary];

    // Set safe defaults for compatibility, then let user preferences override
    config[@"enableExtGL43"] = @1;
    config[@"enableExtDirectStateAccess"] = @1;
    config[@"maxGlslCacheSize"] = @128;
    config[@"customGLVersion"] = @0x030100;

    id enableAngle = getPrefObject(@"mobileglues.enable_angle");
    if (enableAngle) config[@"enableANGLE"] = [enableAngle boolValue] ? @1 : @0;

    id enableNoError = getPrefObject(@"mobileglues.enable_no_error");
    if (enableNoError) config[@"enableNoError"] = @([enableNoError intValue]);

    id enableExtTimerQuery = getPrefObject(@"mobileglues.enable_ext_timer_query");
    if (enableExtTimerQuery) config[@"enableExtTimerQuery"] = [enableExtTimerQuery boolValue] ? @1 : @0;

    id enableExtComputeShader = getPrefObject(@"mobileglues.enable_ext_compute_shader");
    if (enableExtComputeShader) config[@"enableExtComputeShader"] = [enableExtComputeShader boolValue] ? @1 : @0;

    id enableExtDirectStateAccess = getPrefObject(@"mobileglues.enable_ext_direct_state_access");
    if (enableExtDirectStateAccess) config[@"enableExtDirectStateAccess"] = [enableExtDirectStateAccess boolValue] ? @1 : @0;

    id maxGlslCacheSize = getPrefObject(@"mobileglues.max_glsl_cache_size");
    if (maxGlslCacheSize) config[@"maxGlslCacheSize"] = @([maxGlslCacheSize intValue]);

    id multidrawMode = getPrefObject(@"mobileglues.multidraw_mode");
    if (multidrawMode) config[@"multidrawMode"] = @([multidrawMode intValue]);

    id angleDepthClearFixMode = getPrefObject(@"mobileglues.angle_depth_clear_fix_mode");
    if (angleDepthClearFixMode) config[@"angleDepthClearFixMode"] = [angleDepthClearFixMode boolValue] ? @1 : @0;

    id customGlVersion = getPrefObject(@"mobileglues.custom_gl_version");
    if (customGlVersion) {
        NSString *verStr = [customGlVersion description];
        if ([verStr isEqualToString:@"3.0"]) config[@"customGLVersion"] = @0x030000;
        else if ([verStr isEqualToString:@"3.1"]) config[@"customGLVersion"] = @0x030100;
        else if ([verStr isEqualToString:@"3.2"]) config[@"customGLVersion"] = @0x030200;
        else if ([verStr isEqualToString:@"3.3"]) config[@"customGLVersion"] = @0x030300;
        else if ([verStr isEqualToString:@"4.0"]) config[@"customGLVersion"] = @0x040000;
        else if ([verStr isEqualToString:@"4.1"]) config[@"customGLVersion"] = @0x040100;
        else if ([verStr isEqualToString:@"4.2"]) config[@"customGLVersion"] = @0x040200;
        else if ([verStr isEqualToString:@"4.3"]) config[@"customGLVersion"] = @0x040300;
        else if ([verStr isEqualToString:@"4.4"]) config[@"customGLVersion"] = @0x040400;
        else if ([verStr isEqualToString:@"4.5"]) config[@"customGLVersion"] = @0x040500;
        else if ([verStr isEqualToString:@"4.6"]) config[@"customGLVersion"] = @0x040600;
    }

    id fsr1Setting = getPrefObject(@"mobileglues.fsr1_setting");
    if (fsr1Setting) config[@"fsr1Setting"] = @([fsr1Setting intValue]);

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:&error];
    if (jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [fm createDirectoryAtPath:mgDirPath withIntermediateDirectories:YES attributes:nil error:nil];
        [jsonString writeToFile:[mgDirPath stringByAppendingPathComponent:@"config.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[JavaLauncher] MobileGlues config written to %@/config.json", mgDirPath);
    } else {
        NSLog(@"[JavaLauncher] Failed to serialize MobileGlues config: %@", error);
    }
}

void init_loadCustomJvmFlags(int* argc, const char** argv) {
    NSString *jvmargs = [PLProfiles resolveKeyForCurrentProfile:@"javaArgs"];
    if (jvmargs == nil) return;
    // Make the separator happy
    jvmargs = [jvmargs stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    jvmargs = [@" " stringByAppendingString:jvmargs];

    NSLog(@"[JavaLauncher] Reading custom JVM flags");
    NSArray *argsToPurge = @[@"Xms", @"Xmx", @"d32", @"d64"];
    for (NSString *arg in [jvmargs componentsSeparatedByString:@" -"]) {
        NSString *jvmarg = [arg stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (jvmarg.length == 0) continue;
        BOOL ignore = NO;
        for (NSString *argToPurge in argsToPurge) {
            if ([jvmarg hasPrefix:argToPurge]) {
                NSLog(@"[JavaLauncher] Ignored JVM flag: -%@", jvmarg);
                ignore = YES;
                break;
            }
        }
        if (ignore) continue;

        ++*argc;
        argv[*argc] = [@"-" stringByAppendingString:jvmarg].UTF8String;

        NSLog(@"[JavaLauncher] Added custom JVM flag: %s", argv[*argc]);
    }
}

int launchJVM(NSString *username, id launchTarget, int width, int height, int minVersion) {
    NSLog(@"[JavaLauncher] Beginning JVM launch");

    init_loadDefaultEnv();
    init_loadCustomEnv();
    init_loadMobileGluesConfig();

    BOOL requiresTXMWorkaround = DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM);
    BOOL jit26AlwaysAttached = getPrefBool(@"debug.debug_always_attached_jit");
    if (requiresTXMWorkaround) {
        static void *result;
        if(!result) result = JIT26CreateRegionLegacy(getpagesize());
        if ((uint32_t)result != 0x690000E0) {
            munmap(result, getpagesize());
            // we can't continue since legacy script only allows calling breakpoint once
            NSString *inBundleScriptPath = [NSBundle.mainBundle pathForResource:@"UniversalJIT26" ofType:@"js"];
            NSString *lcAppInfoPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"];
            NSMutableDictionary *lcAppInfo = [NSMutableDictionary dictionaryWithContentsOfFile:lcAppInfoPath];
            if(lcAppInfo) {
                // if this is inside LiveContainer, we assign script ourselves and prompt user to restart Amethyst
                lcAppInfo[@"jitLaunchScriptJs"] = [[NSData dataWithContentsOfFile:inBundleScriptPath] base64EncodedStringWithOptions:0];
                if([lcAppInfo writeToFile:lcAppInfoPath atomically:YES]) {
                    showDialog(localize(@"Error", nil), @"Amethyst was launched with a legacy script. We have updated the script to Universal, please restart LiveContainer to continue.");
                    [PLLogOutputView handleExitCode:1];
                    return 1;
                }
            }
            [NSFileManager.defaultManager copyItemAtPath:inBundleScriptPath toPath:[NSString stringWithFormat:@"%s/UniversalJIT26.js", getenv("POJAV_HOME")] error:nil];
            showDialog(localize(@"Error", nil), @"Support for legacy script has been removed. Please switch to Universal JIT script. To import it, long-press on Amethyst when enabling JIT in StikDebug and tap \"Assign Script\", then go to Amethyst's Documents directory and pick it. (on sideloaded StikDebug, the builtin script is named Amethyst-MeloNX.js)");
            [PLLogOutputView handleExitCode:1];
            return 1;
        }
        JIT26SendJITScript([NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"UniversalJIT26Extension" ofType:@"js"]]);
        JIT26SetDetachAfterFirstBr(!jit26AlwaysAttached);
        // make sure we don't get stuck in EXC_BAD_ACCESS
        task_set_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS, 0, EXCEPTION_DEFAULT, MACHINE_THREAD_STATE);
    }
    if (!requiresTXMWorkaround || jit26AlwaysAttached) {
        if (jit26AlwaysAttached) {
            // Only allow StikDebug to catch our breakpoints to prevent any stutters
            task_set_exception_ports(mach_task_self(), EXC_MASK_ALL & ~EXC_MASK_BREAKPOINT, 0,
                EXCEPTION_DEFAULT, THREAD_STATE_NONE);
        }
        // Activate Library Validation bypass for external runtime and dylibs (JNA, etc)
        init_bypassDyldLibValidation();
    } else {
        NSLog(@"[DyldLVBypass] Hook disabled! Loading unsigned dylib will cause code signature error.");
    }

    BOOL launchJar = NO;
    NSString *gameDir;
    NSString *defaultJRETag;
    NSCAssert(launchTarget, @"Unexpected nil launchTarget");
    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        // Get preferred Java version from current profile
        int preferredJavaVersion = [PLProfiles resolveKeyForCurrentProfile:@"javaVersion"].intValue;
        if (preferredJavaVersion > 0) {
            if (minVersion > preferredJavaVersion) {
                NSLog(@"[JavaLauncher] Profile's preferred Java version (%d) does not meet the minimum version (%d), dropping request", preferredJavaVersion, minVersion);
            } else {
                NSDebugLog(@"[PLProfiles] Applying javaVersion");
                minVersion = preferredJavaVersion;
            }
        }
        if (minVersion <= 8) {
            defaultJRETag = @"1_16_5_older";
        } else {
            defaultJRETag = @"1_17_newer";
        }

        // Setup AMETHYST_RENDERER
        NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
        NSLog(@"[JavaLauncher] RENDERER is set to %@\n", renderer);
        setenv("AMETHYST_RENDERER", renderer.UTF8String, 1);

        // Apply Zink-specific environment variables if Zink renderer is selected
        if ([renderer hasPrefix:@"libOSMesa"]) {
            [ZinkConfig applyZinkEnvironmentFromPreferences];
            // Show active config summary as a console-readable env var + log
            NSString *configSummary = [ZinkConfig activeConfigSummary];
            NSLog(@"[ZinkConfig] ========== Zink Renderer Active ==========");
            NSLog(@"[ZinkConfig] %@", configSummary);
            setenv("ZINK_ACTIVE_CONFIG", configSummary.UTF8String, 1);
        }
        // Setup gameDir
        gameDir = [NSString stringWithFormat:@"%s/instances/%@/%@",
            getenv("POJAV_HOME"), getPrefObject(@"general.game_directory"),
            [PLProfiles resolveKeyForCurrentProfile:@"gameDir"]]
            .stringByStandardizingPath;
    } else {
        defaultJRETag = @"execute_jar";
        gameDir = @(getenv("POJAV_GAME_DIR"));
        launchJar = YES;
    }
    NSLog(@"[JavaLauncher] Looking for Java %d or later", minVersion);
    NSString *javaHome = getSelectedJavaHome(defaultJRETag, minVersion);

    if (javaHome == nil) {
        UIKit_returnToSplitView();
        BOOL isExecuteJar = [defaultJRETag isEqualToString:@"execute_jar"];
        showDialog(localize(@"Error", nil), [NSString stringWithFormat:localize(@"java.error.missing_runtime", nil),
            isExecuteJar ? [launchTarget lastPathComponent] : PLProfiles.current.selectedProfile[@"lastVersionId"], minVersion]);
        return 1;
    } else if ([javaHome hasPrefix:@(getenv("POJAV_HOME"))]) {
        // Symlink libawt_xawt.dylib
        NSString *dest = [NSString stringWithFormat:@"%@/lib/libawt_xawt.dylib", javaHome];
        NSString *source = [NSString stringWithFormat:@"%@/Frameworks/libawt_xawt.dylib", NSBundle.mainBundle.bundlePath];
        NSError *error;
        [fm createSymbolicLinkAtPath:dest withDestinationPath:source error:&error];
        if (error) {
            NSLog(@"[JavaLauncher] Symlink libawt_xawt.dylib failed: %@", error.localizedDescription);
        }
    }

    setenv("JAVA_HOME", javaHome.UTF8String, 1);
    NSLog(@"[JavaLauncher] JAVA_HOME has been set to %@", javaHome);

    int allocmem;
    if (getPrefBool(@"java.auto_ram")) {
        CGFloat autoRatio = getEntitlementValue(@"com.apple.private.memorystatus") ? 0.4 : 0.25;
        allocmem = roundf((NSProcessInfo.processInfo.physicalMemory >> 20) * autoRatio);
    } else {
        allocmem = getPrefInt(@"java.allocated_memory");
    }
    NSLog(@"[JavaLauncher] Max RAM allocation is set to %d MB", allocmem);
    if (!validateVirtualMemorySpace(allocmem)) {
        UIKit_returnToSplitView();
        if (getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")) {
            showDialog(localize(@"Error", nil), @"Insufficient contiguous virtual memory space. Lower memory allocation and try again.");
        } else {
            showDialog(localize(@"Error", nil), @"Insufficient contiguous virtual memory space. Increased Memory Limit entitlement is missing, please add it via GetMoreRam app.");
        }
        return 1;
    }

    int margc = -1;
    const char *margv[1000];

    margv[++margc] = [NSString stringWithFormat:@"%@/bin/java", javaHome].UTF8String;
    margv[++margc] = "-XstartOnFirstThread";
    if (!launchJar) {
        margv[++margc] = "-Djava.system.class.loader=net.kdt.pojavlaunch.PojavClassLoader";
    }
    margv[++margc] = "-Xms128M";
    margv[++margc] = [NSString stringWithFormat:@"-Xmx%dM", allocmem].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Djava.library.path=%@/Frameworks", NSBundle.mainBundle.bundlePath].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.dir=%@", gameDir].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.home=%s", getenv("POJAV_HOME")].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.timezone=%@", NSTimeZone.localTimeZone.name].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-DUIScreen.maximumFramesPerSecond=%d", (int)UIScreen.mainScreen.maximumFramesPerSecond].UTF8String;
    margv[++margc] = "-Dorg.lwjgl.glfw.checkThread0=false";
    margv[++margc] = "-Dorg.lwjgl.system.allocator=system";
    //margv[++margc] = "-Dorg.lwjgl.util.NoChecks=true";
    margv[++margc] = "-Dlog4j2.formatMsgNoLookups=true";

    // Preset OpenGL libname
    const char *glLibName = getenv("AMETHYST_RENDERER");
    if (glLibName) {
        if (!strcmp(glLibName, "auto")) {
            // workaround only applies to 1.20.2+
            glLibName = RENDERER_NAME_MTL_ANGLE;
        }
        // libMoltenVK is a Vulkan loader, not a GL implementation; binding it as
        // opengl.libname makes LWJGL fail looking up GL symbols. The Vulkan
        // libname is set in PojavLauncher.java instead.
        //
        // BUT: Minecraft 26.2's NativeLibrariesBootstrap.loadOpenGL() initializes
        // org.lwjgl.opengl.GL during startup REGARDLESS of which renderer the
        // game ultimately uses. With opengl.libname unset, LWJGL falls back to
        // MacOSXLibraryBundle.getWithIdentifier("com.apple.opengl") which fails
        // on iOS (no system OpenGL framework) →
        //   java.lang.UnsatisfiedLinkError: Failed to retrieve bundle with
        //   identifier: com.apple.opengl
        // Point opengl.libname at libmobileglues.dylib for Vulkan setups —
        // MobileGlues is purpose-built for GL-on-Metal/Vulkan on mobile and
        // already uses our shipped libspirv-cross.dylib for shader translation.
        // GL.create() finds GL function pointers; if Minecraft ever does call
        // a GL entry point (compat code, shader build, etc.) MobileGlues can
        // route it through Vulkan rather than crashing like a context-less
        // gl4es would.
        if (strcmp(glLibName, RENDERER_NAME_VULKAN) == 0) {
            setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "1", 1);
            setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1);
            setenv("MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS", "1", 1);
        }
        const char *openglLibName = (strcmp(glLibName, RENDERER_NAME_VULKAN) == 0)
            ? RENDERER_NAME_MOBILEGLUES
            : glLibName;
        margv[++margc] = [NSString stringWithFormat:@"-Dorg.lwjgl.opengl.libname=%s", openglLibName].UTF8String;
    }

    // Point LWJGL spvc bindings at libspirv-cross-c-shared.0.dylib (the one
    // MobileGlues ships and that's already loaded into the process by the
    // time spvc.<clinit> runs). LWJGL's default would be to dlopen
    // "libspirv-cross.dylib"; if we ship a separate file with that filename
    // it collides at dyld registration because both share the install_name
    // @rpath/libspirv-cross-c-shared.0.dylib. Reusing the already-loaded
    // C library avoids the duplicate.
    //
    // NOTE: LWJGL's Library.loadNative passes the configured libname through
    // Platform.mapLibraryNameBundled which on macOS prefixes "lib" and
    // suffixes ".dylib". Pass just the base name "spirv-cross-c-shared.0"
    // so the result is libspirv-cross-c-shared.0.dylib (not
    // liblibspirv-cross-c-shared.0.dylib.dylib).
    margv[++margc] = "-Dorg.lwjgl.spvc.libname=spirv-cross-c-shared.0";

    NSString *librariesPath = [NSString stringWithFormat:@"%@/libs", NSBundle.mainBundle.bundlePath];
    margv[++margc] = [NSString stringWithFormat:@"-javaagent:%@/patchjna_agent.jar=", librariesPath].UTF8String;
    if(getPrefBool(@"general.cosmetica")) {
        margv[++margc] = [NSString stringWithFormat:@"-javaagent:%@/arc_dns_injector.jar=23.95.137.176", librariesPath].UTF8String;
    }

    // Workaround random stack guard allocation crashes
    margv[++margc] = "-XX:+UnlockExperimentalVMOptions";
    margv[++margc] = "-XX:+DisablePrimordialThreadGuardPages";

    // Use ParallelGC instead of G1GC. On mobile with limited heap (~922MB),
    // G1GC's Full GC can pause the app for 1-2 minutes, causing the "freeze
    // then resume" issue. ParallelGC is more efficient for small heaps and
    // avoids stop-the-world compaction stalls on iOS.
    margv[++margc] = "-XX:+UseParallelGC";
    margv[++margc] = "-XX:ParallelGCThreads=2";

    // On iOS 26+, use mirror mapped JIT for better code cache performance.
    // JDK 25 (jre25-ios-v1) has a bug in MirrorMappedCodeCache that causes
    // SIGBUS in ScavengableNMethods::register_nmethod during JIT compilation.
    // jre25-ios-v2 is supposed to fix this, but keep the flag off for Java 25
    // until v2 is confirmed stable across all devices.
    NSString *currentJavaHome = [NSString stringWithUTF8String:getenv("JAVA_HOME") ?: ""];
    BOOL isJava25Home = [currentJavaHome containsString:@"java-25"];
    if (@available(iOS 26.0, *)) {
        if (!isJava25Home) {
            margv[++margc] = "-XX:+MirrorMappedCodeCache";
        }
    }

    // Disable Forge 1.16.x early progress window
    margv[++margc] = "-Dfml.earlyprogresswindow=false";

    // Load java
    NSString *libjlipath8 = [NSString stringWithFormat:@"%@/lib/jli/libjli.dylib", javaHome]; // java 8
    NSString *libjlipath11 = [NSString stringWithFormat:@"%@/lib/libjli.dylib", javaHome]; // java 11+
    BOOL isJava8 = [fm fileExistsAtPath:libjlipath8];
    setenv("INTERNAL_JLI_PATH", (isJava8 ? libjlipath8 : libjlipath11).UTF8String, 1);
    NSLog(@"[Bisect] About to dlopen libjli at %s", getenv("INTERNAL_JLI_PATH"));
    fflush(stdout); fflush(stderr);
    void* libjli = dlopen(getenv("INTERNAL_JLI_PATH"), RTLD_GLOBAL);
    NSLog(@"[Bisect] dlopen returned %p", libjli);
    fflush(stdout); fflush(stderr);

    if (!libjli) {
        const char *error = dlerror();
        NSLog(@"[Init] JLI lib = NULL: %s", error);
        UIKit_returnToSplitView();
        showDialog(localize(@"Error", nil), @(error));
        return 1;
    }

    // Setup Caciocavallo
    margv[++margc] = "-Djava.awt.headless=false";
    margv[++margc] = "-Dcacio.font.fontmanager=sun.awt.X11FontManager";
    margv[++margc] = "-Dcacio.font.fontscaler=sun.font.FreetypeFontScaler";
    margv[++margc] = [NSString stringWithFormat:@"-Dcacio.managed.screensize=%dx%d", width, height].UTF8String;
    margv[++margc] = "-Dswing.defaultlaf=javax.swing.plaf.metal.MetalLookAndFeel";
    if (isJava8) {
        // Setup Caciocavallo
        margv[++margc] = "-Dawt.toolkit=net.java.openjdk.cacio.ctc.CTCToolkit";
        margv[++margc] = "-Djava.awt.graphicsenv=net.java.openjdk.cacio.ctc.CTCGraphicsEnvironment";
    } else {
        // Required by Cosmetica to inject DNS
        margv[++margc] = "--add-opens=java.base/java.net=ALL-UNNAMED";

        // Setup Caciocavallo
        margv[++margc] = "-Dawt.toolkit=com.github.caciocavallosilano.cacio.ctc.CTCToolkit";
        margv[++margc] = "-Djava.awt.graphicsenv=com.github.caciocavallosilano.cacio.ctc.CTCGraphicsEnvironment";

        // Required by Caciocavallo17 to access internal API
        margv[++margc] = "--add-exports=java.desktop/java.awt=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/java.awt.peer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.image=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.java2d=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/java.awt.dnd.peer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.event=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.datatransfer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.font=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.base/sun.security.action=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.base/java.util=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/java.awt=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/sun.font=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/sun.java2d=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED";

        // TODO: workaround, will be removed once the startup part works without PLaunchApp
        margv[++margc] = "--add-exports=cpw.mods.bootstraplauncher/cpw.mods.bootstraplauncher=ALL-UNNAMED";
    }

    // Add Caciocavallo bootclasspath
    NSString *cacio_classpath = [NSString stringWithFormat:@"-Xbootclasspath/%s", isJava8 ? "p" : "a"];
    NSString *cacio_libs_path = [NSString stringWithFormat:@"%@/libs_caciocavallo%s", NSBundle.mainBundle.bundlePath, isJava8 ? "" : "17"];
    NSArray *files = [fm contentsOfDirectoryAtPath:cacio_libs_path error:nil];
    for(NSString *file in files) {
        if ([file hasSuffix:@".jar"]) {
            cacio_classpath = [NSString stringWithFormat:@"%@:%@/%@", cacio_classpath, cacio_libs_path, file];
        }
    }
    margv[++margc] = cacio_classpath.UTF8String;

    if (!getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing")) {
        // In jailed environment, where extended virtual addressing entitlement isn't
        // present (for free dev account), allocating compressed space fails.
        // FIXME: does extended VA allow allocating compressed class space?
        margv[++margc] = "-XX:-UseCompressedClassPointers";
    }

    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        for (NSString *arg in launchTarget[@"arguments"][@"jvm_processed"]) {
            margv[++margc] = arg.UTF8String;
        }
    }

    init_loadCustomJvmFlags(&margc, (const char **)margv);
    NSLog(@"[Init] Found JLI lib");

    NSString *classpath = [NSString stringWithFormat:@"%@/*", librariesPath];
    if (launchJar) {
        classpath = [classpath stringByAppendingFormat:@":%@", launchTarget];
    }
    margv[++margc] = "-cp";
    margv[++margc] = classpath.UTF8String;
    margv[++margc] = "net.kdt.pojavlaunch.PojavLauncher";

    if (launchJar) {
        margv[++margc] = "-jar";
    } else {
        margv[++margc] = username.UTF8String;
    }

    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        margv[++margc] = [launchTarget[@"id"] UTF8String];
    } else {
        margv[++margc] = [launchTarget UTF8String];
    }
    //margv[++margc] = "ghidra.GhidraRun";

    pJLI_Launch = (JLI_Launch_func *)dlsym(libjli, "JLI_Launch");

    if (NULL == pJLI_Launch) {
        NSLog(@"[Init] JLI_Launch = NULL");
        return -2;
    }

    NSLog(@"[Init] Calling JLI_Launch");

    // Cr4shed known issue: exit after crash dump,
    // reset signal handler so that JVM can catch them
    signal(SIGSEGV, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGFPE, SIG_DFL);

    // Free split VC
    tmpRootVC = nil;

    return pJLI_Launch(++margc, margv,
                   0, NULL, // sizeof(const_jargs) / sizeof(char *), const_jargs,
                   0, NULL, // sizeof(const_appclasspath) / sizeof(char *), const_appclasspath,
                   // These values are ignored in Java 17, so keep it anyways
                   "1.8.0-internal",
                   "1.8",

                   "java", "openjdk",
                   /* (const_jargs != NULL) ? JNI_TRUE : */ JNI_FALSE,
                   JNI_TRUE, JNI_FALSE, JNI_TRUE);
}
