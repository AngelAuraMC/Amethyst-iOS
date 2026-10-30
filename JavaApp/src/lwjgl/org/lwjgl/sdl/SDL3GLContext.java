package org.lwjgl.sdl;

import org.lwjgl.system.FunctionProvider;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.HashMap;
import java.util.Map;

final class SDL3GLContext {
    private SDL3GLContext() {
    }

    private static final int EGL_NONE = 0x3038;
    private static final int EGL_RED_SIZE = 0x3024;
    private static final int EGL_GREEN_SIZE = 0x3023;
    private static final int EGL_BLUE_SIZE = 0x3022;
    private static final int EGL_ALPHA_SIZE = 0x3021;
    private static final int EGL_DEPTH_SIZE = 0x3025;
    private static final int EGL_STENCIL_SIZE = 0x3026;
    private static final int EGL_SURFACE_TYPE = 0x3033;
    private static final int EGL_RENDERABLE_TYPE = 0x3040;
    private static final int EGL_WINDOW_BIT = 0x0004;
    private static final int EGL_PBUFFER_BIT = 0x0001;
    private static final int EGL_OPENGL_BIT = 0x0008;
    private static final int EGL_OPENGL_API = 0x30A2;
    private static final int EGL_WIDTH = 0x3057;
    private static final int EGL_HEIGHT = 0x3056;
    private static final int EGL_CONTEXT_MAJOR_VERSION = 0x3098;
    private static final int EGL_CONTEXT_MINOR_VERSION = 0x30FB;
    private static final int EGL_CONTEXT_OPENGL_PROFILE_MASK = 0x30FD;
    private static final int EGL_CONTEXT_FLAGS = 0x30FC;

    private static final long SDL_WINDOW_OPENGL = 0x2L;
    private static final long SDL_WINDOW_METAL = 0x20000000L;
    private static final long SDL_WINDOW_HIGH_PIXEL_DENSITY = 0x2000L;
    private static final int SIZE_CHECK_EVERY = 15;

    // what minecraft asked for through SDL_GL_SetAttribute, -1 is not set
    private static final int[] attrs = new int[32];

    static {
        resetAttrs();
    }

    private static final Object lock = new Object();
    private static final Map<Long, Win> windows = new HashMap<>();
    private static final Map<Long, Ctx> contexts = new HashMap<>();
    // {window, context} that are current on the calling thread
    private static final ThreadLocal<long[]> current = new ThreadLocal<long[]>() {
        @Override
        protected long[] initialValue() {
            return new long[2];
        }
    };

    private static boolean eglReady;
    private static boolean eglFailed;
    private static long dpy;
    private static int swapInterval = 1;
    private static int swaps;

    private static long fnGetDisplay, fnInitialize, fnBindAPI, fnChooseConfig, fnCreateContext, fnDestroyContext;
    private static long fnCreatePlatformWindowSurface, fnDestroySurface, fnMakeCurrent, fnSwapBuffers, fnSwapInterval, fnGetError;

    private static final class Win {
        long window;
        long view;
        long layer;
        long surface;
        long surfaceConfig;
        int w;
        int h;
    }

    private static final class Ctx {
        long egl;
        long config;
        long window;
    }

    // ---------- switches ----------

    static boolean active() {
        if (!SDL3Config.GL_MOBILEGL || eglFailed) {
            return false;
        }
        try {
            String lib = System.getProperty("org.lwjgl.opengl.libname");
            if (lib == null) return false;
            String l = lib.toLowerCase();
            return l.contains("mobilegl") && !l.contains("mobileglues");
        } catch (Throwable t) {
            return false;
        }
    }

    // ---------- window creation ----------

    // OPENGL windows become METAL ones, the metal layer is what MobileGL draws into
    static long windowFlags(long flags) {
        if ((flags & SDL_WINDOW_OPENGL) != 0L && active()) {
            SDL3GL.once("window.flags", "window asked for SDL_WINDOW_OPENGL, creating it as SDL_WINDOW_METAL for MobileGL");
            return (flags & ~SDL_WINDOW_OPENGL) | SDL_WINDOW_METAL | SDL_WINDOW_HIGH_PIXEL_DENSITY;
        }
        return flags;
    }

