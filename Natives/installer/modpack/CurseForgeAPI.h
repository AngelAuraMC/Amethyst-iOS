#import <Foundation/Foundation.h>
#import "ModpackAPI.h"

@interface CurseForgeAPI : ModpackAPI
+ (BOOL)isConfigured;
+ (NSString *)apiKey;
+ (BOOL)setAPIKey:(NSString *)key error:(NSError **)error;
+ (NSDictionary *)searchParameters:(NSDictionary *)filters classID:(NSNumber *)classID offset:(NSUInteger)offset;
+ (NSDictionary *)versionFromFile:(NSDictionary *)file;
@end
