// Real menu, split controller, account list and skin loader; unrelated services are stubbed.
#import <UIKit/UIKit.h>
#import "LauncherMenuViewController.h"
#import "LauncherSplitViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherProfilesViewController.h"
#import "LauncherNewsViewController.h"
#import "LauncherPreferencesViewController.h"
#import "AccountListViewController.h"
#import "authenticator/BaseAuthenticator.h"
#import "ALTServerConnection.h"
#import "PLAccountSkin.h"

static BaseAuthenticator *current;
static NSMutableArray *checks;
static NSMutableDictionary *metrics;
static NSUInteger profileRequests, textureRequests;
static BOOL offline;
static UIWindow *testWindow;
static NSString *const firstID = @"11111111111111111111111111111111";
static NSString *const secondID = @"22222222222222222222222222222222";

// Match the launcher's production UIKit hooks, which keep both size classes regular.
@implementation UITraitCollection (LauncherTesting)
- (UIUserInterfaceSizeClass)horizontalSizeClass { return UIUserInterfaceSizeClassRegular; }
- (UIUserInterfaceSizeClass)verticalSizeClass { return UIUserInterfaceSizeClassRegular; }
@end

@interface ReusingTable : UITableView
@property(nonatomic) UITableViewCell *reusedCell;
@end
@implementation ReusingTable
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier { return self.reusedCell; }
@end

NSString *localize(NSString *key, NSString *comment) { return NSLocalizedString(key, nil); }
id getPrefObject(NSString *key) { return [key isEqual:@"internal.selected_account"] ? current.authData[@"username"] : @"configured"; }
BOOL getPrefBool(NSString *key) { return [key isEqual:@"general.hidden_sidebar"]; }
BOOL getEntitlementValue(NSString *key) { return YES; }
BOOL isJITEnabled(BOOL check) { return YES; }
UIEdgeInsets getDefaultSafeArea(void) { return UIEdgeInsetsZero; }
void setPrefObject(NSString *key, id value) {}
void setPrefBool(NSString *key, BOOL value) {}
void openLink(UIViewController *vc, NSURL *url) {}
void showDialog(NSString *title, NSString *message) {}
void customNSLog(const char *file, int line, const char *function, NSString *format, ...) {}
NSMutableDictionary *parseJSONFromFile(NSString *path) { return [[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:NSJSONReadingMutableContainers error:nil] mutableCopy]; }

@implementation BaseAuthenticator
+ (id)current { return current; }
+ (void)setCurrent:(BaseAuthenticator *)value { current = value; }
@end
@implementation LocalAuthenticator @end
@implementation MicrosoftAuthenticator @end
#ifdef LAUNCHER_BASELINE
@implementation LauncherMenuViewController (BaselineLayout)
- (void)layoutAccountButton {}
@end
#endif
@implementation ALTServerManager
+ (ALTServerManager *)sharedManager { return nil; }
@end
@implementation ALTServerConnection @end
@implementation PLPrefTableViewController @end
@implementation LauncherNewsViewController
- (NSString *)imageName { return @"MenuNews"; }
@end
@implementation LauncherPreferencesViewController
- (NSString *)imageName { return @"MenuSettings"; }
@end
@implementation LauncherNavigationController
- (void)fetchLocalVersionList {}
- (void)reloadProfileList {}
@end
@implementation LauncherProfilesViewController
- (instancetype)init { if ((self = [super init])) self.title = @"Profiles"; return self; }
- (NSString *)imageName { return @"MenuProfiles"; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    LauncherMenuViewController *menu = (id)[(UINavigationController *)self.splitViewController.viewControllers[0] viewControllers][0];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:nil action:nil];
    if (@available(iOS 26.0, *)) add.sharesBackground = NO;
    self.navigationItem.rightBarButtonItems = @[[menu drawAccountButton], add];
}
@end

@interface PLAccountSkin (Testing)
+ (UIImage *)headFromSkin:(UIImage *)image;
+ (NSURL *)skinURLFromProfile:(NSDictionary *)profile;
@end

