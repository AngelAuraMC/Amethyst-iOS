package org.lwjgl.sdl;

import org.lwjgl.system.MemoryStack;

final class SDL3Lifecycle {
    private SDL3Lifecycle() {
    }

    static native boolean nativeIsBackground();

    private static boolean enabled = SDL3Config.BACKGROUND_PAUSE;
    private static boolean wasBackground;

    static void awaitForeground() {
        if (!enabled) {
            return;
        }
        boolean background;
        try {
            background = nativeIsBackground();
        } catch (UnsatisfiedLinkError e) {
            // old sdl3_hook.m without the lifecycle hooks
            enabled = false;
            SDL3Bridge.warn("lifecycle hooks missing from the native side, background pause disabled");
            return;
        } catch (Throwable t) {
            enabled = false;
            return;
        }

        if (!background) {
            if (wasBackground) {
                wasBackground = false;
                SDL3Bridge.trace("[SDL3 TRACE] app back in the foreground");
                pushFocus(true);
            }
            return;
        }

        if (!wasBackground) {
            wasBackground = true;
            SDL3Bridge.trace("[SDL3 TRACE] app went to the background, holding the game thread");
            pushFocus(false);
        }
        try {
            while (nativeIsBackground()) {
                Thread.sleep(50L);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Throwable ignored) {
        }
    }

    private static void pushFocus(boolean gained) {
        long window = SDL3Bridge.currentWindow();
        if (window == 0L) {
            return;
        }
        try (MemoryStack stack = MemoryStack.stackPush()) {
            SDL_Event ev = SDL_Event.calloc(stack);
            ev.window().set(
                gained ? SDLEvents.SDL_EVENT_WINDOW_FOCUS_GAINED : SDLEvents.SDL_EVENT_WINDOW_FOCUS_LOST,
                0L, SDL3Bridge.currentWindowId(), 0, 0);
            SDLEvents.SDL_PushEvent(ev);
        } catch (Throwable t) {
            SDL3Bridge.warn("could not push the focus event: " + t);
        }
    }
}
