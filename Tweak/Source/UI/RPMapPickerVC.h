#import <UIKit/UIKit.h>
@class RPContainer;
NS_ASSUME_NONNULL_BEGIN
@interface RPMapPickerVC : UIViewController
- (instancetype)initWithContainer:(RPContainer *)container onCommit:(void(^)(void))cb;
@end
NS_ASSUME_NONNULL_END
