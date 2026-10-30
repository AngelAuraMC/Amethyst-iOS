/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  org.jspecify.annotations.Nullable
 *  org.lwjgl.PointerBuffer
 *  org.lwjgl.system.APIUtil
 *  org.lwjgl.system.Checks
 *  org.lwjgl.system.CustomBuffer
 *  org.lwjgl.system.FunctionProvider
 *  org.lwjgl.system.JNI
 *  org.lwjgl.system.MemoryStack
 *  org.lwjgl.system.MemoryUtil
 *  org.lwjgl.system.NativeType
 */
package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import org.lwjgl.PointerBuffer;
import org.lwjgl.sdl.SDL;
import org.lwjgl.sdl.SDLStdinc;
import org.lwjgl.sdl.SDL_ClipboardCleanupCallbackI;
import org.lwjgl.sdl.SDL_ClipboardDataCallbackI;
import org.lwjgl.system.APIUtil;
import org.lwjgl.system.Checks;
import org.lwjgl.system.CustomBuffer;
import org.lwjgl.system.FunctionProvider;
import org.lwjgl.system.JNI;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.NativeType;

public class SDLClipboard {
    protected SDLClipboard() {
        throw new UnsupportedOperationException();
    }

    public static boolean nSDL_SetClipboardText(long text) {
        long __functionAddress = Functions.SetClipboardText;
        return (SDL3Bridge.invokeOnMain(__functionAddress, text, 0L, 0L, 0L) & 0xFFL) != 0L;
    }

