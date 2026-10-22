#import <Foundation/Foundation.h>
#import "ModpackUtils.h"
#import "UnzipKit.h"

@class MinecraftResourceDownloadTask;

@interface ModpackAPI : NSObject
@property(nonatomic) NSString *baseURL;
@property(nonatomic) NSError *lastError;
@property(nonatomic) BOOL reachedLastPage;

- (instancetype)initWithURL:(NSString *)url;
- (NSMutableArray *)searchModWithFilters:(NSDictionary *)filters previousPageResult:(NSMutableArray *)prevResult;
- (void)loadDetailsOfMod:(NSMutableDictionary *)item;

- (void)installModpackFromDetail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion;
// The installer chooses a profile folder within the target instance.
- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)instanceRoot;

- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params;
- (id)postEndpoint:(NSString *)endpoint params:(NSDictionary *)params;
- (NSDictionary<NSString *, NSString *> *)requestHeaders;
- (NSArray<NSDictionary *> *)categoriesForContentType:(NSString *)type;
- (NSArray<NSDictionary *> *)versionsForProject:(NSString *)projectID filters:(NSDictionary *)filters;

- (NSDictionary *)projectForID:(NSString *)projectID;
- (NSDictionary *)versionForID:(NSString *)versionID projectID:(NSString *)projectID;
@end
