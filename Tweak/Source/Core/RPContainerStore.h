#import <Foundation/Foundation.h>
#import "RPContainer.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const kRPContainersChanged;
extern NSString * const kRPActiveChanged;

@interface RPContainerStore : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<RPContainer *> *containers;
@property (nonatomic, copy) NSString *activeCID;
@property (nonatomic, assign) BOOL isolationDegraded;

- (void)load;

- (nullable RPContainer *)containerForCID:(NSString *)cid;
- (nullable RPContainer *)activeContainer;

- (nullable RPContainer *)createWithName:(NSString *)name cid:(nullable NSString *)cid error:(NSError **)error;
- (BOOL)renameContainer:(RPContainer *)container to:(NSString *)newName error:(NSError **)error;
- (BOOL)removeContainer:(RPContainer *)container error:(NSError **)error;
- (BOOL)setActiveCID:(NSString *)cid error:(NSError **)error;

- (BOOL)setLocation:(nullable NSNumber *)lat
                lng:(nullable NSNumber *)lng
               name:(nullable NSString *)locName
       forContainer:(RPContainer *)container
              error:(NSError **)error;

- (BOOL)setDeviceModel:(nullable NSString *)model
            iosVersion:(nullable NSString *)iosVersion
         marketingName:(nullable NSString *)marketingName
          forContainer:(RPContainer *)container
                 error:(NSError **)error;

- (BOOL)setAppLanguage:(nullable NSString *)lang
                region:(nullable NSString *)region
          forContainer:(RPContainer *)container
                 error:(NSError **)error;

- (void)resetAll;

@end

NS_ASSUME_NONNULL_END
