#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MinecraftOptionUtils : NSObject

@property(nonatomic) NSString *optionsPath;

+ (void)setupOptionsAtGameDir:(NSString *)gameDir;
+ (instancetype)sharedInstance;

- (void)loadFromPath:(NSString *)optionsPath;
- (void)setKey:(NSString *)key value:(NSString *)value;
- (void)setDefaultForKey:(NSString *)key value:(NSString *)value;
- (nullable NSString *)getValueForKey:(NSString *)key;
- (void)updateMCGuiScale;
- (void)save;

@end

NS_ASSUME_NONNULL_END
