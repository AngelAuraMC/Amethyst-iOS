package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.nio.ShortBuffer;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;

public class SDLKeyboard {
   public static final int SDL_TEXTINPUT_TYPE_TEXT = 0;
   public static final int SDL_TEXTINPUT_TYPE_TEXT_NAME = 1;
   public static final int SDL_TEXTINPUT_TYPE_TEXT_EMAIL = 2;
   public static final int SDL_TEXTINPUT_TYPE_TEXT_USERNAME = 3;
   public static final int SDL_TEXTINPUT_TYPE_TEXT_PASSWORD_HIDDEN = 4;
   public static final int SDL_TEXTINPUT_TYPE_TEXT_PASSWORD_VISIBLE = 5;
   public static final int SDL_TEXTINPUT_TYPE_NUMBER = 6;
   public static final int SDL_TEXTINPUT_TYPE_NUMBER_PASSWORD_HIDDEN = 7;
   public static final int SDL_TEXTINPUT_TYPE_NUMBER_PASSWORD_VISIBLE = 8;
   public static final int SDL_CAPITALIZE_NONE = 0;
   public static final int SDL_CAPITALIZE_SENTENCES = 1;
   public static final int SDL_CAPITALIZE_WORDS = 2;
   public static final int SDL_CAPITALIZE_LETTERS = 3;
   public static final String SDL_PROP_TEXTINPUT_TYPE_NUMBER = "SDL.textinput.type";
   public static final String SDL_PROP_TEXTINPUT_CAPITALIZATION_NUMBER = "SDL.textinput.capitalization";
   public static final String SDL_PROP_TEXTINPUT_AUTOCORRECT_BOOLEAN = "SDL.textinput.autocorrect";
   public static final String SDL_PROP_TEXTINPUT_MULTILINE_BOOLEAN = "SDL.textinput.multiline";
   public static final String SDL_PROP_TEXTINPUT_ANDROID_INPUTTYPE_NUMBER = "SDL.textinput.android.inputtype";

   protected SDLKeyboard() {
      throw new UnsupportedOperationException();
   }

   @NativeType("bool")
   public static boolean SDL_HasKeyboard() {
      long __functionAddress = SDLKeyboard.Functions.HasKeyboard;
      return JNI.invokeZ(__functionAddress);
   }

   public static long nSDL_GetKeyboards(long count) {
      long __functionAddress = SDLKeyboard.Functions.GetKeyboards;
      return JNI.invokePP(count, __functionAddress);
   }

