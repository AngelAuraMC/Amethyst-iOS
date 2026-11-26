#import <mach-o/dyld.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>

#import "AppDelegate.h"
#import "customcontrols/CustomControlsUtils.h"
#import "HostManagerBridge.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "PLLogOutputView.h"
#import "PLProfiles.h"
#import "SurfaceViewController.h"
#import "UIKit+hook.h"
#import "config.h"

#include <execinfo.h>
#include <fcntl.h>
#include <libgen.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include "utils.h"
#include "codesign.h"

#define CS_PLATFORM_BINARY 0x4000000
#define PT_TRACE_ME 0
#define PT_DETACH 11 
int ptrace(int, pid_t, caddr_t, int);
#define fm NSFileManager.defaultManager
extern char** environ;

static char s_bootTracePath[PATH_MAX];
static const int s_bootSignals[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGSYS, SIGTRAP };

static void trace_append_str(char *buf, size_t *pos, size_t cap, const char *s) {
    if (!s) s = "(null)";
    while (*s && *pos + 1 < cap) {
        buf[(*pos)++] = *s++;
    }
}

static void trace_append_u64(char *buf, size_t *pos, size_t cap, uint64_t val, int base) {
    static const char digits[] = "0123456789abcdef";
    char tmp[32];
    int n = 0;
    if (val == 0) {
        tmp[n++] = '0';
    } else {
        while (val > 0 && n < (int)sizeof(tmp)) {
            tmp[n++] = digits[val % (uint64_t)base];
            val /= (uint64_t)base;
        }
    }
    while (n > 0 && *pos + 1 < cap) {
        buf[(*pos)++] = tmp[--n];
    }
}

static void trace_write_raw(const char *data, size_t len, int flags) {
    if (!s_bootTracePath[0] || !data || len == 0) return;
    int fd = open(s_bootTracePath, flags, 0644);
    if (fd < 0) return;
    size_t written = 0;
    while (written < len) {
        ssize_t w = write(fd, data + written, len - written);
        if (w <= 0) break;
        written += (size_t)w;
    }
    fsync(fd);
    close(fd);
}

void amethyst_boot_trace(const char *step) {
    char buf[256];
    size_t pos = 0;
    trace_append_str(buf, &pos, sizeof(buf), "[STEP] ");
    trace_append_str(buf, &pos, sizeof(buf), step);
    trace_append_str(buf, &pos, sizeof(buf), "\n");
    trace_write_raw(buf, pos, O_WRONLY | O_CREAT | O_APPEND);
}

static void amethyst_boot_signal_handler(int sig, siginfo_t *info, void *ucontext) {
    (void)ucontext;
    if (s_bootTracePath[0]) {
        int fd = open(s_bootTracePath, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            char buf[256];
            size_t pos = 0;
            trace_append_str(buf, &pos, sizeof(buf), "[CRASH] sig=");
            trace_append_u64(buf, &pos, sizeof(buf), (uint64_t)(sig > 0 ? sig : 0), 10);
            trace_append_str(buf, &pos, sizeof(buf), " code=");
            trace_append_u64(buf, &pos, sizeof(buf), (uint64_t)(info ? (uint32_t)info->si_code : 0), 10);
            trace_append_str(buf, &pos, sizeof(buf), " addr=0x");
            trace_append_u64(buf, &pos, sizeof(buf), (uint64_t)(uintptr_t)(info ? info->si_addr : NULL), 16);
            trace_append_str(buf, &pos, sizeof(buf), "\n");
            (void)write(fd, buf, pos);
            void *bt[32];
            int frames = backtrace(bt, 32);
            if (frames > 0) {
                backtrace_symbols_fd(bt, frames, fd);
            }
            fsync(fd);
            close(fd);
        }
    }
    raise(sig);
}

void amethyst_uninstall_boot_signal_handlers(void) {
    for (size_t i = 0; i < sizeof(s_bootSignals) / sizeof(s_bootSignals[0]); i++) {
        signal(s_bootSignals[i], SIG_DFL);
    }
}

