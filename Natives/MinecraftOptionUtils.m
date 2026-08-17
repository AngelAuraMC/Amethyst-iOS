#import "LauncherPreferences.h"
#import "MinecraftOptionUtils.h"
#import "environ.h"

@interface MinecraftOptionUtils ()
@property(nonatomic) NSMutableArray<NSString *> *lineList;
@end

@implementation MinecraftOptionUtils

+ (void)setupOptionsAtGameDir:(NSString *)gameDir {
    NSAssert(windowWidth > 0 && windowHeight > 0, @"called before setting windowWidth/windowHeight?");
    MinecraftOptionUtils *options = [MinecraftOptionUtils sharedInstance];
    options.optionsPath = [gameDir stringByAppendingPathComponent:@"options.txt"];
    // initial gui scale, also implicitly calls load
    [options updateMCGuiScale];
    [options setKey:@"fullscreen" value:@"false"];
    [options setKey:@"overrideWidth" value:@(windowWidth)];
    [options setKey:@"overrideHeight" value:@(windowHeight)];
    // Default settings for performance
    [options setDefaultForKey:@"mipmapLevels" value:@"0"];
    [options setDefaultForKey:@"particles" value:@"1"];
    [options setDefaultForKey:@"renderDistance" value:@"2"];
    [options setDefaultForKey:@"simulationDistance" value:@"5"];
    [options applyPerformancePreset];
    [options save];
}

/* Unlike the defaults above, a preset is authoritative: it rewrites these video
 * settings on every launch, so that picking one actually takes effect on a world
 * that has already been played. "off" leaves the game's own settings alone. */
- (void)applyPerformancePreset {
    NSString *preset = getPrefObject(@"video.performance_preset");
    if (![preset isKindOfClass:NSString.class] || [preset isEqualToString:@"off"]) {
        return;
    }

    int renderDistance, simulationDistance, particles, mipmapLevels, biomeBlend;
    BOOL clouds;
    if ([preset isEqualToString:@"balanced"]) {
        renderDistance = 8; simulationDistance = 8; particles = 1;
        mipmapLevels = 2; biomeBlend = 1; clouds = YES;
    } else if ([preset isEqualToString:@"performance"]) {
        renderDistance = 5; simulationDistance = 5; particles = 2;
        mipmapLevels = 0; biomeBlend = 0; clouds = NO;
    } else if ([preset isEqualToString:@"minimum"]) {
        renderDistance = 2; simulationDistance = 5; particles = 2;
        mipmapLevels = 0; biomeBlend = 0; clouds = NO;
    } else {
        NSLog(@"[Options] Unknown performance preset %@", preset);
        return;
    }

    NSLog(@"[Options] Applying the %@ performance preset", preset);
    [self setKey:@"renderDistance" value:@(renderDistance).stringValue];
    // simulationDistance exists since 1.18, mipmapLevels/biomeBlendRadius since 1.8/1.13
    [self setKey:@"simulationDistance" value:@(simulationDistance).stringValue];
    [self setKey:@"particles" value:@(particles).stringValue];
    [self setKey:@"mipmapLevels" value:@(mipmapLevels).stringValue];
    [self setKey:@"biomeBlendRadius" value:@(biomeBlend).stringValue];
    [self setKey:@"clouds" value:clouds ? @"true" : @"false"];
    [self setKey:@"entityShadows" value:@"false"];
    // graphicsMode replaced the older fancyGraphics flag in 1.17; both are set so
    // the preset applies across versions. Minecraft drops the key it does not know.
    [self setKey:@"graphicsMode" value:@"0"];
    [self setKey:@"fancyGraphics" value:@"false"];
}

+ (instancetype)sharedInstance {
    static MinecraftOptionUtils *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[MinecraftOptionUtils alloc] init];
    });

    return sharedInstance;
}

- (void)load {
    NSAssert(self.optionsPath.length, @"optionsPath is not set");
    self.lineList = [NSMutableArray array];

    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:self.optionsPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];

    if (error != nil) {
        NSLog(@"Could not load options.txt: %@", error);
        return;
    }

    // mutableCopy: setKey: mutates this in place, and componentsSeparatedBy...
    // is only documented to return an immutable array
    self.lineList = [[contents componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]] mutableCopy];
}

- (void)ensureLoaded {
    NSAssert(self.lineList != nil, @"Unitialized MinecraftOptionUtils");
}

- (void)setKey:(NSString *)key value:(NSString *)value {
    [self ensureLoaded];

    NSString *prefix = [key stringByAppendingString:@":"];

    for (NSUInteger i = 0; i < self.lineList.count; i++) {
        NSString *line = self.lineList[i];

        if ([line hasPrefix:prefix]) {
            self.lineList[i] = [NSString stringWithFormat:@"%@:%@", key, value];
            return;
        }
    }

    [self.lineList addObject:[NSString stringWithFormat:@"%@:%@", key, value]];
}

- (void)setDefaultForKey:(NSString *)key value:(NSString *)value {
    if ([self getValueForKey:key] == nil) {
        [self.lineList addObject:[NSString stringWithFormat:@"%@:%@", key, value]];
    }
}

- (nullable NSString *)getValueForKey:(NSString *)key {
    [self ensureLoaded];

    NSString *prefix = [key stringByAppendingString:@":"];

    for (NSString *line in self.lineList) {
        if ([line hasPrefix:prefix]) {
            NSRange range = [line rangeOfString:@":"];

            if (range.location != NSNotFound) {
                return [line substringFromIndex:range.location + 1];
            }
        }
    }

    return nil;
}

- (void)removeValueForKey:(NSString *)key {
    [self ensureLoaded];

    NSString *prefix = [key stringByAppendingString:@":"];

    NSIndexSet *indexes = [self.lineList indexesOfObjectsPassingTest:^BOOL(NSString *line, NSUInteger idx, BOOL *stop) {
        return [line hasPrefix:prefix];
    }];

    if (indexes.count > 0) {
        [self.lineList removeObjectsAtIndexes:indexes];
    }
}

- (void)updateMCGuiScale {
    [self load];
    guiScale = [self getValueForKey:@"guiScale"].intValue;
    //guiScale = (str == null ? 0 :Integer.parseInt(str));

    int scale = MAX(MIN(windowWidth / 320, windowHeight / 240), 1);
    if(scale < guiScale || guiScale == 0){
        guiScale = scale;
    }
}

- (void)save {
    [self ensureLoaded];

    if (self.optionsPath.length == 0) {
        NSLog(@"Could not save options.txt: optionsPath is not set");
        return;
    }

    NSString *result = [self.lineList componentsJoinedByString:@"\n"];

    NSError *error = nil;
    BOOL success = [result writeToFile:self.optionsPath
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:&error];

    if (!success) {
        NSLog(@"Could not save options.txt: %@", error);
    }

    self.lineList = nil;
}

@end
