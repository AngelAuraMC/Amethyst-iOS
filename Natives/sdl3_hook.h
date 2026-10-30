#ifndef AMETHYST_SDL3_HOOK_H
#define AMETHYST_SDL3_HOOK_H

#include <stdbool.h>

void AmethystSDL3Prepare(void);
void AmethystSDL3Loaded(void);
void AmethystSDL3ApplyResolutionScale(void);

// input forwarding: once the SDL window exists, touch/keyboard/control events go to
// SDL3Bridge.onInput() (-> SDL_PushEvent) instead of the GLFW callbacks
enum {
    AM_SDL_INPUT_CURSOR = 0, // a=action(ACTION_*), f1/f2 = x/y (or dx/dy) in window points
    AM_SDL_INPUT_BUTTON = 1, // a=GLFW button, b=action, c=GLFW modifiers (kept in SDL mod state)
    AM_SDL_INPUT_KEY    = 2, // a=GLFW key, b=scancode, c=action, d=GLFW mods
    AM_SDL_INPUT_CHAR   = 3, // a=codepoint
    AM_SDL_INPUT_SCROLL = 4, // f1/f2 = x/y offset
    AM_SDL_INPUT_SCREEN = 5  // a/b = amethyst's render size in pixels (already resolution-scaled)
};
bool AmethystSDL3InputActive(void);
void AmethystSDL3ForwardInput(int kind, int a, int b, int c, int d, float f1, float f2);

#endif
