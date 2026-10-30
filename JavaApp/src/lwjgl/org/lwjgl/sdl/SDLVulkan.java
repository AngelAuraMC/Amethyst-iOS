package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.nio.LongBuffer;
import org.lwjgl.PointerBuffer;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;
import org.lwjgl.vulkan.VkAllocationCallbacks;
import org.lwjgl.vulkan.VkInstance;
import org.lwjgl.vulkan.VkPhysicalDevice;

public class SDLVulkan {
   protected SDLVulkan() {
      throw new UnsupportedOperationException();
   }

   public static boolean nSDL_Vulkan_LoadLibrary(long path) {
      long __functionAddress = SDLVulkan.Functions.Vulkan_LoadLibrary;
      return JNI.invokePZ(path, __functionAddress);
   }

   @NativeType("bool")
   public static boolean SDL_Vulkan_LoadLibrary(@NativeType("char const *") ByteBuffer path) {
      if (Checks.CHECKS) {
         Checks.checkNT1Safe(path);
      }

      return nSDL_Vulkan_LoadLibrary(MemoryUtil.memAddressSafe(path));
   }

   @NativeType("bool")
   public static boolean SDL_Vulkan_LoadLibrary(@NativeType("char const *") CharSequence path) {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();

      boolean var5;
      try {
         stack.nUTF8Safe(path, true);
         long pathEncoded = path == null ? 0L : stack.getPointerAddress();
         var5 = nSDL_Vulkan_LoadLibrary(pathEncoded);
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   @NativeType("SDL_FunctionPointer")
   public static long SDL_Vulkan_GetVkGetInstanceProcAddr() {
      long __functionAddress = SDLVulkan.Functions.Vulkan_GetVkGetInstanceProcAddr;
      return JNI.invokeP(__functionAddress);
   }

   public static void SDL_Vulkan_UnloadLibrary() {
      long __functionAddress = SDLVulkan.Functions.Vulkan_UnloadLibrary;
      JNI.invokeV(__functionAddress);
   }

   public static long nSDL_Vulkan_GetInstanceExtensions(long count) {
      long __functionAddress = SDLVulkan.Functions.Vulkan_GetInstanceExtensions;
      return JNI.invokePP(count, __functionAddress);
   }

   @NativeType("char const * const *")
   public static PointerBuffer SDL_Vulkan_GetInstanceExtensions() {
      MemoryStack stack = MemoryStack.stackGet();
      int stackPointer = stack.getPointer();
      IntBuffer count = stack.callocInt(1);

      PointerBuffer var5;
      try {
         long __result = nSDL_Vulkan_GetInstanceExtensions(MemoryUtil.memAddress(count));
         var5 = MemoryUtil.memPointerBufferSafe(__result, count.get(0));
      } finally {
         stack.setPointer(stackPointer);
      }

      return var5;
   }

   public static boolean nSDL_Vulkan_CreateSurface(long window, long instance, long allocator, long surface) {
      long __functionAddress = SDLVulkan.Functions.Vulkan_CreateSurface;
      if (Checks.CHECKS) {
         Checks.check(window);
      }

      SDL3Bridge.trace("[SDL3 TRACE] SDL_Vulkan_CreateSurface BEGIN");
      boolean result = (SDL3Bridge.invokeOnMain(__functionAddress, window, instance, allocator, surface) & 0xFFL) != 0L;
      SDL3Bridge.trace("[SDL3 TRACE] SDL_Vulkan_CreateSurface END result=" + result);
      if (result) {
         // SDL's metal view exists now, make sure it gets moved under amethyst's controls
         SDL3Bridge.attachWindow(window);
      } else {
         SDL3Bridge.warn("SDL_Vulkan_CreateSurface failed: " + SDL3Bridge.mainThreadError());
      }
      return result;
   }

   @NativeType("bool")
   public static boolean SDL_Vulkan_CreateSurface(@NativeType("SDL_Window *") long window, VkInstance instance, @NativeType("VkAllocationCallbacks const *") VkAllocationCallbacks allocator, @NativeType("VkSurfaceKHR *") LongBuffer surface) {
      if (Checks.CHECKS) {
         Checks.check(surface, 1);
      }

      return nSDL_Vulkan_CreateSurface(window, instance.address(), MemoryUtil.memAddressSafe(allocator), MemoryUtil.memAddress(surface));
   }

   public static void nSDL_Vulkan_DestroySurface(long instance, long surface, long allocator) {
      long __functionAddress = SDLVulkan.Functions.Vulkan_DestroySurface;
      SDL3Bridge.invokeOnMain(__functionAddress, instance, surface, allocator, 0L);
   }

   public static void SDL_Vulkan_DestroySurface(VkInstance instance, @NativeType("VkSurfaceKHR") long surface, @NativeType("VkAllocationCallbacks const *") VkAllocationCallbacks allocator) {
      nSDL_Vulkan_DestroySurface(instance.address(), surface, MemoryUtil.memAddressSafe(allocator));
   }

   @NativeType("bool")
   public static boolean SDL_Vulkan_GetPresentationSupport(VkInstance instance, VkPhysicalDevice physicalDevice, @NativeType("Uint32") int queueFamilyIndex) {
      long __functionAddress = SDLVulkan.Functions.Vulkan_GetPresentationSupport;
      return JNI.invokePPZ(instance.address(), physicalDevice.address(), queueFamilyIndex, __functionAddress);
   }

   public static final class Functions {
      public static final long Vulkan_LoadLibrary = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Vulkan_LoadLibrary");
      public static final long Vulkan_GetVkGetInstanceProcAddr = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Vulkan_GetVkGetInstanceProcAddr");
      public static final long Vulkan_UnloadLibrary = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Vulkan_UnloadLibrary");
      public static final long Vulkan_GetInstanceExtensions = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Vulkan_GetInstanceExtensions");
      public static final long Vulkan_CreateSurface = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Vulkan_CreateSurface");
      public static final long Vulkan_DestroySurface = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Vulkan_DestroySurface");
      public static final long Vulkan_GetPresentationSupport = APIUtil.apiGetFunctionAddress(SDL.getLibrary(), "SDL_Vulkan_GetPresentationSupport");

      private Functions() {
      }
   }
}
