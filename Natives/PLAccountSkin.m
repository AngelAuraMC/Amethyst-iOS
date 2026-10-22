#import "PLAccountSkin.h"

@interface PLAccountSkinEntry : NSObject
@property(nonatomic) UIImage *head;
@property(nonatomic) NSDate *refreshedAt;
@end
@implementation PLAccountSkinEntry
@end

@implementation PLAccountSkin

+ (NSString *)profileIDForAccount:(NSDictionary *)account {
    if ([account[@"username"] hasPrefix:@"Demo."]) return nil;
    NSString *profile = account[@"profileId"];
    if (![profile isKindOfClass:NSString.class]) return nil;
    profile = [[profile stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    if (profile.length != 32 || [profile rangeOfCharacterFromSet:invalid].location != NSNotFound ||
        [profile isEqualToString:@"00000000000000000000000000000000"]) return nil;
    return profile;
}

+ (NSURL *)skinURL:(id)value {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithString:[value stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"]];
    if (![url.host.lowercaseString isEqualToString:@"textures.minecraft.net"] ||
        ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString]) return nil;
    url.scheme = @"https";
    return url.URL;
}

+ (NSURL *)skinURLFromProfile:(NSDictionary *)profile {
    if (![profile isKindOfClass:NSDictionary.class] || ![profile[@"properties"] isKindOfClass:NSArray.class]) return nil;
    for (id property in profile[@"properties"]) {
        if (![property isKindOfClass:NSDictionary.class] || ![property[@"name"] isEqual:@"textures"] ||
            ![property[@"value"] isKindOfClass:NSString.class]) continue;
        NSData *data = [[NSData alloc] initWithBase64EncodedString:property[@"value"] options:0];
        id payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![payload isKindOfClass:NSDictionary.class]) continue;
        id textures = payload[@"textures"];
        id skin = [textures isKindOfClass:NSDictionary.class] ? textures[@"SKIN"] : nil;
        if ([skin isKindOfClass:NSDictionary.class]) return [self skinURL:skin[@"url"]];
    }
    return nil;
}

+ (UIImage *)headFromSkin:(UIImage *)skin {
    CGImageRef image = skin.CGImage;
    if (!image) return nil;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (width < 64 || width % 64 || (height != width && height != width / 2)) return nil;
    CGFloat scale = width / 64.0;
    CGImageRef face = CGImageCreateWithImageInRect(image, CGRectMake(8 * scale, 8 * scale, 8 * scale, 8 * scale));
    CGImageRef hat = CGImageCreateWithImageInRect(image, CGRectMake(40 * scale, 8 * scale, 8 * scale, 8 * scale));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32) format:format];
    UIImage *head = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSetInterpolationQuality(context.CGContext, kCGInterpolationNone);
        [[UIImage imageWithCGImage:face] drawInRect:CGRectMake(0, 0, 32, 32)];
        // Legacy 64x32 skins often leave the entire hat region opaque; Minecraft ignores it.
        BOOL transparentHat = NO;
        if (height != width) {
            // Decode the whole legacy hat area, matching Minecraft's opaque-hat compatibility rule.
            size_t hatWidth = 32 * scale, hatHeight = 16 * scale;
            CGImageRef hatArea = CGImageCreateWithImageInRect(image, CGRectMake(32 * scale, 0, hatWidth, hatHeight));
            NSMutableData *rgba = [NSMutableData dataWithLength:hatWidth * hatHeight * 4];
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGContextRef bitmap = CGBitmapContextCreate(rgba.mutableBytes, hatWidth, hatHeight, 8, hatWidth * 4,
                colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
            if (bitmap) {
                CGContextDrawImage(bitmap, CGRectMake(0, 0, hatWidth, hatHeight), hatArea);
                const uint8_t *bytes = rgba.bytes;
                for (size_t i = 3; i < rgba.length; i += 4) {
                    if (bytes[i] < 128) { transparentHat = YES; break; }
                }
                CGContextRelease(bitmap);
            }
            CGColorSpaceRelease(colorSpace);
            CGImageRelease(hatArea);
        }
        if (height == width || transparentHat) {
            [[UIImage imageWithCGImage:hat] drawInRect:CGRectMake(0, 0, 32, 32)];
        }
    }];
    CGImageRelease(face);
    CGImageRelease(hat);
    return head;
}

+ (NSString *)cachePath:(NSString *)profile {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"account-heads"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:[profile stringByAppendingPathExtension:@"png"]];
}

+ (UIImage *)placeholder {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32) format:format];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGContextSetInterpolationQuality(context.CGContext, kCGInterpolationNone);
            [[UIImage imageNamed:@"DefaultAccount"] drawInRect:CGRectMake(0, 0, 32, 32)];
        }];
    });
    return image;
}

+ (void)loadHeadForAccount:(NSDictionary *)account completion:(void (^)(UIImage *))completion {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self loadHeadForAccount:account completion:completion]; });
        return;
    }
    NSString *profile = [self profileIDForAccount:account];
    UIImage *placeholder = [self placeholder];
    if (!profile) { completion(placeholder); return; }

    static NSCache<NSString *, PLAccountSkinEntry *> *cache;
    static NSMutableDictionary<NSString *, NSMutableArray *> *pending;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; pending = [NSMutableDictionary new]; });
    PLAccountSkinEntry *entry = [cache objectForKey:profile];
    if (!entry) {
        entry = [PLAccountSkinEntry new];
        entry.head = [UIImage imageWithContentsOfFile:[self cachePath:profile]];
        [cache setObject:entry forKey:profile];
    }
    completion(entry.head ?: placeholder);
    if (entry.refreshedAt && -entry.refreshedAt.timeIntervalSinceNow < 300) return;
    if (pending[profile]) { [pending[profile] addObject:[completion copy]]; return; }
    pending[profile] = [NSMutableArray arrayWithObject:[completion copy]];

    void (^finish)(UIImage *) = ^(UIImage *head) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (head) {
                entry.head = head;
                entry.refreshedAt = NSDate.date;
                [UIImagePNGRepresentation(head) writeToFile:[self cachePath:profile] atomically:YES];
            }
            NSArray *callbacks = [pending[profile] copy];
            [pending removeObjectForKey:profile];
            for (void (^callback)(UIImage *) in callbacks) callback(entry.head ?: placeholder);
        });
    };
    NSString *endpoint = [@"https://sessionserver.mojang.com/session/minecraft/profile/" stringByAppendingString:profile];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:endpoint]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSURL *skin = [self skinURLFromProfile:payload] ?: [self skinURL:account[@"minecraftSkinURL"]];
        if (!skin) { finish(nil); return; }
        NSURLRequest *texture = [NSURLRequest requestWithURL:skin cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:10];
        [[NSURLSession.sharedSession dataTaskWithRequest:texture completionHandler:^(NSData *bytes, NSURLResponse *response, NSError *error) {
            finish(bytes ? [self headFromSkin:[UIImage imageWithData:bytes]] : nil);
        }] resume];
    }] resume];
}
@end
