#import "RPCameraFeed.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

@implementation RPCameraFeed {
    NSURL *_url;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_out;
    CIContext *_ci;
    NSLock *_lock;
    CVPixelBufferPoolRef _pool;
    int _poolW, _poolH;
    OSType _poolFmt;
}

- (instancetype)initWithURL:(NSURL *)url {
    self=[super init];
    if(self){
        _url=url;
        _lock=[[NSLock alloc] init];
        _ci=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:[NSNull null]}];
        [self resetReader];
    }
    return self;
}
- (void)resetReader {
    AVURLAsset *asset = [AVURLAsset assetWithURL:_url];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) return;
    NSError *err=nil;
    _reader = [AVAssetReader assetReaderWithAsset:asset error:&err];
    if (err || !_reader) return;
    NSDictionary *opts = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
    _out = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:opts];
    _out.alwaysCopiesSampleData = NO;
    if ([_reader canAddOutput:_out]) [_reader addOutput:_out];
    [_reader startReading];
}
- (CVPixelBufferRef)copyPixelBufferForWidth:(int)w height:(int)h pixelFormat:(OSType)fmt {
    [_lock lock];
    CMSampleBufferRef sb = [_out copyNextSampleBuffer];
    if (!sb) { [self resetReader]; sb = [_out copyNextSampleBuffer]; }
    CVPixelBufferRef src = NULL;
    if (sb) { src = CMSampleBufferGetImageBuffer(sb); if (src) CVPixelBufferRetain(src); CFRelease(sb); }
    if (!src) { [_lock unlock]; return NULL; }
    // Ensure pool
    if (!_pool || _poolW!=w || _poolH!=h || _poolFmt!=fmt) {
        if (_pool) CVPixelBufferPoolRelease(_pool);
        NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey:@(fmt),(id)kCVPixelBufferWidthKey:@(w),(id)kCVPixelBufferHeightKey:@(h),(id)kCVPixelBufferIOSurfacePropertiesKey:@{}};
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attrs, &_pool);
        _poolW=w; _poolH=h; _poolFmt=fmt;
    }
    CVPixelBufferRef dst=NULL;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &dst);
    if (!dst) { CVPixelBufferRelease(src); [_lock unlock]; return NULL; }
    CIImage *img = [CIImage imageWithCVPixelBuffer:src];
    // aspect fill
    CGFloat sw = CVPixelBufferGetWidth(src), sh = CVPixelBufferGetHeight(src);
    CGFloat scale = MAX(w/sw, h/sh);
    CGFloat nw = sw*scale, nh = sh*scale;
    img = [img imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    img = [img imageByCroppingToRect:CGRectMake((nw-w)/2, (nh-h)/2, w, h)];
    [_ci render:img toCVPixelBuffer:dst];
    CVPixelBufferRelease(src);
    [_lock unlock];
    return dst;
}
- (void)invalidate {
    [_lock lock];
    [_reader cancelReading]; _reader=nil; _out=nil;
    if (_pool) { CVPixelBufferPoolRelease(_pool); _pool=NULL; }
    [_lock unlock];
}
- (void)dealloc { [self invalidate]; }
@end
