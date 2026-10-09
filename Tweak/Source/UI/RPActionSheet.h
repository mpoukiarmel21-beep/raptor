#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, RPActionStyle){ RPActionStyleDefault, RPActionStyleAccent, RPActionStyleAccentSoft, RPActionStyleDestructive, RPActionStyleCancel };
@interface RPAction : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *symbol;
@property (nonatomic, assign) RPActionStyle style;
@property (nonatomic, copy, nullable) void (^handler)(void);
+ (instancetype)actionWithTitle:(NSString *)t symbol:(nullable NSString *)s style:(RPActionStyle)st handler:(nullable void(^)(void))h;
@end
@interface RPActionSheet : UIViewController
- (instancetype)initWithTitle:(nullable NSString *)title message:(nullable NSString *)message;
- (void)addAction:(RPAction *)action;
- (void)presentFrom:(UIViewController *)vc;
@end
NS_ASSUME_NONNULL_END
