#import "AFNetworking.h"
#import "LauncherNavigationController.h"
#import "installer/FabricUtils.h"
#import "installer/ForgeInstallViewController.h"
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
        // The Forge maven lays installers out as <mc>-<forge>, unlike the version id
        info[@"loaderVendor"] = @"Forge";
        info[@"loaderVersion"] = [NSString stringWithFormat:@"%@-%@", minecraftVersion, dependency[@"forge"]];
    } else if (dependency[@"neoforge"]) {
        info[@"id"] = [NSString stringWithFormat:@"neoforge-%@", dependency[@"neoforge"]];
        info[@"loaderVendor"] = @"NeoForge";
        info[@"loaderVersion"] = dependency[@"neoforge"];
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

+ (void)installLoaderIfNeeded:(NSDictionary *)depInfo {
    NSString *versionID = depInfo[@"id"];
    NSString *vendor = depInfo[@"loaderVendor"];
    NSString *loaderVersion = depInfo[@"loaderVersion"];
    if (!vendor || !loaderVersion) {
        return;
    }

    // Nothing to do when the loader this pack wants is already installed
    NSString *versionPath = [NSString stringWithFormat:@"%s/versions/%@", getenv("POJAV_GAME_DIR"), versionID];
    if ([NSFileManager.defaultManager fileExistsAtPath:versionPath]) {
        NSLog(@"[ModpackDL] %@ is already installed", versionID);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:localize(@"modpack.loader.title", nil)
            message:[NSString stringWithFormat:localize(@"modpack.loader.message", nil), vendor, loaderVersion]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"modpack.loader.install", nil)
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self runLoaderInstallerForVendor:vendor version:loaderVersion];
            }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"modpack.loader.later", nil)
            style:UIAlertActionStyleCancel handler:nil]];
        [currentVC() presentViewController:alert animated:YES completion:nil];
    });
}

// Downloads the vendor's official installer and hands it to the Java GUI runner,
// the same path the Forge/NeoForge screen uses for a manually created profile.
+ (void)runLoaderInstallerForVendor:(NSString *)vendor version:(NSString *)version {
    NSString *urlString = [NSString stringWithFormat:
        ForgeInstallViewController.endpoints[vendor][@"installer"], version];
    NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp.jar"];
    NSLog(@"[ModpackDL] Downloading %@ installer: %@", vendor, urlString);

    AFURLSessionManager *manager = [AFURLSessionManager new];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    NSURLSessionDownloadTask *task = [manager downloadTaskWithRequest:request progress:nil
    destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        [NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
        return [NSURL fileURLWithPath:outPath];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                showDialog(localize(@"Error", nil), error.localizedDescription);
                return;
            }
            UIViewController *topVC = currentVC();
            if (![topVC isKindOfClass:UISplitViewController.class] ||
                ((UISplitViewController *)topVC).viewControllers.count < 2) {
                // Not on the launcher screen anymore; the jar stays in place so
                // the user can still run it from the mod installer
                NSLog(@"[ModpackDL] Cannot reach the launcher to run the installer");
                showDialog(localize(@"Error", nil), localize(@"modpack.loader.no_launcher", nil));
                return;
            }
            showDialog(localize(@"modpack.loader.title", nil),
                [NSString stringWithFormat:localize(@"modpack.loader.running", nil), vendor]);
            LauncherNavigationController *navVC = (id)((UISplitViewController *)topVC).viewControllers[1];
            [navVC enterModInstallerWithPath:outPath hitEnterAfterWindowShown:YES];
        });
    }];
    [task resume];
}

@end
