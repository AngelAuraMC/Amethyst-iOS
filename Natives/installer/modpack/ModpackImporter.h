#import <Foundation/Foundation.h>

// Installs a modpack from a file on disk, as opposed to one picked from the
// modpack browser. The pack format is detected from the contents of the archive.
@interface ModpackImporter : NSObject

// Copies the file out of its original location (it may be a security scoped URL
// owned by another app) and installs it.
+ (void)importModpackAtURL:(NSURL *)url;

// Installs a package the launcher already owns a copy of. The file is consumed:
// it is deleted once the pack has been unpacked.
+ (void)importModpackAtPath:(NSString *)path;

// A pack opened from another app can arrive before the launcher UI exists to
// install it. It is held here until the launcher is ready.
+ (void)flushPendingImport;

@end
