#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSNotificationName const ModrinthModInstallStateDidChangeNotification;

@interface ModrinthModInstallation : NSObject
@property(nonatomic, copy) NSString *provider;
@property(nonatomic, readonly) NSString *modsDirectory;
@property(nonatomic, readonly) NSString *projectID;
@property(nonatomic, readonly) NSArray<NSDictionary *> *installedVersions;
@property(nonatomic, readonly) NSDictionary *installingVersion;
@property(nonatomic, readonly) NSProgress *progress;
@property(nonatomic, readonly) NSError *error;
@property(nonatomic, readonly) BOOL checking, busy, verifying;
@property(nonatomic, copy) void (^stateChanged)(void);

+ (BOOL)isInstalling;
+ (BOOL)recoverDirectory:(NSString *)directory error:(NSError **)error;
+ (instancetype)installationForDirectory:(NSString *)directory projectID:(NSString *)projectID;
+ (instancetype)installationForDirectory:(NSString *)directory projectID:(NSString *)projectID provider:(NSString *)provider;
+ (NSDictionary *)fileForVersion:(NSDictionary *)version extension:(NSString *)extension;
+ (NSDictionary *)jarFileForVersion:(NSDictionary *)version;
+ (NSString *)sha1ForFile:(NSString *)path error:(NSError **)error;
- (instancetype)initWithDirectory:(NSString *)directory projectID:(NSString *)projectID sessionConfiguration:(NSURLSessionConfiguration *)configuration;
- (void)inspectWithVersions:(NSArray<NSDictionary *> *)versions;
- (void)installVersion:(NSDictionary *)version;
- (void)installVersion:(NSDictionary *)version resolvingDependenciesWithFilters:(NSDictionary *)filters;
- (void)enableVersion:(NSDictionary *)version resolvingDependenciesWithFilters:(NSDictionary *)filters;
- (void)resolveDependenciesWithFilters:(NSDictionary *)filters;
- (void)cancel;
@end
