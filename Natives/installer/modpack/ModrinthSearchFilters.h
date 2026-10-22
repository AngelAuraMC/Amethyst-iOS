#import <Foundation/Foundation.h>

// Kept independent of UIKit so profile resolution and API filters can be tested on macOS.
@interface ModrinthSearchFilters : NSObject
+ (NSDictionary *)defaultsForProfile:(NSDictionary *)profile instanceRoot:(NSString *)root latestVersions:(NSDictionary *)latest;
+ (NSDictionary *)searchParameters:(NSDictionary *)filters offset:(NSUInteger)offset limit:(NSUInteger)limit;
+ (NSArray<NSString *> *)modCategoriesFromTags:(NSArray *)tags;
+ (NSString *)contentTypeForFilters:(NSDictionary *)filters;
+ (NSDictionary *)defaultsForProfile:(NSDictionary *)profile instanceRoot:(NSString *)root latestVersions:(NSDictionary *)latest contentType:(NSString *)type;
+ (NSArray<NSString *> *)categoriesFromTags:(NSArray *)tags contentType:(NSString *)type;
+ (NSDictionary *)versionParameters:(NSDictionary *)filters;
+ (NSArray<NSDictionary *> *)versions:(NSArray *)versions matchingFilters:(NSDictionary *)filters;
@end
