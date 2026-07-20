package com.apple.ios.audio;

class NativeAudioCapture {
    static {
        System.loadLibrary("audio_capture");
    }

    static native long init(int sampleRate, int channels, int bitsPerSample, boolean bigEndian);
    static native void start(long handle);
    static native void stop(long handle);
    static native void release(long handle);
    static native int read(long handle, byte[] buffer, int offset, int length);
    static native int available(long handle);
}