static UIImage *skinFixture(BOOL second, BOOL legacy, BOOL opaqueHat) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, legacy ? 32 : 64) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        if (opaqueHat) { [UIColor.blueColor setFill]; UIRectFill(CGRectMake(32, 0, 32, 16)); }
        [(second ? UIColor.greenColor : UIColor.redColor) setFill]; UIRectFill(CGRectMake(8, 8, 8, 8));
        if (!opaqueHat) { [UIColor.yellowColor setFill]; UIRectFill(CGRectMake(40, 8, 4, 4)); }
    }];
}
static BOOL pixelMatches(UIImage *image, NSUInteger x, NSUInteger y, NSUInteger r, NSUInteger g, NSUInteger b) {
    if (!image) return NO;
    size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image.CGImage);
    const uint8_t *bytes = data.bytes; NSUInteger index = (y * width + x) * 4;
    BOOL matches = abs(bytes[index] - (int)r) < 3 && abs(bytes[index + 1] - (int)g) < 3 && abs(bytes[index + 2] - (int)b) < 3;
    CGContextRelease(context); CGColorSpaceRelease(space); return matches;
}

@interface SkinProtocol : NSURLProtocol
@property BOOL stopped;
@end
@implementation SkinProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [@[@"sessionserver.mojang.com", @"textures.minecraft.net"] containsObject:request.URL.host]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    BOOL profile = [self.request.URL.host isEqual:@"sessionserver.mojang.com"];
    BOOL second = [self.request.URL.lastPathComponent isEqual:secondID];
    if (profile) profileRequests++; else textureRequests++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (second ? 400 : 150) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (self.stopped) return;
        if (offline) { [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]]; return; }
        NSData *data;
        if (profile) {
            NSDictionary *textures = @{@"textures": @{@"SKIN": @{@"url": [@"http://textures.minecraft.net/texture/" stringByAppendingString:second ? secondID : firstID]}}};
            NSString *value = [[NSJSONSerialization dataWithJSONObject:textures options:0 error:nil] base64EncodedStringWithOptions:0];
            data = [NSJSONSerialization dataWithJSONObject:@{@"properties": @[@{@"name": @"textures", @"value": value}]} options:0 error:nil];
        } else data = UIImagePNGRepresentation(skinFixture(second, NO, NO));
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": profile ? @"application/json" : @"image/png"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading { self.stopped = YES; }
@end

static NSString *documents(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject; }
static void report(NSString *failure) {
    NSDictionary *result = @{@"passed": @(failure == nil), @"checks": checks, @"metrics": metrics, @"failure": failure ?: @""};
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[documents() stringByAppendingPathComponent:@"ui-test.json"] atomically:YES];
}
static void require(BOOL condition, NSString *message) { if (!condition) { report(message); exit(1); } [checks addObject:message]; }
static void after(NSTimeInterval seconds, void (^block)(void)) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC), dispatch_get_main_queue(), block); }
static void screenshot(NSString *name) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:testWindow.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { [testWindow drawViewHierarchyInRect:testWindow.bounds afterScreenUpdates:YES]; }];
    [UIImagePNGRepresentation(image) writeToFile:[documents() stringByAppendingPathComponent:name] atomically:YES];
}
static NSArray<UIButton *> *leftButtons(UIView *view, UINavigationBar *bar) {
    NSMutableArray *result = [NSMutableArray new];
    for (UIView *child in view.subviews) {
        if (child.hidden || child.alpha < 0.1) continue;
        CGRect frame = [child convertRect:child.bounds toView:bar];
        if ([child isKindOfClass:UIButton.class] && frame.size.width > 0 && CGRectGetMidX(frame) < bar.bounds.size.width / 3) [result addObject:child];
        else [result addObjectsFromArray:leftButtons(child, bar)];
    }
    return result;
}

