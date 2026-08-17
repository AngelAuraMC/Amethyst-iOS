#import <Foundation/Foundation.h>
#import "UnzipKit.h"

@interface ModpackUtils : NSObject

+ (void)archive:(UZKArchive *)archive extractDirectory:(NSString *)dir toPath:(NSString *)path error:(NSError **)error;
+ (NSDictionary *)infoForDependencies:(NSDictionary *)dependency;

// Creates (and selects) the launcher profile for a freshly installed modpack.
+ (void)createProfileNamed:(NSString *)name gameDir:(NSString *)gameDirName versionID:(NSString *)versionID;

// Offers to run the vendor's installer for a pack that needs Forge or NeoForge,
// which have no metadata endpoint to install from directly. No-op when the
// loader the pack asks for is already installed.
+ (void)installLoaderIfNeeded:(NSDictionary *)depInfo;

@end
