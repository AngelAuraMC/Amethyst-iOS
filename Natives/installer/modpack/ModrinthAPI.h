#import <Foundation/Foundation.h>
#import "ModpackAPI.h"

@interface ModrinthAPI : ModpackAPI
- (NSArray<NSString *> *)modCategories;
- (NSArray<NSDictionary *> *)versionsForProject:(NSString *)projectID filters:(NSDictionary *)filters;
- (NSDictionary<NSString *, NSDictionary *> *)versionsForFileHashes:(NSArray<NSString *> *)hashes;
@end
