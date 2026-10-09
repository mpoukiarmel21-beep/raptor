#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPPaths : NSObject

+ (void)captureRealHome;

+ (NSString *)realHome;
+ (NSString *)controlDir;
+ (NSString *)containersFile;
+ (NSString *)activeFile;
+ (NSString *)containerRootForCID:(NSString *)cid;
+ (NSString *)cameraDir;
+ (NSString *)globalCameraVideoPath;
+ (NSString *)logDirectory;

+ (BOOL)ensureSkeletonAtRoot:(NSString *)root error:(NSError **)error;
+ (void)reapplyProtectionRecursivelyAtRoot:(NSString *)root;
+ (void)wipeRealSessionFiles;
+ (BOOL)ensureControlDir;

@end

NS_ASSUME_NONNULL_END
