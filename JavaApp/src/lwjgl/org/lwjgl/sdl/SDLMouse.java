package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;

public class SDLMouse {
   public static final int SDL_SYSTEM_CURSOR_DEFAULT = 0;
   public static final int SDL_SYSTEM_CURSOR_TEXT = 1;
   public static final int SDL_SYSTEM_CURSOR_WAIT = 2;
   public static final int SDL_SYSTEM_CURSOR_CROSSHAIR = 3;
   public static final int SDL_SYSTEM_CURSOR_PROGRESS = 4;
   public static final int SDL_SYSTEM_CURSOR_NWSE_RESIZE = 5;
   public static final int SDL_SYSTEM_CURSOR_NESW_RESIZE = 6;
   public static final int SDL_SYSTEM_CURSOR_EW_RESIZE = 7;
   public static final int SDL_SYSTEM_CURSOR_NS_RESIZE = 8;
   public static final int SDL_SYSTEM_CURSOR_MOVE = 9;
   public static final int SDL_SYSTEM_CURSOR_NOT_ALLOWED = 10;
   public static final int SDL_SYSTEM_CURSOR_POINTER = 11;
   public static final int SDL_SYSTEM_CURSOR_NW_RESIZE = 12;
   public static final int SDL_SYSTEM_CURSOR_N_RESIZE = 13;
   public static final int SDL_SYSTEM_CURSOR_NE_RESIZE = 14;
   public static final int SDL_SYSTEM_CURSOR_E_RESIZE = 15;
   public static final int SDL_SYSTEM_CURSOR_SE_RESIZE = 16;
   public static final int SDL_SYSTEM_CURSOR_S_RESIZE = 17;
   public static final int SDL_SYSTEM_CURSOR_SW_RESIZE = 18;
   public static final int SDL_SYSTEM_CURSOR_W_RESIZE = 19;
   public static final int SDL_SYSTEM_CURSOR_COUNT = 20;
   public static final int SDL_MOUSEWHEEL_NORMAL = 0;
   public static final int SDL_MOUSEWHEEL_FLIPPED = 1;
   public static final int SDL_BUTTON_LEFT = 1;
   public static final int SDL_BUTTON_MIDDLE = 2;
   public static final int SDL_BUTTON_RIGHT = 3;
   public static final int SDL_BUTTON_X1 = 4;
   public static final int SDL_BUTTON_X2 = 5;
   public static final int SDL_BUTTON_LMASK = SDL_BUTTON_MASK(1);
   public static final int SDL_BUTTON_MMASK = SDL_BUTTON_MASK(2);
   public static final int SDL_BUTTON_RMASK = SDL_BUTTON_MASK(3);
   public static final int SDL_BUTTON_X1MASK = SDL_BUTTON_MASK(4);
   public static final int SDL_BUTTON_X2MASK = SDL_BUTTON_MASK(5);

   protected SDLMouse() {
      throw new UnsupportedOperationException();
   }

   @NativeType("bool")
   public static boolean SDL_HasMouse() {
      long __functionAddress = SDLMouse.Functions.HasMouse;
      return JNI.invokeZ(__functionAddress);
   }

   public static long nSDL_GetMice(long count) {
      long __functionAddress = SDLMouse.Functions.GetMice;
      return JNI.invokePP(count, __functionAddress);
   }

