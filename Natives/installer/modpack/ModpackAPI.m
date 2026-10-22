#import "AFNetworking.h"
#import "MinecraftResourceDownloadTask.h"
#import "ModpackAPI.h"
#import "utils.h"

@implementation ModpackAPI

#pragma mark Interface methods

- (instancetype)initWithURL:(NSString *)url {
    self = [super init];
    self.baseURL = url;
    return self;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    [self doesNotRecognizeSelector:_cmd];
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters previousPageResult:(NSMutableArray *)prevResult {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)instanceRoot {
    [self doesNotRecognizeSelector:_cmd];
}

- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params {
    return [self requestEndpoint:endpoint params:params post:NO];
}
- (NSDictionary *)requestHeaders { return @{}; }

- (id)postEndpoint:(NSString *)endpoint params:(NSDictionary *)params {
    return [self requestEndpoint:endpoint params:params post:YES];
}

- (id)requestEndpoint:(NSString *)endpoint params:(NSDictionary *)params post:(BOOL)post {
    self.lastError = nil;
    __block id result;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    NSString *url = [self.baseURL stringByAppendingPathComponent:endpoint];
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    if (post) manager.requestSerializer = [AFJSONRequestSerializer serializer];
    manager.requestSerializer.timeoutInterval = 30;
    if ([self.baseURL containsString:@"api.modrinth.com"]) {
        [manager.requestSerializer setValue:@"AngelAuraAmethyst/1.0 (https://github.com/AngelAuraMC/Amethyst-iOS)" forHTTPHeaderField:@"User-Agent"];
    }
    void (^success)(NSURLSessionDataTask *, id) = ^(NSURLSessionDataTask *task, id obj) {
        result = obj;
        dispatch_group_leave(group);
    };
    void (^failure)(NSURLSessionDataTask *, NSError *) = ^(NSURLSessionDataTask *operation, NSError *error) {
        self.lastError = error;
        dispatch_group_leave(group);
    };
    if (post) [manager POST:url parameters:params headers:self.requestHeaders progress:nil success:success failure:failure];
    else [manager GET:url parameters:params headers:self.requestHeaders progress:nil success:success failure:failure];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [manager invalidateSessionCancelingTasks:NO resetSession:NO];
    //NSLog(@"%@", result);
    return result;
}

- (void)installModpackFromDetail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion {
    // Pass details to LauncherNavigationController
    NSDictionary* userInfo = @{
        @"detail": modDetail,
        @"index": @(selectedVersion)
    };
    [NSNotificationCenter.defaultCenter 
        postNotificationName:@"InstallModpack" 
        object:self userInfo:userInfo];
}

@end
