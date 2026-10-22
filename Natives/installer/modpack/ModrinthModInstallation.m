#import "ModrinthModInstallation.h"
#import "ModrinthAPI.h"
#import "InstalledModsManager.h"
#import "AFURLSessionManager.h"
#include <CommonCrypto/CommonDigest.h>

NSNotificationName const ModrinthModInstallStateDidChangeNotification = @"ModrinthModInstallStateDidChange";
static ModrinthModInstallation *activeInstallation;

static NSError *MIError(NSString *key) {
    return [NSError errorWithDomain:@"ModrinthInstallation" code:1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(key, nil)}];
}
static BOOL MIFileName(id name, NSString *extension) {
    return [name isKindOfClass:NSString.class] && [name length] && [[name pathExtension].lowercaseString isEqual:extension] && ![name containsString:@"/"] && ![name containsString:@"\\"] && ![name hasPrefix:@"."];
}
static BOOL MILocalName(id name, NSString *extension) { return MIFileName(name, extension) || ([name isKindOfClass:NSString.class] && [name hasSuffix:@".disabled"] && MIFileName([name stringByDeletingPathExtension], extension)); }
static NSString *MIHash(NSData *data) {
    CC_SHA1_CTX context;
    CC_SHA1_Init(&context);
    const unsigned char *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining) {
        CC_LONG count = (CC_LONG)MIN(remaining, (NSUInteger)UINT32_MAX);
        CC_SHA1_Update(&context, bytes, count);
        bytes += count;
        remaining -= count;
    }
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &context);
    NSMutableString *hash = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [hash appendFormat:@"%02x", digest[i]];
    return hash;
}
static NSDictionary *MIIdentity(NSDictionary *version, NSString *projectID) {
    NSMutableDictionary *identity = [NSMutableDictionary new];
    for (NSString *key in @[@"id", @"name", @"version_number", @"date_published", @"project_id", @"provider"]) {
        if ([version[key] isKindOfClass:NSString.class]) identity[key] = version[key];
    }
    for (NSString *key in @[@"dependencies", @"game_versions", @"loaders", @"files"]) if ([version[key] isKindOfClass:NSArray.class]) identity[key] = [InstalledModsManager persistentObject:version[key]];
    if (projectID) identity[@"project_id"] = projectID;
    return identity;
}

@interface ModrinthModInstallation ()
@property(nonatomic) NSString *modsDirectory, *projectID;
@property(nonatomic) NSArray<NSDictionary *> *installedVersions;
@property(nonatomic) NSDictionary *installingVersion;
@property(nonatomic) NSProgress *progress;
@property(nonatomic) NSError *error;
@property(nonatomic) BOOL checking, busy, verifying;
@property(nonatomic) AFURLSessionManager *manager;
@property(nonatomic) NSURLSessionDataTask *task;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSArray *dependencyPlan;
@property(nonatomic) NSMutableDictionary *dependencyPayloads;
@property(nonatomic) NSUInteger dependencyIndex;
@property(nonatomic) NSString *dependencyStage;
@end

