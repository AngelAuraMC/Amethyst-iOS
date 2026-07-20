/*
 * The contents of this file is dual-licensed under 2
 * alternative Open Source/Free licenses: LGPL 2.1 or later and
 * Apache License 2.0. (starting with JNA version 4.0.0).
 *
 * You can freely decide which license you want to apply to
 * the project.
 *
 * You may obtain a copy of the LGPL License at:
 *
 * http://www.gnu.org/licenses/licenses.html
 *
 * A copy is also included in the downloadable source code package
 * containing JNA, in file "LGPL2.1".
 *
 * You may obtain a copy of the Apache License at:
 *
 * http://www.apache.org/licenses/
 *
 * A copy is also included in the downloadable source code package
 * containing JNA, in file "AL2.0".
 */
package com.sun.jna;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.*;
import java.util.*;
import java.util.logging.Level;
import java.util.logging.Logger;

/** Provide simplified platform information. */
public final class Platform {
    public static final int UNSPECIFIED = -1;
    public static final int MAC = 0;
    public static final int LINUX = 1;
    public static final int WINDOWS = 2;
    public static final int SOLARIS = 3;
    public static final int FREEBSD = 4;
    public static final int OPENBSD = 5;
    public static final int WINDOWSCE = 6;
    public static final int AIX = 7;
    public static final int ANDROID = 8;
    public static final int GNU = 9;
    public static final int KFREEBSD = 10;
    public static final int NETBSD = 11;
    public static final int DRAGONFLYBSD = 12;

    /** Whether read-only (final) fields within Structures are supported. */
    public static final boolean RO_FIELDS;
    /** Whether this platform provides NIO Buffers. */
    public static final boolean HAS_BUFFERS;
    /** Whether this platform provides the AWT Component class; also false if
     * running headless.
     */
    public static final boolean HAS_AWT;
    /** Whether this platform supports the JAWT library. */
    public static final boolean HAS_JAWT;
    /** Canonical name of this platform's math library. */
    public static final String MATH_LIBRARY_NAME;
    /** Canonical name of this platform's C runtime library. */
    public static final String C_LIBRARY_NAME;
    /** Whether in-DLL callbacks are supported. */
    public static final boolean HAS_DLL_CALLBACKS;
    /** Canonical resource prefix for the current platform.  This value is
     * used to load bundled native libraries from the class path.
     */
    public static final String RESOURCE_PREFIX;

    private static final int osType;
    /** Current platform architecture. */
    public static final String ARCH;

    private static final Set<String> matchingClassNames = new HashSet<String>();
    private static Object stackWalker;
    private static Method stackWalkerGetCaller;

    static {
        matchingClassNames.add("de.maxhenkel.voicechat.config.ClientConfig");
        matchingClassNames.add("de.maxhenkel.voicechat.VoicechatClient");
        // MicrophoneManager removed: on iOS, OpenAL AudioUnit capture is broken,
        // so we let isMac() return true so the mod uses Java microphone (javax.sound via AVFoundation)
        // matchingClassNames.add("de.maxhenkel.voicechat.voice.client.microphone.MicrophoneManager");
        matchingClassNames.add("de.maxhenkel.voicechat.macos.VersionCheck");
        // NativeValidator removed: on iOS, macOS native dylibs (Opus, LAME, RNNoise, Speex)
        // are incompatible and crash with SIGILL. Removing this lets isMac() return true,
        // which causes NativeValidator to check macOS version via VersionCheck and skip.
        // The mod falls back to pure Java Opus (Concentus) for voice chat.
        // matchingClassNames.add("de.maxhenkel.voicechat.natives.NativeValidator");
        matchingClassNames.add("de.maxhenkel.voicechat.natives.OpusManager");
        matchingClassNames.add("de.maxhenkel.voicechat.natives.LameManager");
        matchingClassNames.add("de.maxhenkel.voicechat.natives.RNNoiseManager");
        matchingClassNames.add("de.maxhenkel.voicechat.natives.SpeexManager");
        matchingClassNames.add("de.maxhenkel.opus4j.OpusDecoder");
        matchingClassNames.add("de.maxhenkel.opus4j.OpusEncoder");
        matchingClassNames.add("de.maxhenkel.voicechat.plugins.impl.opus.NativeOpusDecoderImpl");
        matchingClassNames.add("de.maxhenkel.voicechat.plugins.impl.opus.NativeOpusEncoderImpl");
        matchingClassNames.add("de.maxhenkel.voicechat.voice.client.AudioChannel");
        matchingClassNames.add("de.maxhenkel.voicechat.voice.client.AudioEncoder");
        matchingClassNames.add("de.maxhenkel.voicechat.voice.client.MicrophoneThread");
        matchingClassNames.add("su.plo.voice.client.audio.device.VoiceDeviceManager");
    }

