//
//  TouchControllerPreferencesViewController.m
//  Angel Aura Amethyst
//
//  TouchController 设置页面实现
//

#import "TouchControllerPreferencesViewController.h"
#import "LauncherPreferences.h"
#import "PLPreferences.h"
#import "config.h"
#import "utils.h"

// 定义通信方式枚举
typedef NS_ENUM(NSInteger, TouchControllerCommMode) {
    TouchControllerCommModeDisabled = 0,
    TouchControllerCommModeUDP = 1,
    TouchControllerCommModeStaticLib = 2
};

@interface TouchControllerPreferencesViewController ()

@end

@implementation TouchControllerPreferencesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"preference.touchcontroller.title", nil);
    
    // 添加关闭按钮
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
}

- (void)initViewCreation {
    __weak typeof(self) weakSelf = self;

    // 确保所有选项都可见
    self.prefSectionsVisible = YES;

    // 设置偏好获取和保存块
    self.getPreference = ^id(NSString *section, NSString *key){
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        return getPrefObject(keyFull);
    };
    self.setPreference = ^(NSString *section, NSString *key, id value){
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        setPrefObject(keyFull, value);
    };

    // 调用父类初始化
    [super initViewCreation];

    // 通信方式选择
    self.typeChildPane = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        cell.textLabel.text = item[@"title"];
        NSInteger mode = [weakSelf.getPreference(section, key) integerValue];
        switch (mode) {
            case TouchControllerCommModeUDP:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.mode.udp", nil) ?: @"UDP Protocol";
                break;
            case TouchControllerCommModeStaticLib:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.mode.staticlib", nil) ?: @"Static Library";
                break;
            default:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.mode.disabled", nil) ?: @"Disabled";
                break;
        }
    };

    // 按钮类型
    self.typeButton = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        cell.textLabel.text = item[@"title"];
        cell.textLabel.textColor = weakSelf.view.tintColor;
    };

    // 滑块类型（震动强度）
    self.typeSlider = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = item[@"title"];

        // 创建滑块
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
        NSInteger value = [weakSelf.getPreference(section, key) integerValue];
        if (value < 1) value = 1;
        if (value > 3) value = 3;
        slider.value = value;
        slider.minimumValue = [item[@"min"] floatValue];
        slider.maximumValue = [item[@"max"] floatValue];
        slider.continuous = YES;

        // 设置详细文本
        switch (value) {
            case 1:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.light", nil) ?: @"Light";
                break;
            case 2:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.medium", nil) ?: @"Medium";
                break;
            case 3:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.heavy", nil) ?: @"Heavy";
                break;
            default:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.medium", nil) ?: @"Medium";
                break;
        }

        // 滑块变化处理
        [slider addTarget:weakSelf action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];

        // 将滑块添加到附件视图
        cell.accessoryView = slider;
    };

    // 开关类型
    self.typeSwitch = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        UISwitch *view = [[UISwitch alloc] init];
        NSArray *customSwitchValue = item[@"customSwitchValue"];
        if (customSwitchValue == nil) {
            [view setOn:[weakSelf.getPreference(section, key) boolValue] animated:NO];
        } else {
            id preferenceValue = weakSelf.getPreference(section, key);
            BOOL isEnabled = NO;
            if ([preferenceValue isKindOfClass:[NSString class]]) {
                isEnabled = [preferenceValue isEqualToString:customSwitchValue[1]];
            } else if ([preferenceValue isKindOfClass:[NSNumber class]]) {
                isEnabled = [preferenceValue integerValue] == [customSwitchValue[1] integerValue];
            }
            [view setOn:isEnabled animated:NO];
        }
        [view addTarget:weakSelf action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = view;
    };

    // 设置偏好设置部分
    self.prefSections = @[@"control"];

    // 配置设置内容
    self.prefContents = @[
        @[
            @{@"key": @"mod_touch_mode",
              @"icon": @"antenna.radiowaves.left.and.right",
              @"hasDetail": @YES,
              @"type": self.typeChildPane,
              @"canDismissWithSwipe": @NO,
              @"title": localize(@"preference.touchcontroller.mode.title", nil) ?: @"Communication Mode"
            },
            @{@"key": @"mod_touch_vibrate_enable",
              @"icon": @"waveform.path",
              @"type": self.typeSwitch,
              @"canDismissWithSwipe": @NO,
              @"title": localize(@"preference.touchcontroller.vibrate.enable", nil) ?: @"Enable Vibration"
            },
            @{@"key": @"mod_touch_vibrate_intensity",
              @"icon": @"speaker.wave.2",
              @"type": self.typeSlider,
              @"hasDetail": @YES,
              @"canDismissWithSwipe": @NO,
              @"min": @1,
              @"max": @3,
              @"step": @1,
              @"title": localize(@"preference.touchcontroller.vibrate.intensity", nil) ?: @"Vibration Intensity"
            },
            @{@"key": @"mod_touch_moveview_enable",
              @"icon": @"arrow.triangle.2.circlepath",
              @"type": self.typeSwitch,
              @"canDismissWithSwipe": @NO,
              @"title": localize(@"preference.touchcontroller.moveview.enable", nil) ?: @"Enable Move View"
            },
            @{@"key": @"mod_touch_about",
              @"icon": @"info.circle",
              @"type": self.typeButton,
              @"canDismissWithSwipe": @NO,
              @"action": ^void(){
                  [weakSelf showInfoAlert];
              },
              @"title": localize(@"preference.touchcontroller.about", nil) ?: @"About TouchController"
            }
        ]
    ];
}

