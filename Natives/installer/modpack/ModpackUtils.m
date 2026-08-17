#import "installer/FabricUtils.h"
#import "ModpackUtils.h"
#import "PLProfiles.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@implementation ModpackUtils

+ (void)archive:(UZKArchive *)archive extractDirectory:(NSString *)dir toPath:(NSString *)path error:(NSError *__autoreleasing*)error {
    [archive performOnFilesInArchive:^(UZKFileInfo *fileInfo, BOOL *stop) {
        if (![fileInfo.filename hasPrefix:dir] ||
            fileInfo.filename.length <= dir.length) {
            return;
        }
        NSString *fileName = [fileInfo.filename substringFromIndex:dir.length+1];
        NSString *destItemPath = [path stringByAppendingPathComponent:fileName];
        NSString *destDirPath = fileInfo.isDirectory ? destItemPath : destItemPath.stringByDeletingLastPathComponent;
        BOOL createdDir = [NSFileManager.defaultManager createDirectoryAtPath:destDirPath
            withIntermediateDirectories:YES
            attributes:nil error:error];
        if (!createdDir) {
            *stop = YES;
            return;
        } else if (fileInfo.isDirectory) {
            return;
        }

        NSData *data = [archive extractData:fileInfo error:error];
        BOOL written = [data writeToFile:destItemPath options:NSDataWritingAtomic error:error];
        *stop = !data || !written;
        if (!*stop) {
            NSLog(@"[ModpackDL] Extracted %@", fileInfo.filename);
        }
    } error:error];
}

+ (NSDictionary *)infoForDependencies:(NSDictionary *)dependency {
    NSMutableDictionary *info = [NSMutableDictionary new];
    NSString *minecraftVersion = dependency[@"minecraft"];
    if (dependency[@"forge"]) {
        info[@"id"] = [NSString stringWithFormat:@"%@-forge-%@", minecraftVersion, dependency[@"forge"]];
        info[@"needsManualInstall"] = @"1";
    } else if (dependency[@"neoforge"]) {
        info[@"id"] = [NSString stringWithFormat:@"neoforge-%@", dependency[@"neoforge"]];
        info[@"needsManualInstall"] = @"1";
    } else if (dependency[@"fabric-loader"]) {
        info[@"id"] = [NSString stringWithFormat:@"fabric-loader-%@-%@", dependency[@"fabric-loader"], minecraftVersion];
        info[@"json"] = [NSString stringWithFormat:FabricUtils.endpoints[@"Fabric"][@"json"], minecraftVersion, dependency[@"fabric-loader"]];
    } else if (dependency[@"quilt-loader"]) {
        info[@"id"] = [NSString stringWithFormat:@"quilt-loader-%@-%@", dependency[@"quilt-loader"], minecraftVersion];
        info[@"json"] = [NSString stringWithFormat:FabricUtils.endpoints[@"Quilt"][@"json"], minecraftVersion, dependency[@"quilt-loader"]];
    } else if (minecraftVersion.length > 0) {
        // A pack without a mod loader still targets a plain Minecraft version
        info[@"id"] = minecraftVersion;
    }
    return info;
}

+ (void)createProfileNamed:(NSString *)name gameDir:(NSString *)gameDirName versionID:(NSString *)versionID {
    // Fall back to the directory name so a pack with no name in its index still
    // produces a usable profile instead of throwing on a nil dictionary value.
    NSString *profileName = name.length > 0 ? name : gameDirName;
    NSMutableDictionary *profile = @{
        @"gameDir": [NSString stringWithFormat:@"./custom_gamedir/%@", gameDirName],
        @"name": profileName,
        @"lastVersionId": versionID.length > 0 ? versionID : @"latest-release"
    }.mutableCopy;

    // The modpack browser writes the artwork of the selected pack here. It is
    // absent for a locally imported file, in which case the profile keeps the
    // default icon rather than a stale one from an earlier install.
    NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
    NSData *iconData = [NSData dataWithContentsOfFile:tmpIconPath];
    if (iconData.length > 0) {
        profile[@"icon"] = [NSString stringWithFormat:@"data:image/png;base64,%@",
            [iconData base64EncodedStringWithOptions:0]];
    }

    PLProfiles.current.profiles[profileName] = profile;
    PLProfiles.current.selectedProfileName = profileName;
}

+ (void)warnAboutManualLoaderInstall:(NSString *)versionID {
    NSLog(@"[ModpackDL] %@ must be installed manually", versionID);
    dispatch_async(dispatch_get_main_queue(), ^{
        showDialog(localize(@"modpack.warning.title", nil),
            [NSString stringWithFormat:localize(@"modpack.warning.manual_loader", nil), versionID]);
    });
}

@end
