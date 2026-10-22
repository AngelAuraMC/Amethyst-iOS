#import <UIKit/UIKit.h>

@interface ModrinthModsViewController : UITableViewController <UISearchBarDelegate>
- (NSString *)imageName;
- (NSString *)contentType;
@end

@interface LauncherResourcePacksViewController : ModrinthModsViewController @end
@interface LauncherShaderPacksViewController : ModrinthModsViewController @end
