#import "AmethystPairing.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include "idevice.h"

static NSString *const PINNotification = @"amethyst.pairing.pin";

static NSError *PairingError(NSString *key) {
    return [NSError errorWithDomain:@"AmethystPairing" code:1
        userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(key, nil)}];
}

static NSError *ConsumeError(IdeviceFfiError *error) {
    if (!error) return nil;
    // Do not log protocol errors or include protocol payloads in the UI.
    idevice_error_free(error);
    return PairingError(@"jit.pairing.error.handshake");
}

@interface AmethystPairingService : NSObject <AmethystPairingSession, NSNetServiceDelegate> {
    int _listener, _connection;
    BOOL _cancelled, _finished;
}
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, copy) void (^progress)(NSString *, NSString *);
@property(nonatomic, copy) void (^completion)(NSData *, NSError *);
@property(nonatomic) NSNetService *service;
@property(nonatomic) NSError *terminalError;
@property(nonatomic) AVAudioEngine *audio;
@property(nonatomic) AVAudioPlayerNode *player;
@property(nonatomic, copy) NSString *oldCategory, *oldMode;
@property(nonatomic) AVAudioSessionCategoryOptions oldOptions;
@property(nonatomic) UIBackgroundTaskIdentifier backgroundTask;
- (BOOL)isCancelled;
- (void)stopWithError:(NSError *)error;
@end

static void PairingPIN(const char *pin, void *context) {
    AmethystPairingService *session = (__bridge AmethystPairingService *)context;
    NSString *value = pin ? [NSString stringWithUTF8String:pin] : nil;
    if (!value.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (session.isCancelled || !session.progress) return;
        session.progress(@"pin", value);
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = NSLocalizedString(@"jit.pairing.pin.title", nil);
        content.body = [NSString stringWithFormat:NSLocalizedString(@"jit.pairing.pin.body", nil), value];
        content.sound = UNNotificationSound.defaultSound;
        [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:
            [UNNotificationRequest requestWithIdentifier:PINNotification content:content trigger:nil]
            withCompletionHandler:^(NSError *error) {
                if (error) dispatch_async(dispatch_get_main_queue(), ^{
                    [session stopWithError:PairingError(@"jit.pairing.error.notifications")];
                });
            }];
    });
}

@implementation AmethystPairingService

- (instancetype)init {
    if ((self = [super init])) {
        _listener = _connection = -1;
        _backgroundTask = UIBackgroundTaskInvalid;
        _hostname = [NSString stringWithFormat:@"Amethyst-%06u", arc4random_uniform(1000000)];
    }
    return self;
}

- (BOOL)isCancelled {
    @synchronized (self) { return _cancelled; }
}

- (void)startWithProgress:(void (^)(NSString *, NSString *))progress
              completion:(void (^)(NSData *, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Pairing starts on the main thread");
    self.progress = progress;
    self.completion = completion;
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:
        (UNAuthorizationOptionAlert | UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.isCancelled) { [self finish:nil error:self.terminalError]; return; }
            if (!granted || error) {
                [self finish:nil error:PairingError(@"jit.pairing.error.notifications")];
                return;
            }
            NSError *audioError;
            if (![self startKeepAlive:&audioError]) {
                [self finish:nil error:PairingError(@"jit.pairing.error.background")];
                return;
            }
            self.backgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"Amethyst pairing"
                expirationHandler:^{
                    // Background audio owns the longer pairing session. Release
                    // this finite transition task as soon as the system asks.
                    [self endBackgroundTask];
                }];
            // A pairing session is always bounded, including when Settings is open.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (!self->_finished) [self stopWithError:PairingError(@"jit.pairing.error.timeout")];
            });
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self pair]; });
        });
    }];
}

