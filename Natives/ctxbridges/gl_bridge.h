#pragma once

#include <EGL/egl.h>

typedef struct {
    PFNEGLBINDAPIPROC eglBindAPI;
    PFNEGLCHOOSECONFIGPROC eglChooseConfig;
    PFNEGLCREATECONTEXTPROC eglCreateContext;
    PFNEGLCREATEWINDOWSURFACEPROC eglCreateWindowSurface;
    PFNEGLDESTROYCONTEXTPROC eglDestroyContext;
    PFNEGLDESTROYSURFACEPROC eglDestroySurface;
    PFNEGLGETCONFIGATTRIBPROC eglGetConfigAttrib;
    PFNEGLGETCONFIGSPROC eglGetConfigs;
    PFNEGLGETCURRENTCONTEXTPROC eglGetCurrentContext;
    PFNEGLGETCURRENTSURFACEPROC eglGetCurrentSurface;
    PFNEGLGETDISPLAYPROC eglGetDisplay;
    PFNEGLGETERRORPROC eglGetError;
    PFNEGLGETPLATFORMDISPLAYPROC eglGetPlatformDisplay;
    PFNEGLINITIALIZEPROC eglInitialize;
    PFNEGLMAKECURRENTPROC eglMakeCurrent;
    PFNEGLQUERYSTRINGPROC eglQueryString;
    PFNEGLRELEASETHREADPROC eglReleaseThread;
    PFNEGLSWAPBUFFERSPROC eglSwapBuffers;
    PFNEGLSWAPINTERVALPROC eglSwapInterval;
    PFNEGLTERMINATEPROC eglTerminate;
    PFNEGLGETPROCADDRESSPROC eglGetProcAddress;
} egl_library;

typedef struct {
    //struct ANativeWindow *nativeSurface;
    EGLConfig  config;
    EGLint     format;
    EGLContext context;
    EGLSurface surface;
} gl_render_window_t;

void set_gl_bridge_tbl();
void amethyst_refresh_benchmark_state(void);

typedef struct {
    double estimated_fps;       // Estimated swap cadence FPS
    double frame_time_ms;       // Last frame time in ms
    double max_gap_ms;          // Maximum frame gap in ms in current/recent window
    uint32_t drops_33ms;        // Frame drops (>33.3ms) in current/recent window
    uint32_t stutters_50ms;     // Stutters (>50ms) in current/recent window
    char renderer[64];          // Active renderer name
} amethyst_metrics_snapshot_t;

void amethyst_get_metrics_snapshot(amethyst_metrics_snapshot_t *out_snapshot);
void amethyst_set_hud_active(int active);