@implementation ModrinthModInstallation
+ (BOOL)isInstalling { return activeInstallation != nil; }
+ (BOOL)recoverDirectory:(NSString *)directory error:(NSError **)error {
    if ([activeInstallation.modsDirectory isEqual:directory.stringByStandardizingPath]) return YES;
    ModrinthModInstallation *installation = [self new];
    installation.modsDirectory = directory.stringByStandardizingPath;
    return [installation recoverTransactions:error] && [InstalledModsManager recoverDirectory:directory error:error];
}
+ (instancetype)installationForDirectory:(NSString *)directory projectID:(NSString *)projectID {
    return [self installationForDirectory:directory projectID:projectID provider:@"modrinth"];
}
+ (instancetype)installationForDirectory:(NSString *)directory projectID:(NSString *)projectID provider:(NSString *)provider {
    directory = directory.stringByStandardizingPath;
    if ([activeInstallation.modsDirectory isEqual:directory] && [activeInstallation.projectID isEqual:projectID] && [activeInstallation.provider isEqual:provider]) return activeInstallation;
    ModrinthModInstallation *installation = [[self alloc] initWithDirectory:directory projectID:projectID sessionConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    installation.provider = provider;
    return installation;
}
- (instancetype)initWithDirectory:(NSString *)directory projectID:(NSString *)projectID sessionConfiguration:(NSURLSessionConfiguration *)configuration {
    if ((self = [super init])) {
        self.modsDirectory = directory.stringByStandardizingPath;
        self.projectID = projectID;
        self.provider = @"modrinth";
        self.installedVersions = @[];
        configuration.timeoutIntervalForRequest = 60;
        self.manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
        self.manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    }
    return self;
}
+ (NSDictionary *)jarFileForVersion:(NSDictionary *)version {
    return [self fileForVersion:version extension:@"jar"];
}
+ (NSDictionary *)fileForVersion:(NSDictionary *)version extension:(NSString *)extension {
    NSDictionary *first;
    id files = version[@"files"];
    if (![files isKindOfClass:NSArray.class]) return nil;
    for (id file in files) {
        if (![file isKindOfClass:NSDictionary.class] || !MIFileName(file[@"filename"], extension)) continue;
        if ([@[@"sources-jar", @"javadoc-jar", @"dev-jar"] containsObject:file[@"file_type"] ?: NSNull.null]) continue;
        if ([file[@"primary"] isKindOfClass:NSNumber.class] && [file[@"primary"] boolValue]) return file;
        if (!first) first = file;
    }
    return first;
}
+ (NSString *)sha1ForFile:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    return data ? MIHash(data) : nil;
}
- (NSString *)fileExtension { return [@[@"resourcepacks", @"shaderpacks"] containsObject:self.modsDirectory.lastPathComponent] ? @"zip" : @"jar"; }
- (NSString *)stateDirectory {
    NSString *root = [self.modsDirectory.stringByDeletingLastPathComponent stringByAppendingPathComponent:@".amethyst-modrinth"];
    return [self.fileExtension isEqual:@"jar"] ? root : [root stringByAppendingPathComponent:self.modsDirectory.lastPathComponent];
}
- (NSString *)identityKey:(NSString *)hash { return [self.provider isEqual:@"modrinth"] ? hash : [NSString stringWithFormat:@"%@:%@", self.provider, hash]; }
- (void)dealloc { [self.manager invalidateSessionCancelingTasks:YES resetSession:NO]; }
- (void)changed { if (self.stateChanged) self.stateChanged(); }

// A journal keeps the previous JARs recoverable if the app stops during replacement.
- (BOOL)recoverTransactions:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [self.stateDirectory stringByAppendingPathComponent:@"transactions"];
    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil]) {
        NSString *transaction = [root stringByAppendingPathComponent:name];
        NSDictionary *journal = [NSDictionary dictionaryWithContentsOfFile:[transaction stringByAppendingPathComponent:@"journal.plist"]];
        if (!journal) continue;
        if (![journal[@"complete"] boolValue]) {
            NSString *target = journal[@"target"];
            NSArray *previous = journal[@"previous"];
            if (!MILocalName(target, self.fileExtension) || ![previous isKindOfClass:NSArray.class]) { if (error) *error = MIError(@"mods.install.recovery_error"); return NO; }
            for (NSString *filename in previous) {
                if (!MILocalName(filename, self.fileExtension)) { if (error) *error = MIError(@"mods.install.recovery_error"); return NO; }
                NSString *backup = [[transaction stringByAppendingPathComponent:@"backup"] stringByAppendingPathComponent:filename];
                NSData *data = [NSData dataWithContentsOfFile:backup options:0 error:error];
                if (!data || ![data writeToFile:[self.modsDirectory stringByAppendingPathComponent:filename] options:NSDataWritingAtomic error:error]) return NO;
            }
            if (![previous containsObject:target]) {
                NSString *path = [self.modsDirectory stringByAppendingPathComponent:target];
                if ([fm fileExistsAtPath:path] && ![fm removeItemAtPath:path error:error]) return NO;
            }
        }
        if (![fm removeItemAtPath:transaction error:error]) return NO;
    }
    return YES;
}

