#import "AFNetworking.h"
#import "CurseForgeAPI.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceDownloadTask.h"
#import "ModpackUtils.h"
#import "PLProfiles.h"
#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

// https://docs.curseforge.com/#curseforge-class-ids
#define kCurseForgeClassIDMod 6
#define kCurseForgeClassIDResourcePack 12
#define kCurseForgeClassIDWorld 17
#define kCurseForgeClassIDShaderPack 6552

// The bulk endpoints accept a limited number of ids per call, so requests are chunked.
#define kCurseForgeBulkChunkSize 100

// hashes[].algo values used by the CurseForge API
#define kCurseForgeHashAlgoSha1 1

@implementation CurseForgeAPI

- (instancetype)init {
    self = [super initWithURL:@"https://api.curseforge.com/v1"];
    _apiKey = [CurseForgeAPI resolvedAPIKey];
    return self;
}

+ (NSString *)resolvedAPIKey {
    id prefKey = getPrefObject(@"general.curseforge_api_key");
    if ([prefKey isKindOfClass:NSString.class]) {
        NSString *trimmed = [prefKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) {
            return trimmed;
        }
    }
    // Set at build time with `make CURSEFORGE_API_KEY=...`, empty when unset
    const char *compiledKey = CONFIG_CURSEFORGE_API_KEY;
    if (compiledKey != NULL && strlen(compiledKey) > 0) {
        return @(compiledKey);
    }
    return nil;
}

#pragma mark - Requests

