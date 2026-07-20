#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DebugServer : NSObject

+ (instancetype)shared;

+ (NSString *)generateToken;

- (BOOL)startWithPort:(uint16_t)port
        localhostOnly:(BOOL)localhostOnly
                token:(NSString *)token;

- (void)stop;

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) uint16_t boundPort;

- (NSString *)displayURL;

@end

NS_ASSUME_NONNULL_END