- (void)inspectWithVersions:(NSArray<NSDictionary *> *)versions {
    if (self.busy || self.checking) return;
    self.checking = YES;
    self.error = nil;
    NSUInteger generation = ++self.generation;
    [self changed];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableArray *installed = [NSMutableArray new];
        NSMutableDictionary *identities = [[NSDictionary dictionaryWithContentsOfFile:[self.stateDirectory stringByAppendingPathComponent:@"index.plist"]] mutableCopy] ?: [NSMutableDictionary new];
        for (NSDictionary *version in versions) {
            NSArray *files = [version[@"files"] isKindOfClass:NSArray.class] ? version[@"files"] : @[];
            for (id file in files) {
                if (![file isKindOfClass:NSDictionary.class] || ![file[@"hashes"] isKindOfClass:NSDictionary.class]) continue;
                NSString *hash = file[@"hashes"][@"sha1"];
                if ([hash isKindOfClass:NSString.class]) {
                    identities[[self identityKey:hash.lowercaseString]] = MIIdentity(version, self.projectID);
                }
            }
        }
        NSMutableDictionary *localFiles = [NSMutableDictionary new];
        NSMutableArray *unknown = [NSMutableArray new];
        if ([self recoverTransactions:&error] && [fm fileExistsAtPath:self.modsDirectory]) {
            NSArray *names = [fm contentsOfDirectoryAtPath:self.modsDirectory error:&error];
            for (NSString *filename in names) {
                if (!MILocalName(filename, self.fileExtension)) continue;
                NSString *path = [self.modsDirectory stringByAppendingPathComponent:filename];
                if (![[fm attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeRegular]) continue;
                NSString *hash = [self.class sha1ForFile:path error:&error];
                if (!hash) break;
                NSMutableArray *sameHash = localFiles[hash] ?: (localFiles[hash] = [NSMutableArray new]);
                [sameHash addObject:filename];
                if (!identities[[self identityKey:hash]] && ![unknown containsObject:hash]) [unknown addObject:hash];
            }
        }
        if (!error && unknown.count && [self.provider isEqual:@"modrinth"]) {
            ModrinthAPI *api = [ModrinthAPI new];
            NSDictionary *resolved = [api versionsForFileHashes:unknown];
            error = api.lastError;
            for (NSString *hash in resolved) {
                if ([resolved[hash] isKindOfClass:NSDictionary.class]) identities[hash] = MIIdentity(resolved[hash], nil);
            }
        }
        for (NSString *hash in localFiles) {
            NSDictionary *identity = identities[[self identityKey:hash]];
            if (![identity isKindOfClass:NSDictionary.class] || ![identity[@"project_id"] isEqual:self.projectID]) continue;
            for (NSString *filename in localFiles[hash]) [installed addObject:@{@"filename": filename, @"sha1": hash, @"version": identity}];
        }
        if (!error) {
            [fm createDirectoryAtPath:self.stateDirectory withIntermediateDirectories:YES attributes:nil error:nil];
            [identities writeToFile:[self.stateDirectory stringByAppendingPathComponent:@"index.plist"] atomically:YES];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) return;
            self.checking = NO;
            self.installedVersions = installed;
            self.error = error;
            [self changed];
        });
    });
}

