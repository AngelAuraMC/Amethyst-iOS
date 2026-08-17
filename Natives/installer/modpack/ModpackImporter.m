#import "CurseForgeAPI.h"
#import "ModpackImporter.h"
#import "ModpackUtils.h"
#import "ModrinthAPI.h"
#import "UnzipKit.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@implementation ModpackImporter

static NSString *pendingImportPath;
static BOOL launcherIsReady;

+ (void)importModpackAtURL:(NSURL *)url {
    // Modpacks run to hundreds of megabytes, so the copy stays off the main thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSString *importDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"modpack_import"];
        NSString *destPath = [importDir stringByAppendingPathComponent:url.lastPathComponent];

        NSError *error;
        [NSFileManager.defaultManager createDirectoryAtPath:importDir withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager removeItemAtPath:destPath error:nil];
        BOOL copied = [NSFileManager.defaultManager copyItemAtPath:url.path toPath:destPath error:&error];
        if (scoped) {
            [url stopAccessingSecurityScopedResource];
        }

        if (!copied) {
            NSLog(@"[ModpackImport] Unable to copy %@: %@", url.path, error.localizedDescription);
            NSString *reason = error.localizedDescription ?: @"?";
            dispatch_async(dispatch_get_main_queue(), ^{
                showDialog(localize(@"Error", nil), [NSString stringWithFormat:
                    localize(@"modpack.error.open_failed", nil), reason]);
            });
            return;
        }
        [self importModpackAtPath:destPath];
    });
}

+ (void)importModpackAtPath:(NSString *)path {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ModpackAPI *api = [self apiForPackageAtPath:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Both the readiness flag and the pending path are only ever touched
            // on the main thread
            if (!launcherIsReady) {
                NSLog(@"[ModpackImport] Launcher is not ready yet, holding %@", path.lastPathComponent);
                pendingImportPath = path;
                return;
            }
            if (!api) {
                [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                showDialog(localize(@"Error", nil), localize(@"modpack.error.unsupported", nil));
                return;
            }
            if ([api isKindOfClass:CurseForgeAPI.class] && !((CurseForgeAPI *)api).apiKey) {
                [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                showDialog(localize(@"Error", nil), localize(@"modpack.error.curseforge_key", nil));
                return;
            }

            // The browser leaves the artwork of the last installed pack behind;
            // drop it so this import does not adopt an unrelated icon.
            [NSFileManager.defaultManager removeItemAtPath:
                [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"] error:nil];

            [NSNotificationCenter.defaultCenter
                postNotificationName:@"InstallModpack"
                object:api
                userInfo:@{@"packagePath": path}];
        });
    });
}

// Modrinth packs carry modrinth.index.json, CurseForge exports carry manifest.json.
+ (ModpackAPI *)apiForPackageAtPath:(NSString *)path {
    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&error];
    if (!archive || error) {
        NSLog(@"[ModpackImport] Unable to open %@: %@", path.lastPathComponent, error.localizedDescription);
        return nil;
    }

    if ([archive extractDataFromFile:@"modrinth.index.json" error:nil]) {
        NSLog(@"[ModpackImport] %@ is a Modrinth pack", path.lastPathComponent);
        return [ModrinthAPI new];
    }
    if ([archive extractDataFromFile:@"manifest.json" error:nil]) {
        NSLog(@"[ModpackImport] %@ is a CurseForge pack", path.lastPathComponent);
        return [CurseForgeAPI new];
    }
    NSLog(@"[ModpackImport] %@ is not a recognized modpack", path.lastPathComponent);
    return nil;
}

+ (void)flushPendingImport {
    launcherIsReady = YES;
    if (!pendingImportPath) {
        return;
    }
    NSString *path = pendingImportPath;
    pendingImportPath = nil;
    [self importModpackAtPath:path];
}

@end
