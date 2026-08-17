#import <UIKit/UIKit.h>

@interface ForgeInstallViewController : UITableViewController

// Maven endpoints keyed by vendor name ("Forge", "NeoForge"), each holding an
// "installer" URL format taking the version string, and a "metadata" URL.
+ (NSDictionary *)endpoints;

@end
