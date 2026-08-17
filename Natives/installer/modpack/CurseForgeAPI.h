#import <Foundation/Foundation.h>
#import "ModpackAPI.h"

@interface CurseForgeAPI : ModpackAPI

// The key used to talk to api.curseforge.com. Resolved from the user preference
// general.curseforge_api_key first, then from CONFIG_CURSEFORGE_API_KEY if the
// build was configured with one. Returns nil when no key is available.
@property(nonatomic, readonly) NSString *apiKey;

+ (NSString *)resolvedAPIKey;

@end
