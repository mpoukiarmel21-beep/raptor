#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface RPDiagnostics : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)msg;
@end
#define RPLog(fmt, ...) [[RPDiagnostics shared] log:[NSString stringWithFormat:(fmt), ##__VA_ARGS__]]
#define RPErr(fmt, ...) [[RPDiagnostics shared] log:[NSString stringWithFormat:@"[ERR] " fmt, ##__VA_ARGS__]]
NS_ASSUME_NONNULL_END
