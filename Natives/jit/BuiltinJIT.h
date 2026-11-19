#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const BuiltinJITStatusDidChangeNotification;

@interface BuiltinJIT : NSObject
@property(class, nonatomic, readonly) BuiltinJIT *shared;
@property(nonatomic, readonly) BOOL busy;
@property(nonatomic, readonly) BOOL pairing;
@property(nonatomic, readonly) BOOL hasPairingFile;
@property(nonatomic, readonly, nullable) NSString *pairingFileName;
@property(nonatomic, readonly) NSString *status;
@property(nonatomic, readonly, nullable) NSNumber *txmPresent;

+ (nullable NSString *)unavailableReason;
+ (nullable NSString *)onDevicePairingUnavailableReason;
- (void)startOnDevicePairingWithCompletion:(void (^)(NSError * _Nullable error))completion;
- (void)cancelOnDevicePairing;
- (BOOL)importPairingFile:(NSURL *)url error:(NSError **)error;
- (BOOL)removePairingFile:(NSError **)error;
- (void)prepareWithCompletion:(void (^)(NSError * _Nullable error))completion;
- (void)resetDDIWithCompletion:(void (^)(NSError * _Nullable error))completion;
// The ready callback runs when the host can start its existing JIT protocol.
// Keep the extension request alive until that protocol's script detaches.
- (void)enableWithReadyHandler:(void (^)(NSError * _Nullable error))handler;
- (void)cancelPendingEnable;
@end

NS_ASSUME_NONNULL_END
