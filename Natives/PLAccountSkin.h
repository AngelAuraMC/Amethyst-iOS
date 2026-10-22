#import <UIKit/UIKit.h>

@interface PLAccountSkin : NSObject
// Delivers the cached head first, then the refreshed head, on the main queue.
// Local/demo accounts use the bundled placeholder and make no network requests.
+ (void)loadHeadForAccount:(NSDictionary *)account completion:(void (^)(UIImage *head))completion;
@end
