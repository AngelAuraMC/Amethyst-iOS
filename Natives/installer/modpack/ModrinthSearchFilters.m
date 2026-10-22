#import "ModrinthSearchFilters.h"

static NSString *MRString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *MRCapture(NSString *value, NSString *pattern) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    return match ? [value substringWithRange:[match rangeAtIndex:1]] : @"";
}

static NSString *MRLoader(NSString *identifier, NSDictionary *metadata) {
    NSMutableString *hints = [identifier.lowercaseString mutableCopy];
    [hints appendFormat:@" %@", MRString(metadata[@"mainClass"]).lowercaseString];
    id libraries = metadata[@"libraries"];
    if ([libraries isKindOfClass:NSArray.class]) {
        for (id library in libraries) {
            if ([library isKindOfClass:NSDictionary.class]) [hints appendFormat:@" %@", MRString(library[@"name"]).lowercaseString];
        }
    }
    // Quilt can include Fabric libraries and NeoForge can contain Forge names.
    if ([hints containsString:@"quilt-loader"] || [hints containsString:@"org.quiltmc"]) return @"quilt";
    if ([hints containsString:@"neoforge"] || [hints containsString:@"net.neoforged"]) return @"neoforge";
    if ([hints containsString:@"fabric-loader"] || [hints containsString:@"net.fabricmc"]) return @"fabric";
    if ([hints containsString:@"net.minecraftforge"] || [hints containsString:@"cpw.mods.modlauncher"] || [hints containsString:@"cpw.mods.fml"] || MRCapture(identifier, @"(?:^|[-_])(forge)(?:[-_]|$)").length) return @"forge";
    if ([hints containsString:@"liteloader"]) return @"liteloader";
    return @"";
}

static NSString *MRGameVersion(NSString *identifier) {
    NSString *game = MRCapture(identifier, @"^(?:fabric|quilt)-loader-[0-9.]+-(.+)$");
    if (!game.length) game = MRCapture(identifier, @"^(?:forge-)?([0-9]+\\.[0-9]+(?:\\.[0-9]+)?)-forge(?:-|$)");
    if (!game.length) game = MRCapture(identifier, @"^forge-([0-9]+\\.[0-9]+(?:\\.[0-9]+)?)-");
    if (game.length) return game;
    // Only recognize actual Minecraft IDs; a custom profile name is not a version.
    return MRCapture(identifier, @"^((?:[0-9]+\\.[0-9]+(?:\\.[0-9]+)?(?:[- ](?:pre|rc|snapshot)(?:[- ]?[0-9]+))?|[0-9]{2}w[0-9]{2}[a-z]|[ab][0-9]+\\.[0-9]+(?:\\.[0-9]+)?))$");
}

static NSString *MRJSON(id value) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding];
}

@implementation ModrinthSearchFilters

+ (NSDictionary *)defaultsForProfile:(NSDictionary *)profile instanceRoot:(NSString *)root latestVersions:(NSDictionary *)latest {
    NSString *identifier = MRString(profile[@"lastVersionId"]);
    if ([identifier isEqualToString:@"latest-release"]) identifier = MRString(latest[@"release"]);
    if ([identifier isEqualToString:@"latest-snapshot"]) identifier = MRString(latest[@"snapshot"]);
    NSString *loader = @"", *game = @"";
    NSMutableSet *visited = [NSMutableSet new];
    while (identifier.length && ![visited containsObject:identifier] && visited.count < 64) {
        [visited addObject:identifier];
        NSDictionary *metadata = @{};
        if ([identifier isEqualToString:identifier.lastPathComponent] && root.length) {
            NSString *path = [[root stringByAppendingPathComponent:@"versions"] stringByAppendingPathComponent:identifier];
            NSData *data = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:[identifier stringByAppendingString:@".json"]]];
            id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([parsed isKindOfClass:NSDictionary.class]) metadata = parsed;
        }
        if (!loader.length) loader = MRLoader(identifier, metadata);
        NSString *parent = MRString(metadata[@"inheritsFrom"]);
        if (!parent.length) parent = MRString(metadata[@"jar"]);
        // An explicit base version takes precedence over heuristics in a custom ID.
        if (!parent.length || [parent isEqualToString:identifier]) {
            if (!game.length) game = MRGameVersion(identifier);
            break;
        }
        identifier = parent;
    }
    return @{@"isModpack": @NO, @"name": @"", @"mcVersion": game, @"loader": loader, @"categories": @[], @"index": @"relevance"};
}

