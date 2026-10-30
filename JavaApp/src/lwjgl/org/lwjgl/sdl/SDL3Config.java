package org.lwjgl.sdl;

final class SDL3Config {
    private SDL3Config() {
    }

    // AMETHYST_SDL_TRACE=1 as a custom env var turns on the native trace lines, so it turns on the java ones too
    static final boolean TRACE = flag("amethyst.sdl.trace", envFlag("AMETHYST_SDL_TRACE"));
    static final boolean BACKGROUND_PAUSE = flag("amethyst.sdl.backgroundPause", true);
    static final boolean GL_KEEP_LOAD_PATH = flag("amethyst.sdl.glKeepLoadPath", false);
    static final boolean GL_SDL_PROC = flag("amethyst.sdl.glSdlProc", false);
    static final boolean GL_MOBILEGL = flag("amethyst.sdl.glMobileGL", true);
    static final boolean NATIVE_GAMEPAD = flag("amethyst.nativeGamepad", false);

    private static boolean envFlag(String name) {
        try {
            String v = System.getenv(name);
            return v != null && !v.isEmpty() && !v.equals("0");
        } catch (Throwable t) {
            return false;
        }
    }

    private static boolean flag(String name, boolean fallback) {
        try {
            String value = System.getProperty(name);
            if (value == null) {
                return fallback;
            }
            value = value.trim();
            if (value.equalsIgnoreCase("true") || value.equals("1")) {
                return true;
            }
            if (value.equalsIgnoreCase("false") || value.equals("0")) {
                return false;
            }
        } catch (Throwable ignored) {
        }
        return fallback;
    }
}
