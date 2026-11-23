#import <Foundation/Foundation.h>
#import "ExperimentalViewController.h"
#import "LauncherPreferences.h"
#import "PLLogOutputView.h"
#import "utils.h"

@interface ExperimentalViewController ()
@end

@implementation ExperimentalViewController

- (id)init {
    self = [super init];
    self.title = localize(@"launcher.menu.experimental", @"Experimental");
    return self;
}

- (NSString *)imageName {
    return @"flask";
}

- (void)viewDidLoad {
    self.getPreference = ^id(NSString *section, NSString *key) {
        NSString *fullKey = [NSString stringWithFormat:@"experimental.%@", key];
        id val = getPrefObject(fullKey);
        if ([key isEqualToString:@"log_text_size"]) {
            int intVal = val ? [val intValue] : 5;
            if (intVal < 1 || intVal > 9) return @(5);
            return @(intVal);
        }
        return val;
    };

    self.setPreference = ^(NSString *section, NSString *key, id value) {
        NSString *fullKey = [NSString stringWithFormat:@"experimental.%@", key];
        setPrefObject(fullKey, value);
    };

    self.hasDetail = YES;
    self.prefDetailVisible = YES;

    self.prefSections = @[@"diagnostics", @"renderer_opt", @"runtime_exp", @"reset"];

    __weak typeof(self) weakSelf = self;
    void(^resetAction)(void) = ^{
        setPrefBool(@"experimental.benchmark", NO);
        setPrefBool(@"experimental.fps_log", NO);
        setPrefBool(@"experimental.shader_error_log", NO);
        setPrefInt(@"experimental.log_text_size", 5);
        [PLLogOutputView updateLogTextSize:5];
        setPrefObject(@"experimental.draw_batching", @"default");
        setPrefObject(@"experimental.use_vbo", @"default");
        setPrefObject(@"experimental.mipmap_mode", @"default");
        setPrefBool(@"experimental.no_shader_lod", NO);
        setPrefObject(@"experimental.shrink_texture", @"default");
        setPrefBool(@"experimental.no_vao_cache", NO);
        setPrefBool(@"experimental.low_stutter_jvm", NO);
        setPrefObject(@"experimental.adaptive_render_scale", @"unsupported");
        [weakSelf.tableView reloadData];
    };

    self.prefContents = @[
        @[
            // Diagnostics & Metrics
            @{@"icon": @"waveform.path.ecg"},
            @{
                @"key": @"benchmark",
                @"hasDetail": @YES,
                @"icon": @"speedometer",
                @"type": self.typeSwitch
            },
            @{
                @"key": @"fps_log",
                @"hasDetail": @YES,
                @"icon": @"chart.bar.xaxis",
                @"type": self.typeSwitch
            },
            @{
                @"key": @"shader_error_log",
                @"hasDetail": @YES,
                @"icon": @"exclamationmark.bubble",
                @"type": self.typeSwitch
            },
            @{
                @"key": @"log_text_size",
                @"hasDetail": @YES,
                @"icon": @"textformat.size",
                @"type": self.typeSlider,
                @"min": @(1),
                @"max": @(9),
                @"action": ^(int val) {
                    [PLLogOutputView updateLogTextSize:val];
                }
            }
        ],
        @[
            // Engine & Runtime
            @{@"icon": @"gearshape.2"},
            @{
                @"key": @"low_stutter_jvm",
                @"hasDetail": @YES,
                @"icon": @"bolt.badge.clock",
                @"type": self.typeSwitch
            },
            @{
                @"key": @"adaptive_render_scale",
                @"hasDetail": @YES,
                @"icon": @"viewfinder",
                @"type": self.typePickField,
                @"pickKeys": @[@"unsupported"],
                @"pickList": @[@"Deferred (Under Research)"]
            }
        ],
        @[
            // Reset to Safe Defaults
            @{@"icon": @"arrow.counterclockwise"},
            @{
                @"key": @"reset_defaults",
                @"hasDetail": @YES,
                @"icon": @"arrow.counterclockwise.circle",
                @"type": self.typeButton,
                @"destructive": @YES,
                @"showConfirmPrompt": @YES,
                @"action": resetAction
            }
        ]
    ];

    [super viewDidLoad];
}

@end
