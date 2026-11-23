#import <UIKit/UIKit.h>

@interface PLLogOutputView : UIView
@property(nonatomic) UINavigationController *navController;
- (void)actionStartStopLogOutput;
- (void)actionToggleLogOutput;
+ (void)appendToLog:(NSString *)line;
+ (BOOL)handleExitCode:(int)code;
+ (void)updateLogTextSize:(int)level;
+ (int)currentLogTextSizeLevel;
+ (CGFloat)fontSizeForLevel:(int)level;
+ (CGFloat)rowHeightForLevel:(int)level;
+ (UIFont *)logFontForLevel:(int)level;
@end