    static void windowProps(int props) {
        if (props == 0 || !active()) {
            return;
        }
        try {
            long flags = SDLProperties.SDL_GetNumberProperty(props, SDLVideo.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, 0L);
            boolean gl = SDLProperties.SDL_GetBooleanProperty(props, SDLVideo.SDL_PROP_WINDOW_CREATE_OPENGL_BOOLEAN, false)
                || (flags & SDL_WINDOW_OPENGL) != 0L;
            if (!gl) {
                return;
            }
            SDL3GL.once("window.props", "window properties asked for opengl, creating it as metal for MobileGL");
            SDLProperties.SDL_SetBooleanProperty(props, SDLVideo.SDL_PROP_WINDOW_CREATE_OPENGL_BOOLEAN, false);
            SDLProperties.SDL_SetBooleanProperty(props, SDLVideo.SDL_PROP_WINDOW_CREATE_METAL_BOOLEAN, true);
            SDLProperties.SDL_SetBooleanProperty(props, SDLVideo.SDL_PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN, true);
            if (flags != 0L) {
                SDLProperties.SDL_SetNumberProperty(props, SDLVideo.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, flags & ~SDL_WINDOW_OPENGL);
            }
        } catch (Throwable t) {
            SDL3Bridge.warn("could not switch window properties to metal: " + t);
        }
    }

    // ---------- attributes ----------

    private static void resetAttrs() {
        for (int i = 0; i < attrs.length; i++) {
            attrs[i] = -1;
        }
    }

    static void setAttribute(int attr, int value) {
        if (attr >= 0 && attr < attrs.length) {
            attrs[attr] = value;
        }
    }

    static void resetAttributes() {
        resetAttrs();
    }

    private static int attr(int attr, int fallback) {
        int v = attrs[attr];
        return v < 0 ? fallback : v;
    }

    // ---------- EGL ----------

    private static boolean ensureEgl() {
        if (eglReady) {
            return true;
        }
        if (eglFailed) {
            return false;
        }
        FunctionProvider p = SDL3GL.provider();
        if (p == null) {
            return fail("the LWJGL gl library isn't loaded, can't find MobileGL's EGL");
        }
        fnGetDisplay = p.getFunctionAddress("eglGetDisplay");
        fnInitialize = p.getFunctionAddress("eglInitialize");
        fnBindAPI = p.getFunctionAddress("eglBindAPI");
        fnChooseConfig = p.getFunctionAddress("eglChooseConfig");
        fnCreateContext = p.getFunctionAddress("eglCreateContext");
        fnDestroyContext = p.getFunctionAddress("eglDestroyContext");
        fnCreatePlatformWindowSurface = p.getFunctionAddress("eglCreatePlatformWindowSurface");
        fnDestroySurface = p.getFunctionAddress("eglDestroySurface");
        fnMakeCurrent = p.getFunctionAddress("eglMakeCurrent");
        fnSwapBuffers = p.getFunctionAddress("eglSwapBuffers");
        fnSwapInterval = p.getFunctionAddress("eglSwapInterval");
        fnGetError = p.getFunctionAddress("eglGetError");
        if (fnGetDisplay == 0L || fnInitialize == 0L || fnBindAPI == 0L || fnChooseConfig == 0L || fnCreateContext == 0L
            || fnDestroyContext == 0L || fnCreatePlatformWindowSurface == 0L || fnDestroySurface == 0L
            || fnMakeCurrent == 0L || fnSwapBuffers == 0L || fnSwapInterval == 0L || fnGetError == 0L) {
            return fail("libMobileGL doesn't export the EGL functions that are needed");
        }
        long display = JNI.invokePP(0L, fnGetDisplay);
        if (display == 0L) {
            return fail("eglGetDisplay returned no display");
        }
        if (JNI.invokePPPI(display, 0L, 0L, fnInitialize) == 0) {
            return fail("eglInitialize failed, egl error 0x" + Integer.toHexString(JNI.invokeI(fnGetError)));
        }
        dpy = display;
        eglReady = true;
        SDL3GL.once("egl.ready", "MobileGL EGL display is up");
        return true;
    }

    private static boolean fail(String why) {
        eglFailed = true;
        SDL3Bridge.warn("MobileGL EGL bridge off: " + why);
        return false;
    }

    private static String eglError() {
        try {
            return "egl error 0x" + Integer.toHexString(JNI.invokeI(fnGetError));
        } catch (Throwable t) {
            return "egl error unknown";
        }
    }

