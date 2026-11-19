#import "BuiltinJIT.h"
#import "LauncherPreferences.h"
#import "utils.h"
#import <Security/Security.h>
#import <TargetConditionals.h>
#include <dlfcn.h>

NSNotificationName const BuiltinJITStatusDidChangeNotification = @"BuiltinJITStatusDidChange";
static NSString *const RequestKey = @"amethyst-jit-request";
static NSString *const ResponseKey = @"amethyst-jit-response";

// NSExtension is SPI. The helper uses a classic extension point so sideloaders
// can rewrite its bundle identifier together with the containing application.
@interface NSObject (AmethystJITExtension)
+ (id)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *, NSArray *))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *, NSError *))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *))block;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))completion;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)identifier;
@end

@interface BuiltinJIT ()
@property(nonatomic) BOOL busy, enabling, deliveredReady;
@property(nonatomic, copy) NSString *status, *operation;
@property(nonatomic, strong) NSNumber *txmPresent;
@property(nonatomic, strong) id helper;
@property(nonatomic, strong) NSUUID *requestIdentifier, *generation;
@property(nonatomic, strong) dispatch_source_t readinessTimer;
@property(nonatomic, copy) void (^completion)(NSError *);
@end

@implementation BuiltinJIT

+ (instancetype)shared {
    static BuiltinJIT *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [BuiltinJIT new]; });
    return manager;
}

+ (NSURL *)helperURL {
    return [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"AmethystJITHelper.appex"];
}

+ (NSString *)unavailableReason {
#if TARGET_OS_SIMULATOR || TARGET_OS_MACCATALYST || TARGET_OS_TV
    return localize(@"jit.error.device", nil);
#else
    if (@available(iOS 17.4, *)) {
        if (getenv("LC_HOME_PATH")) return localize(@"jit.error.livecontainer", nil);
        if (![NSBundle bundleWithURL:self.helperURL].bundleIdentifier.length) {
            return localize(@"jit.error.helper", nil);
        }
        return nil;
    }
    return localize(@"jit.error.os", nil);
#endif
}

- (NSString *)status {
    return _status ?: localize(@"jit.status.idle", nil);
}

- (void)publishStatus:(NSString *)status {
    self.status = status;
    [NSNotificationCenter.defaultCenter postNotificationName:BuiltinJITStatusDidChangeNotification object:self];
}

- (NSMutableDictionary *)pairingQuery {
    return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".StikJIT"],
        (__bridge id)kSecAttrAccount: @"pairingFile"} mutableCopy];
}

- (NSData *)pairingData {
    NSMutableDictionary *query = self.pairingQuery;
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    return status == errSecSuccess ? CFBridgingRelease(result) : nil;
}

- (NSString *)pairingFileName {
    NSMutableDictionary *query = self.pairingQuery;
    query[(__bridge id)kSecReturnAttributes] = @YES;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
    NSDictionary *attributes = CFBridgingRelease(result);
    return attributes[(__bridge id)kSecAttrLabel] ?: @"pairingFile.plist";
}

- (BOOL)hasPairingFile { return self.pairingFileName != nil; }

static NSError *JITError(NSString *message) {
    return [NSError errorWithDomain:@"AmethystStikJIT" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (BOOL)importPairingFile:(NSURL *)url error:(NSError **)error {
    if (self.busy) { if (error) *error = JITError(localize(@"jit.error.busy", nil)); return NO; }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!data) return NO;
    id plist = data.length <= 2 * 1024 * 1024 ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
    NSDictionary *record = [plist isKindOfClass:NSDictionary.class] ? plist : nil;
    if (![record[@"public_key"] isKindOfClass:NSData.class] || [record[@"public_key"] length] != 32 ||
        ![record[@"private_key"] isKindOfClass:NSData.class] || [record[@"private_key"] length] != 32 ||
        ![record[@"identifier"] isKindOfClass:NSString.class] || ![record[@"identifier"] length]) {
        if (error) *error = JITError(localize(@"jit.error.pairing_format", nil));
        return NO;
    }
    NSDictionary *values = @{(__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrLabel: url.lastPathComponent,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
    NSMutableDictionary *query = self.pairingQuery;
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)values);
    if (status == errSecItemNotFound) {
        [query addEntriesFromDictionary:values];
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    if (status != errSecSuccess) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        return NO;
    }
    self.txmPresent = nil;
    [self publishStatus:localize(@"jit.status.imported", nil)];
    return YES;
}

- (BOOL)removePairingFile:(NSError **)error {
    if (self.busy) { if (error) *error = JITError(localize(@"jit.error.busy", nil)); return NO; }
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)self.pairingQuery);
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        return NO;
    }
    self.txmPresent = nil;
    [self publishStatus:localize(@"jit.status.idle", nil)];
    return YES;
}

- (void)prepareWithCompletion:(void (^)(NSError *))completion {
    [self runOperation:@"prepare" completion:completion];
}

- (void)resetDDIWithCompletion:(void (^)(NSError *))completion {
    [self runOperation:@"resetDDI" completion:completion];
}

- (void)enableWithReadyHandler:(void (^)(NSError *))handler {
    [self runOperation:@"enable" completion:handler];
}

