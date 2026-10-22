#import "MinecraftResourceDownloadTask.h"
#import "ModrinthAPI.h"
#import "utils.h"
#import "ModrinthSearchFilters.h"
#import "PLProfiles.h"

@implementation ModrinthAPI

- (instancetype)init {
    return [super initWithURL:@"https://api.modrinth.com/v2"];
}

- (NSArray<NSString *> *)modCategories {
    NSArray *records = [self categoriesForContentType:@"mod"];
    return records ? [records valueForKey:@"id"] : nil;
}
- (NSArray<NSDictionary *> *)categoriesForContentType:(NSString *)type {
    id response = [self getEndpoint:@"tag/category" params:nil];
    if (!response) return nil;
    if (![response isKindOfClass:NSArray.class]) {
        self.lastError = [NSError errorWithDomain:@"Modrinth" code:4 userInfo:@{NSLocalizedDescriptionKey: localize(@"content.modrinth.invalid_categories", nil)}];
        return nil;
    }
    NSMutableArray *records = [NSMutableArray new];
    for (NSString *name in [ModrinthSearchFilters categoriesFromTags:response contentType:type]) [records addObject:@{@"id": name, @"slug": name}];
    return records;
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary *)searchFilters previousPageResult:(NSMutableArray *)modrinthSearchResult {
    int limit = 50;

    NSDictionary *params = [ModrinthSearchFilters searchParameters:searchFilters offset:modrinthSearchResult.count limit:limit];
    NSDictionary *response = [self getEndpoint:@"search" params:params];
    if (!response) {
        return nil;
    }

    if (![response isKindOfClass:NSDictionary.class] || ![response[@"hits"] isKindOfClass:NSArray.class]) {
        self.lastError = [NSError errorWithDomain:@"Modrinth" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"content.modrinth.invalid_search", nil)}];
        return nil;
    }
    NSMutableArray *result = modrinthSearchResult ? [modrinthSearchResult mutableCopy] : [NSMutableArray new];
    for (NSDictionary *hit in response[@"hits"]) {
        if (![hit isKindOfClass:NSDictionary.class] || ![hit[@"project_id"] isKindOfClass:NSString.class]) continue;
        BOOL isModpack = [hit[@"project_type"] isEqualToString:@"modpack"];
        [result addObject:@{
            @"apiSource": @(1), // Constant MODRINTH
            @"isModpack": @(isModpack),
            @"id": hit[@"project_id"],
            @"provider": @"modrinth",
            @"contentType": [ModrinthSearchFilters contentTypeForFilters:searchFilters],
            @"websiteUrl": [NSString stringWithFormat:@"https://modrinth.com/%@/%@", [ModrinthSearchFilters contentTypeForFilters:searchFilters], hit[@"project_id"]],
            @"title": [hit[@"title"] isKindOfClass:NSString.class] ? hit[@"title"] : @"",
            @"description": [hit[@"description"] isKindOfClass:NSString.class] ? hit[@"description"] : @"",
            @"imageUrl": [hit[@"icon_url"] isKindOfClass:NSString.class] ? hit[@"icon_url"] : @"",
            @"author": [hit[@"author"] isKindOfClass:NSString.class] ? hit[@"author"] : @""
        }.mutableCopy];
    }
    self.reachedLastPage = result.count >= [response[@"total_hits"] unsignedLongValue];
    return result;
}

- (NSArray<NSDictionary *> *)versionsForProject:(NSString *)projectID filters:(NSDictionary *)filters {
    id response = [self getEndpoint:[NSString stringWithFormat:@"project/%@/version", projectID] params:[ModrinthSearchFilters versionParameters:filters]];
    if (!response) return nil;
    if (![response isKindOfClass:NSArray.class]) {
        self.lastError = [NSError errorWithDomain:@"Modrinth" code:2 userInfo:@{NSLocalizedDescriptionKey: localize(@"content.modrinth.invalid_versions", nil)}];
        return nil;
    }
    // Search facets describe projects; only version tags prove this particular version matches both filters.
    return [ModrinthSearchFilters versions:response matchingFilters:filters];
}

- (NSDictionary<NSString *, NSDictionary *> *)versionsForFileHashes:(NSArray<NSString *> *)hashes {
    if (!hashes.count) return @{};
    id response = [self postEndpoint:@"version_files" params:@{@"hashes": hashes, @"algorithm": @"sha1"}];
    if (!response) return nil;
    if (![response isKindOfClass:NSDictionary.class]) {
        self.lastError = [NSError errorWithDomain:@"Modrinth" code:3 userInfo:@{NSLocalizedDescriptionKey: localize(@"content.modrinth.invalid_files", nil)}];
        return nil;
    }
    return response;
}