    private static long chooseConfig() {
        int alpha = attr(SDLVideo.SDL_GL_ALPHA_SIZE, 8);
        int depth = attr(SDLVideo.SDL_GL_DEPTH_SIZE, 24);
        int stencil = attr(SDLVideo.SDL_GL_STENCIL_SIZE, 8);
        // wanted first, then looser if MobileGL has no such config
        int[][] tries = {{alpha, depth, stencil}, {alpha, 0, 0}, {0, 0, 0}};
        for (int[] t : tries) {
            long config = chooseConfig(t[0], t[1], t[2]);
            if (config != 0L) {
                return config;
            }
        }
        return 0L;
    }

    private static long chooseConfig(int alpha, int depth, int stencil) {
        try (MemoryStack stack = MemoryStack.stackPush()) {
            IntBuffer list = stack.mallocInt(17);
            list.put(EGL_RED_SIZE).put(8).put(EGL_GREEN_SIZE).put(8).put(EGL_BLUE_SIZE).put(8)
                .put(EGL_ALPHA_SIZE).put(Math.max(alpha, 0))
                .put(EGL_DEPTH_SIZE).put(Math.max(depth, 0))
                .put(EGL_STENCIL_SIZE).put(Math.max(stencil, 0))
                .put(EGL_SURFACE_TYPE).put(EGL_WINDOW_BIT | EGL_PBUFFER_BIT)
                .put(EGL_RENDERABLE_TYPE).put(EGL_OPENGL_BIT)
                .put(EGL_NONE).flip();
            java.nio.ByteBuffer configs = stack.malloc(8);
            IntBuffer count = stack.mallocInt(1);
            JNI.invokeI(EGL_OPENGL_API, fnBindAPI);
            int ok = JNI.invokePPPPI(dpy, MemoryUtil.memAddress(list), MemoryUtil.memAddress(configs), 1,
                MemoryUtil.memAddress(count), fnChooseConfig);
            if (ok == 0 || count.get(0) < 1) {
                return 0L;
            }
            return MemoryUtil.memGetAddress(MemoryUtil.memAddress(configs));
        }
    }

    // ---------- windows and surfaces ----------

    private static Win window(long window) {
        Win w = windows.get(window);
        if (w != null) {
            return w;
        }
        long view = SDLMetal.SDL_Metal_CreateView(window);
        if (view == 0L) {
            SDL3Bridge.warn("SDL_Metal_CreateView failed for the gl window: " + SDL3Bridge.lastError());
            return null;
        }
        long layer = SDLMetal.SDL_Metal_GetLayer(view);
        if (layer == 0L) {
            SDL3Bridge.warn("SDL_Metal_GetLayer returned no layer");
            SDLMetal.SDL_Metal_DestroyView(view);
            return null;
        }
        w = new Win();
        w.window = window;
        w.view = view;
        w.layer = layer;
        windows.put(window, w);
        SDL3GL.once("window.layer", "gl window 0x" + Long.toHexString(window) + " has metal layer 0x" + Long.toHexString(layer));
        return w;
    }

    private static void windowSize(Win w) {
        try (MemoryStack stack = MemoryStack.stackPush()) {
            IntBuffer size = stack.mallocInt(2);
            if (SDLVideo.rawWindowSizeInPixels(w.window, MemoryUtil.memAddress(size), MemoryUtil.memAddress(size) + 4L)) {
                w.w = Math.max(1, SDL3Bridge.scalePixels(size.get(0)));
                w.h = Math.max(1, SDL3Bridge.scalePixels(size.get(1)));
                return;
            }
        }
        if (w.w <= 0) {
            w.w = 1;
            w.h = 1;
        }
    }

    private static long createSurface(Win w, long config) {
        try (MemoryStack stack = MemoryStack.stackPush()) {
            java.nio.LongBuffer list = stack.mallocLong(5);
            list.put(EGL_WIDTH).put(w.w).put(EGL_HEIGHT).put(w.h).put(EGL_NONE).flip();
            return JNI.invokePPPPP(dpy, config, w.layer, MemoryUtil.memAddress(list), fnCreatePlatformWindowSurface);
        }
    }

    private static boolean ensureSurface(Win w, long config) {
        if (w.surface != 0L) {
            return true;
        }
        windowSize(w);
        long surface = createSurface(w, config);
        if (surface == 0L) {
            SDL3Bridge.warn("eglCreatePlatformWindowSurface failed for " + w.w + "x" + w.h + ": " + eglError());
            return false;
        }
        w.surface = surface;
        w.surfaceConfig = config;
        SDL3GL.once("surface", "gl surface created " + w.w + "x" + w.h);
        syncLayer(w);
        return true;
    }