// 滑块值变化处理
- (void)sliderValueChanged:(UISlider *)slider {
    NSInteger value = (NSInteger)round(slider.value);
    self.setPreference(@"control", @"mod_touch_vibrate_intensity", @(value));

    // 更新详细文本
    UITableViewCell *cell = (UITableViewCell *)slider.superview;
    while (cell && ![cell isKindOfClass:[UITableViewCell class]]) {
        cell = (UITableViewCell *)cell.superview;
    }

    if (cell) {
        switch (value) {
            case 1:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.light", nil) ?: @"Light";
                break;
            case 2:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.medium", nil) ?: @"Medium";
                break;
            case 3:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.heavy", nil) ?: @"Heavy";
                break;
            default:
                cell.detailTextLabel.text = localize(@"preference.touchcontroller.vibrate.intensity.medium", nil) ?: @"Medium";
                break;
        }
    }
}

- (void)updateTouchControllerSetting:(TouchControllerCommMode)mode {
    switch (mode) {
        case TouchControllerCommModeDisabled:
            // 禁用 TouchController
            self.setPreference(@"control", @"mod_touch_enable", @NO);
            self.setPreference(@"control", @"mod_touch_mode", @0);
            [self removeUDPEnvironmentVariable];
            NSLog(@"[TouchController] Disabled");
            break;

        case TouchControllerCommModeUDP:
            // 启用 UDP 模式
            self.setPreference(@"control", @"mod_touch_enable", @YES);
            self.setPreference(@"control", @"mod_touch_mode", @1);
            [self setUDPEnvironmentVariable];
            NSLog(@"[TouchController] Enabled with UDP mode");
            break;

        case TouchControllerCommModeStaticLib:
            // 启用静态库模式
            self.setPreference(@"control", @"mod_touch_enable", @YES);
            self.setPreference(@"control", @"mod_touch_mode", @2);
            [self removeUDPEnvironmentVariable];
            NSLog(@"[TouchController] Enabled with Static Library mode");
            break;
    }
}

- (void)setUDPEnvironmentVariable {
    NSString *currentEnv = getPrefObject(@"java.env_variables");
    if ([currentEnv isKindOfClass:[NSString class]]) {
        if (![currentEnv containsString:@"TOUCH_CONTROLLER_PROXY=12450"]) {
            NSString *newEnv = [currentEnv stringByAppendingString:@" TOUCH_CONTROLLER_PROXY=12450"];
            setPrefObject(@"java.env_variables", newEnv);
        }
    } else {
        setPrefObject(@"java.env_variables", @"TOUCH_CONTROLLER_PROXY=12450");
    }
}

- (void)removeUDPEnvironmentVariable {
    NSString *currentEnv = getPrefObject(@"java.env_variables");
    if ([currentEnv isKindOfClass:[NSString class]]) {
        NSString *newEnv = [currentEnv stringByReplacingOccurrencesOfString:@" TOUCH_CONTROLLER_PROXY=12450" withString:@""];
        setPrefObject(@"java.env_variables", newEnv);
    }
}