- (BOOL)startKeepAlive:(NSError **)error {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    self.oldCategory = session.category;
    self.oldMode = session.mode;
    self.oldOptions = session.categoryOptions;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
        options:AVAudioSessionCategoryOptionMixWithOthers error:error] || ![session setActive:YES error:error]) return NO;
    self.audio = [AVAudioEngine new];
    self.player = [AVAudioPlayerNode new];
    [self.audio attachNode:self.player];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    [self.audio connect:self.player to:self.audio.mainMixerNode format:format];
    AVAudioPCMBuffer *silence = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:44100];
    silence.frameLength = 44100;
    memset(silence.floatChannelData[0], 0, 44100 * sizeof(float));
    [self.player scheduleBuffer:silence atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
    if (![self.audio startAndReturnError:error]) return NO;
    [self.player play];
    return YES;
}

- (void)pair {
    @autoreleasepool {
        PairableHostHandle *host = NULL;
        RpPairingFileHandle *record = NULL;
        char *serviceID = NULL;
        uint8_t *txtBytes = NULL, *recordBytes = NULL;
        uintptr_t txtLength = 0, recordLength = 0;
        NSError *error = nil;
        NSData *data = nil;
        do {
            error = ConsumeError(pairable_host_prepare(self.hostname.UTF8String, "Mac17,7", false,
                &host, &serviceID, &txtBytes, &txtLength, NULL));
            if (error) break;
            if (!host || !serviceID || !txtBytes || txtLength > 64 * 1024) {
                error = PairingError(@"jit.pairing.error.handshake"); break;
            }
            id txt = [NSPropertyListSerialization propertyListWithData:
                [NSData dataWithBytes:txtBytes length:txtLength] options:0 format:nil error:&error];
            if (![txt isKindOfClass:NSDictionary.class]) {
                error = PairingError(@"jit.pairing.error.handshake"); break;
            }
            NSMutableDictionary *records = [NSMutableDictionary new];
            for (NSString *key in txt) {
                id value = txt[key];
                if ([value isKindOfClass:NSString.class]) value = [value dataUsingEncoding:NSUTF8StringEncoding];
                if ([value isKindOfClass:NSNumber.class]) value = [[value stringValue] dataUsingEncoding:NSUTF8StringEncoding];
                if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSData.class]) records[key] = value;
            }
            int listener = socket(AF_INET, SOCK_STREAM, 0);
            @synchronized (self) { _listener = listener; }
            if (self.isCancelled) break;
            struct sockaddr_in address = {0};
            address.sin_len = sizeof(address);
            address.sin_family = AF_INET;
            address.sin_addr.s_addr = INADDR_ANY;
            socklen_t size = sizeof(address);
            if (listener < 0 || fcntl(listener, F_SETFL, O_NONBLOCK) ||
                bind(listener, (struct sockaddr *)&address, size) || listen(listener, 1) ||
                getsockname(listener, (struct sockaddr *)&address, &size)) {
                error = PairingError(@"jit.pairing.error.network"); break;
            }
            NSString *name = [NSString stringWithUTF8String:serviceID];
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (self.isCancelled) return;
                self.service = [[NSNetService alloc] initWithDomain:@"local."
                    type:@"_remotepairing-pairable-host._tcp." name:name port:ntohs(address.sin_port)];
                self.service.delegate = self;
                [self.service setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:records]];
                [self.service publish];
            });
            int connection = -1;
            while (!self.isCancelled) {
                // Do not depend on shutdown waking accept on a listening socket.
                struct pollfd event = {.fd = listener, .events = POLLIN};
                int ready = poll(&event, 1, 250);
                if (ready == 0) continue;
                if (ready < 0) { if (errno == EINTR) continue; break; }
                if (!(event.revents & POLLIN)) break;
                connection = accept(listener, NULL, NULL);
                if (connection < 0) {
                    if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
                    break;
                }
                // Darwin may inherit O_NONBLOCK from the listening socket.
                if (fcntl(connection, F_SETFL, 0)) { close(connection); connection = -1; break; }
                // Only this phone may pair. A nearby device cannot replace its record.
                struct sockaddr_in peer = {0}, local = {0};
                socklen_t peerSize = sizeof(peer), localSize = sizeof(local);
                BOOL sameDevice = !getpeername(connection, (struct sockaddr *)&peer, &peerSize) &&
                    !getsockname(connection, (struct sockaddr *)&local, &localSize) &&
                    peer.sin_family == AF_INET && peer.sin_addr.s_addr == local.sin_addr.s_addr;
                if (sameDevice) break;
                close(connection);
                connection = -1;
            }
            @synchronized (self) {
                _connection = connection;
                if (_cancelled && connection >= 0) shutdown(connection, SHUT_RDWR);
            }
            if (self.isCancelled) break;
            if (connection < 0) { error = PairingError(@"jit.pairing.error.network"); break; }
            error = ConsumeError(pairable_host_accept_fd(host, connection, PairingPIN,
                (__bridge void *)self, NULL, &record));
            if (error || self.isCancelled) break;
            if (!record) { error = PairingError(@"jit.pairing.error.handshake"); break; }
            error = ConsumeError(rp_pairing_file_to_bytes(record, &recordBytes, &recordLength));
            if (error) break;
            if (!recordBytes || recordLength == 0 || recordLength > 2 * 1024 * 1024) {
                error = PairingError(@"jit.pairing.error.handshake"); break;
            }
            data = [NSData dataWithBytes:recordBytes length:recordLength];
        } while (0);
        @synchronized (self) {
            if (_connection >= 0) close(_connection);
            if (_listener >= 0) close(_listener);
            _connection = _listener = -1;
        }
        rp_pairing_file_free(record);
        pairable_host_free(host);
        idevice_string_free(serviceID);
        idevice_data_free(txtBytes, txtLength);
        idevice_data_free(recordBytes, recordLength);
        dispatch_async(dispatch_get_main_queue(), ^{ [self finish:data error:error]; });
    }
}