    private static void destroyWindow(Win w) {
        if (w.surface != 0L) {
            JNI.invokePPI(dpy, w.surface, fnDestroySurface);
            w.surface = 0L;
        }
        if (w.view != 0L) {
            SDLMetal.SDL_Metal_DestroyView(w.view);
            w.view = 0L;
        }
        windows.remove(w.window);
    }

    private static boolean layerSizingBroken;

    private static native void nativeSetDrawableSize(long layer, int w, int h);

    private static void syncLayer(Win w) {
        if (layerSizingBroken) {
            return;
        }
        windowSize(w);
        try {
            nativeSetDrawableSize(w.layer, w.w, w.h);
        } catch (UnsatisfiedLinkError e) {
            layerSizingBroken = true;
            SDL3Bridge.warn("the resolution setting can't be applied to the gl layer, sdl3_gl_layer.m isn't in the build");
        } catch (Throwable t) {
            layerSizingBroken = true;
            SDL3Bridge.warn("layer sizing failed: " + t);
        }
    }

    // ---------- SDL_GL_* ----------

    static long createContext(long window) {
        synchronized (lock) {
            if (!ensureEgl()) {
                setError("MobileGL EGL is not available");
                return 0L;
            }
            Win w = window(window);
            if (w == null) {
                setError("could not make a metal layer for the gl window");
                return 0L;
            }
            long config = chooseConfig();
            if (config == 0L) {
                setError("MobileGL has no matching EGL config");
                SDL3Bridge.warn("eglChooseConfig found nothing, " + eglError());
                return 0L;
            }

            // MobileGL is opengl 4.6 whatever minecraft asks for (it asks 3.3), so the context is made as 4.6.
            // iris and sodium look at what they get, not what was requested
            int askedMajor = attr(SDLVideo.SDL_GL_CONTEXT_MAJOR_VERSION, 0);
            int askedMinor = attr(SDLVideo.SDL_GL_CONTEXT_MINOR_VERSION, 0);
            int major = Math.max(4, askedMajor);
            int minor = askedMajor > 4 || (askedMajor == 4 && askedMinor > 6) ? askedMinor : 6;
            int profile = attr(SDLVideo.SDL_GL_CONTEXT_PROFILE_MASK, 1);
            int flags = attr(SDLVideo.SDL_GL_CONTEXT_FLAGS, 0);
            long share = 0L;
            long[] cur = current.get();
            if (attr(SDLVideo.SDL_GL_SHARE_WITH_CURRENT_CONTEXT, 0) == 1 && cur[1] != 0L) {
                share = cur[1];
            }

            long egl;
            try (MemoryStack stack = MemoryStack.stackPush()) {
                IntBuffer list = stack.mallocInt(9);
                list.put(EGL_CONTEXT_MAJOR_VERSION).put(major).put(EGL_CONTEXT_MINOR_VERSION).put(minor);
                if (profile == 1 || profile == 2) {
                    list.put(EGL_CONTEXT_OPENGL_PROFILE_MASK).put(profile);
                }
                if (flags > 0) {
                    list.put(EGL_CONTEXT_FLAGS).put(flags);
                }
                list.put(EGL_NONE).flip();
                JNI.invokeI(EGL_OPENGL_API, fnBindAPI);
                egl = JNI.invokePPPPP(dpy, config, share, MemoryUtil.memAddress(list), fnCreateContext);
            }
            if (egl == 0L) {
                setError("eglCreateContext failed for OpenGL " + major + "." + minor);
                SDL3Bridge.warn("eglCreateContext " + major + "." + minor + " profile=" + profile + " failed, " + eglError());
                dropIfUnused(w);
                return 0L;
            }

            Ctx c = new Ctx();
            c.egl = egl;
            c.config = config;
            c.window = window;
            contexts.put(egl, c);

            if (!ensureSurface(w, config) || JNI.invokePPPPI(dpy, w.surface, w.surface, egl, fnMakeCurrent) == 0) {
                SDL3Bridge.warn("could not make the new gl context current, " + eglError());
                setError("could not make the MobileGL context current");
                contexts.remove(egl);
                JNI.invokePPI(dpy, egl, fnDestroyContext);
                dropIfUnused(w);
                return 0L;
            }
            cur[0] = window;
            cur[1] = egl;
            SDL3GL.once("egl.context", "MobileGL context created: OpenGL " + major + "." + minor + " (minecraft asked " + askedMajor + "." + askedMinor + ") profile=" + profile
                + " share=" + (share != 0L) + " egl=0x" + Long.toHexString(egl));
            return egl;
        }
    }

