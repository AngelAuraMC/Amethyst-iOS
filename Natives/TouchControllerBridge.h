//
//  TouchControllerBridge.h
//  Angel Aura Amethyst
//
//  TouchController JNI 桥接头文件
//  提供 Minecraft TouchController Mod 与 iOS 启动器之间的通信接口
//

#ifndef TouchControllerBridge_h
#define TouchControllerBridge_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * TouchController 桥接类
 * 负责管理 TouchController 静态库的初始化和通信
 */
@interface TouchControllerBridge : NSObject

/**
 * 初始化 TouchController 桥接
 * @return 初始化是否成功
 */
+ (BOOL)initializeTouchController;

/**
 * 创建新的 TouchController 传输对象
 * @param name 传输对象名称（Unix Domain Socket 路径）
 * @return 传输对象句柄（如果失败返回 -1）
 */
+ (long long)createTransportWithName:(NSString *)name;

/**
 * 从 TouchController 接收数据
 * @param handle 传输对象句柄
 * @param buffer 接收缓冲区
 * @return 接收的字节数（如果无数据返回 0，如果失败返回 -1）
 */
+ (int)receiveFromTransport:(long long)handle buffer:(NSMutableData *)buffer;

/**
 * 向 TouchController 发送数据
 * @param handle 传输对象句柄
 * @param data 要发送的数据
 * @return 发送是否成功
 */
+ (BOOL)sendToTransport:(long long)handle data:(NSData *)data;

/**
 * 销毁 TouchController 传输对象
 * @param handle 传输对象句柄
 */
+ (void)destroyTransport:(long long)handle;

/**
 * 检查 TouchController 是否可用
 * @return TouchController 是否已正确初始化
 */
+ (BOOL)isTouchControllerAvailable;

@end

#ifdef __cplusplus
}
#endif

#endif /* TouchControllerBridge_h */