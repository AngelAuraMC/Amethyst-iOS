package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import org.lwjgl.PointerBuffer;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;

public class SDLEvents {
   public static final int SDL_EVENT_FIRST = 0;
   public static final int SDL_EVENT_QUIT = 256;
   public static final int SDL_EVENT_TERMINATING = 257;
   public static final int SDL_EVENT_LOW_MEMORY = 258;
   public static final int SDL_EVENT_WILL_ENTER_BACKGROUND = 259;
   public static final int SDL_EVENT_DID_ENTER_BACKGROUND = 260;
   public static final int SDL_EVENT_WILL_ENTER_FOREGROUND = 261;
   public static final int SDL_EVENT_DID_ENTER_FOREGROUND = 262;
   public static final int SDL_EVENT_LOCALE_CHANGED = 263;
   public static final int SDL_EVENT_SYSTEM_THEME_CHANGED = 264;
   public static final int SDL_EVENT_DISPLAY_ORIENTATION = 337;
   public static final int SDL_EVENT_DISPLAY_ADDED = 338;
   public static final int SDL_EVENT_DISPLAY_REMOVED = 339;
   public static final int SDL_EVENT_DISPLAY_MOVED = 340;
   public static final int SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED = 341;
   public static final int SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED = 342;
   public static final int SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED = 343;
   public static final int SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED = 344;
   public static final int SDL_EVENT_DISPLAY_FIRST = 337;
   public static final int SDL_EVENT_DISPLAY_LAST = 344;
   public static final int SDL_EVENT_WINDOW_SHOWN = 514;
   public static final int SDL_EVENT_WINDOW_HIDDEN = 515;
   public static final int SDL_EVENT_WINDOW_EXPOSED = 516;
   public static final int SDL_EVENT_WINDOW_MOVED = 517;
   public static final int SDL_EVENT_WINDOW_RESIZED = 518;
   public static final int SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED = 519;
   public static final int SDL_EVENT_WINDOW_METAL_VIEW_RESIZED = 520;
   public static final int SDL_EVENT_WINDOW_MINIMIZED = 521;
   public static final int SDL_EVENT_WINDOW_MAXIMIZED = 522;
   public static final int SDL_EVENT_WINDOW_RESTORED = 523;
   public static final int SDL_EVENT_WINDOW_MOUSE_ENTER = 524;
   public static final int SDL_EVENT_WINDOW_MOUSE_LEAVE = 525;
   public static final int SDL_EVENT_WINDOW_FOCUS_GAINED = 526;
   public static final int SDL_EVENT_WINDOW_FOCUS_LOST = 527;
   public static final int SDL_EVENT_WINDOW_CLOSE_REQUESTED = 528;
   public static final int SDL_EVENT_WINDOW_HIT_TEST = 529;
   public static final int SDL_EVENT_WINDOW_ICCPROF_CHANGED = 530;
   public static final int SDL_EVENT_WINDOW_DISPLAY_CHANGED = 531;
   public static final int SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED = 532;
   public static final int SDL_EVENT_WINDOW_SAFE_AREA_CHANGED = 533;
   public static final int SDL_EVENT_WINDOW_OCCLUDED = 534;
   public static final int SDL_EVENT_WINDOW_ENTER_FULLSCREEN = 535;
   public static final int SDL_EVENT_WINDOW_LEAVE_FULLSCREEN = 536;
   public static final int SDL_EVENT_WINDOW_DESTROYED = 537;
   public static final int SDL_EVENT_WINDOW_HDR_STATE_CHANGED = 538;
   public static final int SDL_EVENT_WINDOW_FIRST = 514;
   public static final int SDL_EVENT_WINDOW_LAST = 538;
   public static final int SDL_EVENT_KEY_DOWN = 768;
   public static final int SDL_EVENT_KEY_UP = 769;
   public static final int SDL_EVENT_TEXT_EDITING = 770;
   public static final int SDL_EVENT_TEXT_INPUT = 771;
   public static final int SDL_EVENT_KEYMAP_CHANGED = 772;
   public static final int SDL_EVENT_KEYBOARD_ADDED = 773;
   public static final int SDL_EVENT_KEYBOARD_REMOVED = 774;
   public static final int SDL_EVENT_TEXT_EDITING_CANDIDATES = 775;
   public static final int SDL_EVENT_SCREEN_KEYBOARD_SHOWN = 776;
   public static final int SDL_EVENT_SCREEN_KEYBOARD_HIDDEN = 777;
   public static final int SDL_EVENT_MOUSE_MOTION = 1024;
   public static final int SDL_EVENT_MOUSE_BUTTON_DOWN = 1025;
   public static final int SDL_EVENT_MOUSE_BUTTON_UP = 1026;
   public static final int SDL_EVENT_MOUSE_WHEEL = 1027;
   public static final int SDL_EVENT_MOUSE_ADDED = 1028;
   public static final int SDL_EVENT_MOUSE_REMOVED = 1029;
   public static final int SDL_EVENT_JOYSTICK_AXIS_MOTION = 1536;
   public static final int SDL_EVENT_JOYSTICK_BALL_MOTION = 1537;
   public static final int SDL_EVENT_JOYSTICK_HAT_MOTION = 1538;
   public static final int SDL_EVENT_JOYSTICK_BUTTON_DOWN = 1539;
   public static final int SDL_EVENT_JOYSTICK_BUTTON_UP = 1540;
   public static final int SDL_EVENT_JOYSTICK_ADDED = 1541;
   public static final int SDL_EVENT_JOYSTICK_REMOVED = 1542;
   public static final int SDL_EVENT_JOYSTICK_BATTERY_UPDATED = 1543;
   public static final int SDL_EVENT_JOYSTICK_UPDATE_COMPLETE = 1544;
   public static final int SDL_EVENT_GAMEPAD_AXIS_MOTION = 1616;
   public static final int SDL_EVENT_GAMEPAD_BUTTON_DOWN = 1617;
   public static final int SDL_EVENT_GAMEPAD_BUTTON_UP = 1618;
   public static final int SDL_EVENT_GAMEPAD_ADDED = 1619;
   public static final int SDL_EVENT_GAMEPAD_REMOVED = 1620;
   public static final int SDL_EVENT_GAMEPAD_REMAPPED = 1621;
   public static final int SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN = 1622;
   public static final int SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION = 1623;
   public static final int SDL_EVENT_GAMEPAD_TOUCHPAD_UP = 1624;
   public static final int SDL_EVENT_GAMEPAD_SENSOR_UPDATE = 1625;
   public static final int SDL_EVENT_GAMEPAD_UPDATE_COMPLETE = 1626;
   public static final int SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED = 1627;
   public static final int SDL_EVENT_FINGER_DOWN = 1792;
   public static final int SDL_EVENT_FINGER_UP = 1793;
   public static final int SDL_EVENT_FINGER_MOTION = 1794;
   public static final int SDL_EVENT_FINGER_CANCELED = 1795;
   public static final int SDL_EVENT_PINCH_BEGIN = 1808;
   public static final int SDL_EVENT_PINCH_UPDATE = 1809;
   public static final int SDL_EVENT_PINCH_END = 1810;
   public static final int SDL_EVENT_CLIPBOARD_UPDATE = 2304;
   public static final int SDL_EVENT_DROP_FILE = 4096;
   public static final int SDL_EVENT_DROP_TEXT = 4097;
   public static final int SDL_EVENT_DROP_BEGIN = 4098;
   public static final int SDL_EVENT_DROP_COMPLETE = 4099;
   public static final int SDL_EVENT_DROP_POSITION = 4100;
   public static final int SDL_EVENT_AUDIO_DEVICE_ADDED = 4352;
   public static final int SDL_EVENT_AUDIO_DEVICE_REMOVED = 4353;
   public static final int SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED = 4354;
   public static final int SDL_EVENT_SENSOR_UPDATE = 4608;
   public static final int SDL_EVENT_PEN_PROXIMITY_IN = 4864;
   public static final int SDL_EVENT_PEN_PROXIMITY_OUT = 4865;
   public static final int SDL_EVENT_PEN_DOWN = 4866;
   public static final int SDL_EVENT_PEN_UP = 4867;
   public static final int SDL_EVENT_PEN_BUTTON_DOWN = 4868;
   public static final int SDL_EVENT_PEN_BUTTON_UP = 4869;
   public static final int SDL_EVENT_PEN_MOTION = 4870;
   public static final int SDL_EVENT_PEN_AXIS = 4871;
   public static final int SDL_EVENT_CAMERA_DEVICE_ADDED = 5120;
   public static final int SDL_EVENT_CAMERA_DEVICE_REMOVED = 5121;
   public static final int SDL_EVENT_CAMERA_DEVICE_APPROVED = 5122;
   public static final int SDL_EVENT_CAMERA_DEVICE_DENIED = 5123;
   public static final int SDL_EVENT_RENDER_TARGETS_RESET = 8192;
   public static final int SDL_EVENT_RENDER_DEVICE_RESET = 8193;
   public static final int SDL_EVENT_RENDER_DEVICE_LOST = 8194;
   public static final int SDL_EVENT_PRIVATE0 = 16384;
   public static final int SDL_EVENT_PRIVATE1 = 16385;
   public static final int SDL_EVENT_PRIVATE2 = 16386;
   public static final int SDL_EVENT_PRIVATE3 = 16387;
   public static final int SDL_EVENT_POLL_SENTINEL = 32512;
   public static final int SDL_EVENT_USER = 32768;
   public static final int SDL_EVENT_LAST = 65535;
   public static final int SDL_EVENT_ENUM_PADDING = Integer.MAX_VALUE;
   public static final int SDL_ADDEVENT = 0;
   public static final int SDL_PEEKEVENT = 1;
   public static final int SDL_GETEVENT = 2;