static void amethyst_init_boot_trace(int argc, char *argv[]) {
    const char *home = getenv("AME_HOME");
    if (!home || !home[0]) return;
    snprintf(s_bootTracePath, sizeof(s_bootTracePath), "%s/jit_boot_trace.txt", home);

    uint32_t csFlags = 0;
    csops(getpid(), CS_OPS_STATUS, &csFlags, sizeof(csFlags));

    char buf[384];
    size_t pos = 0;
    trace_append_str(buf, &pos, sizeof(buf), "[BOOT] argc=");
    trace_append_u64(buf, &pos, sizeof(buf), (uint64_t)(argc > 0 ? argc : 0), 10);
    trace_append_str(buf, &pos, sizeof(buf), " pid=");
    trace_append_u64(buf, &pos, sizeof(buf), (uint64_t)getpid(), 10);
    trace_append_str(buf, &pos, sizeof(buf), " ppid=");
    trace_append_u64(buf, &pos, sizeof(buf), (uint64_t)getppid(), 10);
    trace_append_str(buf, &pos, sizeof(buf), " cs_flags=0x");
    trace_append_u64(buf, &pos, sizeof(buf), (uint64_t)csFlags, 16);
    trace_append_str(buf, &pos, sizeof(buf), " jb=");
    trace_append_u64(buf, &pos, sizeof(buf), isJailbroken ? 1 : 0, 10);
    if (argc > 1 && argv[1]) {
        trace_append_str(buf, &pos, sizeof(buf), " arg1=");
        trace_append_str(buf, &pos, sizeof(buf), argv[1]);
    }
    trace_append_str(buf, &pos, sizeof(buf), "\n");
    trace_write_raw(buf, pos, O_WRONLY | O_CREAT | O_TRUNC);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = amethyst_boot_signal_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
    sigemptyset(&sa.sa_mask);
    for (size_t i = 0; i < sizeof(s_bootSignals) / sizeof(s_bootSignals[0]); i++) {
        sigaction(s_bootSignals[i], &sa, NULL);
    }
}

void printEntitlementAvailability(NSString *key) {
    NSLog(@"* %@: %@", key, getEntitlementValue(key) ? @"YES" : @"NO");
}

void uncaughtExceptionHandler(NSException *exception) {
    amethyst_boot_trace("uncaught_ns_exception");
    NSLog(@"Uncaught exception: %@", exception.description);
    NSLog(@"Call stack: %@", exception.callStackSymbols);

    // Synchronously write exception details to latestlog.txt in case the process aborts before the async logger flushes
    const char *home = getenv("AME_HOME");
    if (home) {
        NSString *logPath = [NSString stringWithFormat:@"%s/latestlog.txt", home];
        NSString *crashMsg = [NSString stringWithFormat:@"\n[FATAL] Uncaught exception: %@\nReason: %@\nCall stack:\n%@\n",
                              exception.name, exception.reason, [exception.callStackSymbols componentsJoinedByString:@"\n"]];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (file) {
            [file seekToEndOfFile];
            [file writeData:[crashMsg dataUsingEncoding:NSUTF8StringEncoding]];
            [file synchronizeFile];
            [file closeFile];
        }
    }

    usleep(50000);
    handle_fatal_exit(SIGABRT);
}

bool init_checkForsubstrated() {
    // Please kindly tell pwn20wnd that he sucks
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;
    size_t size = 0;
    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    if (st != 0 || size == 0) {
        return false;
    }
    struct kinfo_proc * process = NULL;
    struct kinfo_proc * newprocess = NULL;
    do {
        if (size > SIZE_MAX - (size / 10)) {
            free(process);
            return false;
        }
        size += size / 10;
        newprocess = realloc(process, size);
        if (!newprocess){
            free(process);
            return false;
        }
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
    } while (st == -1 && errno == ENOMEM);
    bool found = false;
    if (st == 0){
        if (size % sizeof(struct kinfo_proc) == 0){
            int nprocess = (int)(size / sizeof(struct kinfo_proc));
            if (nprocess){
                for (int i = nprocess - 1; i >= 0; i--){
                    if(strcmp(process[i].kp_proc.p_comm,"substrated") == 0) {
                        found = true;
                        break;
                    }
                }
            }
        }
    }
    free(process);
    return found;
}

bool init_checkForJailbreak() {
    if (NSProcessInfo.processInfo.macCatalystApp) {
        // macOS doesn't automatically enable JIT.
        return false;
    } else if (init_checkForsubstrated()) {
        return true;
    }

    // Check if posix_spawn is hooked
    for (int i=0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i),"/usr/lib/pspawn_payload-stg2.dylib") == 0 ||
            strstr(_dyld_get_image_name(i),"/systemhook.dylib") != NULL) {
            return true;
        }
    }

    // Check if we have platform bit set
    uint32_t flags = 0;
    csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
    if ((flags & CS_PLATFORM_BINARY) != 0) {
        return true;
    }

    return opendir("/Applications") != NULL;
}