- (BOOL)commitData:(NSData *)data file:(NSDictionary *)file error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:self.modsDirectory withIntermediateDirectories:YES attributes:nil error:error] || ![self recoverTransactions:error]) return NO;
    NSString *filename = file[@"filename"];
    NSString *destination = [self.modsDirectory stringByAppendingPathComponent:filename];
    NSMutableArray *previous = [NSMutableArray new];
    for (NSDictionary *entry in self.installedVersions) {
        NSString *old = entry[@"filename"];
        if (![[self.class sha1ForFile:[self.modsDirectory stringByAppendingPathComponent:old] error:error] isEqual:entry[@"sha1"]]) { if (error) *error = MIError(@"mods.install.changed_file"); return NO; }
        [previous addObject:old];
    }
    if ([fm fileExistsAtPath:destination] && ![previous containsObject:filename]) { if (error) *error = MIError(@"mods.install.name_conflict"); return NO; }
    NSString *transaction = [[self.stateDirectory stringByAppendingPathComponent:@"transactions"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *backup = [transaction stringByAppendingPathComponent:@"backup"];
    if (![fm createDirectoryAtPath:backup withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    for (NSString *old in previous) {
        if (![fm copyItemAtPath:[self.modsDirectory stringByAppendingPathComponent:old] toPath:[backup stringByAppendingPathComponent:old] error:error]) { [fm removeItemAtPath:transaction error:nil]; return NO; }
    }
    NSMutableDictionary *journal = [@{@"target": filename, @"previous": previous, @"complete": @NO} mutableCopy];
    NSString *journalPath = [transaction stringByAppendingPathComponent:@"journal.plist"];
    if (![journal writeToFile:journalPath atomically:YES]) { if (error) *error = MIError(@"mods.install.recovery_error"); [fm removeItemAtPath:transaction error:nil]; return NO; }
    BOOL success = [data writeToFile:destination options:NSDataWritingAtomic error:error];
    for (NSString *old in previous) {
        if (success && ![old isEqual:filename]) success = [fm removeItemAtPath:[self.modsDirectory stringByAppendingPathComponent:old] error:error];
    }
    if (success) {
        journal[@"complete"] = @YES;
        success = [journal writeToFile:journalPath atomically:YES];
        if (!success && error) *error = MIError(@"mods.install.recovery_error");
    }
    NSError *recoveryError;
    if (![self recoverTransactions:&recoveryError] && !success && error) *error = recoveryError;
    return success;
}

- (void)installVersion:(NSDictionary *)version {
    if (self.busy || self.checking) return;
    if (activeInstallation) { self.error = MIError(@"mods.install.busy"); [self changed]; return; }
    NSDictionary *file = [self.class fileForVersion:version extension:self.fileExtension];
    NSDictionary *hashes = [file[@"hashes"] isKindOfClass:NSDictionary.class] ? file[@"hashes"] : @{};
    NSString *hash = hashes[@"sha1"];
    NSURL *url = [NSURL URLWithString:[file[@"url"] isKindOfClass:NSString.class] ? file[@"url"] : @""];
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    if ([version[@"downloadUnavailable"] boolValue] || !file || ![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length || ![hash isKindOfClass:NSString.class] || hash.length != 40 || [hash rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound || ![file[@"size"] isKindOfClass:NSNumber.class] || [file[@"size"] longLongValue] <= 0 || ![version[@"id"] isKindOfClass:NSString.class] || ![version[@"id"] length] || ([version[@"project_id"] isKindOfClass:NSString.class] && ![version[@"project_id"] isEqual:self.projectID])) {
        self.error = MIError(@"content.download.unavailable"); [self changed]; return;
    }
    self.error = nil;
    self.busy = YES;
    self.verifying = NO;
    self.installingVersion = version;
    self.progress = [NSProgress progressWithTotalUnitCount:[file[@"size"] longLongValue]];
    activeInstallation = self;
    [NSNotificationCenter.defaultCenter postNotificationName:ModrinthModInstallStateDidChangeNotification object:self];
    [self changed];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"AngelAuraAmethyst/1.0 (https://github.com/AngelAuraMC/Amethyst-iOS)" forHTTPHeaderField:@"User-Agent"];
    self.task = [self.manager dataTaskWithRequest:request uploadProgress:nil downloadProgress:^(NSProgress *progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.busy || self.verifying) return;
            self.progress.completedUnitCount = MIN(progress.completedUnitCount, self.progress.totalUnitCount);
            [self changed];
        });
    } completionHandler:^(NSURLResponse *response, id object, NSError *downloadError) {
        self.verifying = YES;
        [self changed];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = downloadError;
            NSData *data = [object isKindOfClass:NSData.class] ? object : nil;
            if (self.progress.cancelled) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
            if (!error && (data.length != [file[@"size"] unsignedLongLongValue] || ![MIHash(data) isEqual:hash.lowercaseString])) error = MIError(@"mods.install.hash_error");
            if (!error) [self commitData:data file:file error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                self.verifying = NO;
                self.task = nil;
                self.error = error;
                if (!error) {
                    self.progress.completedUnitCount = self.progress.totalUnitCount;
                    NSDictionary *identity = MIIdentity(version, self.projectID);
                    self.installedVersions = @[@{@"filename": file[@"filename"], @"sha1": hash.lowercaseString, @"version": identity}];
                    NSMutableDictionary *index = [[NSDictionary dictionaryWithContentsOfFile:[self.stateDirectory stringByAppendingPathComponent:@"index.plist"]] mutableCopy] ?: [NSMutableDictionary new];
                    index[[self identityKey:hash.lowercaseString]] = identity;
                    [index writeToFile:[self.stateDirectory stringByAppendingPathComponent:@"index.plist"] atomically:YES];
                }
                if (activeInstallation == self) activeInstallation = nil;
                [NSNotificationCenter.defaultCenter postNotificationName:ModrinthModInstallStateDidChangeNotification object:self];
                [self changed];
            });
        });
    }];
    [self.task resume];
}
- (void)installVersion:(NSDictionary *)version resolvingDependenciesWithFilters:(NSDictionary *)filters {
    [self startDependencyOperation:version filters:filters];
}
- (void)resolveDependenciesWithFilters:(NSDictionary *)filters { [self startDependencyOperation:nil filters:filters]; }
- (void)enableVersion:(NSDictionary *)version resolvingDependenciesWithFilters:(NSDictionary *)filters {
    NSMutableDictionary *context = filters.mutableCopy; context[@"enableRequested"] = @YES;
    [self startDependencyOperation:version filters:context];
}
- (void)startDependencyOperation:(NSDictionary *)version filters:(NSDictionary *)filters {
    if (self.busy || self.checking) return;
    if (activeInstallation) { self.error = MIError(@"mods.install.busy"); [self changed]; return; }
    self.busy = YES; self.checking = YES; self.verifying = NO; self.error = nil;
    self.installingVersion = version ?: @{@"version_number": NSLocalizedString(@"mods.installed.dependencies", nil)};
    self.progress = [NSProgress progressWithTotalUnitCount:0]; activeInstallation = self;
    [NSNotificationCenter.defaultCenter postNotificationName:ModrinthModInstallStateDidChangeNotification object:self]; [self changed];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        NSArray *entries = [InstalledModsManager entriesInDirectory:self.modsDirectory identify:YES error:&error];
        BOOL disabled = NO;
        for (NSDictionary *entry in entries) if ([entry[@"version"][@"project_id"] isEqual:self.projectID] && [entry[@"provider"] isEqual:self.provider]) disabled |= ![entry[@"enabled"] boolValue];
        if ([filters[@"enableRequested"] boolValue]) disabled = NO;
        NSArray *requested = version ? @[@{@"version":version, @"provider":self.provider, @"disabled":@(disabled)}] : @[];
        NSArray *plan = entries ? [InstalledModsManager planForEntries:entries requested:requested filters:filters error:&error] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checking = NO;
            if (error || self.progress.cancelled) { [self finishDependencyOperation:error ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]]; return; }
            self.dependencyPlan = plan; self.dependencyIndex = 0; self.dependencyPayloads = [NSMutableDictionary new];
            self.dependencyStage = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"amethyst-mod-download-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            NSError *stageError;
            if (![NSFileManager.defaultManager createDirectoryAtPath:self.dependencyStage withIntermediateDirectories:YES attributes:nil error:&stageError]) { [self finishDependencyOperation:stageError]; return; }
            int64_t total = 0;
            for (NSDictionary *item in plan) total += [[self.class fileForVersion:item[@"version"] extension:self.fileExtension][@"size"] longLongValue];
            self.progress.totalUnitCount = total; [self downloadNextDependency];
        });
    });
}
- (void)downloadNextDependency {
    if (self.progress.cancelled) { [self finishDependencyOperation:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]]; return; }
    if (self.dependencyIndex == self.dependencyPlan.count) {
        self.verifying = YES; [self changed];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error;
            if (self.dependencyPlan.count && ![InstalledModsManager commitPlan:self.dependencyPlan payloads:self.dependencyPayloads directory:self.modsDirectory error:&error] && !error) error = MIError(@"mods.install.recovery_error");
            dispatch_async(dispatch_get_main_queue(), ^{ [self finishDependencyOperation:error]; });
        });
        return;
    }
    NSDictionary *item = self.dependencyPlan[self.dependencyIndex], *version = item[@"version"];
    NSDictionary *file = [self.class fileForVersion:version extension:self.fileExtension]; NSString *hash = file[@"hashes"][@"sha1"];
    NSURL *url = [NSURL URLWithString:[file[@"url"] isKindOfClass:NSString.class] ? file[@"url"] : @""];
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    if (!file || [version[@"downloadUnavailable"] boolValue] || ![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length || ![hash isKindOfClass:NSString.class] || hash.length != 40 || [hash rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound || [file[@"size"] longLongValue] <= 0) { [self finishDependencyOperation:MIError(@"content.download.unavailable")]; return; }
    // Reactivating a verified local file needs no download. It still participates in the batch journal.
    for (NSDictionary *entry in item[@"previous"]) if ([entry[@"sha1"] isEqual:hash.lowercaseString]) {
        NSData *data = [NSData dataWithContentsOfFile:[self.modsDirectory stringByAppendingPathComponent:entry[@"filename"]] options:NSDataReadingMappedIfSafe error:nil];
        if (data.length == [file[@"size"] unsignedLongLongValue] && [MIHash(data) isEqual:hash.lowercaseString]) {
            NSError *stageError; NSString *path = [self.dependencyStage stringByAppendingPathComponent:hash];
            if (![data writeToFile:path options:NSDataWritingAtomic error:&stageError]) { [self finishDependencyOperation:stageError]; return; }
            self.dependencyPayloads[hash] = path; self.progress.completedUnitCount += data.length; self.dependencyIndex++;
            [self downloadNextDependency]; return;
        }
    }
    self.installingVersion = version; [self changed];
    int64_t completed = self.progress.completedUnitCount;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"AngelAuraAmethyst/1.0 (https://github.com/AngelAuraMC/Amethyst-iOS)" forHTTPHeaderField:@"User-Agent"];
    self.task = [self.manager dataTaskWithRequest:request uploadProgress:nil downloadProgress:^(NSProgress *progress) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.busy && !self.verifying) { self.progress.completedUnitCount = completed + MIN(progress.completedUnitCount, [file[@"size"] longLongValue]); [self changed]; } });
    } completionHandler:^(NSURLResponse *response, id object, NSError *downloadError) {
        NSData *data = [object isKindOfClass:NSData.class] ? object : nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = downloadError;
            if (!error && (data.length != [file[@"size"] unsignedLongLongValue] || ![MIHash(data) isEqual:hash.lowercaseString])) error = MIError(@"mods.install.hash_error");
            NSString *path = [self.dependencyStage stringByAppendingPathComponent:hash];
            if (!error) [data writeToFile:path options:NSDataWritingAtomic error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) { [self finishDependencyOperation:error]; return; }
                self.dependencyPayloads[hash] = path;
                self.progress.completedUnitCount = completed + data.length; self.dependencyIndex++; [self downloadNextDependency];
            });
        });
    }];
    [self.task resume];
}
- (void)finishDependencyOperation:(NSError *)error {
    self.busy = NO; self.checking = NO; self.verifying = NO; self.task = nil; self.error = error;
    self.dependencyPayloads = nil; self.dependencyPlan = nil;
    if (self.dependencyStage) [NSFileManager.defaultManager removeItemAtPath:self.dependencyStage error:nil];
    self.dependencyStage = nil;
    if (activeInstallation == self) activeInstallation = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:ModrinthModInstallStateDidChangeNotification object:self]; [self changed];
    if (!error) [self inspectWithVersions:@[]];
}
- (void)cancel { [self.progress cancel]; [self.task cancel]; }
@end
