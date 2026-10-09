#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSString *RPLang(void);
NSString *RPLL(NSString *key, NSString *fallbackFR);
@interface RPL10n : NSObject
+ (void)setOverrideLanguage:(nullable NSString *)lang; // fr/en
+ (nullable NSString *)overrideLanguage;
@end
NS_ASSUME_NONNULL_END