void init_logDeviceAndVer(char *argument) {
    // Amethyst version
    NSLog(@"[Pre-Init] Amethyst INIT!");
    NSLog(@"[Pre-Init] Version: %@-%s", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"], CONFIG_TYPE);
    NSLog(@"[Pre-Init] Commit: %s (%s)", CONFIG_COMMIT, CONFIG_BRANCH);
    
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    const char *type;
    if (!access(tsPath.UTF8String, F_OK)) {
        type = "TrollStore";
    } else if (isJailbroken) {
        type = "Jailbroken";
    } else {
        type = "Unjailbroken";
    }
    setenv("AME_DETECTEDINST", type, 1);
    
    NSLog(@"[Pre-Init] Device: %@", [HostManager GetModelName]);
    NSLog(@"[Pre-Init] %@ (%s)", UIDevice.currentDevice.completeOSVersion, type);
    
    NSLog(@"[Pre-init] Entitlements availability:");
    printEntitlementAvailability(@"com.apple.developer.kernel.extended-virtual-addressing");
    printEntitlementAvailability(@"com.apple.developer.kernel.increased-memory-limit");
    printEntitlementAvailability(@"com.apple.private.security.no-sandbox");
    //printEntitlementAvailability(@"dynamic-codesigning");
}

void init_redirectStdio() {
    if (getenv("LOG_TO_CONSOLE") != NULL) {
        NSLog(@"[Pre-init] LOG_TO_CONSOLE is set, not logging to latestlog.txt");
        return;
    }

    NSLog(@"[Pre-init] Starting logging STDIO to latestlog.txt\n");

    NSString *home = @(getenv("AME_HOME"));
    NSString *currName = [home stringByAppendingPathComponent:@"latestlog.txt"];
    NSString *oldName = [home stringByAppendingPathComponent:@"latestlog.old.txt"];
    [fm removeItemAtPath:oldName error:nil];
    [fm moveItemAtPath:currName toPath:oldName error:nil];

    [fm createFileAtPath:currName contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:currName];

    if (!file) {
        NSLog(@"[Pre-init] Error: failed to open %@", currName);
        assert(0 && "Failed to open latestlog.txt. Check oslog for more details.");
    }

    setvbuf(stdout, 0, _IOLBF, 0); // make stdout line-buffered
    setvbuf(stderr, 0, _IONBF, 0); // make stderr unbuffered

    /* create the pipe and redirect stdout and stderr */
    static int pfd[2];
    pipe(pfd);
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));

    /* create the logging thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static BOOL filteredSessionID;
        ssize_t rsize;
        char buf[2048];
        while((rsize = read(pfd[0], buf, sizeof(buf)-1)) > 0) {
            if (rsize < 2048) {
                buf[rsize] = '\0';
            }
            // Filter out Session ID here
            int index;
            if (!filteredSessionID) {
                char *sessionStr = strstr(buf, "(Session ID is ");
                if (sessionStr) {
                    char *censorStr = "(Session ID is <censored>)\n\0";
                    strcpy(sessionStr, censorStr);
                    rsize = strlen(buf);
                    filteredSessionID = true;
                }
            }
            if (canAppendToLog) {
                [PLLogOutputView appendToLog:@(buf)];
            }
            [file writeData:[NSData dataWithBytes:buf length:rsize]];
            [file synchronizeFile];
        }
        [file closeFile];
    });

    // We can start catching exception right now
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
}

void init_setupAccounts() {
    NSString *controlPath = [@(getenv("AME_HOME")) stringByAppendingPathComponent:@"accounts"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
}

void init_setupCustomControls() {
    NSString *controlPath = [@(getenv("AME_HOME")) stringByAppendingPathComponent:@"controlmap"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControl();
    NSString *gamepadControlPath = [controlPath stringByAppendingPathComponent:@"gamepads"];
    [fm createDirectoryAtPath:gamepadControlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControlForGamepad();
}

void init_setupMultiDir() {
    NSString *multidir = getPrefObject(@"general.game_directory");
    if (multidir.length == 0) {
        multidir = @"default";
        setPrefObject(@"general.game_directory", multidir);
        NSLog(@"[Pre-init] Game directory was not set. Defaulting to %@ for future use.\n", multidir);
    } else {
        NSLog(@"[Pre-init] Restored game directory preference (%@)\n", multidir);
    }

    const char *home = getenv("AME_HOME");
    NSString *lasmPath = [NSString stringWithFormat:@"%s/Library/Application Support/minecraft", home];
    NSString *multidirPath = [NSString stringWithFormat:@"%s/instances/%@", home, multidir];


    NSArray *dirsToCreate = @[
        [NSString stringWithFormat:@"%s/.demo", home],
        [NSString stringWithFormat:@"%s/java_runtimes", home],
        lasmPath.stringByDeletingLastPathComponent,
        multidirPath
    ];
    for (NSString *dir in dirsToCreate) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [fm removeItemAtPath:lasmPath error:nil];
    [fm createSymbolicLinkAtPath:lasmPath withDestinationPath:multidirPath error:nil];
    [fm changeCurrentDirectoryPath:lasmPath];
    setenv("GAME_DIR", lasmPath.UTF8String, 1);
}

void init_setupResolvConf() {
    // Write known DNS servers to the config
    NSString *path = [NSString stringWithFormat:@"%s/resolv.conf", getenv("AME_HOME")];
    if (![fm fileExistsAtPath:path]) {
        [@"nameserver 8.8.8.8\n"
         @"nameserver 8.8.4.4"
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

void init_setupHomeDirectory() {
    setenv("HOME", [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path.stringByDeletingLastPathComponent.UTF8String, 1);
    NSString *homeDir;
    NSError *homeError;
    
    BOOL isNotSandboxed = [@(getenv("HOME")).lastPathComponent isEqualToString:NSUserName()];
    homeDir = [NSString stringWithFormat:@"%s/Documents%@", getenv("HOME"),
        isNotSandboxed ? @"/AngelAuraAmethyst":@""];

    if (![fm fileExistsAtPath:homeDir] ) {
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:NO attributes:nil error:&homeError];
    }
    
    if(homeError != nil) {
        // TODO: Persistent storage
        homeError = nil;
        homeDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:YES attributes:nil error:&homeError];
    }
    
    char *resolvedHome = realpath(homeDir.UTF8String, NULL);
    setenv("AME_HOME", resolvedHome ? resolvedHome : homeDir.UTF8String, 1);
    free(resolvedHome);
}

int main(int argc, char *argv[]) {
    if (pJLI_Launch) {
        return pJLI_Launch(argc, (const char **)argv,
                   0, NULL, // sizeof(const_jargs) / sizeof(char *), const_jargs,
                   0, NULL, // sizeof(const_appclasspath) / sizeof(char *), const_appclasspath,
                   "1.8.0-internal",
                   "1.8",

                   "java", "openjdk",
                   /* (const_jargs != NULL) ? JNI_TRUE : */ JNI_FALSE,
                   JNI_TRUE, JNI_FALSE, JNI_TRUE);
    }

    if (argc == 2 && argv[1] != NULL && argv[1][0] == '\0' && !isJITEnabled(true)) {
        NSLog(@"calling ptrace(PT_TRACE_ME)");
        // Child process can call to PT_TRACE_ME
        // then both parent and child processes get CS_DEBUGGED
        int ret = ptrace(PT_TRACE_ME, 0, 0, 0);
        return ret;
    }

    setenv("BUNDLE_PATH", dirname(argv[0]), 1);
    isJailbroken = init_checkForJailbreak();
    init_setupHomeDirectory();
    amethyst_init_boot_trace(argc, argv);
    init_redirectStdio();
    amethyst_boot_trace("init_redirectStdio_ok");
    init_logDeviceAndVer(argv[0]);

    loadPreferences(NO);
    amethyst_boot_trace("loadPreferences_ok");
    init_hookFunctions();
    amethyst_boot_trace("init_hookFunctions_ok");
    init_hookUIKitConstructor();
    amethyst_boot_trace("init_hookUIKit_ok");

    debugLogEnabled = getPrefBool(@"general.debug_logging");
    NSLog(@"[Debugging] Debug log enabled: %@", debugLogEnabled ? @"YES" : @"NO");

    init_setupResolvConf();
    init_setupMultiDir();
    toggleIsolatedPref(NO);
    [PLProfiles updateCurrent];
    init_setupAccounts();
    init_setupCustomControls();

    // If sandbox is disabled, W^X JIT can be enabled by Amethyst itself
    if (getEntitlementValue(@"com.apple.private.security.no-sandbox") && !isJITEnabled(true)) {
        NSLog(@"[Pre-init] no-sandbox: YES, trying to enable JIT");
        int pid;
        int ret = posix_spawnp(&pid, argv[0], NULL, NULL, (char *[]){argv[0], "", NULL}, environ);
        if (ret == 0) {
            // Cleanup child process
            waitpid(pid, NULL, WUNTRACED);
            ptrace(PT_DETACH, pid, NULL, 0);
            kill(pid, SIGTERM);
            wait(NULL);

            if (isJITEnabled(true)) {
                NSLog(@"[Pre-init] JIT has been enabled with PT_TRACE_ME");
            } else {
                NSLog(@"[Pre-init] Failed to enable JIT: unknown reason");
            }
        } else {
            NSLog(@"[Pre-init] Failed to enable JIT: posix_spawn() failed errno %d", errno);
        }
    }

    amethyst_boot_trace("enter_UIApplicationMain");
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