    static boolean makeCurrent(long window, long context) {
        synchronized (lock) {
            long[] cur = current.get();
            if (context == 0L) {
                if (!ensureEgl()) {
                    return false;
                }
                JNI.invokePPPPI(dpy, 0L, 0L, 0L, fnMakeCurrent);
                cur[0] = 0L;
                cur[1] = 0L;
                return true;
            }
            Ctx c = contexts.get(context);
            if (c == null) {
                setError("not a context created through MobileGL");
                return false;
            }
            long target = window != 0L ? window : c.window;
            Win w = window(target);
            if (w == null || !ensureSurface(w, c.config)) {
                setError("no gl surface for the window");
                return false;
            }
            if (cur[1] == context && cur[0] == target) {
                return true;
            }
            if (JNI.invokePPPPI(dpy, w.surface, w.surface, context, fnMakeCurrent) == 0) {
                setError("eglMakeCurrent failed");
                SDL3Bridge.warn("eglMakeCurrent failed, " + eglError());
                return false;
            }
            cur[0] = target;
            cur[1] = context;
            return true;
        }
    }

    static boolean swap(long window) {
        Win w;
        synchronized (lock) {
            w = windows.get(window);
            if (w == null || w.surface == 0L) {
                return false;
            }
            if (++swaps % SIZE_CHECK_EVERY == 0) {
                syncLayer(w);
            }
        }
        return JNI.invokePPI(dpy, w.surface, fnSwapBuffers) != 0;
    }

    static boolean setSwapInterval(int interval) {
        if (!eglReady) {
            return false;
        }
        int v = interval < 0 ? 1 : interval;
        boolean ok = JNI.invokePI(dpy, v, fnSwapInterval) != 0;
        if (ok) {
            swapInterval = interval;
        }
        return ok;
    }

    static boolean getSwapInterval(long out) {
        if (out == 0L) {
            return false;
        }
        MemoryUtil.memPutInt(out, swapInterval);
        return true;
    }

    static long currentWindow() {
        return current.get()[0];
    }

    static long currentContext() {
        return current.get()[1];
    }

    static boolean destroyContext(long context) {
        synchronized (lock) {
            Ctx c = contexts.remove(context);
            if (c == null) {
                return false;
            }
            long[] cur = current.get();
            if (cur[1] == context) {
                JNI.invokePPPPI(dpy, 0L, 0L, 0L, fnMakeCurrent);
                cur[0] = 0L;
                cur[1] = 0L;
            }
            boolean ok = JNI.invokePPI(dpy, context, fnDestroyContext) != 0;
            Win w = windows.get(c.window);
            if (w != null) {
                dropIfUnused(w);
            }
            return ok;
        }
    }

    private static void dropIfUnused(Win w) {
        for (Ctx c : contexts.values()) {
            if (c.window == w.window) {
                return;
            }
        }
        destroyWindow(w);
    }

    // the window is about to be destroyed for real, its surface and metal view go first
    static void windowGone(long window) {
        if (!eglReady) {
            return;
        }
        synchronized (lock) {
            Win w = windows.get(window);
            if (w == null) {
                return;
            }
            long[] cur = current.get();
            if (cur[0] == window) {
                JNI.invokePPPPI(dpy, 0L, 0L, 0L, fnMakeCurrent);
                cur[0] = 0L;
                cur[1] = 0L;
            }
            destroyWindow(w);
        }
    }

    // SDL_SetError with the message as the format string, no varargs. ios arm64 passes varargs on the stack so '%' is escaped instead
    private static void setError(String message) {
        try {
            long fn = org.lwjgl.system.APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetError");
            try (MemoryStack stack = MemoryStack.stackPush()) {
                ByteBuffer text = stack.UTF8(message.replace("%", "%%"));
                JNI.invokePI(MemoryUtil.memAddress(text), fn);
            }
        } catch (Throwable ignored) {
        }
    }
}
