#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <os/lock.h>
#include <objc/runtime.h>
#include "jni.h"

#import "GameSurfaceView.h"
#import "SurfaceViewController.h"
#import "utils.h"

// the [SDL3 TRACE] / [SDL3 EMBED] chatter is off by default, AMETHYST_SDL_TRACE=1 in the custom env vars brings it back
static BOOL AMTraceOn(void) {
    static int on = -1;
    if (on < 0) {
        const char *v = getenv("AMETHYST_SDL_TRACE");
        on = (v != NULL && *v != '\0' && *v != '0') ? 1 : 0;
    }
    return on == 1;
}
#define AMTrace(...) do { if (AMTraceOn()) NSLog(__VA_ARGS__); } while (0)

static UIWindow *gSDLWindow = nil;
static UIView *gSDLView = nil;
static BOOL gSDLInstalled = NO;
static BOOL gObserversInstalled = NO;

// Forward declaration for window retry helper
static void AMScheduleEmbedRetry(int attempt);

static BOOL AMIsSDLView(UIView *view) {
    if (view == nil) return NO;

    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"SDL_uikitmetalview"] ||
           [name containsString:@"SDL_uikitopenglview"];
}

static UIView *AMFindSDLView(UIView *root) {
    if (root == nil) return nil;

    if (AMIsSDLView(root)) {
        return root;
    }

    for (UIView *child in root.subviews) {
        UIView *found = AMFindSDLView(child);
        if (found != nil) return found;
    }

    return nil;
}

static UIWindow *AMFindSDLWindow(void) {
    NSSet<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes;

    for (UIScene *scene in scenes) {
        if (![scene isKindOfClass:UIWindowScene.class])
            continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *window in windowScene.windows) {
            UIView *sdlView = AMFindSDLView(window.rootViewController.view);

            if (sdlView != nil) {
                return window;
            }
        }
    }

    return nil;
}

static void AMRunSyncOnMain(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
        return;
    }

    dispatch_sync(dispatch_get_main_queue(), block);
}

#define AM_MAIN_CALL_TIMEOUT_SECONDS 20

static const char *(*sSDLGetError)(void) = NULL;
static void (*sSDLClearError)(void) = NULL;
static char sMainError[512];
static os_unfair_lock sMainErrorLock = OS_UNFAIR_LOCK_INIT;

static void AMNoteSDLFunction(uint64_t functionAddress) {
    if (sSDLGetError != NULL || functionAddress == 0) return;

    Dl_info info;
    if (dladdr((const void *)(uintptr_t)functionAddress, &info) == 0 || info.dli_fname == NULL) return;

    void *handle = dlopen(info.dli_fname, RTLD_NOW | RTLD_NOLOAD);
    if (handle == NULL) return;

    sSDLClearError = (void (*)(void))dlsym(handle, "SDL_ClearError");
    sSDLGetError = (const char *(*)(void))dlsym(handle, "SDL_GetError");
    dlclose(handle);
}

static void AMBeginMainCall(uint64_t functionAddress) {
    AMNoteSDLFunction(functionAddress);

    os_unfair_lock_lock(&sMainErrorLock);
    sMainError[0] = '\0';
    os_unfair_lock_unlock(&sMainErrorLock);

    if (sSDLClearError != NULL) sSDLClearError();
}

static void AMEndMainCall(void) {
    if (sSDLGetError == NULL) return;

    const char *error = sSDLGetError();
    if (error == NULL || error[0] == '\0') return;

    os_unfair_lock_lock(&sMainErrorLock);
    strlcpy(sMainError, error, sizeof(sMainError));
    os_unfair_lock_unlock(&sMainErrorLock);
}


 // ios stops letting an app submit gpu work in the background, so the Java side holds the game
 // thread while this is set (SDL3Lifecycle).

static volatile bool sAppBackground = false;


static void AMApplyPixelFilter(UIView *view) {
    view.layer.magnificationFilter = kCAFilterNearest;
    view.layer.minificationFilter = kCAFilterNearest;
}

