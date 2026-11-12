#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include <stdint.h>
#include <time.h>
#include "bridge_tbl.h"
#include "environ.h"
#include "gl_bridge.h"
#include "utils.h"

static EGLDisplay g_EglDisplay;
static egl_library handle;
static void* g_tinygl4angle_handle = NULL;
static void* g_gles2_backend_handle = NULL;

void dlsym_EGL() {
    g_tinygl4angle_handle = dlopen("@rpath/libtinygl4angle.dylib", RTLD_GLOBAL);
    NSCAssert(g_tinygl4angle_handle, @(dlerror()));

    // Nạp trực tiếp ANGLE libGLESv2 backend cho GL4ES (tránh qua tinygl4angle shim)
    g_gles2_backend_handle = dlopen("@rpath/libGLESv2.framework/libGLESv2", RTLD_LOCAL);
    if (!g_gles2_backend_handle) {
        g_gles2_backend_handle = dlopen("@rpath/libGLESv2.dylib", RTLD_LOCAL);
    }
    if (!g_gles2_backend_handle) {
        NSLog(@"[Amethyst] Info: libGLESv2 direct dlopen failed, falling back to RTLD_DEFAULT");
        g_gles2_backend_handle = RTLD_DEFAULT;
    }
    handle.eglBindAPI = dlsym(g_tinygl4angle_handle, "eglBindAPI");
    handle.eglChooseConfig = dlsym(g_tinygl4angle_handle, "eglChooseConfig");
    handle.eglCreateContext = dlsym(g_tinygl4angle_handle, "eglCreateContext");
    handle.eglCreateWindowSurface = dlsym(g_tinygl4angle_handle, "eglCreateWindowSurface");
    handle.eglDestroyContext = dlsym(g_tinygl4angle_handle, "eglDestroyContext");
    handle.eglDestroySurface = dlsym(g_tinygl4angle_handle, "eglDestroySurface");
    handle.eglGetConfigAttrib = dlsym(g_tinygl4angle_handle, "eglGetConfigAttrib");
    handle.eglGetCurrentContext = dlsym(g_tinygl4angle_handle, "eglGetCurrentContext");
    handle.eglGetDisplay = dlsym(g_tinygl4angle_handle, "eglGetDisplay");
    handle.eglGetError = dlsym(g_tinygl4angle_handle, "eglGetError");
    handle.eglGetPlatformDisplay = dlsym(g_tinygl4angle_handle, "eglGetPlatformDisplay");
    handle.eglInitialize = dlsym(g_tinygl4angle_handle, "eglInitialize");
    handle.eglMakeCurrent = dlsym(g_tinygl4angle_handle, "eglMakeCurrent");
    handle.eglSwapBuffers = dlsym(g_tinygl4angle_handle, "eglSwapBuffers");
    handle.eglReleaseThread = dlsym(g_tinygl4angle_handle, "eglReleaseThread");
    handle.eglSwapInterval = dlsym(g_tinygl4angle_handle, "eglSwapInterval");
    handle.eglTerminate = dlsym(g_tinygl4angle_handle, "eglTerminate");
    handle.eglGetCurrentSurface = dlsym(g_tinygl4angle_handle, "eglGetCurrentSurface");
    handle.eglGetProcAddress = (PFNEGLGETPROCADDRESSPROC)dlsym(g_tinygl4angle_handle, "eglGetProcAddress");
}

static bool gl_init() {
    dlsym_EGL();

    g_EglDisplay = handle.eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_EglDisplay == EGL_NO_DISPLAY) {
        NSDebugLog(@"EGLBridge: eglGetDisplay(EGL_DEFAULT_DISPLAY) returned EGL_NO_DISPLAY");
        return false;
    }
    if (!handle.eglInitialize(g_EglDisplay, NULL, NULL)) {
        NSDebugLog(@"EGLBridge: Error eglInitialize() failed: 0x%x", handle.eglGetError());
        return false;
    }
    return true;
}

