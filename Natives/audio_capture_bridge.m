#include <Foundation/Foundation.h>
#include <AVFoundation/AVFoundation.h>
#include <pthread.h>
#include "jni.h"

#define CIRCULAR_BUFFER_SIZE (48000 * 2 * 8)

typedef struct {
    uint8_t *buffer;
    size_t size;
    size_t write_pos;
    size_t read_pos;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    volatile BOOL running;
    volatile BOOL destroyed;
} AudioCaptureCtx;

static AudioCaptureCtx *ctx_init() {
    AudioCaptureCtx *ctx = calloc(1, sizeof(AudioCaptureCtx));
    ctx->buffer = malloc(CIRCULAR_BUFFER_SIZE);
    ctx->size = CIRCULAR_BUFFER_SIZE;
    ctx->write_pos = 0;
    ctx->read_pos = 0;
    ctx->running = NO;
    ctx->destroyed = NO;
    pthread_mutex_init(&ctx->mutex, NULL);
    pthread_cond_init(&ctx->cond, NULL);
    return ctx;
}

static void ctx_destroy(AudioCaptureCtx *ctx) {
    if (!ctx) return;
    pthread_mutex_destroy(&ctx->mutex);
    pthread_cond_destroy(&ctx->cond);
    free(ctx->buffer);
    free(ctx);
}

static size_t ctx_available(AudioCaptureCtx *ctx) {
    size_t wp = ctx->write_pos;
    size_t rp = ctx->read_pos;
    return wp >= rp ? wp - rp : 0;
}

static void ctx_write(AudioCaptureCtx *ctx, const uint8_t *data, size_t len) {
    pthread_mutex_lock(&ctx->mutex);
    size_t avail = ctx_available(ctx);
    size_t space = ctx->size - avail;
    if (len > space) len = space;
    if (len > 0) {
        size_t remaining = len;
        while (remaining > 0) {
            size_t pos = ctx->write_pos % ctx->size;
            size_t chunk = ctx->size - pos;
            if (chunk > remaining) chunk = remaining;
            memcpy(ctx->buffer + pos, data, chunk);
            ctx->write_pos += chunk;
            data += chunk;
            remaining -= chunk;
        }
        pthread_cond_broadcast(&ctx->cond);
    }
    pthread_mutex_unlock(&ctx->mutex);
}

static size_t ctx_read(AudioCaptureCtx *ctx, uint8_t *data, size_t len, BOOL block) {
    pthread_mutex_lock(&ctx->mutex);
    while (ctx_available(ctx) == 0) {
        if (!block || !ctx->running || ctx->destroyed) {
            pthread_mutex_unlock(&ctx->mutex);
            return 0;
        }
        pthread_cond_wait(&ctx->cond, &ctx->mutex);
    }
    size_t avail = ctx_available(ctx);
    if (len > avail) len = avail;
    size_t remaining = len;
    while (remaining > 0) {
        size_t pos = ctx->read_pos % ctx->size;
        size_t chunk = ctx->size - pos;
        if (chunk > remaining) chunk = remaining;
        memcpy(data, ctx->buffer + pos, chunk);
        ctx->read_pos += chunk;
        data += chunk;
        remaining -= chunk;
    }
    pthread_mutex_unlock(&ctx->mutex);
    return len;
}

typedef struct {
    void *engine;
    void *outputFormat;
    AudioCaptureCtx *ctx;
} CaptureHandle;

#define HANDLE_ENGINE(h) ((__bridge AVAudioEngine*)(h)->engine)
#define HANDLE_FORMAT(h) ((__bridge AVAudioFormat*)(h)->outputFormat)

static void tapCallback(AVAudioPCMBuffer *buffer, AudioCaptureCtx *ctx) {
    if (!ctx->running || ctx->destroyed) return;
    if (buffer.frameLength == 0) return;

    float * const *floatData = buffer.floatChannelData;
    if (!floatData || !floatData[0]) return;

    size_t frameCount = buffer.frameLength;
    size_t byteCount = frameCount * 2;

    uint8_t *intData = malloc(byteCount);
    if (!intData) return;

    int16_t *samples = (int16_t *)intData;
    for (size_t i = 0; i < frameCount; i++) {
        float sample = floatData[0][i];
        if (sample > 1.0f) sample = 1.0f;
        else if (sample < -1.0f) sample = -1.0f;
        samples[i] = (int16_t)(sample * 32767.0f);
    }

    ctx_write(ctx, intData, byteCount);
    free(intData);
}

