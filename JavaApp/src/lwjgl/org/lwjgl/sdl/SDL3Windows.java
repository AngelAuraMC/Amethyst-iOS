package org.lwjgl.sdl;

import java.util.HashMap;
import java.util.Map;

final class SDL3Windows {
    private SDL3Windows() {
    }

    private static final Map<Long, Integer> live = new HashMap<>();

    private static final long SDL_WINDOW_VULKAN = 0x10000000L;

    // the window that already exists (and counts one more user of it), or 0 if a new one has to be made.
    // a vulkan window is never handed out as a stand in, SDL wants the vulkan flag on it from the start
    static synchronized long reuse(long flags) {
        if ((flags & SDL_WINDOW_VULKAN) != 0L) {
            return 0L;
        }
        for (Map.Entry<Long, Integer> e : live.entrySet()) {
            e.setValue(e.getValue() + 1);
            return e.getKey();
        }
        return 0L;
    }

    static synchronized void created(long window) {
        live.put(window, 1);
    }

    // true when this was the last user and the window should really be destroyed
    static synchronized boolean release(long window) {
        Integer n = live.get(window);
        if (n == null) {
            return true;
        }
        if (n > 1) {
            live.put(window, n - 1);
            return false;
        }
        live.remove(window);
        return true;
    }
}