+ (NSArray<NSString *> *)modCategoriesFromTags:(NSArray *)tags {
    return [self categoriesFromTags:tags contentType:@"mod"];
}
+ (NSString *)contentTypeForFilters:(NSDictionary *)filters {
    NSString *type = MRString(filters[@"contentType"]);
    if ([@[@"mod", @"resourcepack", @"shader", @"modpack"] containsObject:type]) return type;
    return [filters[@"isModpack"] boolValue] ? @"modpack" : @"mod";
}
+ (NSDictionary *)defaultsForProfile:(NSDictionary *)profile instanceRoot:(NSString *)root latestVersions:(NSDictionary *)latest contentType:(NSString *)type {
    NSMutableDictionary *defaults = [[self defaultsForProfile:profile instanceRoot:root latestVersions:latest] mutableCopy];
    defaults[@"contentType"] = type;
    if (![type isEqual:@"mod"]) defaults[@"loader"] = @"";
    return defaults;
}
+ (NSArray<NSString *> *)categoriesFromTags:(NSArray *)tags contentType:(NSString *)type {
    NSMutableOrderedSet *names = [NSMutableOrderedSet new];
    for (id tag in tags) {
        if (![tag isKindOfClass:NSDictionary.class] || ![tag[@"project_type"] isEqual:type] || ![tag[@"header"] isEqual:@"categories"]) continue;
        NSString *name = MRString(tag[@"name"]);
        if (name.length) [names addObject:name];
    }
    return [names.array sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSDictionary *)searchParameters:(NSDictionary *)filters offset:(NSUInteger)offset limit:(NSUInteger)limit {
    NSString *type = [self contentTypeForFilters:filters];
    NSMutableArray *facets = [NSMutableArray arrayWithObject:@[[NSString stringWithFormat:@"project_type:%@", type]]];
    NSString *game = MRString(filters[@"mcVersion"]), *loader = MRString(filters[@"loader"]);
    if (game.length) [facets addObject:@[[NSString stringWithFormat:@"versions:%@", game]]];
    if (loader.length && [type isEqual:@"mod"]) [facets addObject:@[[NSString stringWithFormat:@"categories:%@", loader]]];
    // The website intersects selected content categories with one another and the loader.
    id categories = filters[@"categories"];
    NSMutableSet *seen = [NSMutableSet new];
    if ([categories isKindOfClass:NSArray.class]) for (id category in categories) {
        NSString *name = MRString(category);
        if (!name.length || [seen containsObject:name]) continue;
        [seen addObject:name];
        [facets addObject:@[[NSString stringWithFormat:@"categories:%@", name]]];
    }
    NSString *index = MRString(filters[@"index"]);
    if (![@[@"relevance", @"downloads", @"follows", @"newest", @"updated"] containsObject:index]) index = @"relevance";
    // The HTTP client encodes query parameters. Replacing spaces with '+' changes the search text.
    return @{@"query": MRString(filters[@"name"]), @"facets": MRJSON(facets), @"index": index,
             @"offset": @(offset), @"limit": @(MAX(1, MIN(limit, 100)))};
}

+ (NSDictionary *)versionParameters:(NSDictionary *)filters {
    NSMutableDictionary *params = [@{@"include_changelog": @"false"} mutableCopy];
    NSString *game = MRString(filters[@"mcVersion"]), *loader = MRString(filters[@"loader"]);
    if (game.length) params[@"game_versions"] = MRJSON(@[game]);
    if (loader.length && [[self contentTypeForFilters:filters] isEqual:@"mod"]) params[@"loaders"] = MRJSON(@[loader]);
    return params;
}

+ (NSArray<NSDictionary *> *)versions:(NSArray *)versions matchingFilters:(NSDictionary *)filters {
    NSString *game = MRString(filters[@"mcVersion"]), *loader = MRString(filters[@"loader"]);
    NSMutableArray *matches = [NSMutableArray new];
    for (id version in versions) {
        if (![version isKindOfClass:NSDictionary.class]) continue;
        id games = version[@"game_versions"], loaders = version[@"loaders"];
        if (game.length && (![games isKindOfClass:NSArray.class] || ![games containsObject:game])) continue;
        if (loader.length && [[self contentTypeForFilters:filters] isEqual:@"mod"] && (![loaders isKindOfClass:NSArray.class] || ![loaders containsObject:loader])) continue;
        if (!MRString(version[@"id"]).length) continue;
        [matches addObject:version];
    }
    return matches;
}
@end