static CaptureHandle *createCapture(int sampleRate) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (!session.inputAvailable) {
        NSLog(@"[AudioCapture] No input available");
        return NULL;
    }

    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *inputNode = engine.inputNode;

    AVAudioFormat *requestedFormat = [[AVAudioFormat alloc]
        initWithCommonFormat:AVAudioPCMFormatFloat32
                  sampleRate:sampleRate
                    channels:1
                 interleaved:NO];

    AudioCaptureCtx *ctx = ctx_init();
    ctx->running = YES;

    [inputNode installTapOnBus:0
                    bufferSize:(AVAudioFrameCount)(sampleRate / 10)
                        format:requestedFormat
                         block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        tapCallback(buffer, ctx);
        (void)when;
    }];

    [engine prepare];

    CaptureHandle *handle = calloc(1, sizeof(CaptureHandle));
    handle->engine = (__bridge_retained void*)engine;
    handle->outputFormat = (__bridge_retained void*)requestedFormat;
    handle->ctx = ctx;
    return handle;
}

static void destroyCapture(CaptureHandle *handle) {
    if (!handle) return;
    if (handle->ctx) {
        pthread_mutex_lock(&handle->ctx->mutex);
        handle->ctx->running = NO;
        handle->ctx->destroyed = YES;
        pthread_cond_broadcast(&handle->ctx->cond);
        pthread_mutex_unlock(&handle->ctx->mutex);
        ctx_destroy(handle->ctx);
        handle->ctx = NULL;
    }
    if (handle->engine) {
        AVAudioEngine *e = (__bridge_transfer AVAudioEngine*)handle->engine;
        [e.inputNode removeTapOnBus:0];
        [e stop];
        handle->engine = NULL;
    }
    if (handle->outputFormat) {
        AVAudioFormat *f = (__bridge_transfer AVAudioFormat*)handle->outputFormat;
        (void)f;
        handle->outputFormat = NULL;
    }
    free(handle);
}

#pragma mark - JNI

JNIEXPORT jlong JNICALL Java_com_apple_ios_audio_NativeAudioCapture_init(
    JNIEnv *env, jclass clazz, jint sampleRate, jint channels, jint bitsPerSample, jboolean bigEndian) {

    CaptureHandle *handle = createCapture((int)sampleRate);
    if (!handle || !HANDLE_ENGINE(handle)) {
        NSLog(@"[AudioCapture] Failed to create audio capture");
        if (handle) destroyCapture(handle);
        return 0;
    }

    (void)channels;
    (void)bitsPerSample;
    (void)bigEndian;
    (void)env;
    (void)clazz;

    return (jlong)(intptr_t)handle;
}

JNIEXPORT void JNICALL Java_com_apple_ios_audio_NativeAudioCapture_start(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !HANDLE_ENGINE(handle)) return;
    NSError *error = nil;
    [HANDLE_ENGINE(handle) startAndReturnError:&error];
    if (error) {
        NSLog(@"[AudioCapture] Failed to start engine: %@", error);
    }
    if (handle->ctx) {
        handle->ctx->running = YES;
    }
    (void)env;
    (void)clazz;
}

JNIEXPORT void JNICALL Java_com_apple_ios_audio_NativeAudioCapture_stop(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !HANDLE_ENGINE(handle)) return;
    [HANDLE_ENGINE(handle) pause];
    if (handle->ctx) {
        handle->ctx->running = NO;
        pthread_cond_broadcast(&handle->ctx->cond);
    }
    (void)env;
    (void)clazz;
}

JNIEXPORT void JNICALL Java_com_apple_ios_audio_NativeAudioCapture_release(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    destroyCapture(handle);
    (void)env;
    (void)clazz;
}

JNIEXPORT jint JNICALL Java_com_apple_ios_audio_NativeAudioCapture_read(
    JNIEnv *env, jclass clazz, jlong handlePtr, jbyteArray buffer, jint offset, jint length) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !handle->ctx || !handle->ctx->running) return -1;
    jbyte *elements = (*env)->GetByteArrayElements(env, buffer, NULL);
    if (!elements) return -1;
    int n = (int)ctx_read(handle->ctx, (uint8_t *)(elements + offset), (size_t)length, YES);
    (*env)->ReleaseByteArrayElements(env, buffer, elements, 0);
    return n;
    (void)clazz;
}

JNIEXPORT jint JNICALL Java_com_apple_ios_audio_NativeAudioCapture_available(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !handle->ctx) return 0;
    pthread_mutex_lock(&handle->ctx->mutex);
    size_t avail = ctx_available(handle->ctx);
    pthread_mutex_unlock(&handle->ctx->mutex);
    return (jint)avail;
    (void)env;
    (void)clazz;
}
