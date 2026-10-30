package org.lwjgl.sdl;

import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.NativeType;

public class SDLMetal {
   protected SDLMetal() {
      throw new UnsupportedOperationException();
   }

   @NativeType("SDL_MetalView")
   public static long SDL_Metal_CreateView(@NativeType("SDL_Window *") long window) {
      long __functionAddress = SDLMetal.Functions.Metal_CreateView;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      SDL3Bridge.trace("[SDL3 TRACE] SDL_Metal_CreateView BEGIN");
      long view = SDL3Bridge.invokeOnMain(__functionAddress, window, 0L, 0L, 0L);
      SDL3Bridge.trace("[SDL3 TRACE] SDL_Metal_CreateView END view=" + view);
      if (view != 0L) {
         SDL3Bridge.attachWindow(window);
      } else {
         SDL3Bridge.warn("SDL_Metal_CreateView failed: " + SDL3Bridge.mainThreadError());
      }
      return view;
   }

   public static void SDL_Metal_DestroyView(@NativeType("SDL_MetalView") long view) {
      long __functionAddress = SDLMetal.Functions.Metal_DestroyView;
      if (Checks.CHECKS) {
         Checks.check(view);
      }

      SDL3Bridge.invokeOnMain(__functionAddress, view, 0L, 0L, 0L);
   }

   @NativeType("void *")
   public static long SDL_Metal_GetLayer(@NativeType("SDL_MetalView") long view) {
      long __functionAddress = SDLMetal.Functions.Metal_GetLayer;
      if (Checks.CHECKS) {
         Checks.check(view);
      }

      return SDL3Bridge.invokeOnMain(__functionAddress, view, 0L, 0L, 0L);
   }

   public static final class Functions {
      public static final long Metal_CreateView = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Metal_CreateView");
      public static final long Metal_DestroyView = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Metal_DestroyView");
      public static final long Metal_GetLayer = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Metal_GetLayer");

      private Functions() {
      }
   }
}