   protected SDLEvents() {
      throw new UnsupportedOperationException();
   }

   public static void SDL_PumpEvents() {
      long __functionAddress = SDLEvents.Functions.PumpEvents;
      SDL3Lifecycle.awaitForeground();
      JNI.invokeV(__functionAddress);
   }

   public static int nSDL_PeepEvents(long events, int numevents, int action, int minType, int maxType) {
      long __functionAddress = SDLEvents.Functions.PeepEvents;
      return JNI.invokePI(events, numevents, action, minType, maxType, __functionAddress);
   }

   public static int SDL_PeepEvents(@NativeType("SDL_Event *") SDL_Event.Buffer events, @NativeType("SDL_EventAction") int action, @NativeType("Uint32") int minType, @NativeType("Uint32") int maxType) {
      return nSDL_PeepEvents(MemoryUtil.memAddressSafe(events), Checks.remainingSafe(events), action, minType, maxType);
   }

   @NativeType("bool")
   public static boolean SDL_HasEvent(@NativeType("Uint32") int type) {
      long __functionAddress = SDLEvents.Functions.HasEvent;
      return JNI.invokeZ(type, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_HasEvents(@NativeType("Uint32") int minType, @NativeType("Uint32") int maxType) {
      long __functionAddress = SDLEvents.Functions.HasEvents;
      return JNI.invokeZ(minType, maxType, __functionAddress);
   }

   public static void SDL_FlushEvent(@NativeType("Uint32") int type) {
      long __functionAddress = SDLEvents.Functions.FlushEvent;
      JNI.invokeV(type, __functionAddress);
   }

   public static void SDL_FlushEvents(@NativeType("Uint32") int minType, @NativeType("Uint32") int maxType) {
      long __functionAddress = SDLEvents.Functions.FlushEvents;
      JNI.invokeV(minType, maxType, __functionAddress);
   }

   public static boolean nSDL_PollEvent(long event) {
      long __functionAddress = SDLEvents.Functions.PollEvent;
      SDL3Lifecycle.awaitForeground();
      boolean got = JNI.invokePZ(event, __functionAddress);
      if (got && event != 0L) {
         SDL3Bridge.polledEvent(event);
      }
      return got;
   }

   @NativeType("bool")
   public static boolean SDL_PollEvent(@NativeType("SDL_Event *") SDL_Event event) {
      return nSDL_PollEvent(MemoryUtil.memAddressSafe(event));
   }

   public static boolean nSDL_WaitEvent(long event) {
      long __functionAddress = SDLEvents.Functions.WaitEvent;
      SDL3Lifecycle.awaitForeground();
      boolean got = JNI.invokePZ(event, __functionAddress);
      if (got && event != 0L) {
         SDL3Bridge.polledEvent(event);
      }
      return got;
   }

   @NativeType("bool")
   public static boolean SDL_WaitEvent(@NativeType("SDL_Event *") SDL_Event event) {
      return nSDL_WaitEvent(MemoryUtil.memAddressSafe(event));
   }

   public static boolean nSDL_WaitEventTimeout(long event, int timeoutMS) {
      long __functionAddress = SDLEvents.Functions.WaitEventTimeout;
      SDL3Lifecycle.awaitForeground();
      boolean got = JNI.invokePZ(event, timeoutMS, __functionAddress);
      if (got && event != 0L) {
         SDL3Bridge.polledEvent(event);
      }
      return got;
   }

   @NativeType("bool")
   public static boolean SDL_WaitEventTimeout(@NativeType("SDL_Event *") SDL_Event event, @NativeType("Sint32") int timeoutMS) {
      return nSDL_WaitEventTimeout(MemoryUtil.memAddressSafe(event), timeoutMS);
   }

   public static boolean nSDL_PushEvent(long event) {
      long __functionAddress = SDLEvents.Functions.PushEvent;
      return JNI.invokePZ(event, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_PushEvent(@NativeType("SDL_Event *") SDL_Event event) {
      return nSDL_PushEvent(event.address());
   }

   public static void nSDL_SetEventFilter(long filter, long userdata) {
      long __functionAddress = SDLEvents.Functions.SetEventFilter;
      JNI.invokePPV(filter, userdata, __functionAddress);
   }

   public static void SDL_SetEventFilter(@NativeType("SDL_EventFilter") SDL_EventFilterI filter, @NativeType("void *") long userdata) {
      nSDL_SetEventFilter(MemoryUtil.memAddressSafe(filter), userdata);
   }

   public static boolean nSDL_GetEventFilter(long filter, long userdata) {
      long __functionAddress = SDLEvents.Functions.GetEventFilter;
      return JNI.invokePPZ(filter, userdata, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_GetEventFilter(@NativeType("SDL_EventFilter *") PointerBuffer filter, @NativeType("void **") PointerBuffer userdata) {
      if (Checks.CHECKS) {
         Checks.checkSafe(filter, 1);
         Checks.checkSafe(userdata, 1);
      }

      return nSDL_GetEventFilter(MemoryUtil.memAddressSafe(filter), MemoryUtil.memAddressSafe(userdata));
   }

   public static boolean nSDL_AddEventWatch(long filter, long userdata) {
      long __functionAddress = SDLEvents.Functions.AddEventWatch;
      return JNI.invokePPZ(filter, userdata, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_AddEventWatch(@NativeType("SDL_EventFilter") SDL_EventFilterI filter, @NativeType("void *") long userdata) {
      return nSDL_AddEventWatch(filter.address(), userdata);
   }

   public static void nSDL_RemoveEventWatch(long filter, long userdata) {
      long __functionAddress = SDLEvents.Functions.RemoveEventWatch;
      JNI.invokePPV(filter, userdata, __functionAddress);
   }

   public static void SDL_RemoveEventWatch(@NativeType("SDL_EventFilter") SDL_EventFilterI filter, @NativeType("void *") long userdata) {
      nSDL_RemoveEventWatch(filter.address(), userdata);
   }

   public static void nSDL_FilterEvents(long filter, long userdata) {
      long __functionAddress = SDLEvents.Functions.FilterEvents;
      JNI.invokePPV(filter, userdata, __functionAddress);
   }

   public static void SDL_FilterEvents(@NativeType("SDL_EventFilter") SDL_EventFilterI filter, @NativeType("void *") long userdata) {
      nSDL_FilterEvents(filter.address(), userdata);
   }

   public static void SDL_SetEventEnabled(@NativeType("Uint32") int type, @NativeType("bool") boolean enabled) {
      long __functionAddress = SDLEvents.Functions.SetEventEnabled;
      JNI.invokeV(type, enabled, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_EventEnabled(@NativeType("Uint32") int type) {
      long __functionAddress = SDLEvents.Functions.EventEnabled;
      return JNI.invokeZ(type, __functionAddress);
   }

   @NativeType("Uint32")
   public static int SDL_RegisterEvents(int numevents) {
      long __functionAddress = SDLEvents.Functions.RegisterEvents;
      return JNI.invokeI(numevents, __functionAddress);
   }

   public static long nSDL_GetWindowFromEvent(long event) {
      long __functionAddress = SDLEvents.Functions.GetWindowFromEvent;
      return JNI.invokePP(event, __functionAddress);
   }

   @NativeType("SDL_Window *")
   public static long SDL_GetWindowFromEvent(@NativeType("SDL_Event const *") SDL_Event event) {
      return nSDL_GetWindowFromEvent(event.address());
   }

   public static int nSDL_GetEventDescription(long event, long buf, int buflen) {
      long __functionAddress = SDLEvents.Functions.GetEventDescription;
      return JNI.invokePPI(event, buf, buflen, __functionAddress);
   }

   public static int SDL_GetEventDescription(@NativeType("SDL_Event const *") SDL_Event event, @NativeType("char *") ByteBuffer buf) {
      return nSDL_GetEventDescription(MemoryUtil.memAddressSafe(event), MemoryUtil.memAddressSafe(buf), Checks.remainingSafe(buf));
   }

   @NativeType("int")
   public static String SDL_GetEventDescription(@NativeType("SDL_Event const *") SDL_Event event, int buflen) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      String var6;
      try {
         ByteBuffer buf = stack.malloc(buflen);
         int __result = nSDL_GetEventDescription(MemoryUtil.memAddressSafe(event), MemoryUtil.memAddress(buf), buflen);
         var6 = MemoryUtil.memASCII(buf, __result);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var6;
   }

   @NativeType("int")
   public static String SDL_GetEventDescription(@NativeType("SDL_Event const *") SDL_Event event) {
      return SDL_GetEventDescription(event, SDL_GetEventDescription(event, (ByteBuffer)null) + 1);
   }

   public static final class Functions {
      public static final long PumpEvents = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_PumpEvents");
      public static final long PeepEvents = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_PeepEvents");
      public static final long HasEvent = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_HasEvent");
      public static final long HasEvents = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_HasEvents");
      public static final long FlushEvent = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_FlushEvent");
      public static final long FlushEvents = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_FlushEvents");
      public static final long PollEvent = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_PollEvent");
      public static final long WaitEvent = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_WaitEvent");
      public static final long WaitEventTimeout = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_WaitEventTimeout");
      public static final long PushEvent = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_PushEvent");
      public static final long SetEventFilter = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetEventFilter");
      public static final long GetEventFilter = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetEventFilter");
      public static final long AddEventWatch = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_AddEventWatch");
      public static final long RemoveEventWatch = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_RemoveEventWatch");
      public static final long FilterEvents = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_FilterEvents");
      public static final long SetEventEnabled = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_SetEventEnabled");
      public static final long EventEnabled = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_EventEnabled");
      public static final long RegisterEvents = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_RegisterEvents");
      public static final long GetWindowFromEvent = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetWindowFromEvent");
      public static final long GetEventDescription = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_GetEventDescription");

      private Functions() {
      }
   }
}
