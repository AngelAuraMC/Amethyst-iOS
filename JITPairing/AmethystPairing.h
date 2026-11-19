#import <Foundation/Foundation.h>

// Loaded only by supported iOS device builds. The host does not link this
// framework, so other targets and older iOS versions keep their current setup.
@protocol AmethystPairingSession <NSObject>
- (void)startWithProgress:(void (^)(NSString *stage, NSString *value))progress
              completion:(void (^)(NSData *record, NSError *error))completion;
- (void)cancel;
@end
