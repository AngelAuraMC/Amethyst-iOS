//
//  TouchControllerBridge.m
//  Angel Aura Amethyst
//
//  TouchController JNI 桥接实现
//  实现 Minecraft TouchController Mod 与 iOS 启动器之间的通信
//

#import "TouchControllerBridge.h"
#import <dlfcn.h>
#import <os/log.h>

// TouchController 静态库的 JNI 函数声明
typedef void (*JNI_Init_Func)(void);
typedef long long (*JNI_New_Func)(const char *name);
typedef int (*JNI_Receive_Func)(long long handle, void *buffer, int length);
typedef void (*JNI_Send_Func)(long long handle, const void *buffer, int offset, int length);
typedef void (*JNI_Destroy_Func)(long long handle);

// 函数指针
static JNI_Init_Func g_TouchController_Init = NULL;
static JNI_New_Func g_TouchController_New = NULL;
static JNI_Receive_Func g_TouchController_Receive = NULL;
static JNI_Send_Func g_TouchController_Send = NULL;
static JNI_Destroy_Func g_TouchController_Destroy = NULL;

// 是否已初始化
static BOOL g_Initialized = NO;
static void *g_LibraryHandle = NULL;

// 日志
static os_log_t touchControllerLog = NULL;

@implementation TouchControllerBridge

+ (void)load {
    touchControllerLog = os_log_create("org.angelauramc.amethyst", "TouchController");
    [self initializeTouchController];
}

+ (BOOL)initializeTouchController {
    if (g_Initialized) {
        return YES;
    }

    os_log_info(touchControllerLog, "Initializing TouchController bridge...");

    // 尝试加载 TouchController 静态库
    // 由于是静态链接，我们直接检查符号是否存在
    // 如果静态库已链接到可执行文件中，dlsym(RTLD_DEFAULT) 应该能找到符号
    
    g_TouchController_Init = (JNI_Init_Func)dlsym(RTLD_DEFAULT, "Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_init");
    g_TouchController_New = (JNI_New_Func)dlsym(RTLD_DEFAULT, "Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_new");
    g_TouchController_Receive = (JNI_Receive_Func)dlsym(RTLD_DEFAULT, "Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_receive");
    g_TouchController_Send = (JNI_Send_Func)dlsym(RTLD_DEFAULT, "Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_send");
    g_TouchController_Destroy = (JNI_Destroy_Func)dlsym(RTLD_DEFAULT, "Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_destroy");

    // 检查所有函数是否都找到了
    if (!g_TouchController_Init || !g_TouchController_New || !g_TouchController_Receive || 
        !g_TouchController_Send || !g_TouchController_Destroy) {
        const char *error = dlerror();
        os_log_error(touchControllerLog, "Failed to load TouchController symbols: %s", error ? error : "unknown error");
        g_Initialized = NO;
        return NO;
    }

    // 调用初始化函数
    if (g_TouchController_Init) {
        g_TouchController_Init();
    }

    g_Initialized = YES;
    os_log_info(touchControllerLog, "TouchController bridge initialized successfully");
    return YES;
}

+ (BOOL)isTouchControllerAvailable {
    return g_Initialized;
}

+ (long long)createTransportWithName:(NSString *)name {
    if (!g_Initialized || !g_TouchController_New) {
        os_log_error(touchControllerLog, "TouchController not initialized");
        return -1;
    }

    const char *cName = [name UTF8String];
    long long handle = g_TouchController_New(cName);

    if (handle < 0) {
        os_log_error(touchControllerLog, "Failed to create transport with name: %s", cName);
    } else {
        os_log_debug(touchControllerLog, "Created transport with handle: %lld", handle);
    }

    return handle;
}

+ (int)receiveFromTransport:(long long)handle buffer:(NSMutableData *)buffer {
    if (!g_Initialized || !g_TouchController_Receive) {
        os_log_error(touchControllerLog, "TouchController not initialized");
        return -1;
    }

    if (handle < 0) {
        os_log_error(touchControllerLog, "Invalid transport handle: %lld", handle);
        return -1;
    }

    // 分配缓冲区
    static const int BUFFER_SIZE = 4096;
    uint8_t tempBuffer[BUFFER_SIZE];

    // 调用 JNI 接收函数
    int result = g_TouchController_Receive(handle, tempBuffer, BUFFER_SIZE);

    if (result > 0) {
        // 成功接收数据
        [buffer appendBytes:tempBuffer length:result];
        os_log_debug(touchControllerLog, "Received %d bytes from transport %lld", result, handle);
    } else if (result == 0) {
        // 无数据可用
        os_log_debug(touchControllerLog, "No data available from transport %lld", handle);
    } else {
        // 接收失败
        os_log_error(touchControllerLog, "Failed to receive from transport %lld", handle);
    }

    return result;
}

+ (BOOL)sendToTransport:(long long)handle data:(NSData *)data {
    if (!g_Initialized || !g_TouchController_Send) {
        os_log_error(touchControllerLog, "TouchController not initialized");
        return NO;
    }

    if (handle < 0) {
        os_log_error(touchControllerLog, "Invalid transport handle: %lld", handle);
        return NO;
    }

    if (!data || data.length == 0) {
        os_log_error(touchControllerLog, "No data to send");
        return NO;
    }

    // 调用 JNI 发送函数
    g_TouchController_Send(handle, [data bytes], 0, (int)[data length]);

    os_log_debug(touchControllerLog, "Sent %lu bytes to transport %lld", (unsigned long)[data length], handle);
    return YES;
}

+ (void)destroyTransport:(long long)handle {
    if (!g_Initialized || !g_TouchController_Destroy) {
        os_log_error(touchControllerLog, "TouchController not initialized");
        return;
    }

    if (handle < 0) {
        os_log_error(touchControllerLog, "Invalid transport handle: %lld", handle);
        return;
    }

    g_TouchController_Destroy(handle);
    os_log_debug(touchControllerLog, "Destroyed transport %lld", handle);
}

@end