#import <Foundation/Foundation.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include "bridge_tbl.h"
#include "environ.h"
#include "gl_bridge.h"
#include "utils.h"

static EGLDisplay g_EglDisplay;
static egl_library handle;

void dlsym_EGL() {
    void* dl_handle = dlopen("@rpath/libtinygl4angle.dylib", RTLD_GLOBAL);
    if (!dl_handle) {
        dl_handle = dlopen("@rpath/libEGL.framework/libEGL", RTLD_LOCAL);
    }
    if (!dl_handle) {
        NSLog(@"EGLBridge: Failed to load ANGLE EGL library");
        return;
    }
    BOOL useLTW = [@ RENDERER_NAME_LTW isEqualToString:
        NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"]];

    handle.eglBindAPI = dlsym(dl_handle, "eglBindAPI");
    handle.eglChooseConfig = dlsym(dl_handle, "eglChooseConfig");
    if (useLTW) {
        // Resolve EGL functions from LTW's own handle so its wrappers
        // (eglCreateContext, eglDestroyContext, eglMakeCurrent) are
        // picked up. RTLD_DEFAULT may find ANGLE's instead due to flat
        // namespace search order, so use dlopen + dlsym on the LTW
        // handle directly.
        void* ltw = dlopen("@rpath/libltw.dylib", RTLD_LAZY | RTLD_LOCAL);
        if (ltw) {
            handle.eglCreateContext = dlsym(ltw, "eglCreateContext");
            handle.eglDestroyContext = dlsym(ltw, "eglDestroyContext");
            handle.eglMakeCurrent = dlsym(ltw, "eglMakeCurrent");
        }
        if (!handle.eglCreateContext) handle.eglCreateContext = dlsym(dl_handle, "eglCreateContext");
        if (!handle.eglDestroyContext) handle.eglDestroyContext = dlsym(dl_handle, "eglDestroyContext");
        if (!handle.eglMakeCurrent) handle.eglMakeCurrent = dlsym(dl_handle, "eglMakeCurrent");
    } else {
        handle.eglCreateContext = dlsym(dl_handle, "eglCreateContext");
        handle.eglDestroyContext = dlsym(dl_handle, "eglDestroyContext");
        handle.eglMakeCurrent = dlsym(dl_handle, "eglMakeCurrent");
    }
    handle.eglCreateWindowSurface = dlsym(dl_handle, "eglCreateWindowSurface");
    handle.eglDestroySurface = dlsym(dl_handle, "eglDestroySurface");
    handle.eglGetConfigAttrib = dlsym(dl_handle, "eglGetConfigAttrib");
    handle.eglGetCurrentContext = dlsym(dl_handle, "eglGetCurrentContext");
    handle.eglGetDisplay = dlsym(dl_handle, "eglGetDisplay");
    handle.eglGetError = dlsym(dl_handle, "eglGetError");
    handle.eglGetPlatformDisplay = dlsym(dl_handle, "eglGetPlatformDisplay");
    handle.eglInitialize = dlsym(dl_handle, "eglInitialize");
    handle.eglSwapBuffers = dlsym(dl_handle, "eglSwapBuffers");
    handle.eglReleaseThread = dlsym(dl_handle, "eglReleaseThread");
    handle.eglSwapInterval = dlsym(dl_handle, "eglSwapInterval");
    handle.eglTerminate = dlsym(dl_handle, "eglTerminate");
    handle.eglGetCurrentSurface = dlsym(dl_handle, "eglGetCurrentSurface");
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

    NSString *renderer = NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"];
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
    if (!bundle->config || num_configs == 0) {
        NSDebugLog(@"EGLBridge: No suitable EGL config found (num_configs=%d, config=%p)", num_configs, bundle->config);
        free(bundle);
        return NULL;
    }

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

void gl_make_current(gl_render_window_t* bundle) {
    if(!bundle) {
        if(handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)) {
            currentBundle = NULL;
        }
        return;
    }

    if(handle.eglMakeCurrent(g_EglDisplay, bundle->surface, bundle->surface, bundle->context)) {
        currentBundle = (basic_render_window_t *)bundle;
    } else {
        NSLog(@"EGLBridge: eglMakeCurrent returned with error: 0x%x", handle.eglGetError());
    }
}

void gl_swap_buffers() {
    if (!currentBundle) return;
    if (!handle.eglSwapBuffers(g_EglDisplay, currentBundle->gl.surface) && handle.eglGetError() == EGL_BAD_SURFACE) {
        NSLog(@"eglSwapBuffers error 0x%x", handle.eglGetError());
    }
}

void gl_swap_interval(int swapInterval) {
    handle.eglSwapInterval(g_EglDisplay, swapInterval);
}

void gl_terminate() {
    if (currentBundle) {
        handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        handle.eglDestroySurface(g_EglDisplay, currentBundle->gl.surface);
        handle.eglDestroyContext(g_EglDisplay, currentBundle->gl.context);
        free(currentBundle);
        currentBundle = nil;
    }
    handle.eglTerminate(g_EglDisplay);
    handle.eglReleaseThread();
}

void set_gl_bridge_tbl() {
    br_init = gl_init;
    br_init_context = (br_init_context_t) gl_init_context;
    br_make_current = (br_make_current_t) gl_make_current;
    br_swap_buffers = gl_swap_buffers;
    br_swap_interval = gl_swap_interval;
    br_terminate = gl_terminate;
}
