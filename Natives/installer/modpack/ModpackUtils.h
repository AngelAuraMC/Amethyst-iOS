#import <Foundation/Foundation.h>
#import "UnzipKit.h"

@interface ModpackUtils : NSObject

+ (void)archive:(UZKArchive *)archive extractDirectory:(NSString *)dir toPath:(NSString *)path error:(NSError **)error;
+ (NSDictionary *)infoForDependencies:(NSDictionary *)dependency;

// Creates (and selects) the launcher profile for a freshly installed modpack.
+ (void)createProfileNamed:(NSString *)name gameDir:(NSString *)gameDirName versionID:(NSString *)versionID;

// Tells the user that the pack's mod loader has to be installed by hand, since
// Forge and NeoForge cannot be installed automatically yet.
+ (void)warnAboutManualLoaderInstall:(NSString *)versionID;

@end