- (NSDictionary *)projectForID:(NSString *)projectID {
    id item = [self getEndpoint:[@"project/" stringByAppendingString:projectID] params:nil];
    if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSString.class]) return nil;
    return @{@"id": item[@"id"], @"provider": @"modrinth", @"contentType": @"mod", @"title": item[@"title"] ?: projectID, @"description": item[@"description"] ?: @"", @"imageUrl": [item[@"icon_url"] isKindOfClass:NSString.class] ? item[@"icon_url"] : @"", @"author": @"", @"websiteUrl": [@"https://modrinth.com/mod/" stringByAppendingString:projectID]};
}
- (NSDictionary *)versionForID:(NSString *)versionID projectID:(NSString *)projectID {
    id item = [self getEndpoint:[@"version/" stringByAppendingString:versionID] params:nil];
    return [item isKindOfClass:NSDictionary.class] && [item[@"id"] isKindOfClass:NSString.class] ? item : nil;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    NSArray *response = [self getEndpoint:[NSString stringWithFormat:@"project/%@/version", item[@"id"]] params:nil];
    if (!response) {
        return;
    }
    NSArray<NSString *> *names = [response valueForKey:@"name"];
    NSMutableArray<NSString *> *mcNames = [NSMutableArray new];
    NSMutableArray<NSString *> *urls = [NSMutableArray new];
    NSMutableArray<NSString *> *hashes = [NSMutableArray new];
    NSMutableArray<NSString *> *sizes = [NSMutableArray new];
    [response enumerateObjectsUsingBlock:
  ^(NSDictionary *version, NSUInteger i, BOOL *stop) {
        NSDictionary *file = [version[@"files"] firstObject];
        mcNames[i] = [version[@"game_versions"] firstObject];
        sizes[i] = file[@"size"];
        urls[i] = file[@"url"];
        NSDictionary *hashesMap = file[@"hashes"];
        hashes[i] = hashesMap[@"sha1"] ?: [NSNull null];
    }];
    item[@"versionNames"] = names;
    item[@"mcVersionNames"] = mcNames;
    item[@"versionSizes"] = sizes;
    item[@"versionUrls"] = urls;
    item[@"versionHashes"] = hashes;
    item[@"versionDetailsLoaded"] = @(YES);
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)instanceRoot {
    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:packagePath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:localize(@"content.modpack.error_open", nil), error.localizedDescription]];
        return;
    }

    NSData *indexData = [archive extractDataFromFile:@"modrinth.index.json" error:&error];
    NSDictionary* indexDict = [NSJSONSerialization JSONObjectWithData:indexData options:kNilOptions error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:localize(@"content.modpack.error_index", nil), error.localizedDescription]];
        return;
    }

    PLProfiles *profiles = PLProfiles.current;
    NSDictionary *existingProfile = profiles.profiles[indexDict[@"name"]];
    NSString *gameDirectory;
    if (existingProfile) {
        // Reinstalling a pack keeps its existing worlds and custom folder.
        gameDirectory = [existingProfile[@"gameDir"] isKindOfClass:NSString.class] && [existingProfile[@"gameDir"] length] ? existingProfile[@"gameDir"] : @".";
    } else {
        gameDirectory = @".";
    }
    NSString *destPath = [NSString stringWithFormat:@"%@/%@", instanceRoot, gameDirectory].stringByStandardizingPath;

    downloader.progress.totalUnitCount = [indexDict[@"files"] count];
    for (NSDictionary *indexFile in indexDict[@"files"]) {
/*
        if ([indexFile[@"downloads"] count] > 1) {
            [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Unhandled multiple files download %@", indexFile[@"downloads"]]];
            return;
        }
*/
        NSString *url = [indexFile[@"downloads"] firstObject];
        NSString *sha = indexFile[@"hashes"][@"sha1"];
        NSString *path = [destPath stringByAppendingPathComponent:indexFile[@"path"]];
        NSUInteger size = [indexFile[@"fileSize"] unsignedLongLongValue];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:url size:size sha:sha altName:nil toPath:path];
        if (task) {
            [downloader.fileList addObject:indexFile[@"path"]];
            [task resume];
        } else if (!downloader.progress.cancelled) {
            downloader.progress.completedUnitCount++;
        } else {
            return; // cancelled
        }
    }

    [ModpackUtils archive:archive extractDirectory:@"overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:localize(@"content.modpack.error_overrides", nil), error.localizedDescription]];
        return;
    }

    [ModpackUtils archive:archive extractDirectory:@"client-overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:localize(@"content.modpack.error_client_overrides", nil), error.localizedDescription]];
        return;
    }

    // Delete package cache
    [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];

    // Download dependency client json (if available)
    NSDictionary<NSString *, NSString *> *depInfo = [ModpackUtils infoForDependencies:indexDict[@"dependencies"]];
    if (depInfo[@"json"]) {
        NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("GAME_DIR"), depInfo[@"id"]];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:depInfo[@"json"] size:0 sha:nil altName:nil toPath:jsonPath];
        [task resume];
    }
    // TODO: automation for Forge

    // Create profile
    NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
    profiles.profiles[indexDict[@"name"]] = @{
        @"gameDir": gameDirectory,
        @"name": indexDict[@"name"],
        @"lastVersionId": depInfo[@"id"],
        @"icon": [NSString stringWithFormat:@"data:image/png;base64,%@",
            [[NSData dataWithContentsOfFile:tmpIconPath]
            base64EncodedStringWithOptions:0]]
    }.mutableCopy;
    profiles.selectedProfileName = indexDict[@"name"];
}

@end
