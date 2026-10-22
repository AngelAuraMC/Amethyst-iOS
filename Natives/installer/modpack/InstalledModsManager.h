#import <Foundation/Foundation.h>

@interface InstalledModsManager : NSObject
+ (id)persistentObject:(id)object;
// Synchronous filesystem/API work; call on a worker queue.
+ (NSArray<NSDictionary *> *)entriesInDirectory:(NSString *)directory identify:(BOOL)identify error:(NSError **)error;
+ (NSArray<NSDictionary *> *)checkUpdates:(NSArray<NSDictionary *> *)entries filters:(NSDictionary *)filters;
+ (NSArray<NSDictionary *> *)planForEntries:(NSArray<NSDictionary *> *)entries requested:(NSArray<NSDictionary *> *)requested filters:(NSDictionary *)filters error:(NSError **)error;
+ (BOOL)setEntry:(NSDictionary *)entry enabled:(BOOL)enabled directory:(NSString *)directory error:(NSError **)error;
+ (BOOL)removeEntry:(NSDictionary *)entry directory:(NSString *)directory error:(NSError **)error;
+ (BOOL)commitPlan:(NSArray<NSDictionary *> *)plan payloads:(NSDictionary<NSString *, id> *)payloads directory:(NSString *)directory error:(NSError **)error;
+ (BOOL)recoverDirectory:(NSString *)directory error:(NSError **)error;
@end