static void runTests(LauncherSplitViewController *split) {
    LauncherMenuViewController *menu = (id)[(UINavigationController *)split.viewControllers[0] viewControllers][0];
    [menu loadViewIfNeeded];
    UINavigationController *detail = split.viewControllers[1];
    [menu tableView:menu.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    [menu tableView:menu.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    [testWindow layoutIfNeeded];
    [detail.navigationBar layoutIfNeeded];
    NSArray *buttons = leftButtons(detail.navigationBar, detail.navigationBar);
    metrics[@"leftButtonCount"] = @(buttons.count);
    metrics[@"accountButtonFrame"] = NSStringFromCGRect(menu.accountButton.frame);
    metrics[@"titleFrame"] = NSStringFromCGRect(menu.accountButton.titleLabel.frame);
    metrics[@"titleMeasuredWidth"] = @([menu.accountButton.currentAttributedTitle size].width);
    screenshot(@"initial.png");
#ifdef LAUNCHER_BASELINE
    require(detail.topViewController.navigationItem.leftBarButtonItem != nil, @"Baseline inserts unsupported legacy sidebar item");
    require(detail.topViewController.navigationItem.leftBarButtonItem.image == nil &&
        detail.topViewController.navigationItem.leftBarButtonItem.title.length == 0, @"Legacy sidebar item has no icon or title");
    report(nil);
    return;
#endif
    require(detail.topViewController.navigationItem.leftBarButtonItem == nil, @"Column split has no unsupported legacy sidebar item");
    require(buttons.count == 1, @"Exactly one visible left navigation button");
    require(menu.accountButton.titleLabel.numberOfLines == 2, @"Account has two explicit title lines");
    if (detail.view.bounds.size.width > 600) {
        require(menu.accountButton.titleLabel.bounds.size.width + 0.5 >= [menu.accountButton.currentAttributedTitle size].width, @"Complete Minecraft name and Xbox gamertag fit without clipping");
        require([menu.accountButton.currentAttributedTitle.string isEqual:@"MinecraftPlayer\nXboxPlayer3844"], @"Both account names remain complete");
    }
    require(menu.accountButton.imageView.bounds.size.width == 32 && menu.accountButton.imageView.bounds.size.height == 32, @"Avatar has a fixed 32-point size");
    require(pixelMatches(menu.accountButton.currentImage, 24, 24, 255, 0, 0), @"Toolbar displays the downloaded player's face");
    require(pixelMatches(menu.accountButton.currentImage, 4, 4, 255, 255, 0), @"Toolbar displays the player's hat layer");
    require(CGSizeEqualToSize([PLAccountSkin headFromSkin:skinFixture(NO, YES, YES)].size, CGSizeMake(32, 32)), @"Legacy 64x32 skin is supported");
    require(pixelMatches([PLAccountSkin headFromSkin:skinFixture(NO, YES, YES)], 4, 4, 255, 0, 0), @"Fully opaque legacy hat region is ignored");
    require(pixelMatches([PLAccountSkin headFromSkin:skinFixture(NO, NO, YES)], 4, 4, 0, 0, 255), @"Opaque modern hat is preserved");
    require([PLAccountSkin headFromSkin:[UIImage imageNamed:@"DefaultAccount"]] == nil, @"Non-skin image is rejected");
    require([PLAccountSkin skinURLFromProfile:@{@"properties": @[@{@"name": @"textures", @"value": @"invalid"}]}] == nil, @"Malformed texture metadata is handled");
    NSUInteger requests = profileRequests;
    [PLAccountSkin loadHeadForAccount:current.authData completion:^(UIImage *head) { require(NSThread.isMainThread, @"Cached head callback is on the main thread"); }];
    require(requests == profileRequests, @"Repeated refresh uses the fresh cached skin");
    // Use the actual account list and verify account switching cannot accept a late image.
    AccountListViewController *accounts = [AccountListViewController new]; [accounts loadViewIfNeeded];
    [accounts setValue:[NSMutableArray arrayWithObjects:current.authData, @{@"username": @"Other", @"xboxGamertag": @"OtherXbox", @"profileId": secondID}, nil] forKey:@"accountList"];
    UITableViewCell *cell = [accounts tableView:accounts.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    require(pixelMatches(cell.imageView.image, 24, 24, 255, 0, 0), @"Account picker uses the same real head");
    ReusingTable *table = [ReusingTable new]; table.reusedCell = cell; accounts.tableView = table;
    [accounts tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    [accounts tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    UIImage *addImage = cell.imageView.image;
    require(cell.detailTextLabel.text == nil, @"Reused add-account row clears the previous gamertag");
    current.authData = [@{@"username": @"Other", @"xboxGamertag": @"OtherXbox", @"profileId": secondID} mutableCopy];
    [menu updateAccountInfo];
    current.authData = [@{@"username": @"MinecraftPlayer", @"xboxGamertag": @"XboxPlayer3844", @"profileId": firstID} mutableCopy];
    [menu updateAccountInfo];
    UIButton *sidebar = buttons.firstObject;
    CGPoint center = [sidebar convertPoint:CGPointMake(CGRectGetMidX(sidebar.bounds), CGRectGetMidY(sidebar.bounds)) toView:testWindow];
    UIView *hit = [testWindow hitTest:center withEvent:nil];
    require([hit isDescendantOfView:sidebar] || [sidebar isDescendantOfView:hit], @"System sidebar control passes hit testing");
    // UIKit's sidebar uses an internal interaction, rather than UIControl target/action events.
    [split showColumn:UISplitViewControllerColumnPrimary];
    after(0.8, ^{
        require(split.displayMode != UISplitViewControllerDisplayModeSecondaryOnly, @"System primary-column action opens the menu");
        screenshot(@"sidebar-open.png");
        [split hideColumn:UISplitViewControllerColumnPrimary];
        after(0.6, ^{
            require(pixelMatches(menu.accountButton.currentImage, 24, 24, 255, 0, 0), @"Late download from previous account cannot replace current head");
            require(cell.imageView.image == addImage, @"Late skin download cannot overwrite a reused add-account row");
            // Disk fallback works even in a fresh memory-cache entry while offline.
            NSString *third = @"33333333333333333333333333333333";
            NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"account-heads"];
            [UIImagePNGRepresentation(menu.accountButton.currentImage) writeToFile:[[cache stringByAppendingPathComponent:third] stringByAppendingPathExtension:@"png"] atomically:YES];
            offline = YES;
            [PLAccountSkin loadHeadForAccount:@{@"username": @"Saved", @"profileId": third} completion:^(UIImage *head) { require(pixelMatches(head, 24, 24, 255, 0, 0), @"Offline load retains the head saved on disk"); }];
            NSUInteger before = profileRequests;
            [PLAccountSkin loadHeadForAccount:@{@"username": @"Local", @"profileId": @"00000000-0000-0000-0000-000000000000"} completion:^(UIImage *head) {}];
            [PLAccountSkin loadHeadForAccount:@{@"username": @"Demo.Player", @"profileId": firstID} completion:^(UIImage *head) {}];
            require(before == profileRequests, @"Local and demo accounts make no skin requests");
            after(0.4, ^{
                screenshot(@"final.png"); report(nil);
            });
        });
    });
}

@interface TestApp : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation TestApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    checks = [NSMutableArray new]; metrics = [NSMutableDictionary new];
    [NSURLProtocol registerClass:SkinProtocol.class];
    setenv("AME_HOME", [documents() UTF8String], 1);
    current = [BaseAuthenticator new]; current.authData = [@{@"username": @"MinecraftPlayer", @"xboxGamertag": @"XboxPlayer3844", @"profileId": firstID} mutableCopy];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; testWindow = self.window;
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    LauncherSplitViewController *split = [[LauncherSplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
    self.window.rootViewController = split; [self.window makeKeyAndVisible];
    after(2, ^{ runTests(split); });
    return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(TestApp.class)); } }