- (void)netServiceDidPublish:(NSNetService *)sender {
    if (!_finished && !self.isCancelled && self.progress) self.progress(@"waiting", self.hostname);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *, NSNumber *> *)error {
    [self stopWithError:PairingError(@"jit.pairing.error.network")];
}

- (void)stopWithError:(NSError *)error {
    @synchronized (self) {
        if (_finished || _cancelled) return;
        _cancelled = YES;
        self.terminalError = error;
        // The worker owns each descriptor and closes it only after its FFI call
        // returns. shutdown also interrupts the descriptor duplicated by idevice.
        if (_listener >= 0) shutdown(_listener, SHUT_RDWR);
        if (_connection >= 0) shutdown(_connection, SHUT_RDWR);
    }
    [self.service stop];
    [self.player stop];
    [self.audio stop];
}

- (void)cancel {
    [self stopWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}

- (void)endBackgroundTask {
    if (self.backgroundTask == UIBackgroundTaskInvalid) return;
    UIBackgroundTaskIdentifier task = self.backgroundTask;
    self.backgroundTask = UIBackgroundTaskInvalid;
    [UIApplication.sharedApplication endBackgroundTask:task];
}

- (void)finish:(NSData *)data error:(NSError *)error {
    if (_finished) return;
    _finished = YES;
    if (self.isCancelled) { data = nil; error = self.terminalError; }
    if (!data && !error) error = PairingError(@"jit.pairing.error.handshake");
    self.service.delegate = nil;
    [self.service stop];
    self.service = nil;
    [self.player stop];
    [self.audio stop];
    if (self.oldCategory) {
        [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        [AVAudioSession.sharedInstance setCategory:self.oldCategory mode:self.oldMode options:self.oldOptions error:nil];
    }
    self.player = nil;
    self.audio = nil;
    [self endBackgroundTask];
    UNUserNotificationCenter *notifications = UNUserNotificationCenter.currentNotificationCenter;
    [notifications removePendingNotificationRequestsWithIdentifiers:@[PINNotification]];
    [notifications removeDeliveredNotificationsWithIdentifiers:@[PINNotification]];
    void (^completion)(NSData *, NSError *) = self.completion;
    self.completion = nil;
    self.progress = nil;
    if (completion) completion(data, error);
}
@end