// MoltenVK and ANGLE size their drawable from bounds * contentsScale, so the resolution setting has to live in the scale
void AmethystSDL3ApplyResolutionScale(void) {
    UIView *view = gSDLView;
    const char *renderer = getenv("AME_RENDERER");
    // MobileGL sizes its own surface
    if (view == nil || (renderer != NULL && !strcmp(renderer, RENDERER_NAME_MOBILEGL))) return;

    CGFloat base = view.window.screen.scale;
    if (base <= 0) base = UIScreen.mainScreen.scale;
    CGFloat scale = base * (resolutionScale > 0 ? resolutionScale : 1.0);
    if (fabs(view.layer.contentsScale - scale) < 0.001) return;

    view.layer.contentsScale = scale;
    if ([view.layer isKindOfClass:CAMetalLayer.class] && view.bounds.size.width > 0 && view.bounds.size.height > 0) {
        ((CAMetalLayer *)view.layer).drawableSize =
            CGSizeMake(MAX(round(view.bounds.size.width * scale), 1), MAX(round(view.bounds.size.height * scale), 1));
    }
    [view setNeedsLayout];
}


// MoltenVK compares its swapchain size with the layer's bounds * contentsScale. With the
// resolution setting below 100% those differ, so this logs what the layer really looks like.

static void AMLogSDLViewGeometry(const char *when) {
    UIView *view = gSDLView;
    if (view == nil || !AMTraceOn()) return;

    CGSize drawable = CGSizeZero;
    @try {
        NSValue *value = [view.layer valueForKey:@"drawableSize"];
        if ([value isKindOfClass:NSValue.class]) drawable = value.CGSizeValue;
    } @catch (NSException *exception) {
    }

    NSLog(@"[SDL3 EMBED] %s: bounds=%.1fx%.1f contentsScale=%.2f drawableSize=%.0fx%.0f",
          when,
          view.bounds.size.width, view.bounds.size.height,
          view.layer.contentsScale,
          drawable.width, drawable.height);
}