- (void)showModeSelectionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"preference.touchcontroller.select_mode.title", nil) ?: @"Select Communication Mode"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // 获取当前模式
    NSInteger currentMode = [self.getPreference(@"control", @"mod_touch_mode") integerValue];
    if (currentMode == 0) currentMode = TouchControllerCommModeDisabled;
    if (![self.getPreference(@"control", @"mod_touch_enable") boolValue]) currentMode = TouchControllerCommModeDisabled;

    // 禁用选项
    UIAlertAction *disableAction = [UIAlertAction actionWithTitle:localize(@"preference.touchcontroller.mode.disabled", nil) ?: @"Disabled"
                                                             style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [self updateTouchControllerSetting:TouchControllerCommModeDisabled];
        [self.tableView reloadData];
    }];
    if (currentMode == TouchControllerCommModeDisabled) {
        [disableAction setValue:@(YES) forKey:@"checked"];
    }
    [alert addAction:disableAction];

    // UDP 模式选项
    UIAlertAction *udpAction = [UIAlertAction actionWithTitle:localize(@"preference.touchcontroller.mode.udp", nil) ?: @"UDP Protocol"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        [self updateTouchControllerSetting:TouchControllerCommModeUDP];
        [self.tableView reloadData];
        [self showModeDescriptionAlert:TouchControllerCommModeUDP];
    }];
    if (currentMode == TouchControllerCommModeUDP) {
        [udpAction setValue:@(YES) forKey:@"checked"];
    }
    [alert addAction:udpAction];

    // 静态库模式选项
    UIAlertAction *staticLibAction = [UIAlertAction actionWithTitle:localize(@"preference.touchcontroller.mode.staticlib", nil) ?: @"Static Library"
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * _Nonnull action) {
        [self updateTouchControllerSetting:TouchControllerCommModeStaticLib];
        [self.tableView reloadData];
        [self showModeDescriptionAlert:TouchControllerCommModeStaticLib];
    }];
    if (currentMode == TouchControllerCommModeStaticLib) {
        [staticLibAction setValue:@(YES) forKey:@"checked"];
    }
    [alert addAction:staticLibAction];

    // 取消按钮
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"preference.touchcontroller.cancel", nil) ?: @"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    // iPad 支持
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showModeDescriptionAlert:(TouchControllerCommMode)mode {
    NSString *title, *message;

    switch (mode) {
        case TouchControllerCommModeUDP:
            title = localize(@"preference.touchcontroller.udp.title", nil) ?: @"UDP Protocol Mode";
            message = localize(@"preference.touchcontroller.udp.message", nil) ?: @"TouchController will communicate via UDP port 12450. This mode is compatible with most servers and provides stable network communication.";
            break;

        case TouchControllerCommModeStaticLib:
            title = localize(@"preference.touchcontroller.staticlib.title", nil) ?: @"Static Library Mode";
            message = localize(@"preference.touchcontroller.staticlib.message", nil) ?: @"TouchController will use native static library for high-performance local communication via Unix Domain Socket. This mode provides better performance but requires the static library to be linked.";
            break;

        default:
            return;
    }

    UIAlertController *infoAlert = [UIAlertController alertControllerWithTitle:title
                                                                         message:message
                                                                  preferredStyle:UIAlertControllerStyleAlert];

    [infoAlert addAction:[UIAlertAction actionWithTitle:localize(@"preference.touchcontroller.ok", nil) ?: @"OK"
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];

    [self presentViewController:infoAlert animated:YES completion:nil];
}

- (void)showInfoAlert {
    UIAlertController *infoAlert = [UIAlertController alertControllerWithTitle:localize(@"preference.touchcontroller.about.title", nil) ?: @"About TouchController"
                                                                         message:localize(@"preference.touchcontroller.about.message", nil) ?: @"TouchController is a Minecraft mod that adds touch controls to Java Edition. This launcher supports two communication modes:\n\n• UDP Protocol: Network-based communication\n• Static Library: High-performance local communication\n\nVisit GitHub for more information."
                                                                  preferredStyle:UIAlertControllerStyleAlert];

    [infoAlert addAction:[UIAlertAction actionWithTitle:localize(@"preference.touchcontroller.ok", nil) ?: @"OK"
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];

    [infoAlert addAction:[UIAlertAction actionWithTitle:@"GitHub"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/TouchController/TouchController"]
                                            options:@{}
                                  completionHandler:nil];
    }]];

    [self presentViewController:infoAlert animated:YES completion:nil];
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *key = self.prefContents[indexPath.section][indexPath.row][@"key"];
    if ([key isEqualToString:@"mod_touch_mode"]) {
        [self showModeSelectionAlert];
    } else if ([key isEqualToString:@"mod_touch_about"]) {
        [self showInfoAlert];
    }
}

#pragma mark - Close Button Action

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
