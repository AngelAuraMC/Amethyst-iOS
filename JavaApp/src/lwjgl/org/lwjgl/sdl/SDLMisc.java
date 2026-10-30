package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;

public class SDLMisc {
   protected SDLMisc() {
      throw new UnsupportedOperationException();
   }

   public static boolean nSDL_OpenURL(long url) {
      long __functionAddress = SDLMisc.Functions.OpenURL;
      return (SDL3Bridge.invokeOnMain(__functionAddress, url, 0L, 0L, 0L) & 0xFFL) != 0L;
   }

   @NativeType("bool")
   public static boolean SDL_OpenURL(@NativeType("char const *") ByteBuffer url) {
      if (Checks.CHECKS) {
         Checks.checkNT1(url);
      }

      return nSDL_OpenURL(MemoryUtil.memAddress(url));
   }

   @NativeType("bool")
   public static boolean SDL_OpenURL(@NativeType("char const *") CharSequence url) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      boolean var5;
      try {
         stack.nUTF8(url, true);
         long urlEncoded = stack.getPointerAddress();
         var5 = nSDL_OpenURL(urlEncoded);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   public static final class Functions {
      public static final long OpenURL = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_OpenURL");

      private Functions() {
      }
   }
}
