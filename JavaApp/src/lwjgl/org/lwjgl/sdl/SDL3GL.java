package org.lwjgl.sdl;

import org.lwjgl.system.FunctionProvider;
import org.lwjgl.system.MemoryUtil;

import java.lang.reflect.Method;
import java.util.concurrent.ConcurrentHashMap;

final class SDL3GL {
    private SDL3GL() {
    }

    private static volatile Method getProvider;
    private static volatile boolean broken;
    private static final ConcurrentHashMap<String, Boolean> seen = new ConcurrentHashMap<>();

    // the function provider of the gl library LWJGL loaded (libMobileGL), null if it isn't there
    static FunctionProvider provider() {
        if (broken) {
            return null;
        }
        try {
            Method m = getProvider;
            if (m == null) {
                m = Class.forName("org.lwjgl.opengl.GL", true, SDL3GL.class.getClassLoader()).getMethod("getFunctionProvider");
                getProvider = m;
            }
            Object provider = m.invoke(null);
            return provider instanceof FunctionProvider ? (FunctionProvider) provider : null;
        } catch (Throwable t) {
            broken = true;
            SDL3Bridge.warn("gl lookups through LWJGL are off: " + t);
            return null;
        }
    }

    // address of a gl function in the library LWJGL loaded for opengl, or 0 to let SDL answer
    static long lookup(long namePtr) {
        if (namePtr == 0L || broken || SDL3Config.GL_SDL_PROC) {
            return 0L;
        }
        try {
            FunctionProvider provider = provider();
            if (provider == null) {
                return 0L;
            }
            String name = MemoryUtil.memUTF8(namePtr);
            long address = provider.getFunctionAddress(name);
            if (address != 0L && "glGetError".equals(name)) {
                once("proc.glGetError", "SDL_GL_GetProcAddress(glGetError) answered from the LWJGL gl library");
            }
            return address;
        } catch (Throwable t) {
            broken = true;
            SDL3Bridge.warn("gl lookups through LWJGL are off: " + t);
            return 0L;
        }
    }

    // logs a line the first time a key is seen, so frame loops don't flood the log
    static void once(String key, String line) {
        if (seen.putIfAbsent(key, Boolean.TRUE) == null) {
            SDL3Bridge.warn(line);
        }
    }
}