    static {
        osType = MAC;
        // NOTE: we used to do Class.forName("java.awt.Component"), but that
        // has the unintended side effect of actually loading AWT native libs,
        // which can be problematic
        HAS_AWT = true;
        HAS_JAWT = HAS_AWT && osType != MAC;
        HAS_BUFFERS = true;
        RO_FIELDS = osType != WINDOWSCE;
        C_LIBRARY_NAME = "c";
        MATH_LIBRARY_NAME = "m";
        ARCH = getCanonicalArchitecture(System.getProperty("os.arch"), osType);
        // Windows aarch64 callbacks disabled via ASMFN_OFF (no mingw support)
        HAS_DLL_CALLBACKS = false;
        RESOURCE_PREFIX = getNativeLibraryResourcePrefix();

        try {
            Class cStackWalker = Class.forName("java.lang.StackWalker");
            Class cStackWalkerOption = Class.forName("java.lang.StackWalker$Option");
            Object RETAIN_CLASS_REFERENCE = cStackWalkerOption.getMethod("valueOf", String.class).invoke(null, "RETAIN_CLASS_REFERENCE");
            stackWalker = cStackWalker.getMethod("getInstance", cStackWalkerOption).invoke(null, RETAIN_CLASS_REFERENCE);
            stackWalkerGetCaller = cStackWalker.getMethod("getCallerClass");
        } catch (Throwable th) {
        }
    }
    private Platform() { }
    public static final int getOSType() {
        return osType;
    }
    public static final boolean isMac() {
        try {
            Class caller = (Class)stackWalkerGetCaller.invoke(stackWalker);
            if (matchingClassNames.contains(caller.getName())) {
                return false;
            }
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
        return true;
    }
    public static final boolean isAndroid() {
        return osType == ANDROID;
    }
    public static final boolean isLinux() {
        return osType == LINUX;
    }
    public static final boolean isAIX() {
        return osType == AIX;
    }
    public static final boolean isWindowsCE() {
        return osType == WINDOWSCE;
    }
    /** Returns true for any windows variant. */
    public static final boolean isWindows() {
        return osType == WINDOWS || osType == WINDOWSCE;
    }
    public static final boolean isSolaris() {
        return osType == SOLARIS;
    }
    public static final boolean isDragonFlyBSD() {
        return osType == DRAGONFLYBSD;
    }
    public static final boolean isFreeBSD() {
        return osType == FREEBSD;
    }
    public static final boolean isOpenBSD() {
        return osType == OPENBSD;
    }
    public static final boolean isNetBSD() {
        return osType == NETBSD;
    }
    public static final boolean isGNU() {
        return osType == GNU;
    }
    public static final boolean iskFreeBSD() {
        return osType == KFREEBSD;
    }
    public static final boolean isX11() {
        // TODO: check filesystem for /usr/X11 or some other X11-specific test
        return false;
    }
    public static final boolean hasRuntimeExec() {
        return true;
    }
    public static final boolean is64Bit() {
        return true;
    }

    public static final boolean isIntel() {
        return false;
    }

    public static final boolean isPPC() {
        return false;
    }

    public static final boolean isARM() {
        return true;
    }

    public static final boolean isSPARC() {
        return false;
    }

    public static final boolean isMIPS() {
        return false;
    }

    public static final boolean isLoongArch() {
        return false;
    }

    static String getCanonicalArchitecture(String arch, int platform) {
        return arch;
    }

    static boolean isSoftFloat() {
        return false;
    }

    /** Generate a canonical String prefix based on the current OS
        type/arch/name.
    */
    static String getNativeLibraryResourcePrefix() {
        String prefix = System.getProperty("jna.prefix");
        if(prefix != null) {
            return prefix;
        } else {
            return getNativeLibraryResourcePrefix(getOSType(), System.getProperty("os.arch"), System.getProperty("os.name"));
        }
    }

    /** Generate a canonical String prefix based on the given OS
        type/arch/name.
        @param osType from {@link #getOSType()}
        @param arch from <code>os.arch</code> System property
        @param name from <code>os.name</code> System property
    */
    static String getNativeLibraryResourcePrefix(int osType, String arch, String name) {
        return "darwin-" + arch;
    }
}