package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;

public class SDLMessageBox {
   public static final int SDL_MESSAGEBOX_ERROR = 16;
   public static final int SDL_MESSAGEBOX_WARNING = 32;
   public static final int SDL_MESSAGEBOX_INFORMATION = 64;
   public static final int SDL_MESSAGEBOX_BUTTONS_LEFT_TO_RIGHT = 128;
   public static final int SDL_MESSAGEBOX_BUTTONS_RIGHT_TO_LEFT = 256;
   public static final int SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT = 1;
   public static final int SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT = 2;
   public static final int SDL_MESSAGEBOX_COLOR_BACKGROUND = 0;
   public static final int SDL_MESSAGEBOX_COLOR_TEXT = 1;
   public static final int SDL_MESSAGEBOX_COLOR_BUTTON_BORDER = 2;
   public static final int SDL_MESSAGEBOX_COLOR_BUTTON_BACKGROUND = 3;
   public static final int SDL_MESSAGEBOX_COLOR_BUTTON_SELECTED = 4;
   public static final int SDL_MESSAGEBOX_COLOR_COUNT = 5;

   protected SDLMessageBox() {
      throw new UnsupportedOperationException();
   }

   public static boolean nSDL_ShowMessageBox(long messageboxdata, long buttonid) {
      long __functionAddress = SDLMessageBox.Functions.ShowMessageBox;
      if (Checks.CHECKS) {
         SDL_MessageBoxData.validate(messageboxdata);
      }

      return (SDL3Bridge.invokeOnMain(__functionAddress, messageboxdata, buttonid, 0L, 0L) & 0xFFL) != 0L;
   }

   @NativeType("bool")
   public static boolean SDL_ShowMessageBox(@NativeType("SDL_MessageBoxData const *") SDL_MessageBoxData messageboxdata, @NativeType("int *") IntBuffer buttonid) {
      if (Checks.CHECKS) {
         Checks.checkSafe(buttonid, 1);
      }

      return nSDL_ShowMessageBox(messageboxdata.address(), MemoryUtil.memAddressSafe(buttonid));
   }

   public static boolean nSDL_ShowSimpleMessageBox(int flags, long title, long message, long window) {
      long __functionAddress = SDLMessageBox.Functions.ShowSimpleMessageBox;
      return (SDL3Bridge.invokeOnMain(__functionAddress, flags, title, message, window) & 0xFFL) != 0L;
   }

   @NativeType("bool")
   public static boolean SDL_ShowSimpleMessageBox(@NativeType("SDL_MessageBoxFlags") int flags, @NativeType("char const *") ByteBuffer title, @NativeType("char const *") ByteBuffer message, @NativeType("SDL_Window *") long window) {
      if (Checks.CHECKS) {
         Checks.checkNT1(title);
         Checks.checkNT1(message);
      }

      return nSDL_ShowSimpleMessageBox(flags, MemoryUtil.memAddress(title), MemoryUtil.memAddress(message), window);
   }

   @NativeType("bool")
   public static boolean SDL_ShowSimpleMessageBox(@NativeType("SDL_MessageBoxFlags") int flags, @NativeType("char const *") CharSequence title, @NativeType("char const *") CharSequence message, @NativeType("SDL_Window *") long window) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      boolean var11;
      try {
         stack.nUTF8(title, true);
         long titleEncoded = stack.getPointerAddress();
         stack.nUTF8(message, true);
         long messageEncoded = stack.getPointerAddress();
         var11 = nSDL_ShowSimpleMessageBox(flags, titleEncoded, messageEncoded, window);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var11;
   }

   public static final class Functions {
      public static final long ShowMessageBox = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_ShowMessageBox");
      public static final long ShowSimpleMessageBox = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_ShowSimpleMessageBox");

      private Functions() {
      }
   }
}