static void AMEmbedSDLViewOnMain(void) {
    GameSurfaceView *host = [SurfaceViewController surface];

    if (host == nil) {
        NSLog(@"[SDL3 EMBED] GameSurfaceView unavailable");
        return;
    }

    UIWindow *window = AMFindSDLWindow();

    if (window == nil) {
        AMTrace(@"[SDL3 EMBED] SDL UIWindow not found yet");
        return;
    }

    UIView *sdlView = AMFindSDLView(window.rootViewController.view);

    if (sdlView == nil) {
        AMTrace(@"[SDL3 EMBED] SDL UIKit view not found yet");
        return;
    }

    gSDLWindow = window;
    gSDLView = sdlView;

    AMTrace(@"[SDL3 EMBED] Found SDL window=%p class=%@ key=%d hidden=%d interaction=%d",
          window,
          NSStringFromClass(window.class),
          window.isKeyWindow,
          window.hidden,
          window.userInteractionEnabled);

    AMTrace(@"[SDL3 EMBED] SDL view=%p class=%@ superview=%@ interaction=%d",
          sdlView,
          NSStringFromClass(sdlView.class),
          NSStringFromClass(sdlView.superview.class),
          sdlView.userInteractionEnabled);

    /*
     * If SDL has already been embedded, do nothing.
     */
    if (sdlView.superview == host) {
        sdlView.hidden = NO;
        sdlView.userInteractionEnabled = NO; // Interaction stays off so touchView handles inputs
        AMApplyPixelFilter(sdlView);
        AmethystSDL3ApplyResolutionScale();
        gSDLInstalled = YES;

        AMTrace(@"[SDL3 EMBED] SDL view already embedded");
        return;
    }

    /*
     * Preserve SDL's actual UIKit view. Do not create a fake renderer view.
     */
    [sdlView removeFromSuperview];

    sdlView.translatesAutoresizingMaskIntoConstraints = NO;
    sdlView.hidden = NO;
    /*
     * Interaction has to stay OFF. SDL's view handles touches itself and never calls
     * super, so with it enabled Amethyst's touchView never gets touchesBegan/Moved
     * (cursor, camera, hotbar) and the SDL touch->mouse events would double up with the
     * input Amethyst already forwards (see AmethystSDL3ForwardInput).
     */
    sdlView.userInteractionEnabled = NO;

    /*
     * Put SDL behind Amethyst's existing controls.
     *
     * The previous implementation used addSubview:, which put SDL on top
     * of every existing child of GameSurfaceView.
     */
    [host insertSubview:sdlView atIndex:0];

    [NSLayoutConstraint activateConstraints:@[
        [sdlView.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [sdlView.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [sdlView.topAnchor constraintEqualToAnchor:host.topAnchor],
        [sdlView.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
    ]];

    /*
     * The SDL UIWindow no longer owns the render view. Hide only that
     * secondary window so it cannot cover the Amethyst window.
     */
    window.hidden = YES;
    window.userInteractionEnabled = NO;

    AMApplyPixelFilter(sdlView);
    AmethystSDL3ApplyResolutionScale();
    gSDLInstalled = YES;

    NSLog(@"[SDL3 EMBED] SUCCESS: %@ embedded into GameSurfaceView",
          NSStringFromClass(sdlView.class));

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AMLogSDLViewGeometry("1s after embed");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AMLogSDLViewGeometry("6s after embed");
    });
}

/*
 * SDL can create its UIKit window asynchronously relative to Java's class
 * initialization. Try immediately and again after UIKit window notifications.
 */
static void AMTryEmbed(void) {
    AMRunSyncOnMain(^{
        AMEmbedSDLViewOnMain();
    });
}

static void AMUIKitWindowDidBecomeVisible(NSNotification *note) {
    UIWindow *window = note.object;

    if (![window isKindOfClass:UIWindow.class])
        return;

    AMRunSyncOnMain(^{
        UIView *sdlView = AMFindSDLView(window.rootViewController.view);

        if (sdlView == nil)
            return;

        AMTrace(@"[SDL3 EMBED] SDL window became visible: %p", window);

        /*
         * Delay one main-runloop turn because SDL may still be replacing its
         * generic SDL_uikitview with SDL_uikitmetalview.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            AMEmbedSDLViewOnMain();
        });
    });
}

static void AMUIKitWindowDidBecomeKey(NSNotification *note) {
    UIWindow *window = note.object;

    if (![window isKindOfClass:UIWindow.class])
        return;

    UIView *sdlView = AMFindSDLView(window.rootViewController.view);

    if (sdlView == nil)
        return;

    AMTrace(@"[SDL3 EMBED] SDL window became key: %p", window);

    dispatch_async(dispatch_get_main_queue(), ^{
        AMEmbedSDLViewOnMain();
    });
}

static void AMInstallUIKitObservers(void) {
    if (gObserversInstalled)
        return;

    gObserversInstalled = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserverForName:UIWindowDidBecomeVisibleNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        AMUIKitWindowDidBecomeVisible(note);
    }];

    [center addObserverForName:UIWindowDidBecomeKeyNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        AMUIKitWindowDidBecomeKey(note);
    }];

    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        sAppBackground = true;
        NSLog(@"[SDL3] app entered the background");
    }];

    [center addObserverForName:UIApplicationWillEnterForegroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        sAppBackground = false;
        NSLog(@"[SDL3] app is returning to the foreground");
    }];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        sAppBackground = false;
    }];

    AMTrace(@"[SDL3 EMBED] UIKit window observers installed");
}

/*
 * SDL_SetMainReady must run before SDL initializes its application state.
 */
static void AMSDL3SetMainReady(void) {
    AMRunSyncOnMain(^{
        const char *paths[] = {
            "@executable_path/Frameworks/lwjgl34/libSDL3.dylib",
            "@loader_path/Frameworks/lwjgl34/libSDL3.dylib",
            NULL
        };

        for (int i = 0; paths[i] != NULL; i++) {
            void *handle = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);

            if (handle == NULL)
                continue;

            void (*setMainReady)(void) =
                (void (*)(void))dlsym(handle, "SDL_SetMainReady");

            if (setMainReady != NULL) {
                setMainReady();
                AMTrace(@"[SDL3] SDL_SetMainReady called");
                dlclose(handle);
                return;
            }

            dlclose(handle);
        }

        void *handle =
            dlopen("@rpath/SDL3.framework/SDL3", RTLD_NOW | RTLD_LOCAL);

        if (handle != NULL) {
            void (*setMainReady)(void) =
                (void (*)(void))dlsym(handle, "SDL_SetMainReady");

            if (setMainReady != NULL) {
                setMainReady();
                AMTrace(@"[SDL3] SDL_SetMainReady called");
            }

            dlclose(handle);
        }
    });
}

static void AMSDL3SetMainReadyForControlify(void) {
    AMRunSyncOnMain(^{
        void *handle = dlopen("@executable_path/Frameworks/lwjgl34/libSDL3_controlify.dylib", RTLD_NOW | RTLD_LOCAL);
        if (handle == NULL) {
            NSLog(@"[SDL3] no private SDL copy for Controlify (libSDL3_controlify.dylib), controller mods will not work");
            return;
        }

        void (*setMainReady)(void) = (void (*)(void))dlsym(handle, "SDL_SetMainReady");
        if (setMainReady != NULL) {
            setMainReady();
            AMTrace(@"[SDL3] SDL_SetMainReady called for the Controlify SDL copy");
        } else {
            NSLog(@"[SDL3] SDL_SetMainReady missing in the Controlify SDL copy");
        }
    });
}

void AmethystSDL3Prepare(void) {
    AMTrace(@"[SDL3 TRACE] nativePrepare BEGIN main=%d",
          [NSThread isMainThread]);

    AMInstallUIKitObservers();
    AMRunSyncOnMain(^{
        sAppBackground = UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
    });
    AMSDL3SetMainReady();
    AMSDL3SetMainReadyForControlify();

    
    // SDL turns the phone's accelerometer into a fake joystick by default, which controller mods
    // then list as a gamepad and which keeps CoreMotion running for nothing.
    
    setenv("SDL_ACCELEROMETER_AS_JOYSTICK", "0", 0);

    /*
     * Keep SDL from installing its own home-indicator behavior over
     * Amethyst's presentation.
     */
    setenv("SDL_IOS_HIDE_HOME_INDICATOR", "2", 0);

    NSString *moltenVK =
        [NSBundle.mainBundle.bundlePath
            stringByAppendingPathComponent:@"Frameworks/libMoltenVK.dylib"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:moltenVK]) {
        setenv("SDL_VULKAN_LIBRARY", moltenVK.UTF8String, 1);
        AMTrace(@"[SDL3] SDL_VULKAN_LIBRARY=%@", moltenVK);
    } else {
        NSLog(@"[SDL3] libMoltenVK.dylib not found");
    }

    /*
     * SDL may not have created its UIWindow yet. This is intentionally
     * non-fatal; the UIKit notification handlers will catch it later.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        AMEmbedSDLViewOnMain();
    });

    AMTrace(@"[SDL3 TRACE] nativePrepare END");
}

void AmethystSDL3Loaded(void) {
    AMTrace(@"[SDL3 TRACE] nativeLoaded main=%d",
          [NSThread isMainThread]);

    /*
     * By nativeLoaded the SDL library is definitely resident. Give SDL one
     * more main-thread opportunity to create its UIKit window.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        AMEmbedSDLViewOnMain();
    });
}

JNIEXPORT void JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativePrepare(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    AmethystSDL3Prepare();
}

JNIEXPORT void JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeLoaded(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    AmethystSDL3Loaded();
}

/*
 * These functions are retained for compatibility with the existing
 * SDL3Bridge.java. Minecraft 26.3 does not appear to use them for its
 * actual window creation path, but keeping them prevents JNI symbol
 * mismatches if another LWJGL SDL path calls them.
 */
static BOOL AMInvokeBoolOnMain(long long functionAddress, int flags) {
    if (functionAddress == 0)
        return NO;

    __block BOOL result = NO;

    AMRunSyncOnMain(^{
        BOOL (*fn)(int) =
            (BOOL (*)(int))(uintptr_t)functionAddress;

        AMBeginMainCall((uint64_t)functionAddress);
        result = fn(flags);
        AMEndMainCall();
    });

    return result;
}

JNIEXPORT jboolean JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeInit(JNIEnv *env, jclass clazz,
                                         jlong functionAddress, jint flags) {
    (void)env;
    (void)clazz;

    BOOL result =
        AMInvokeBoolOnMain((long long)functionAddress, (int)flags);

    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeInitSubSystem(JNIEnv *env, jclass clazz,
                                                  jlong functionAddress,
                                                  jint flags) {
    (void)env;
    (void)clazz;

    BOOL result =
        AMInvokeBoolOnMain((long long)functionAddress, (int)flags);

    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeCreateWindow(JNIEnv *env, jclass clazz,
                                                 jlong functionAddress,
                                                 jlong title,
                                                 jint w, jint h,
                                                 jlong flags) {
    (void)env;
    (void)clazz;

    __block void *window = NULL;

    AMRunSyncOnMain(^{
        void *(*fn)(const char *, int, int, uint64_t) =
            (void *(*)(const char *, int, int, uint64_t))
                (uintptr_t)functionAddress;

        AMBeginMainCall((uint64_t)functionAddress);
        window = fn((const char *)(uintptr_t)title,
                    (int)w,
                    (int)h,
                    (uint64_t)flags);
        AMEndMainCall();
    });

    dispatch_async(dispatch_get_main_queue(), ^{
        AMEmbedSDLViewOnMain();
    });

    return (jlong)(uintptr_t)window;
}

JNIEXPORT jlong JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeCreateWindowWithProperties(
    JNIEnv *env, jclass clazz,
    jlong functionAddress, jint props) {
    (void)env;
    (void)clazz;

    __block void *window = NULL;

    AMRunSyncOnMain(^{
        void *(*fn)(uint32_t) =
            (void *(*)(uint32_t))(uintptr_t)functionAddress;

        AMBeginMainCall((uint64_t)functionAddress);
        window = fn((uint32_t)props);
        AMEndMainCall();
    });

    dispatch_async(dispatch_get_main_queue(), ^{
        AMEmbedSDLViewOnMain();
    });

    return (jlong)(uintptr_t)window;
}

/*
 * Input: Amethyst's touch/keyboard/controls all go through CallbackBridge_nativeSend*, which
 * only ever fed GLFW callbacks. Once SDL3Bridge registers itself those calls are forwarded to
 * SDL3Bridge.onInput() and become SDL events.
 */
static JavaVM *sSDLInputVM = NULL;
static jclass sSDLInputClass = NULL;
static jmethodID sSDLInputMethod = NULL;
static volatile bool sSDLInputActive = false;

bool AmethystSDL3InputActive(void) {
    return sSDLInputActive;
}

void AmethystSDL3ForwardInput(int kind, int a, int b, int c, int d, float f1, float f2) {
    if (!sSDLInputActive || sSDLInputVM == NULL) return;

    JNIEnv *env = NULL;
    jint status = (*sSDLInputVM)->GetEnv(sSDLInputVM, (void **)&env, JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if ((*sSDLInputVM)->AttachCurrentThreadAsDaemon(sSDLInputVM, (JNIEnv **)&env, NULL) != JNI_OK) return;
    } else if (status != JNI_OK || env == NULL) {
        return;
    }

    (*env)->CallStaticVoidMethod(env, sSDLInputClass, sSDLInputMethod,
                                 (jint)kind, (jint)a, (jint)b, (jint)c, (jint)d,
                                 (jfloat)f1, (jfloat)f2);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
    }
}

JNIEXPORT void JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeRegisterInput(JNIEnv *env, jclass clazz) {
    (*env)->GetJavaVM(env, &sSDLInputVM);
    if (sSDLInputClass == NULL) {
        sSDLInputClass = (*env)->NewGlobalRef(env, clazz);
    }
    sSDLInputMethod = (*env)->GetStaticMethodID(env, clazz, "onInput", "(IIIIIFF)V");
    if (sSDLInputMethod == NULL) {
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        NSLog(@"[SDL3] SDL3Bridge.onInput not found, input bridge disabled");
        return;
    }
    sSDLInputActive = true;
    NSLog(@"[SDL3] input bridge active");
}

// defined in input_bridge_v3.m: sets isGrabbing and refreshes controls / virtual mouse
JNIEXPORT void JNICALL
Java_org_lwjgl_glfw_CallbackBridge_nativeSetGrabbing(JNIEnv *env, jclass clazz,
                                                     jboolean grabbing, jfloat xset, jfloat yset);

JNIEXPORT void JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeSetGrabbing(JNIEnv *env, jclass clazz, jboolean grabbing) {
    AMTrace(@"[SDL3 TRACE] setGrabbing %d", (int)grabbing);
    Java_org_lwjgl_glfw_CallbackBridge_nativeSetGrabbing(env, clazz, grabbing, 0.0f, 0.0f);
}

extern volatile bool AMControllerPassthrough;

JNIEXPORT void JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeSetControllerPassthrough(JNIEnv *env, jclass clazz, jboolean passthrough) {
    (void)env;
    (void)clazz;
    AMControllerPassthrough = passthrough;
    AMTrace(@"[SDL3] controller passthrough %d", (int)passthrough);
}

JNIEXPORT jlong JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeInvokeOnMain(JNIEnv *env,
                                                 jclass clazz,
                                                 jlong functionAddress,
                                                 jlong a0,
                                                 jlong a1,
                                                 jlong a2,
                                                 jlong a3) {
    (void)env;
    (void)clazz;

    if (functionAddress == 0)
        return 0;

    uint64_t (*fn)(uint64_t, uint64_t, uint64_t, uint64_t) =
        (uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t))
            (uintptr_t)functionAddress;

    if ([NSThread isMainThread]) {
        AMBeginMainCall((uint64_t)functionAddress);
        uint64_t direct = fn((uint64_t)a0, (uint64_t)a1, (uint64_t)a2, (uint64_t)a3);
        AMEndMainCall();
        return (jlong)direct;
    }
    
    __block uint64_t result = 0;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_main_queue(), ^{
        AMBeginMainCall((uint64_t)functionAddress);
        result = fn((uint64_t)a0, (uint64_t)a1, (uint64_t)a2, (uint64_t)a3);
        AMEndMainCall();
        dispatch_semaphore_signal(done);
    });

    dispatch_time_t limit = dispatch_time(DISPATCH_TIME_NOW,
                                          (int64_t)AM_MAIN_CALL_TIMEOUT_SECONDS * (int64_t)NSEC_PER_SEC);
    if (dispatch_semaphore_wait(done, limit) != 0) {
        NSLog(@"[SDL3] main thread call to %p did not finish in %ds, giving up on it",
              (void *)(uintptr_t)functionAddress, AM_MAIN_CALL_TIMEOUT_SECONDS);
        return 0;
    }

    return (jlong)result;
}

JNIEXPORT jstring JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeLastMainError(JNIEnv *env, jclass clazz) {
    (void)clazz;

    char copy[sizeof(sMainError)];
    os_unfair_lock_lock(&sMainErrorLock);
    strlcpy(copy, sMainError, sizeof(copy));
    os_unfair_lock_unlock(&sMainErrorLock);

    return (*env)->NewStringUTF(env, copy);
}

JNIEXPORT jboolean JNICALL
Java_org_lwjgl_sdl_SDL3Lifecycle_nativeIsBackground(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return sAppBackground ? JNI_TRUE : JNI_FALSE;
}

/*
 * The metal view only exists once minecraft has made its vulkan surface, which is after
 * SDL_CreateWindow and not necessarily followed by a UIWindow notification. Keep trying.
 */
static BOOL AMSDLViewIsEmbedded(void) {
    GameSurfaceView *host = [SurfaceViewController surface];
    return gSDLInstalled && gSDLView != nil && host != nil && gSDLView.superview == host;
}

static void AMScheduleEmbedRetry(int attempt) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (AMSDLViewIsEmbedded()) return;

        AMEmbedSDLViewOnMain();

        if (AMSDLViewIsEmbedded() || attempt >= 100) {
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            AMScheduleEmbedRetry(attempt + 1);
        });
    });
}

JNIEXPORT void JNICALL
Java_org_lwjgl_sdl_SDL3Bridge_nativeAttachWindow(JNIEnv *env,
                                                 jclass clazz,
                                                 jlong sdlWindow,
                                                 jlong uiWindow) {
    (void)env;
    (void)clazz;
    (void)sdlWindow;
    (void)uiWindow;

    /*
     * Do not trust the Java-side uiWindow pointer. The real MC 26.3 path
     * creates SDL's UIKit window internally. Rediscover it from UIKit.
     */
    AMScheduleEmbedRetry(0);
}
