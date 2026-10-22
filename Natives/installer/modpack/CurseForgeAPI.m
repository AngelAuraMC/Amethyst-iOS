#import <Foundation/Foundation.h>
#import "CurseForgeAPI.h"
#import "ModrinthSearchFilters.h"
#import <Security/Security.h>

static NSString *CFString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSString *CFIdentifier(id value) { return [value isKindOfClass:NSNumber.class] ? [value stringValue] : CFString(value); }
static NSString *CFKey(void) {
    return [CurseForgeAPI apiKey];
}
static NSNumber *CFLoader(NSDictionary *filters) {
    if (![[ModrinthSearchFilters contentTypeForFilters:filters] isEqual:@"mod"]) return nil;
    return @{@"forge": @1, @"liteloader": @3, @"fabric": @4, @"quilt": @5, @"neoforge": @6}[filters[@"loader"] ?: @""];
}

@implementation CurseForgeAPI
+ (NSDictionary *)keyQuery {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"Amethyst.CurseForge", (__bridge id)kSecAttrAccount: @"api-key"};
}
+ (NSString *)apiKey {
    NSMutableDictionary *query = [self.keyQuery mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSData *data = CFBridgingRelease(result);
    return status == errSecSuccess ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"" : @"";
}
+ (BOOL)setAPIKey:(NSString *)key error:(NSError **)error {
    key = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSDictionary *query = self.keyQuery;
    OSStatus status;
    if (!key.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSDictionary *values = @{(__bridge id)kSecValueData: [key dataUsingEncoding:NSUTF8StringEncoding]};
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)values);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [query mutableCopy];
            [item addEntriesFromDictionary:values];
            item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
    }
    if (status != errSecSuccess) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"content.curseforge.key_error", nil)}];
        return NO;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:@"CurseForgeConfigurationDidChange" object:nil];
    return YES;
}
- (instancetype)init { return [super initWithURL:@"https://api.curseforge.com/v1"]; }
+ (BOOL)isConfigured { return CFKey().length > 0; }
- (NSDictionary *)requestHeaders { return self.class.isConfigured ? @{@"x-api-key": CFKey()} : @{}; }
- (BOOL)checkConfiguration {
    if (self.class.isConfigured) return YES;
    self.lastError = [NSError errorWithDomain:@"CurseForge" code:100 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"content.curseforge.unconfigured", nil)}];
    return NO;
}
- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params {
    return [self checkConfiguration] ? [super getEndpoint:endpoint params:params] : nil;
}
- (id)postEndpoint:(NSString *)endpoint params:(NSDictionary *)params {
    return [self checkConfiguration] ? [super postEndpoint:endpoint params:params] : nil;
}
- (NSArray *)listFromResponse:(id)response {
    if (!response) return nil;
    if ([response isKindOfClass:NSDictionary.class] && [response[@"data"] isKindOfClass:NSArray.class]) return response[@"data"];
    self.lastError = [NSError errorWithDomain:@"CurseForge" code:1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"content.invalid_response", nil)}];
    return nil;
}
- (NSNumber *)classIDForType:(NSString *)type {
    // Discover section IDs instead of embedding IDs that may change on CurseForge.
    static NSDictionary *classIDs;
    @synchronized (CurseForgeAPI.class) { if (classIDs[type]) return classIDs[type]; }
    NSArray *classes = [self listFromResponse:[self getEndpoint:@"categories" params:@{@"gameId": @432, @"classesOnly": @YES}]];
    if (!classes) return nil;
    NSMutableDictionary *ids = [NSMutableDictionary new];
    NSDictionary *types = @{@"mc-mods": @"mod", @"mods": @"mod", @"texture-packs": @"resourcepack", @"resource-packs": @"resourcepack", @"shaders": @"shader", @"modpacks": @"modpack"};
    for (id item in classes) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSNumber.class]) continue;
        NSString *kind = types[CFString(item[@"slug"])];
        if (kind) ids[kind] = item[@"id"];
    }
    @synchronized (CurseForgeAPI.class) { classIDs = ids.copy; }
    if (!ids[type]) self.lastError = [NSError errorWithDomain:@"CurseForge" code:2 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"content.section_unavailable", nil)}];
    return ids[type];
}
- (NSArray<NSDictionary *> *)categoriesForContentType:(NSString *)type {
    NSNumber *classID = [self classIDForType:type];
    if (!classID) return nil;
    NSArray *categories = [self listFromResponse:[self getEndpoint:@"categories" params:@{@"gameId": @432, @"classId": classID}]];
    if (!categories) return nil;
    NSMutableArray *records = [NSMutableArray new];
    for (id item in categories) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSNumber.class] || [item[@"isClass"] boolValue]) continue;
        if (![item[@"classId"] isEqual:classID]) continue;
        [records addObject:@{@"id": CFIdentifier(item[@"id"]), @"name": CFString(item[@"name"]), @"slug": CFString(item[@"slug"])}];
    }
    return [records sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
}
+ (NSDictionary *)searchParameters:(NSDictionary *)filters classID:(NSNumber *)classID offset:(NSUInteger)offset {
    NSNumber *sort = @{@"relevance": @2, @"downloads": @6, @"newest": @11, @"updated": @3}[filters[@"index"]] ?: @2;
    NSMutableDictionary *params = [@{@"gameId": @432, @"classId": classID, @"searchFilter": CFString(filters[@"name"]), @"index": @(offset), @"pageSize": @50, @"sortField": sort, @"sortOrder": @"desc"} mutableCopy];
    NSString *game = CFString(filters[@"mcVersion"]);
    if (game.length) params[@"gameVersion"] = game;
    NSNumber *loader = CFLoader(filters);
    // CurseForge requires a game version together with the search loader parameter.
    if (loader && game.length) params[@"modLoaderType"] = loader;
    NSArray *categories = [filters[@"categories"] isKindOfClass:NSArray.class] ? filters[@"categories"] : @[];
    NSMutableOrderedSet *ids = [NSMutableOrderedSet new];
    for (id category in categories) if (CFString(category).integerValue > 0 && ids.count < 10) [ids addObject:@([category integerValue])];
    if (ids.count) params[@"categoryIds"] = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:ids.array options:0 error:nil] encoding:NSUTF8StringEncoding];
    return params;
}
- (NSMutableArray *)searchModWithFilters:(NSDictionary *)filters previousPageResult:(NSMutableArray *)previous {
    NSNumber *classID = [self classIDForType:[ModrinthSearchFilters contentTypeForFilters:filters]];
    if (!classID) return nil;
    if (previous.count >= 10000) { self.reachedLastPage = YES; return previous.mutableCopy; }
    id response = [self getEndpoint:@"mods/search" params:[self.class searchParameters:filters classID:classID offset:previous.count]];
    NSArray *hits = [self listFromResponse:response];
    if (!hits) return nil;
    NSMutableArray *result = previous.mutableCopy ?: [NSMutableArray new];
    for (id item in hits) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSNumber.class] || ![item[@"classId"] isEqual:classID]) continue;
        NSMutableArray *authors = [NSMutableArray new];
        if ([item[@"authors"] isKindOfClass:NSArray.class]) for (id author in item[@"authors"]) if ([author isKindOfClass:NSDictionary.class] && CFString(author[@"name"]).length) [authors addObject:author[@"name"]];
        NSDictionary *logo = [item[@"logo"] isKindOfClass:NSDictionary.class] ? item[@"logo"] : @{};
        NSDictionary *links = [item[@"links"] isKindOfClass:NSDictionary.class] ? item[@"links"] : @{};
        [result addObject:@{@"id": CFIdentifier(item[@"id"]), @"provider": @"curseforge", @"contentType": [ModrinthSearchFilters contentTypeForFilters:filters], @"title": CFString(item[@"name"]), @"description": CFString(item[@"summary"]), @"author": [authors componentsJoinedByString:@", "], @"imageUrl": CFString(logo[@"thumbnailUrl"]), @"websiteUrl": CFString(links[@"websiteUrl"])}];
    }
    NSDictionary *pagination = [response[@"pagination"] isKindOfClass:NSDictionary.class] ? response[@"pagination"] : @{};
    self.reachedLastPage = !hits.count || previous.count + hits.count >= MIN(10000, [pagination[@"totalCount"] unsignedIntegerValue]);
    return result;
}
+ (NSDictionary *)versionFromFile:(NSDictionary *)file {
    if (![file isKindOfClass:NSDictionary.class] || ![file[@"id"] isKindOfClass:NSNumber.class] || ![file[@"modId"] isKindOfClass:NSNumber.class]) return nil;
    NSString *sha1 = @"";
    if ([file[@"hashes"] isKindOfClass:NSArray.class]) for (id hash in file[@"hashes"]) if ([hash isKindOfClass:NSDictionary.class] && [hash[@"algo"] isEqual:@1]) sha1 = CFString(hash[@"value"]);
    NSArray *games = [file[@"gameVersions"] isKindOfClass:NSArray.class] ? file[@"gameVersions"] : @[];
    NSMutableArray *loaders = [NSMutableArray new], *versions = [NSMutableArray new];
    for (id game in games) {
        if (![game isKindOfClass:NSString.class]) continue;
        if ([@[@"forge", @"fabric", @"quilt", @"neoforge", @"liteloader"] containsObject:[game lowercaseString]]) [loaders addObject:[game lowercaseString]];
        else [versions addObject:game];
    }
    NSDictionary *download = @{@"filename": CFString(file[@"fileName"]), @"url": CFString(file[@"downloadUrl"]), @"size": [file[@"fileLength"] isKindOfClass:NSNumber.class] ? file[@"fileLength"] : @0, @"hashes": @{@"sha1": sha1}, @"primary": @YES};
    BOOL available = [file[@"isAvailable"] boolValue] && ![file[@"isServerPack"] boolValue] && ![file[@"isEarlyAccessContent"] boolValue] && CFString(file[@"downloadUrl"]).length;
    NSMutableArray *dependencies = [NSMutableArray new];
    for (id dep in [file[@"dependencies"] isKindOfClass:NSArray.class] ? file[@"dependencies"] : @[]) {
        if (![dep isKindOfClass:NSDictionary.class]) continue;
        NSString *type = @{@3: @"required", @5: @"incompatible"}[dep[@"relationType"]];
        if (type && CFIdentifier(dep[@"modId"]).length) [dependencies addObject:@{@"project_id": CFIdentifier(dep[@"modId"]), @"dependency_type": type}];
    }
    return @{@"id": CFIdentifier(file[@"id"]), @"project_id": CFIdentifier(file[@"modId"]), @"provider": @"curseforge", @"name": CFString(file[@"displayName"]), @"version_number": CFString(file[@"displayName"]), @"date_published": CFString(file[@"fileDate"]), @"game_versions": versions, @"loaders": loaders, @"version_type": (@{@1: @"release", @2: @"beta", @3: @"alpha"}[file[@"releaseType"]] ?: @""), @"files": @[download], @"downloadUnavailable": @(!available), @"dependencies": dependencies};
}
- (NSArray<NSDictionary *> *)versionsForProject:(NSString *)projectID filters:(NSDictionary *)filters {
    NSMutableArray *versions = [NSMutableArray new];
    NSMutableDictionary *params = [@{@"pageSize": @50} mutableCopy];
    if (CFString(filters[@"mcVersion"]).length) params[@"gameVersion"] = filters[@"mcVersion"];
    if (CFLoader(filters)) params[@"modLoaderType"] = CFLoader(filters);
    for (NSUInteger offset = 0; offset < 10000; offset += 50) {
        params[@"index"] = @(offset);
        id response = [self getEndpoint:[NSString stringWithFormat:@"mods/%@/files", projectID] params:params];
        NSArray *files = [self listFromResponse:response];
        if (!files) return nil;
        for (id file in files) { NSDictionary *version = [self.class versionFromFile:file]; if (version) [versions addObject:version]; }
        NSDictionary *pagination = [response[@"pagination"] isKindOfClass:NSDictionary.class] ? response[@"pagination"] : @{};
        if (!files.count || offset + files.count >= [pagination[@"totalCount"] unsignedIntegerValue]) break;
    }
    return [[ModrinthSearchFilters versions:versions matchingFilters:filters] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"date_published" ascending:NO]]];
}
- (NSDictionary *)projectForID:(NSString *)projectID {
    id response = [self getEndpoint:[@"mods/" stringByAppendingString:projectID] params:nil];
    id item = [response isKindOfClass:NSDictionary.class] ? response[@"data"] : nil;
    if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSNumber.class]) return nil;
    NSDictionary *logo = [item[@"logo"] isKindOfClass:NSDictionary.class] ? item[@"logo"] : @{};
    NSDictionary *links = [item[@"links"] isKindOfClass:NSDictionary.class] ? item[@"links"] : @{};
    return @{@"id": CFIdentifier(item[@"id"]), @"provider": @"curseforge", @"contentType": @"mod", @"title": CFString(item[@"name"]), @"description": CFString(item[@"summary"]), @"imageUrl": CFString(logo[@"thumbnailUrl"]), @"author": @"", @"websiteUrl": CFString(links[@"websiteUrl"])};
}
- (NSDictionary *)versionForID:(NSString *)versionID projectID:(NSString *)projectID {
    id response = [self getEndpoint:[NSString stringWithFormat:@"mods/%@/files/%@", projectID, versionID] params:nil];
    return [response isKindOfClass:NSDictionary.class] ? [self.class versionFromFile:response[@"data"]] : nil;
}
@end