   @NativeType("SDL_MouseID *")
   public static IntBuffer SDL_GetMice() {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();
      IntBuffer count = stack.callocInt(1);

      IntBuffer var5;
      try {
         long __result = nSDL_GetMice(MemoryUtil.memAddress(count));
         var5 = MemoryUtil.memIntBufferSafe(__result, count.get(0));
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   public static long nSDL_GetMouseNameForID(int instance_id) {
      long __functionAddress = SDLMouse.Functions.GetMouseNameForID;
      return JNI.invokeP(instance_id, __functionAddress);
   }

   @NativeType("char const *")
   public static String SDL_GetMouseNameForID(@NativeType("SDL_MouseID") int instance_id) {
      long __result = nSDL_GetMouseNameForID(instance_id);
      return MemoryUtil.memUTF8Safe(__result);
   }

   @NativeType("SDL_Window *")
   public static long SDL_GetMouseFocus() {
      long __functionAddress = SDLMouse.Functions.GetMouseFocus;
      return JNI.invokeP(__functionAddress);
   }

   public static int nSDL_GetMouseState(long x, long y) {
      long __functionAddress = SDLMouse.Functions.GetMouseState;
      return JNI.invokePPI(x, y, __functionAddress);
   }

   @NativeType("SDL_MouseButtonFlags")
   public static int SDL_GetMouseState(@NativeType("float *") FloatBuffer x, @NativeType("float *") FloatBuffer y) {
      if (Checks.CHECKS) {
         Checks.checkSafe(x, 1);
         Checks.checkSafe(y, 1);
      }

      return nSDL_GetMouseState(MemoryUtil.memAddressSafe(x), MemoryUtil.memAddressSafe(y));
   }

   public static int nSDL_GetGlobalMouseState(long x, long y) {
      long __functionAddress = SDLMouse.Functions.GetGlobalMouseState;
      return JNI.invokePPI(x, y, __functionAddress);
   }

   @NativeType("SDL_MouseButtonFlags")
   public static int SDL_GetGlobalMouseState(@NativeType("float *") FloatBuffer x, @NativeType("float *") FloatBuffer y) {
      if (Checks.CHECKS) {
         Checks.checkSafe(x, 1);
         Checks.checkSafe(y, 1);
      }

      return nSDL_GetGlobalMouseState(MemoryUtil.memAddressSafe(x), MemoryUtil.memAddressSafe(y));
   }

   public static int nSDL_GetRelativeMouseState(long x, long y) {
      long __functionAddress = SDLMouse.Functions.GetRelativeMouseState;
      return JNI.invokePPI(x, y, __functionAddress);
   }

   @NativeType("SDL_MouseButtonFlags")
   public static int SDL_GetRelativeMouseState(@NativeType("float *") FloatBuffer x, @NativeType("float *") FloatBuffer y) {
      if (Checks.CHECKS) {
         Checks.checkSafe(x, 1);
         Checks.checkSafe(y, 1);
      }

      return nSDL_GetRelativeMouseState(MemoryUtil.memAddressSafe(x), MemoryUtil.memAddressSafe(y));
   }

   public static void SDL_WarpMouseInWindow(@NativeType("SDL_Window *") long window, float x, float y) {
      long __functionAddress = SDLMouse.Functions.WarpMouseInWindow;
      JNI.invokePV(window, x, y, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_WarpMouseGlobal(float x, float y) {
      long __functionAddress = SDLMouse.Functions.WarpMouseGlobal;
      return JNI.invokeZ(x, y, __functionAddress);
   }

   public static boolean nSDL_SetRelativeMouseTransform(long callback, long userdata) {
      long __functionAddress = SDLMouse.Functions.SetRelativeMouseTransform;
      return JNI.invokePPZ(callback, userdata, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_SetRelativeMouseTransform(@NativeType("SDL_MouseMotionTransformCallback") SDL_MouseMotionTransformCallbackI callback, @NativeType("void *") long userdata) {
      return nSDL_SetRelativeMouseTransform(callback.address(), userdata);
   }

   @NativeType("bool")
   public static boolean SDL_SetWindowRelativeMouseMode(@NativeType("SDL_Window *") long window, @NativeType("bool") boolean enabled) {
      long __functionAddress = SDLMouse.Functions.SetWindowRelativeMouseMode;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      boolean result = (SDL3Bridge.invokeOnMain(__functionAddress, window, enabled ? 1L : 0L, 0L, 0L) & 0xFFL) != 0L;
      SDL3Bridge.setGrabbing(enabled);
      return result;
   }

   @NativeType("bool")
   public static boolean SDL_GetWindowRelativeMouseMode(@NativeType("SDL_Window *") long window) {
      long __functionAddress = SDLMouse.Functions.GetWindowRelativeMouseMode;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return JNI.invokePZ(window, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_CaptureMouse(@NativeType("bool") boolean enabled) {
      long __functionAddress = SDLMouse.Functions.CaptureMouse;
      return JNI.invokeZ(enabled, __functionAddress);
   }

   public static long nSDL_CreateCursor(long data, long mask, int w, int h, int hot_x, int hot_y) {
      long __functionAddress = SDLMouse.Functions.CreateCursor;
      return JNI.invokePPP(data, mask, w, h, hot_x, hot_y, __functionAddress);
   }

   @NativeType("SDL_Cursor *")
   public static long SDL_CreateCursor(@NativeType("Uint8 const *") ByteBuffer data, @NativeType("Uint8 const *") ByteBuffer mask, int w, int h, int hot_x, int hot_y) {
      if (Checks.CHECKS) {
         Checks.check(data, w * h >> 3);
         Checks.check(mask, w * h >> 3);
      }

      return nSDL_CreateCursor(MemoryUtil.memAddress(data), MemoryUtil.memAddress(mask), w, h, hot_x, hot_y);
   }

   public static long nSDL_CreateColorCursor(long surface, int hot_x, int hot_y) {
      long __functionAddress = SDLMouse.Functions.CreateColorCursor;
      return JNI.invokePP(surface, hot_x, hot_y, __functionAddress);
   }

   @NativeType("SDL_Cursor *")
   public static long SDL_CreateColorCursor(@NativeType("SDL_Surface *") SDL_Surface surface, int hot_x, int hot_y) {
      return nSDL_CreateColorCursor(surface.address(), hot_x, hot_y);
   }

   public static long nSDL_CreateAnimatedCursor(long frames, int frame_count, int hot_x, int hot_y) {
      long __functionAddress = SDLMouse.Functions.CreateAnimatedCursor;
      return JNI.invokePP(frames, frame_count, hot_x, hot_y, __functionAddress);
   }

   @NativeType("SDL_Cursor *")
   public static long SDL_CreateAnimatedCursor(@NativeType("SDL_CursorFrameInfo *") SDL_CursorFrameInfo.Buffer frames, int hot_x, int hot_y) {
      return nSDL_CreateAnimatedCursor(frames.address(), frames.remaining(), hot_x, hot_y);
   }

   @NativeType("SDL_Cursor *")
   public static long SDL_CreateSystemCursor(@NativeType("SDL_SystemCursor") int id) {
      long __functionAddress = SDLMouse.Functions.CreateSystemCursor;
      return JNI.invokeP(id, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_SetCursor(@NativeType("SDL_Cursor *") long cursor) {
      long __functionAddress = SDLMouse.Functions.SetCursor;
      if (Checks.CHECKS) {
         Checks.check(cursor);
      }

      return JNI.invokePZ(cursor, __functionAddress);
   }

   @NativeType("SDL_Cursor *")
   public static long SDL_GetCursor() {
      long __functionAddress = SDLMouse.Functions.GetCursor;
      return JNI.invokeP(__functionAddress);
   }

   @NativeType("SDL_Cursor *")
   public static long SDL_GetDefaultCursor() {
      long __functionAddress = SDLMouse.Functions.GetDefaultCursor;
      return JNI.invokeP(__functionAddress);
   }

   public static void SDL_DestroyCursor(@NativeType("SDL_Cursor *") long cursor) {
      long __functionAddress = SDLMouse.Functions.DestroyCursor;
      if (Checks.CHECKS) {
         Checks.check(cursor);
      }

      JNI.invokePV(cursor, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_ShowCursor() {
      long __functionAddress = SDLMouse.Functions.ShowCursor;
      return (SDL3Bridge.invokeOnMain(__functionAddress, 0L, 0L, 0L, 0L) & 0xFFL) != 0L;
   }

   @NativeType("bool")
   public static boolean SDL_HideCursor() {
      long __functionAddress = SDLMouse.Functions.HideCursor;
      return (SDL3Bridge.invokeOnMain(__functionAddress, 0L, 0L, 0L, 0L) & 0xFFL) != 0L;
   }

   @NativeType("bool")
   public static boolean SDL_CursorVisible() {
      long __functionAddress = SDLMouse.Functions.CursorVisible;
      return JNI.invokeZ(__functionAddress);
   }

   @NativeType("uint32_t")
   private static int SDL_BUTTON_MASK(@NativeType("uint32_t") int X) {
      return 1 << X - 1;
   }

   public static final class Functions {
      public static final long HasMouse = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_HasMouse");
      public static final long GetMice = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetMice");
      public static final long GetMouseNameForID = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetMouseNameForID");
      public static final long GetMouseFocus = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetMouseFocus");
      public static final long GetMouseState = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetMouseState");
      public static final long GetGlobalMouseState = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetGlobalMouseState");
      public static final long GetRelativeMouseState = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetRelativeMouseState");
      public static final long WarpMouseInWindow = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_WarpMouseInWindow");
      public static final long WarpMouseGlobal = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_WarpMouseGlobal");
      public static final long SetRelativeMouseTransform = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetRelativeMouseTransform");
      public static final long SetWindowRelativeMouseMode = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetWindowRelativeMouseMode");
      public static final long GetWindowRelativeMouseMode = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetWindowRelativeMouseMode");
      public static final long CaptureMouse = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_CaptureMouse");
      public static final long CreateCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_CreateCursor");
      public static final long CreateColorCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_CreateColorCursor");
      public static final long CreateAnimatedCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_CreateAnimatedCursor");
      public static final long CreateSystemCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_CreateSystemCursor");
      public static final long SetCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetCursor");
      public static final long GetCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetCursor");
      public static final long GetDefaultCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetDefaultCursor");
      public static final long DestroyCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_DestroyCursor");
      public static final long ShowCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_ShowCursor");
      public static final long HideCursor = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_HideCursor");
      public static final long CursorVisible = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_CursorVisible");

      private Functions() {
      }
   }
}
