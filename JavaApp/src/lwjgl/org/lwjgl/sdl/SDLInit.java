package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;

public class SDLInit {
   public static final int SDL_INIT_AUDIO = 16;
   public static final int SDL_INIT_VIDEO = 32;
   public static final int SDL_INIT_JOYSTICK = 512;
   public static final int SDL_INIT_HAPTIC = 4096;
   public static final int SDL_INIT_GAMEPAD = 8192;
   public static final int SDL_INIT_EVENTS = 16384;
   public static final int SDL_INIT_SENSOR = 32768;
   public static final int SDL_INIT_CAMERA = 65536;
   public static final int SDL_APP_CONTINUE = 0;
   public static final int SDL_APP_SUCCESS = 1;
   public static final int SDL_APP_FAILURE = 2;
   public static final String SDL_PROP_APP_METADATA_NAME_STRING = "SDL.app.metadata.name";
   public static final String SDL_PROP_APP_METADATA_VERSION_STRING = "SDL.app.metadata.version";
   public static final String SDL_PROP_APP_METADATA_IDENTIFIER_STRING = "SDL.app.metadata.identifier";
   public static final String SDL_PROP_APP_METADATA_CREATOR_STRING = "SDL.app.metadata.creator";
   public static final String SDL_PROP_APP_METADATA_COPYRIGHT_STRING = "SDL.app.metadata.copyright";
   public static final String SDL_PROP_APP_METADATA_URL_STRING = "SDL.app.metadata.url";
   public static final String SDL_PROP_APP_METADATA_TYPE_STRING = "SDL.app.metadata.type";

   protected SDLInit() {
      throw new UnsupportedOperationException();
   }

   @NativeType("bool")
   public static boolean SDL_Init(@NativeType("SDL_InitFlags") int flags) {
      long __functionAddress = SDLInit.Functions.Init;
      SDL3Bridge.trace("[SDL3 TRACE] SDL_Init BEGIN flags=" + flags);
      boolean result = SDL3Bridge.nativeInit(__functionAddress, flags);
      SDL3Bridge.trace("[SDL3 TRACE] SDL_Init END result=" + result);
      if (!result) {
         SDL3Bridge.warn("SDL_Init(" + flags + ") failed: " + SDL3Bridge.mainThreadError());
      }
      return result;
   }

   @NativeType("bool")
   public static boolean SDL_InitSubSystem(@NativeType("SDL_InitFlags") int flags) {
      long __functionAddress = SDLInit.Functions.InitSubSystem;
      SDL3Bridge.trace("[SDL3 TRACE] SDL_InitSubSystem BEGIN flags=" + flags);
      boolean result = SDL3Bridge.nativeInitSubSystem(__functionAddress, flags);
      SDL3Bridge.trace("[SDL3 TRACE] SDL_InitSubSystem END result=" + result);
      if (!result) {
         SDL3Bridge.warn("SDL_InitSubSystem(" + flags + ") failed: " + SDL3Bridge.mainThreadError());
      }
      return result;
   }

   public static void SDL_QuitSubSystem(@NativeType("SDL_InitFlags") int flags) {
      long __functionAddress = SDLInit.Functions.QuitSubSystem;
      SDL3Bridge.trace("[SDL3 TRACE] SDL_QuitSubSystem(" + flags + ") BEGIN");
      SDL3Bridge.invokeOnMain(__functionAddress, flags, 0L, 0L, 0L);
      SDL3Bridge.trace("[SDL3 TRACE] SDL_QuitSubSystem END");
   }

   @NativeType("SDL_InitFlags")
   public static int SDL_WasInit(@NativeType("SDL_InitFlags") int flags) {
      long __functionAddress = SDLInit.Functions.WasInit;
      return JNI.invokeI(flags, __functionAddress);
   }

   public static void SDL_Quit() {
      long __functionAddress = SDLInit.Functions.Quit;
      SDL3Bridge.armExitWatchdog("SDL_Quit");
      SDL3Bridge.trace("[SDL3 TRACE] SDL_Quit BEGIN");
      SDL3Bridge.invokeOnMain(__functionAddress, 0L, 0L, 0L, 0L);
      SDL3Bridge.trace("[SDL3 TRACE] SDL_Quit END");
   }

   @NativeType("bool")
   public static boolean SDL_IsMainThread() {
      long __functionAddress = SDLInit.Functions.IsMainThread;
      return JNI.invokeZ(__functionAddress);
   }

