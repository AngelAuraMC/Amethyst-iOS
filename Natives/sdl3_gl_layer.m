#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CAMetalLayer.h>
#include "jni.h"

JNIEXPORT void JNICALL
Java_org_lwjgl_sdl_SDL3GLContext_nativeSetDrawableSize(JNIEnv *env, jclass clazz,
                                                       jlong layerPtr, jint width, jint height) {
    (void)env;
    (void)clazz;
    if (layerPtr == 0 || width <= 0 || height <= 0) return;

    CAMetalLayer *layer = (__bridge CAMetalLayer *)(void *)(intptr_t)layerPtr;
    CGSize want = CGSizeMake(width, height);
    if (CGSizeEqualToSize(layer.drawableSize, want)) return;

    void (^apply)(void) = ^{
        if (!CGSizeEqualToSize(layer.drawableSize, want)) {
            // SDL puts the size back on every re-layout, so this can come around a lot
            static int logged = 0;
            if (logged++ < 4) {
                NSLog(@"[SDL3 EMBED] gl layer drawableSize %.0fx%.0f -> %dx%d",
                      layer.drawableSize.width, layer.drawableSize.height, (int)width, (int)height);
            }
            layer.drawableSize = want;
        }
    };
    if ([NSThread isMainThread]) {
        apply();
    } else {
        dispatch_async(dispatch_get_main_queue(), apply);
    }
}
