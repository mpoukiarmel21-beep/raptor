#import <Foundation/Foundation.h>
@class RPContainer;
NS_ASSUME_NONNULL_BEGIN
@interface RPLocaleSpoof : NSObject
+ (void)installForContainer:(RPContainer *)container;
+ (NSString *)displayNameForLanguage:(NSString *)lang;
+ (NSString *)displayNameForRegion:(NSString *)region;
+ (NSString *)deviceLanguage;
+ (NSString *)deviceRegion;
+ (NSArray<NSString *> *)supportedLanguageCodes;
+ (NSArray<NSString *> *)supportedRegionCodes;
@end
NS_ASSUME_NONNULL_END