    @NativeType(value="bool")
    public static boolean SDL_SetClipboardText(@NativeType(value="char const *") ByteBuffer text) {
        if (Checks.CHECKS) {
            Checks.checkNT1((ByteBuffer)text);
        }
        return SDLClipboard.nSDL_SetClipboardText(MemoryUtil.memAddress((ByteBuffer)text));
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    @NativeType(value="bool")
    public static boolean SDL_SetClipboardText(@NativeType(value="char const *") CharSequence text) {
        MemoryStack stack = MemoryStack.stackGet();
        int stackPointer = stack.getPointer();
        try {
            stack.nUTF8(text, true);
            long textEncoded = stack.getPointerAddress();
            boolean bl = SDLClipboard.nSDL_SetClipboardText(textEncoded);
            return bl;
        }
        finally {
            stack.setPointer(stackPointer);
        }
    }

    public static long nSDL_GetClipboardText() {
        long __functionAddress = Functions.GetClipboardText;
        return SDL3Bridge.invokeOnMain(__functionAddress, 0L, 0L, 0L, 0L);
    }

    @NativeType(value="char *")
    public static String SDL_GetClipboardText() {
        long __result = 0L;
        try {
            __result = SDLClipboard.nSDL_GetClipboardText();
            String string = MemoryUtil.memUTF8Safe((long)__result);
            return string;
        }
        finally {
            SDLStdinc.nSDL_free(__result);
        }
    }

    @NativeType(value="bool")
    public static boolean SDL_HasClipboardText() {
        long __functionAddress = Functions.HasClipboardText;
        return (SDL3Bridge.invokeOnMain(__functionAddress, 0L, 0L, 0L, 0L) & 0xFFL) != 0L;
    }

    public static boolean nSDL_SetPrimarySelectionText(long text) {
        long __functionAddress = Functions.SetPrimarySelectionText;
        return JNI.invokePZ((long)text, (long)__functionAddress);
    }

    @NativeType(value="bool")
    public static boolean SDL_SetPrimarySelectionText(@NativeType(value="char const *") ByteBuffer text) {
        if (Checks.CHECKS) {
            Checks.checkNT1((ByteBuffer)text);
        }
        return SDLClipboard.nSDL_SetPrimarySelectionText(MemoryUtil.memAddress((ByteBuffer)text));
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    @NativeType(value="bool")
    public static boolean SDL_SetPrimarySelectionText(@NativeType(value="char const *") CharSequence text) {
        MemoryStack stack = MemoryStack.stackGet();
        int stackPointer = stack.getPointer();
        try {
            stack.nUTF8(text, true);
            long textEncoded = stack.getPointerAddress();
            boolean bl = SDLClipboard.nSDL_SetPrimarySelectionText(textEncoded);
            return bl;
        }
        finally {
            stack.setPointer(stackPointer);
        }
    }

    public static long nSDL_GetPrimarySelectionText() {
        long __functionAddress = Functions.GetPrimarySelectionText;
        return JNI.invokeP((long)__functionAddress);
    }

    @NativeType(value="char *")
    public static String SDL_GetPrimarySelectionText() {
        long __result = 0L;
        try {
            __result = SDLClipboard.nSDL_GetPrimarySelectionText();
            String string = MemoryUtil.memUTF8Safe((long)__result);
            return string;
        }
        finally {
            SDLStdinc.nSDL_free(__result);
        }
    }

    @NativeType(value="bool")
    public static boolean SDL_HasPrimarySelectionText() {
        long __functionAddress = Functions.HasPrimarySelectionText;
        return JNI.invokeZ((long)__functionAddress);
    }

    public static boolean nSDL_SetClipboardData(long callback, long cleanup, long userdata, long mime_types, long num_mime_types) {
        long __functionAddress = Functions.SetClipboardData;
        return JNI.invokePPPPPZ((long)callback, (long)cleanup, (long)userdata, (long)mime_types, (long)num_mime_types, (long)__functionAddress);
    }

    @NativeType(value="bool")
    public static boolean SDL_SetClipboardData(@NativeType(value="SDL_ClipboardDataCallback") SDL_ClipboardDataCallbackI callback, @NativeType(value="SDL_ClipboardCleanupCallback") SDL_ClipboardCleanupCallbackI cleanup, @NativeType(value="void *") long userdata, @NativeType(value="char const **") PointerBuffer mime_types) {
        return SDLClipboard.nSDL_SetClipboardData(callback.address(), cleanup.address(), userdata, MemoryUtil.memAddress((CustomBuffer)mime_types), mime_types.remaining());
    }

    @NativeType(value="bool")
    public static boolean SDL_ClearClipboardData() {
        long __functionAddress = Functions.ClearClipboardData;
        return (SDL3Bridge.invokeOnMain(__functionAddress, 0L, 0L, 0L, 0L) & 0xFFL) != 0L;
    }

    public static long nSDL_GetClipboardData(long mime_type, long size) {
        long __functionAddress = Functions.GetClipboardData;
        return JNI.invokePPP((long)mime_type, (long)size, (long)__functionAddress);
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    @NativeType(value="void *")
    public static ByteBuffer SDL_GetClipboardData(@NativeType(value="char const *") ByteBuffer mime_type) {
        if (Checks.CHECKS) {
            Checks.checkNT1((ByteBuffer)mime_type);
        }
        MemoryStack stack = MemoryStack.stackGet();
        int stackPointer = stack.getPointer();
        PointerBuffer size = stack.callocPointer(1);
        try {
            long __result = SDLClipboard.nSDL_GetClipboardData(MemoryUtil.memAddress((ByteBuffer)mime_type), MemoryUtil.memAddress((CustomBuffer)size));
            ByteBuffer byteBuffer = MemoryUtil.memByteBufferSafe((long)__result, (int)((int)size.get(0)));
            return byteBuffer;
        }
        finally {
            stack.setPointer(stackPointer);
        }
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    @NativeType(value="void *")
    public static ByteBuffer SDL_GetClipboardData(@NativeType(value="char const *") CharSequence mime_type) {
        MemoryStack stack = MemoryStack.stackGet();
        int stackPointer = stack.getPointer();
        try {
            PointerBuffer size = stack.callocPointer(1);
            stack.nASCII(mime_type, true);
            long mime_typeEncoded = stack.getPointerAddress();
            long __result = SDLClipboard.nSDL_GetClipboardData(mime_typeEncoded, MemoryUtil.memAddress((CustomBuffer)size));
            ByteBuffer byteBuffer = MemoryUtil.memByteBufferSafe((long)__result, (int)((int)size.get(0)));
            return byteBuffer;
        }
        finally {
            stack.setPointer(stackPointer);
        }
    }

    public static boolean nSDL_HasClipboardData(long mime_type) {
        long __functionAddress = Functions.HasClipboardData;
        return JNI.invokePZ((long)mime_type, (long)__functionAddress);
    }

    @NativeType(value="bool")
    public static boolean SDL_HasClipboardData(@NativeType(value="char const *") ByteBuffer mime_type) {
        if (Checks.CHECKS) {
            Checks.checkNT1((ByteBuffer)mime_type);
        }
        return SDLClipboard.nSDL_HasClipboardData(MemoryUtil.memAddress((ByteBuffer)mime_type));
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    @NativeType(value="bool")
    public static boolean SDL_HasClipboardData(@NativeType(value="char const *") CharSequence mime_type) {
        MemoryStack stack = MemoryStack.stackGet();
        int stackPointer = stack.getPointer();
        try {
            stack.nASCII(mime_type, true);
            long mime_typeEncoded = stack.getPointerAddress();
            boolean bl = SDLClipboard.nSDL_HasClipboardData(mime_typeEncoded);
            return bl;
        }
        finally {
            stack.setPointer(stackPointer);
        }
    }

    public static long nSDL_GetClipboardMimeTypes(long num_mime_types) {
        long __functionAddress = Functions.GetClipboardMimeTypes;
        return JNI.invokePP((long)num_mime_types, (long)__functionAddress);
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    @NativeType(value="char **")
    public static PointerBuffer SDL_GetClipboardMimeTypes() {
        MemoryStack stack = MemoryStack.stackGet();
        int stackPointer = stack.getPointer();
        PointerBuffer num_mime_types = stack.callocPointer(1);
        try {
            long __result = SDLClipboard.nSDL_GetClipboardMimeTypes(MemoryUtil.memAddress((CustomBuffer)num_mime_types));
            PointerBuffer pointerBuffer = MemoryUtil.memPointerBufferSafe((long)__result, (int)((int)num_mime_types.get(0)));
            return pointerBuffer;
        }
        finally {
            stack.setPointer(stackPointer);
        }
    }

    public static final class Functions {
        public static final long SetClipboardText = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_SetClipboardText");
        public static final long GetClipboardText = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_GetClipboardText");
        public static final long HasClipboardText = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_HasClipboardText");
        public static final long SetPrimarySelectionText = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_SetPrimarySelectionText");
        public static final long GetPrimarySelectionText = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_GetPrimarySelectionText");
        public static final long HasPrimarySelectionText = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_HasPrimarySelectionText");
        public static final long SetClipboardData = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_SetClipboardData");
        public static final long ClearClipboardData = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_ClearClipboardData");
        public static final long GetClipboardData = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_GetClipboardData");
        public static final long HasClipboardData = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_HasClipboardData");
        public static final long GetClipboardMimeTypes = APIUtil.apiGetFunctionAddress((FunctionProvider)SDL.getLibrary(), (String)"SDL_GetClipboardMimeTypes");

        private Functions() {
        }
    }
}

