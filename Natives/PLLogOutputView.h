#import <UIKit/UIKit.h>

@interface PLLogOutputView : UIView
@property(nonatomic) UINavigationController *navController;
- (void)actionStartStopLogOutput;
- (void)actionToggleLogOutput;
+ (void)appendToLog:(NSString *)line;
+ (void)handleExitCode:(int)code;
@end