gl_render_window_t* gl_init_context(gl_render_window_t *share) {
    gl_render_window_t* bundle = calloc(1, sizeof(gl_render_window_t));

    NSString *renderer = NSProcessInfo.processInfo.environment[@"RENDERER"];
    BOOL angleDesktopGL = [renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE];

    const EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT|EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, angleDesktopGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };

    EGLint num_configs;
    EGLint vid;
    if (!handle.eglChooseConfig(g_EglDisplay, attribs, &bundle->config, 1, &num_configs)) {
        NSDebugLog(@"EGLBridge: Error couldn't get an EGL visual config: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    assert(bundle->config);
    assert(num_configs > 0);

    if (!handle.eglGetConfigAttrib(g_EglDisplay, bundle->config, EGL_NATIVE_VISUAL_ID, &vid)) {
        NSDebugLog(@"EGLBridge: Error eglGetConfigAttrib() failed: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    EGLBoolean bindResult;
    if (angleDesktopGL) {
        NSDebugLog(@"EGLBridge: Binding to desktop OpenGL");
        bindResult = handle.eglBindAPI(EGL_OPENGL_API);
    } else {
        NSDebugLog(@"EGLBridge: Binding to OpenGL ES");
        bindResult = handle.eglBindAPI(EGL_OPENGL_ES_API);
    }
    if (!bindResult) NSDebugLog(@"EGLBridge: bind failed: %p\n", handle.eglGetError());

    bundle->surface = handle.eglCreateWindowSurface(g_EglDisplay, bundle->config, (__bridge EGLNativeWindowType)SurfaceViewController.surface.layer, NULL);
    if (!bundle->surface) {
        NSDebugLog(@"EGLBridge: eglCreateWindowSurface finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    const EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    bundle->context = handle.eglCreateContext(g_EglDisplay, bundle->config, share ? share->context : EGL_NO_CONTEXT, ctx_attribs);
    if (!bundle->context) {
        NSDebugLog(@"EGLBridge: Error eglCreateContext finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    //NSDebugLog(@"EGLBridge: Created CTX pointer = %p (source = %p)", bundle->context, share?share->context:0);

    return bundle;
}

extern void* get_gl4es_116_handle(void);

static void* amethyst_gles_proc_address(const char* name) {
    if (!name) return NULL;
    void* sym = NULL;
    // 1. Tìm trực tiếp trong ANGLE libGLESv2 backend (tránh hoàn toàn tinygl4angle vì tinygl4angle chặn #version es)
    if (g_gles2_backend_handle) {
        sym = dlsym(g_gles2_backend_handle, name);
    }
    // 2. Nếu là extension runtime, gọi eglGetProcAddress từ ANGLE EGL
    if (!sym && handle.eglGetProcAddress) {
        sym = (void*)handle.eglGetProcAddress(name);
    }
    // 3. Fallback sang RTLD_NEXT như upstream GL4ES cho Apple Darwin
    if (!sym) {
        sym = dlsym(RTLD_NEXT, name);
    }
    if (!sym) {
        NSLog(@"[Amethyst] Warning: Failed to resolve GLES proc address for '%s'", name);
    }
    return sym;
}

static void init_gl4es_116_if_needed(void) {
    static dispatch_once_t once_control;

    void* gl4esHandle = get_gl4es_116_handle();
    if (!gl4esHandle) {
        return;
    }

    dispatch_once(&once_control, ^{
        NSLog(@"[Amethyst] Context is CURRENT. Initializing GL4ES 1.1.6...");

        typedef void (*gl4es_set_proc_t)(void *(*)(const char *));
        gl4es_set_proc_t set_proc = (gl4es_set_proc_t)dlsym(gl4esHandle, "set_getprocaddress");
        if (set_proc) {
            NSLog(@"[Amethyst] Setting GL4ES 1.1.6 proc address resolver via ANGLE backend (libtinygl4angle)...");
            set_proc(amethyst_gles_proc_address);
        }

        typedef void (*gl4es_init_func_t)(void);
        gl4es_init_func_t init_func = (gl4es_init_func_t)dlsym(gl4esHandle, "initialize_gl4es");
        if (init_func) {
            NSLog(@"[Amethyst] Calling initialize_gl4es() from GL4ES 1.1.6 (handle=%p)...", gl4esHandle);
            init_func();
            NSLog(@"[Amethyst] GL4ES 1.1.6 initialized successfully on active context!");
        } else {
            NSLog(@"[Amethyst] ERROR: Could not find initialize_gl4es in GL4ES 1.1.6 handle: %s", dlerror());
        }
    });
}

void gl_make_current(gl_render_window_t* bundle) {
    if(!bundle) {
        if(handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)) {
            currentBundle = NULL;
        }
        return;
    }

    if(handle.eglMakeCurrent(g_EglDisplay, bundle->surface, bundle->surface, bundle->context)) {
        currentBundle = (basic_render_window_t *)bundle;
        init_gl4es_116_if_needed();
    } else {
        NSLog(@"EGLBridge: eglMakeCurrent returned with error: 0x%x", handle.eglGetError());
    }
}

#import <os/lock.h>

static int s_benchmark_enabled = 0;
static int s_fps_log_enabled = 0;
static int s_hud_active = 0;
static int s_metrics_active = 0;

static os_unfair_lock s_metrics_lock = OS_UNFAIR_LOCK_INIT;
static amethyst_metrics_snapshot_t s_live_snapshot = {0};

static uint64_t s_last_swap_time_ns = 0;
static uint64_t s_window_start_time_ns = 0;
static uint64_t s_frame_count = 0;
static uint32_t s_drops_33ms = 0;
static uint32_t s_stutters_50ms = 0;
static uint64_t s_max_interval_ns = 0;

static uint64_t s_hud_window_start_ns = 0;
static uint32_t s_hud_rolling_frames = 0;
static double s_current_fps = 0.0;

static void update_metrics_active_flag(void) {
    s_metrics_active = (s_benchmark_enabled || s_fps_log_enabled || s_hud_active) ? 1 : 0;
}

static void update_snapshot_renderer_name(void) {
    const char *rend = getenv("RENDERER");
    os_unfair_lock_lock(&s_metrics_lock);
    if (!rend) {
        snprintf(s_live_snapshot.renderer, sizeof(s_live_snapshot.renderer), "Unknown");
    } else if (strcmp(rend, RENDERER_NAME_GL4ES_116) == 0) {
        snprintf(s_live_snapshot.renderer, sizeof(s_live_snapshot.renderer), "GL4ES 1.1.6");
    } else if (strcmp(rend, RENDERER_NAME_GL4ES) == 0) {
        snprintf(s_live_snapshot.renderer, sizeof(s_live_snapshot.renderer), "GL4ES 1.1.4");
    } else if (strcmp(rend, RENDERER_NAME_MTL_ANGLE) == 0) {
        snprintf(s_live_snapshot.renderer, sizeof(s_live_snapshot.renderer), "ANGLE (Desktop GL)");
    } else if (strcmp(rend, RENDERER_NAME_MOBILEGLUES) == 0) {
        snprintf(s_live_snapshot.renderer, sizeof(s_live_snapshot.renderer), "MobileGLUES");
    } else if (strcmp(rend, RENDERER_NAME_VK_ZINK) == 0) {
        snprintf(s_live_snapshot.renderer, sizeof(s_live_snapshot.renderer), "OSMesa/Zink");
    } else {
        snprintf(s_live_snapshot.renderer, sizeof(s_live_snapshot.renderer), "%s", rend);
    }
    os_unfair_lock_unlock(&s_metrics_lock);
}

void amethyst_refresh_benchmark_state(void) {
    const char *b = getenv("AMETHYST_RENDER_BENCHMARK");
    const char *f = getenv("AMETHYST_FPS_LOG");
    s_benchmark_enabled = (b && strcmp(b, "1") == 0) ? 1 : 0;
    s_fps_log_enabled = (f && strcmp(f, "1") == 0) ? 1 : 0;
    update_metrics_active_flag();

    // Reset stats when refreshing, so downtime between launches is not counted as a spike
    s_last_swap_time_ns = 0;
    s_window_start_time_ns = 0;
    s_frame_count = 0;
    s_drops_33ms = 0;
    s_stutters_50ms = 0;
    s_max_interval_ns = 0;
    s_hud_window_start_ns = 0;
    s_hud_rolling_frames = 0;
    s_current_fps = 0.0;

    update_snapshot_renderer_name();

    NSLog(@"[Amethyst Benchmark] State refreshed: benchmark=%d, fps_log=%d, hud=%d",
          s_benchmark_enabled, s_fps_log_enabled, s_hud_active);
}

void amethyst_set_hud_active(int active) {
    s_hud_active = active ? 1 : 0;
    update_metrics_active_flag();

    if (s_hud_active) {
        update_snapshot_renderer_name();
    } else if (!s_metrics_active) {
        s_last_swap_time_ns = 0;
        s_window_start_time_ns = 0;
        s_frame_count = 0;
        s_drops_33ms = 0;
        s_stutters_50ms = 0;
        s_max_interval_ns = 0;
        s_hud_window_start_ns = 0;
        s_hud_rolling_frames = 0;
        s_current_fps = 0.0;
    }
}

void amethyst_get_metrics_snapshot(amethyst_metrics_snapshot_t *out_snapshot) {
    if (!out_snapshot) return;

    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t now_ns = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;

    os_unfair_lock_lock(&s_metrics_lock);
    *out_snapshot = s_live_snapshot;
    // If no swap has occurred for over 1.0s, the game is paused/idle/loading
    if (s_last_swap_time_ns == 0 || (now_ns > s_last_swap_time_ns && (now_ns - s_last_swap_time_ns) > 1000000000ULL)) {
        out_snapshot->estimated_fps = 0.0;
        out_snapshot->frame_time_ms = 0.0;
    }
    os_unfair_lock_unlock(&s_metrics_lock);
}

static void amethyst_benchmark_on_swap(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t now_ns = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;

    if (s_last_swap_time_ns == 0) {
        s_last_swap_time_ns = now_ns;
        s_window_start_time_ns = now_ns;
        s_hud_window_start_ns = now_ns;
        s_hud_rolling_frames = 0;
        return;
    }

    uint64_t interval_ns = now_ns - s_last_swap_time_ns;
    s_last_swap_time_ns = now_ns;

    // Loading / pause / resume gap filter: intervals > 1.0s are treated as discontinuity
    if (interval_ns > 1000000000ULL) {
        s_window_start_time_ns = now_ns;
        s_hud_window_start_ns = now_ns;
        s_hud_rolling_frames = 0;
        s_frame_count = 0;
        s_drops_33ms = 0;
        s_stutters_50ms = 0;
        s_max_interval_ns = 0;
        return;
    }

    s_frame_count++;
    s_hud_rolling_frames++;

    if (interval_ns > s_max_interval_ns) {
        s_max_interval_ns = interval_ns;
    }
    if (interval_ns > 33333333ULL) { // > 33.3ms (cadence drop below ~30 fps)
        s_drops_33ms++;
    }
    if (interval_ns > 50000000ULL) { // > 50.0ms (cadence stutter below ~20 fps)
        s_stutters_50ms++;
    }

    // Update rolling HUD FPS calculation (~every 500ms)
    uint64_t hud_elapsed_ns = now_ns - s_hud_window_start_ns;
    if (hud_elapsed_ns >= 500000000ULL) {
        if (s_hud_rolling_frames >= 2) {
            s_current_fps = (double)s_hud_rolling_frames / ((double)hud_elapsed_ns / 1.0e9);
        }
        s_hud_window_start_ns = now_ns;
        s_hud_rolling_frames = 0;
    }

    // Thread-safe update of live metrics snapshot
    double frame_time_ms = (double)interval_ns / 1.0e6;
    os_unfair_lock_lock(&s_metrics_lock);
    s_live_snapshot.estimated_fps = s_current_fps;
    s_live_snapshot.frame_time_ms = frame_time_ms;
    s_live_snapshot.max_gap_ms = (double)s_max_interval_ns / 1.0e6;
    s_live_snapshot.drops_33ms = s_drops_33ms;
    s_live_snapshot.stutters_50ms = s_stutters_50ms;
    os_unfair_lock_unlock(&s_metrics_lock);

    // Benchmark and FPS Log reporting window (>= 5.0 seconds)
    uint64_t window_duration_ns = now_ns - s_window_start_time_ns;
    if (window_duration_ns >= 5000000000ULL) {
        double duration_sec = (double)window_duration_ns / 1.0e9;

        if (s_frame_count >= 5) {
            double avg_fps = (double)s_frame_count / duration_sec;
            double max_interval_ms = (double)s_max_interval_ns / 1.0e6;

            if (s_benchmark_enabled) {
                const char *renderer = getenv("RENDERER");
                const char *batch = getenv("LIBGL_BATCH");
                const char *vbo = getenv("LIBGL_USEVBO");
                const char *mipmap = getenv("LIBGL_MIPMAP");
                const char *noshaderlod = getenv("LIBGL_NOSHADERLOD");
                const char *shrink = getenv("LIBGL_SHRINK");
                const char *novaocache = getenv("LIBGL_NOVAOCACHE");

                NSLog(@"[Amethyst Benchmark] ===== %.1fs Window Summary =====", duration_sec);
                NSLog(@"[Amethyst Benchmark] Renderer: %s", renderer ? renderer : "unknown");
                NSLog(@"[Amethyst Benchmark] Flags: BATCH=%s, VBO=%s, MIPMAP=%s, NOSHADERLOD=%s, SHRINK=%s, NOVAOCACHE=%s",
                      batch ? batch : "default",
                      vbo ? vbo : "default",
                      mipmap ? mipmap : "default",
                      noshaderlod ? noshaderlod : "off",
                      shrink ? shrink : "default",
                      novaocache ? novaocache : "off");
                NSLog(@"[Amethyst Benchmark] Swap-Completion Cadence: Est. FPS: %.1f | Frames: %llu | Max Interval: %.2f ms",
                      avg_fps, (unsigned long long)s_frame_count, max_interval_ms);
                NSLog(@"[Amethyst Benchmark] Frame Gaps: >33.3ms (drops): %u | >50.0ms (stutter spikes): %u",
                      s_drops_33ms, s_stutters_50ms);
                NSLog(@"[Amethyst Benchmark] ===================================");
            } else if (s_fps_log_enabled) {
                NSLog(@"[Amethyst FPS] Swap-Completion Cadence: %.1f FPS (Frames: %llu, window: %.1fs, max gap: %.1f ms, drops >33ms: %u, stutters >50ms: %u)",
                      avg_fps, (unsigned long long)s_frame_count, duration_sec, max_interval_ms, s_drops_33ms, s_stutters_50ms);
            }
        }

        s_window_start_time_ns = now_ns;
        s_frame_count = 0;
        s_drops_33ms = 0;
        s_stutters_50ms = 0;
        s_max_interval_ns = 0;
    }
}

void gl_swap_buffers() {
    EGLBoolean swap_ok = handle.eglSwapBuffers(g_EglDisplay, currentBundle->gl.surface);
    if (!swap_ok) {
        if (handle.eglGetError() == EGL_BAD_SURFACE) {
            NSLog(@"eglSwapBuffers error 0x%x", handle.eglGetError());
        }
        return;
    }

    if (__builtin_expect(s_metrics_active, 0)) {
        amethyst_benchmark_on_swap();
    }
}

void gl_swap_interval(int swapInterval) {
    handle.eglSwapInterval(g_EglDisplay, swapInterval);
}

void gl_terminate() {
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    handle.eglDestroySurface(g_EglDisplay, currentBundle->gl.surface);
    handle.eglDestroyContext(g_EglDisplay, currentBundle->gl.context);
    handle.eglTerminate(g_EglDisplay);
    handle.eglReleaseThread();
    free(currentBundle);
    currentBundle = nil;
}

void set_gl_bridge_tbl() {
    br_init = gl_init;
    br_init_context = (br_init_context_t) gl_init_context;
    br_make_current = (br_make_current_t) gl_make_current;
    br_swap_buffers = gl_swap_buffers;
    br_swap_interval = gl_swap_interval;
    br_terminate = gl_terminate;
}
