#import "config.h"
#import "utils.h"
#import "LauncherPreferences.h"
#import "PLPreferences.h"
#import "UIKit+hook.h"
#import <CoreFoundation/CoreFoundation.h>

static PLPreferences* pref;

void loadPreferences(BOOL reset) {
    assert(getenv("POJAV_HOME"));
    if (reset) {
        [pref reset];
    } else {
        pref = [[PLPreferences alloc] initWithAutomaticMigrator];
    }
}

void toggleIsolatedPref(BOOL forceEnable) {
    if (!pref.instancePath) {
        pref.instancePath = [NSString stringWithFormat:@"%s/launcher_preferences.plist", getenv("POJAV_GAME_DIR")];
    }
    [pref toggleIsolationForced:forceEnable];
}

id getPrefObject(NSString *key) {
    return [pref getObject:key];
}
BOOL getPrefBool(NSString *key) {
    return [getPrefObject(key) boolValue];
}
float getPrefFloat(NSString *key) {
    return [getPrefObject(key) floatValue];
}
NSInteger getPrefInt(NSString *key) {
    return [getPrefObject(key) intValue];
}

void setPrefObject(NSString *key, id value) {
    [pref setObject:key value:value];
}
void setPrefBool(NSString *key, BOOL value) {
    setPrefObject(key, @(value));
}
void setPrefFloat(NSString *key, float value) {
    setPrefObject(key, @(value));
}
void setPrefInt(NSString *key, NSInteger value) {
    setPrefObject(key, @(value));
}

void resetWarnings() {
    for (int i = 0; i < pref.globalPref[@"warnings"].count; i++) {
        NSString *key = pref.globalPref[@"warnings"].allKeys[i];
        pref.globalPref[@"warnings"][key] = @YES;
    }
}

#pragma mark Safe area

CGRect getSafeArea(CGRect screenBounds) {
    UIEdgeInsets safeArea = UIEdgeInsetsFromString(getPrefObject(@"control.control_safe_area"));
    if (screenBounds.size.width < screenBounds.size.height) {
        safeArea = UIEdgeInsetsMake(safeArea.right, safeArea.top, safeArea.left, safeArea.bottom);
    }
    return UIEdgeInsetsInsetRect(screenBounds, safeArea);
}

void setSafeArea(CGSize screenSize, CGRect frame) {
    UIEdgeInsets safeArea;
    // TODO: make safe area consistent across opposite orientations?
    if (screenSize.width < screenSize.height) {
        safeArea = UIEdgeInsetsMake(
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame),
            frame.origin.y);
    } else {
        safeArea = UIEdgeInsetsMake(
            frame.origin.y,
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame));
    }
    setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(safeArea));
}

UIEdgeInsets getDefaultSafeArea() {
    UIEdgeInsets safeArea = UIApplication.sharedApplication.windows.firstObject.safeAreaInsets;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    if (screenSize.width < screenSize.height) {
        safeArea.left = safeArea.top;
        safeArea.right = safeArea.bottom;
    }
    safeArea.top = safeArea.bottom = 0;
    return safeArea;
}

#pragma mark Java runtime

// Finds a runtime bundled inside the app that satisfies minVersion. Runtimes
// ship as java_runtimes/java-<major>-openjdk, and the app can carry ones that
// java_homes does not list, so they are discovered rather than assumed.
static NSString* findInternalJavaHome(int minVersion) {
    NSString *internalPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"java_runtimes"];
    NSArray *runtimes = [NSFileManager.defaultManager contentsOfDirectoryAtPath:internalPath error:nil];
    NSString *bestPath;
    int bestVersion = 0;
    for (NSString *runtime in runtimes) {
        if (![runtime hasPrefix:@"java-"] || ![runtime hasSuffix:@"-openjdk"]) {
            continue;
        }
        int version = [runtime substringFromIndex:@"java-".length].intValue;
        // Prefer the oldest runtime that is still new enough
        if (version >= minVersion && (bestVersion == 0 || version < bestVersion)) {
            bestVersion = version;
            bestPath = [internalPath stringByAppendingPathComponent:runtime];
        }
    }
    if (bestPath) {
        NSLog(@"[JavaRuntime] Falling back to bundled Java %d for requested Java >= %d", bestVersion, minVersion);
    }
    return bestPath;
}

NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion) {
    NSDictionary *pref = getPrefObject(@"java.java_homes");
    NSDictionary<NSString *, NSString *> *selected = pref[@"0"];
    NSString *selectedVer = selected[defaultJRETag];
    if (minVersion > selectedVer.intValue) {
        NSArray *sortedVersions = [pref.allKeys valueForKeyPath:@"self.integerValue"];
        sortedVersions = [sortedVersions sortedArrayUsingSelector:@selector(compare:)];
        // The tag's runtime is too old, so it must not be kept as the fallback
        selectedVer = nil;
        for (NSNumber *version in sortedVersions) {
            if (version.intValue >= minVersion) {
                selectedVer = version.stringValue;
                break;
            }
        }
        if (!selectedVer) {
            // A runtime shipped with the app may still satisfy the request even
            // when it is absent from java_homes
            NSString *internalDir = findInternalJavaHome(minVersion);
            if (internalDir) {
                return internalDir;
            }
            NSLog(@"Error: requested Java >= %d was not installed!", minVersion);
            return nil;
        }
    }

    id selectedDir = pref[selectedVer];
    if ([selectedDir isEqualToString:@"internal"]) {
        selectedDir = [NSString stringWithFormat:@"%@/java_runtimes/java-%@-openjdk", NSBundle.mainBundle.bundlePath, selectedVer];
    } else {
        selectedDir = [NSString stringWithFormat:@"%s/java_runtimes/%@", getenv("POJAV_HOME"), selectedDir];
    }

    if ([NSFileManager.defaultManager fileExistsAtPath:selectedDir]) {
        return selectedDir;
    } else {
        NSLog(@"Error: selected runtime for %@ does not exist: %@", defaultJRETag, selectedDir);
        return nil;
    }
}

#pragma mark Renderer
NSArray* getRendererKeys(BOOL containsDefault) {
    NSMutableArray *array = @[
        @"auto",
        @ RENDERER_NAME_GL4ES,
        @ RENDERER_NAME_MTL_ANGLE,
        @ RENDERER_NAME_MOBILEGLUES,
        @ RENDERER_NAME_VK_ZINK
    ].mutableCopy;

    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }
    
    return array;
}

NSArray* getRendererNames(BOOL containsDefault) {
    NSMutableArray *array;

    array = @[
        localize(@"preference.title.renderer.debug.auto", nil),
        localize(@"preference.title.renderer.debug.gl4es", nil),
        localize(@"preference.title.renderer.debug.angle", nil),
        localize(@"preference.title.renderer.debug.mg", nil),
        localize(@"preference.title.renderer.debug.zink", nil)
    ].mutableCopy;

    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }

    return array;
}

#pragma mark Performance

NSArray* getPerformancePresetKeys(void) {
    return @[@"off", @"balanced", @"performance", @"minimum"];
}

NSArray* getPerformancePresetNames(void) {
    return @[
        localize(@"preference.title.performance_preset.off", nil),
        localize(@"preference.title.performance_preset.balanced", nil),
        localize(@"preference.title.performance_preset.performance", nil),
        localize(@"preference.title.performance_preset.minimum", nil)
    ];
}

NSArray* getGCTypeKeys(void) {
    return @[@"default", @"serial", @"parallel"];
}

NSArray* getGCTypeNames(void) {
    return @[
        localize(@"preference.title.gc_type.default", nil),
        localize(@"preference.title.gc_type.serial", nil),
        localize(@"preference.title.gc_type.parallel", nil)
    ];
}
