#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface RPListOption : NSObject
@property (nonatomic, copy) NSString *value, *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
+ (instancetype)optionWithValue:(NSString*)v title:(NSString*)t subtitle:(nullable NSString*)s;
@end
@interface RPListPickerVC : UITableViewController
- (instancetype)initWithTitle:(NSString*)title options:(NSArray<RPListOption*>*)opts selectedValue:(nullable NSString*)sel onPick:(void(^)(RPListOption*))cb;
@end
NS_ASSUME_NONNULL_END