   @NativeType("SDL_KeyboardID *")
   public static IntBuffer SDL_GetKeyboards() {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();
      IntBuffer count = stack.callocInt(1);

      IntBuffer var5;
      try {
         long __result = nSDL_GetKeyboards(MemoryUtil.memAddress(count));
         var5 = MemoryUtil.memIntBufferSafe(__result, count.get(0));
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   public static long nSDL_GetKeyboardNameForID(int instance_id) {
      long __functionAddress = SDLKeyboard.Functions.GetKeyboardNameForID;
      return JNI.invokeP(instance_id, __functionAddress);
   }

   @NativeType("char const *")
   public static String SDL_GetKeyboardNameForID(@NativeType("SDL_KeyboardID") int instance_id) {
      long __result = nSDL_GetKeyboardNameForID(instance_id);
      return MemoryUtil.memUTF8Safe(__result);
   }

   @NativeType("SDL_Window *")
   public static long SDL_GetKeyboardFocus() {
      long __functionAddress = SDLKeyboard.Functions.GetKeyboardFocus;
      return JNI.invokeP(__functionAddress);
   }

   public static long nSDL_GetKeyboardState(long numkeys) {
      long __functionAddress = SDLKeyboard.Functions.GetKeyboardState;
      return JNI.invokePP(numkeys, __functionAddress);
   }

   @NativeType("bool const *")
   public static ByteBuffer SDL_GetKeyboardState() {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();
      IntBuffer numkeys = stack.callocInt(1);

      ByteBuffer var5;
      try {
         long __result = nSDL_GetKeyboardState(MemoryUtil.memAddress(numkeys));
         var5 = MemoryUtil.memByteBufferSafe(__result, numkeys.get(0));
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   public static void SDL_ResetKeyboard() {
      long __functionAddress = SDLKeyboard.Functions.ResetKeyboard;
      JNI.invokeV(__functionAddress);
   }

   @NativeType("SDL_Keymod")
   public static short SDL_GetModState() {
      long __functionAddress = SDLKeyboard.Functions.GetModState;
      return JNI.invokeC(__functionAddress);
   }

   public static void SDL_SetModState(@NativeType("SDL_Keymod") short modstate) {
      long __functionAddress = SDLKeyboard.Functions.SetModState;
      JNI.invokeCV(modstate, __functionAddress);
   }

   @NativeType("SDL_Keycode")
   public static int SDL_GetKeyFromScancode(@NativeType("SDL_Scancode") int scancode, @NativeType("SDL_Keymod") short modstate, @NativeType("bool") boolean key_event) {
      long __functionAddress = SDLKeyboard.Functions.GetKeyFromScancode;
      return JNI.invokeCI(scancode, modstate, key_event, __functionAddress);
   }

   public static int nSDL_GetScancodeFromKey(int key, long modstate) {
      long __functionAddress = SDLKeyboard.Functions.GetScancodeFromKey;
      return JNI.invokePI(key, modstate, __functionAddress);
   }

   @NativeType("SDL_Scancode")
   public static int SDL_GetScancodeFromKey(@NativeType("SDL_Keycode") int key, @NativeType("SDL_Keymod *") ShortBuffer modstate) {
      if (Checks.CHECKS) {
         Checks.checkSafe(modstate, 1);
      }

      return nSDL_GetScancodeFromKey(key, MemoryUtil.memAddressSafe(modstate));
   }

   public static boolean nSDL_SetScancodeName(int scancode, long name) {
      long __functionAddress = SDLKeyboard.Functions.SetScancodeName;
      return JNI.invokePZ(scancode, name, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_SetScancodeName(@NativeType("SDL_Scancode") int scancode, @NativeType("char const *") ByteBuffer name) {
      if (Checks.CHECKS) {
         Checks.checkNT1(name);
      }

      return nSDL_SetScancodeName(scancode, MemoryUtil.memAddress(name));
   }

   public static long nSDL_GetScancodeName(int scancode) {
      long __functionAddress = SDLKeyboard.Functions.GetScancodeName;
      return JNI.invokeP(scancode, __functionAddress);
   }

   @NativeType("char const *")
   public static String SDL_GetScancodeName(@NativeType("SDL_Scancode") int scancode) {
      long __result = nSDL_GetScancodeName(scancode);
      return MemoryUtil.memUTF8Safe(__result);
   }

   public static int nSDL_GetScancodeFromName(long name) {
      long __functionAddress = SDLKeyboard.Functions.GetScancodeFromName;
      return JNI.invokePI(name, __functionAddress);
   }

   @NativeType("SDL_Scancode")
   public static int SDL_GetScancodeFromName(@NativeType("char const *") ByteBuffer name) {
      if (Checks.CHECKS) {
         Checks.checkNT1(name);
      }

      return nSDL_GetScancodeFromName(MemoryUtil.memAddress(name));
   }

   @NativeType("SDL_Scancode")
   public static int SDL_GetScancodeFromName(@NativeType("char const *") CharSequence name) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      int var5;
      try {
         stack.nUTF8(name, true);
         long nameEncoded = stack.getPointerAddress();
         var5 = nSDL_GetScancodeFromName(nameEncoded);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   public static long nSDL_GetKeyName(int key) {
      long __functionAddress = SDLKeyboard.Functions.GetKeyName;
      return JNI.invokeP(key, __functionAddress);
   }

   @NativeType("char const *")
   public static String SDL_GetKeyName(@NativeType("SDL_Keycode") int key) {
      long __result = nSDL_GetKeyName(key);
      return MemoryUtil.memUTF8Safe(__result);
   }

   public static int nSDL_GetKeyFromName(long name) {
      long __functionAddress = SDLKeyboard.Functions.GetKeyFromName;
      return JNI.invokePI(name, __functionAddress);
   }

   @NativeType("SDL_Keycode")
   public static int SDL_GetKeyFromName(@NativeType("char const *") ByteBuffer name) {
      if (Checks.CHECKS) {
         Checks.checkNT1(name);
      }

      return nSDL_GetKeyFromName(MemoryUtil.memAddress(name));
   }

   @NativeType("SDL_Keycode")
   public static int SDL_GetKeyFromName(@NativeType("char const *") CharSequence name) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      int var5;
      try {
         stack.nUTF8(name, true);
         long nameEncoded = stack.getPointerAddress();
         var5 = nSDL_GetKeyFromName(nameEncoded);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   @NativeType("bool")
   public static boolean SDL_StartTextInput(@NativeType("SDL_Window *") long window) {
      // no-op on purpose: real SDL_StartTextInput would put up SDL's own uikit keyboard (off the main thread too)
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return true;
   }

   @NativeType("bool")
   public static boolean SDL_StartTextInputWithProperties(@NativeType("SDL_Window *") long window, @NativeType("SDL_PropertiesID") int props) {
      long __functionAddress = SDLKeyboard.Functions.StartTextInputWithProperties;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return JNI.invokePZ(window, props, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_TextInputActive(@NativeType("SDL_Window *") long window) {
      long __functionAddress = SDLKeyboard.Functions.TextInputActive;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return JNI.invokePZ(window, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_StopTextInput(@NativeType("SDL_Window *") long window) {
      // no-op, see SDL_StartTextInput
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return true;
   }

   @NativeType("bool")
   public static boolean SDL_ClearComposition(@NativeType("SDL_Window *") long window) {
      long __functionAddress = SDLKeyboard.Functions.ClearComposition;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return JNI.invokePZ(window, __functionAddress);
   }

   public static boolean nSDL_SetTextInputArea(long window, long rect, int cursor) {
      long __functionAddress = SDLKeyboard.Functions.SetTextInputArea;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return JNI.invokePPZ(window, rect, cursor, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_SetTextInputArea(@NativeType("SDL_Window *") long window, @NativeType("SDL_Rect const *") SDL_Rect.Buffer rect, int cursor) {
      if (Checks.CHECKS) {
         Checks.checkSafe(rect, 1);
      }

      return nSDL_SetTextInputArea(window, MemoryUtil.memAddressSafe(rect), cursor);
   }

   public static boolean nSDL_GetTextInputArea(long window, long rect, long cursor) {
      long __functionAddress = SDLKeyboard.Functions.GetTextInputArea;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return JNI.invokePPPZ(window, rect, cursor, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_GetTextInputArea(@NativeType("SDL_Window *") long window, @NativeType("SDL_Rect *") SDL_Rect.Buffer rect, @NativeType("int *") IntBuffer cursor) {
      if (Checks.CHECKS) {
         Checks.checkSafe(rect, 1);
         Checks.checkSafe(cursor, 1);
      }

      return nSDL_GetTextInputArea(window, MemoryUtil.memAddressSafe(rect), MemoryUtil.memAddressSafe(cursor));
   }

   @NativeType("bool")
   public static boolean SDL_HasScreenKeyboardSupport() {
      long __functionAddress = SDLKeyboard.Functions.HasScreenKeyboardSupport;
      return JNI.invokeZ(__functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_ScreenKeyboardShown(@NativeType("SDL_Window *") long window) {
      long __functionAddress = SDLKeyboard.Functions.ScreenKeyboardShown;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      return JNI.invokePZ(window, __functionAddress);
   }

   public static final class Functions {
      public static final long HasKeyboard = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_HasKeyboard");
      public static final long GetKeyboards = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetKeyboards");
      public static final long GetKeyboardNameForID = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetKeyboardNameForID");
      public static final long GetKeyboardFocus = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetKeyboardFocus");
      public static final long GetKeyboardState = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetKeyboardState");
      public static final long ResetKeyboard = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_ResetKeyboard");
      public static final long GetModState = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetModState");
      public static final long SetModState = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetModState");
      public static final long GetKeyFromScancode = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetKeyFromScancode");
      public static final long GetScancodeFromKey = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetScancodeFromKey");
      public static final long SetScancodeName = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetScancodeName");
      public static final long GetScancodeName = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetScancodeName");
      public static final long GetScancodeFromName = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetScancodeFromName");
      public static final long GetKeyName = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetKeyName");
      public static final long GetKeyFromName = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetKeyFromName");
      public static final long StartTextInput = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_StartTextInput");
      public static final long StartTextInputWithProperties = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_StartTextInputWithProperties");
      public static final long TextInputActive = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_TextInputActive");
      public static final long StopTextInput = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_StopTextInput");
      public static final long ClearComposition = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_ClearComposition");
      public static final long SetTextInputArea = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetTextInputArea");
      public static final long GetTextInputArea = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetTextInputArea");
      public static final long HasScreenKeyboardSupport = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_HasScreenKeyboardSupport");
      public static final long ScreenKeyboardShown = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_ScreenKeyboardShown");

      private Functions() {
      }
   }
}