// Performs a synchronous request against the CurseForge API. Must not be called
// on the main thread; the modpack installer already runs on a background queue.
- (id)requestEndpoint:(NSString *)endpoint method:(NSString *)method params:(id)params {
    if (!self.apiKey) {
        return nil;
    }

    __block id result;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    NSString *url = [self.baseURL stringByAppendingPathComponent:endpoint];
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer = [AFJSONRequestSerializer serializer];
    NSDictionary *headers = @{@"x-api-key": self.apiKey, @"Accept": @"application/json"};

    void (^success)(NSURLSessionTask *, id) = ^(NSURLSessionTask *task, id obj) {
        result = obj;
        dispatch_group_leave(group);
    };
    void (^failure)(NSURLSessionTask *, NSError *) = ^(NSURLSessionTask *task, NSError *error) {
        self.lastError = error;
        NSLog(@"[CurseForge] Request to %@ failed: %@", endpoint, error.localizedDescription);
        dispatch_group_leave(group);
    };

    if ([method isEqualToString:@"POST"]) {
        [manager POST:url parameters:params headers:headers progress:nil success:success failure:failure];
    } else {
        [manager GET:url parameters:params headers:headers progress:nil success:success failure:failure];
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    return result;
}

// Resolves the fileID list of a manifest into file metadata, keyed by fileID.
- (NSDictionary *)resolveFilesWithIDs:(NSArray<NSNumber *> *)fileIDs {
    NSMutableDictionary *filesByID = [NSMutableDictionary new];
    for (NSUInteger offset = 0; offset < fileIDs.count; offset += kCurseForgeBulkChunkSize) {
        NSRange range = NSMakeRange(offset, MIN(kCurseForgeBulkChunkSize, fileIDs.count - offset));
        NSArray *chunk = [fileIDs subarrayWithRange:range];
        NSDictionary *response = [self requestEndpoint:@"mods/files" method:@"POST" params:@{@"fileIds": chunk}];
        if (!response) {
            return nil;
        }
        for (NSDictionary *file in response[@"data"]) {
            if (file[@"id"]) {
                filesByID[file[@"id"]] = file;
            }
        }
    }
    return filesByID;
}

// Resolves the projectID list of a manifest into the subdirectory each file
// belongs in. Best effort: on failure everything lands in mods/, which is where
// the overwhelming majority of modpack files go anyway.
- (NSDictionary *)resolveSubdirectoriesWithModIDs:(NSArray<NSNumber *> *)modIDs {
    NSMutableDictionary *subdirectoryByModID = [NSMutableDictionary new];
    for (NSUInteger offset = 0; offset < modIDs.count; offset += kCurseForgeBulkChunkSize) {
        NSRange range = NSMakeRange(offset, MIN(kCurseForgeBulkChunkSize, modIDs.count - offset));
        NSArray *chunk = [modIDs subarrayWithRange:range];
        NSDictionary *response = [self requestEndpoint:@"mods" method:@"POST" params:@{@"modIds": chunk}];
        if (!response) {
            NSLog(@"[CurseForge] Unable to determine file categories, defaulting to mods/");
            return subdirectoryByModID;
        }
        for (NSDictionary *mod in response[@"data"]) {
            if (mod[@"id"]) {
                subdirectoryByModID[mod[@"id"]] = [self subdirectoryForClassID:[mod[@"classId"] integerValue]];
            }
        }
    }
    return subdirectoryByModID;
}

- (NSString *)subdirectoryForClassID:(NSInteger)classID {
    switch (classID) {
        case kCurseForgeClassIDResourcePack: return @"resourcepacks";
        case kCurseForgeClassIDShaderPack: return @"shaderpacks";
        case kCurseForgeClassIDWorld: return @"saves";
        case kCurseForgeClassIDMod:
        default: return @"mods";
    }
}

- (NSString *)sha1ForFile:(NSDictionary *)file {
    for (NSDictionary *hash in file[@"hashes"]) {
        if ([hash[@"algo"] integerValue] == kCurseForgeHashAlgoSha1) {
            return hash[@"value"];
        }
    }
    return nil;
}

// Some authors opt out of third-party distribution, which leaves downloadUrl
// null. The file is still served from the CDN under a path derived from its id.
- (NSString *)downloadURLForFile:(NSDictionary *)file {
    NSString *url = file[@"downloadUrl"];
    if ([url isKindOfClass:NSString.class] && url.length > 0) {
        return url;
    }
    NSString *fileName = file[@"fileName"];
    if (!fileName) {
        return nil;
    }
    unsigned long long fileID = [file[@"id"] unsignedLongLongValue];
    NSString *escapedName = [fileName stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    return [NSString stringWithFormat:@"https://edge.forgecdn.net/files/%llu/%llu/%@",
        fileID / 1000, fileID % 1000, escapedName];
}

#pragma mark - Dependencies

// Translates a CurseForge manifest's minecraft block into the dependency shape
// ModpackUtils understands.
- (NSDictionary *)dependenciesFromManifest:(NSDictionary *)manifest {
    NSDictionary *minecraft = manifest[@"minecraft"];
    NSMutableDictionary *dependencies = [NSMutableDictionary new];
    dependencies[@"minecraft"] = minecraft[@"version"];

    NSArray *modLoaders = minecraft[@"modLoaders"];
    NSDictionary *primaryLoader = modLoaders.firstObject;
    for (NSDictionary *loader in modLoaders) {
        if ([loader[@"primary"] boolValue]) {
            primaryLoader = loader;
            break;
        }
    }

    NSString *loaderID = primaryLoader[@"id"];
    NSRange separator = [loaderID rangeOfString:@"-"];
    if (separator.location == NSNotFound) {
        return dependencies;
    }
    NSString *loaderName = [loaderID substringToIndex:separator.location];
    NSString *loaderVersion = [loaderID substringFromIndex:separator.location + 1];

    if ([loaderName isEqualToString:@"forge"]) {
        dependencies[@"forge"] = loaderVersion;
    } else if ([loaderName isEqualToString:@"neoforge"]) {
        dependencies[@"neoforge"] = loaderVersion;
    } else if ([loaderName isEqualToString:@"fabric"]) {
        dependencies[@"fabric-loader"] = loaderVersion;
    } else if ([loaderName isEqualToString:@"quilt"]) {
        dependencies[@"quilt-loader"] = loaderVersion;
    }
    return dependencies;
}

#pragma mark - Installation

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)destPath {
    if (!self.apiKey) {
        [downloader finishDownloadWithErrorString:localize(@"modpack.error.curseforge_key", nil)];
        return;
    }

    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:packagePath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to open modpack package: %@", error.localizedDescription]];
        return;
    }

    NSData *manifestData = [archive extractDataFromFile:@"manifest.json" error:&error];
    if (!manifestData) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to read manifest.json: %@", error.localizedDescription]];
        return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:kNilOptions error:&error];
    if (error || !manifest) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to parse manifest.json: %@", error.localizedDescription]];
        return;
    }
    if (![manifest[@"manifestType"] isEqualToString:@"minecraftModpack"]) {
        [downloader finishDownloadWithErrorString:localize(@"modpack.error.unsupported_manifest", nil)];
        return;
    }

    NSArray *manifestFiles = manifest[@"files"];
    NSMutableArray<NSNumber *> *fileIDs = [NSMutableArray new];
    NSMutableArray<NSNumber *> *modIDs = [NSMutableArray new];
    for (NSDictionary *file in manifestFiles) {
        if (file[@"fileID"]) {
            [fileIDs addObject:file[@"fileID"]];
        }
        if (file[@"projectID"]) {
            [modIDs addObject:file[@"projectID"]];
        }
    }

    NSDictionary *filesByID = [self resolveFilesWithIDs:fileIDs];
    if (!filesByID) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:
            localize(@"modpack.error.curseforge_resolve", nil), self.lastError.localizedDescription ?: @"?"]];
        return;
    }
    NSDictionary *subdirectoryByModID = [self resolveSubdirectoriesWithModIDs:modIDs];

    downloader.progress.totalUnitCount = manifestFiles.count;
    for (NSDictionary *manifestFile in manifestFiles) {
        if (downloader.progress.cancelled) {
            return;
        }

        // A manifest entry missing its ids cannot be resolved, and a nil
        // subscript key would raise
        NSNumber *fileID = manifestFile[@"fileID"];
        NSNumber *projectID = manifestFile[@"projectID"];
        NSDictionary *file = fileID ? filesByID[fileID] : nil;
        NSString *url = [self downloadURLForFile:file];
        if (!file || !url) {
            // A file the API refuses to describe cannot be installed. Requiring
            // it is fatal; an optional one only costs that mod.
            if ([manifestFile[@"required"] boolValue]) {
                [downloader finishDownloadWithErrorString:[NSString stringWithFormat:
                    localize(@"modpack.error.curseforge_unavailable", nil), projectID ?: @"?"]];
                return;
            }
            NSLog(@"[CurseForge] Skipping unavailable optional file %@", fileID);
            downloader.progress.completedUnitCount++;
            continue;
        }

        NSString *subdirectory = (projectID ? subdirectoryByModID[projectID] : nil) ?: @"mods";
        NSString *relativePath = [subdirectory stringByAppendingPathComponent:file[@"fileName"]];
        NSString *path = [destPath stringByAppendingPathComponent:relativePath];
        NSUInteger size = [file[@"fileLength"] unsignedLongLongValue];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:url size:size sha:[self sha1ForFile:file] altName:nil toPath:path];
        if (task) {
            [downloader.fileList addObject:relativePath];
            [task resume];
        } else if (!downloader.progress.cancelled) {
            downloader.progress.completedUnitCount++;
        } else {
            return; // cancelled
        }
    }

    NSString *overrideDirectory = manifest[@"overrides"] ?: @"overrides";
    [ModpackUtils archive:archive extractDirectory:overrideDirectory toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to extract %@ from modpack package: %@", overrideDirectory, error.localizedDescription]];
        return;
    }

    // Delete package cache
    [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];

    // Download dependency client json (if available)
    NSDictionary<NSString *, NSString *> *depInfo = [ModpackUtils infoForDependencies:[self dependenciesFromManifest:manifest]];
    if (depInfo[@"json"]) {
        NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), depInfo[@"id"]];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:depInfo[@"json"] size:0 sha:nil altName:nil toPath:jsonPath];
        [task resume];
    } else if (depInfo[@"needsManualInstall"]) {
        [ModpackUtils warnAboutManualLoaderInstall:depInfo[@"id"]];
    }

    [ModpackUtils createProfileNamed:manifest[@"name"] gameDir:destPath.lastPathComponent versionID:depInfo[@"id"]];
}

@end
