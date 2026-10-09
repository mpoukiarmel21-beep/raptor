#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
NS_ASSUME_NONNULL_BEGIN
@interface RPCameraFeed : NSObject
- (instancetype)initWithURL:(NSURL *)url;
- (nullable CVPixelBufferRef)copyPixelBufferForWidth:(int)w height:(int)h pixelFormat:(OSType)fmt CF_RETURNS_RETAINED;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