   public static boolean nSDL_RunOnMainThread(long callback, long userdata, boolean wait_complete) {
      long __functionAddress = SDLInit.Functions.RunOnMainThread;
      return JNI.invokePPZ(callback, userdata, wait_complete, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_RunOnMainThread(@NativeType("SDL_MainThreadCallback") SDL_MainThreadCallbackI callback, @NativeType("void *") long userdata, @NativeType("bool") boolean wait_complete) {
      return nSDL_RunOnMainThread(callback.address(), userdata, wait_complete);
   }

   public static boolean nSDL_SetAppMetadata(long appname, long appversion, long appidentifier) {
      long __functionAddress = SDLInit.Functions.SetAppMetadata;
      return JNI.invokePPPZ(appname, appversion, appidentifier, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_SetAppMetadata(@NativeType("char const *") ByteBuffer appname, @NativeType("char const *") ByteBuffer appversion, @NativeType("char const *") ByteBuffer appidentifier) {
      if (Checks.CHECKS) {
         Checks.checkNT1Safe(appname);
         Checks.checkNT1Safe(appversion);
         Checks.checkNT1Safe(appidentifier);
      }

      return nSDL_SetAppMetadata(MemoryUtil.memAddressSafe(appname), MemoryUtil.memAddressSafe(appversion), MemoryUtil.memAddressSafe(appidentifier));
   }

   @NativeType("bool")
   public static boolean SDL_SetAppMetadata(@NativeType("char const *") CharSequence appname, @NativeType("char const *") CharSequence appversion, @NativeType("char const *") CharSequence appidentifier) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      boolean var11;
      try {
         stack.nUTF8Safe(appname, true);
         long appnameEncoded = appname == null ? 0L : stack.getPointerAddress();
         stack.nUTF8Safe(appversion, true);
         long appversionEncoded = appversion == null ? 0L : stack.getPointerAddress();
         stack.nUTF8Safe(appidentifier, true);
         long appidentifierEncoded = appidentifier == null ? 0L : stack.getPointerAddress();
         var11 = nSDL_SetAppMetadata(appnameEncoded, appversionEncoded, appidentifierEncoded);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var11;
   }

   public static boolean nSDL_SetAppMetadataProperty(long name, long value) {
      long __functionAddress = SDLInit.Functions.SetAppMetadataProperty;
      return JNI.invokePPZ(name, value, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_SetAppMetadataProperty(@NativeType("char const *") ByteBuffer name, @NativeType("char const *") ByteBuffer value) {
      if (Checks.CHECKS) {
         Checks.checkNT1(name);
         Checks.checkNT1(value);
      }

      return nSDL_SetAppMetadataProperty(MemoryUtil.memAddress(name), MemoryUtil.memAddress(value));
   }

   @NativeType("bool")
   public static boolean SDL_SetAppMetadataProperty(@NativeType("char const *") CharSequence name, @NativeType("char const *") CharSequence value) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      boolean var8;
      try {
         stack.nASCII(name, true);
         long nameEncoded = stack.getPointerAddress();
         stack.nUTF8(value, true);
         long valueEncoded = stack.getPointerAddress();
         var8 = nSDL_SetAppMetadataProperty(nameEncoded, valueEncoded);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var8;
   }

   public static long nSDL_GetAppMetadataProperty(long name) {
      long __functionAddress = SDLInit.Functions.GetAppMetadataProperty;
      return JNI.invokePP(name, __functionAddress);
   }

   @NativeType("char const *")
   public static String SDL_GetAppMetadataProperty(@NativeType("char const *") ByteBuffer name) {
      if (Checks.CHECKS) {
         Checks.checkNT1(name);
      }

      long __result = nSDL_GetAppMetadataProperty(MemoryUtil.memAddress(name));
      return MemoryUtil.memUTF8Safe(__result);
   }

   @NativeType("char const *")
   public static String SDL_GetAppMetadataProperty(@NativeType("char const *") CharSequence name) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      String var7;
      try {
         stack.nASCII(name, true);
         long nameEncoded = stack.getPointerAddress();
         long __result = nSDL_GetAppMetadataProperty(nameEncoded);
         var7 = MemoryUtil.memUTF8Safe(__result);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var7;
   }

   public static final class Functions {
      public static final long Init = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Init");
      public static final long InitSubSystem = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_InitSubSystem");
      public static final long QuitSubSystem = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_QuitSubSystem");
      public static final long WasInit = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_WasInit");
      public static final long Quit = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Quit");
      public static final long IsMainThread = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_IsMainThread");
      public static final long RunOnMainThread = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_RunOnMainThread");
      public static final long SetAppMetadata = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetAppMetadata");
      public static final long SetAppMetadataProperty = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetAppMetadataProperty");
      public static final long GetAppMetadataProperty = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetAppMetadataProperty");

      private Functions() {
      }
   }
}