- (void)runOperation:(NSString *)operation completion:(void (^)(NSError *))completion {
    NSAssert(NSThread.isMainThread, @"JIT requests must start on the main thread");
    NSString *reason = self.class.unavailableReason;
    if (!reason && self.busy) reason = localize(@"jit.error.busy", nil);
    if (!reason && !getEntitlementValue(@"get-task-allow")) reason = localize(@"jit.error.signing", nil);
    NSData *pairing = nil;
    if (!reason && ![operation isEqualToString:@"resetDDI"]) {
        pairing = self.pairingData;
        if (!pairing.length) reason = localize(@"jit.error.pairing_missing", nil);
    }
    if (reason) { completion(JITError(reason)); return; }

    NSMutableDictionary *request = [@{@"operation": operation, @"targetPID": @(getpid()),
        @"forceScript": @(getPrefBool(@"jit.force_script"))} mutableCopy];
    if (pairing) request[@"pairingData"] = pairing;
    BOOL enabling = [operation isEqualToString:@"enable"];
    if (enabling) {
        NSData *script = [NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"UniversalJIT26" withExtension:@"js"]];
        if (!script.length) { completion(JITError(localize(@"jit.error.script", nil))); return; }
        request[@"scriptBase64"] = [script base64EncodedStringWithOptions:0];
        // Respect the same JIT_FLAGS overrides as the existing Java launcher.
        request[@"forceScript"] = @(getPrefBool(@"jit.force_script") || DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM));
    }

    Class extensionClass = NSClassFromString(@"NSExtension");
    if (!extensionClass) {
        dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW);
        extensionClass = NSClassFromString(@"NSExtension");
    }
    NSError *error;
    NSString *identifier = [NSBundle bundleWithURL:self.class.helperURL].bundleIdentifier;
    id helper = [extensionClass extensionWithIdentifier:identifier error:&error];
    if (!helper) { completion(error ?: JITError(localize(@"jit.error.helper", nil))); return; }

    self.helper = helper;
    self.busy = YES;
    self.enabling = enabling;
    self.operation = operation;
    self.deliveredReady = NO;
    self.completion = completion;
    NSUUID *generation = self.generation = NSUUID.UUID;
    __weak BuiltinJIT *weakSelf = self;
    [helper setRequestCompletionBlock:^(NSUUID *uuid, NSArray *items) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf.generation isEqual:generation]) return;
            id response = [items.firstObject isKindOfClass:NSExtensionItem.class] ? [items.firstObject userInfo][ResponseKey] : nil;
            if (![response isKindOfClass:NSDictionary.class]) {
                [weakSelf finish:JITError(localize(@"jit.error.response", nil))];
                return;
            }
            weakSelf.txmPresent = [response[@"txmPresent"] isKindOfClass:NSNumber.class] ? response[@"txmPresent"] : nil;
            NSError *result = [response[@"success"] boolValue] ? nil : JITError(response[@"message"] ?: localize(@"jit.error.response", nil));
            if (!result && weakSelf.enabling && !weakSelf.deliveredReady && !isJITEnabled(NO)) {
                result = JITError(localize(@"jit.error.not_ready", nil));
            }
            [weakSelf finish:result];
        });
    }];
    [helper setRequestCancellationBlock:^(NSUUID *uuid, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([weakSelf.generation isEqual:generation]) [weakSelf finish:error ?: JITError(localize(@"jit.error.interrupted", nil))];
        });
    }];
    [helper setRequestInterruptionBlock:^(NSUUID *uuid) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([weakSelf.generation isEqual:generation]) [weakSelf finish:JITError(localize(@"jit.error.interrupted", nil))];
        });
    }];
    [self publishStatus:localize(@"jit.status.working", nil)];
    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{RequestKey: request};
    [helper beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *uuid) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf.generation isEqual:generation]) {
                if (uuid) [helper cancelExtensionRequestWithIdentifier:uuid];
                return;
            }
            weakSelf.requestIdentifier = uuid;
            if (!uuid) [weakSelf finish:JITError(localize(@"jit.error.helper", nil))];
        });
    }];
    if (enabling) {
        self.readinessTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(self.readinessTimer, DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(self.readinessTimer, ^{
            if (isJITEnabled(NO)) [weakSelf deliverReady];
        });
        dispatch_resume(self.readinessTimer);
    }
    // A script can legitimately remain attached for the entire game. The startup
    // deadline applies only until readiness, never to an active debugger session.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([weakSelf.generation isEqual:generation] && !weakSelf.deliveredReady) {
            [weakSelf abort:JITError(localize(@"jit.error.timeout", nil))];
        }
    });
}

- (void)stopReadinessTimer {
    if (self.readinessTimer) dispatch_source_cancel(self.readinessTimer);
    self.readinessTimer = nil;
}

- (void)deliverReady {
    if (self.deliveredReady) return;
    self.deliveredReady = YES;
    [self stopReadinessTimer];
    [self publishStatus:localize(@"jit.status.attached", nil)];
    void (^completion)(NSError *) = self.completion;
    self.completion = nil;
    if (completion) completion(nil);
}

- (void)finish:(NSError *)error {
    [self stopReadinessTimer];
    void (^completion)(NSError *) = self.completion;
    self.completion = nil;
    self.generation = nil;
    self.requestIdentifier = nil;
    self.helper = nil;
    self.busy = NO;
    NSString *successKey = self.enabling ? @"jit.status.enabled" : ([self.operation isEqualToString:@"resetDDI"] ? @"jit.status.reset" : @"jit.status.prepared");
    [self publishStatus:error ? error.localizedDescription : localize(successKey, nil)];
    NSLog(@"[StikJIT] %@", self.status);
    if (completion) completion(error);
}

- (void)abort:(NSError *)error {
    id helper = self.helper;
    NSUUID *identifier = self.requestIdentifier;
    [self finish:error];
    if (identifier) [helper cancelExtensionRequestWithIdentifier:identifier];
}

- (void)cancelPendingEnable {
    if (self.busy && self.enabling && !self.deliveredReady) {
        [self abort:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    }
}

@end
