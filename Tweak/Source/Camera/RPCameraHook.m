#import "RPCameraHook.h"
#import "RPCameraFeed.h"
#import "RPPaths.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static RPCameraFeed *gFeed = nil;
static NSURL *gURL = nil;

static CMSampleBufferRef RPCreateSampleBuffer(CVPixelBufferRef pb, CMTime pts) {
    CMSampleBufferRef sb=NULL;
    CMVideoFormatDescriptionRef fmt=NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pb, &fmt);
    CMSampleTimingInfo ti = {kCMTimeInvalid, pts, kCMTimeInvalid};
    CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pb, fmt, &ti, &sb);
    if (fmt) CFRelease(fmt);
    return sb;
}

@implementation RPCameraHook

+ (void)installGlobal {
    static dispatch_once_t once; dispatch_once(&once, ^{
        NSString *path = [RPPaths globalCameraVideoPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
        gURL = [NSURL fileURLWithPath:path];
        gFeed = [[RPCameraFeed alloc] initWithURL:gURL];
        // Data path
        Method m = class_getInstanceMethod([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:));
        if (m) {
            IMP orig = method_getImplementation(m);
            typedef void (*Fn)(id,SEL,id,dispatch_queue_t);
            Fn fn = (Fn)orig;
            method_setImplementation(m, imp_implementationWithBlock(^(AVCaptureVideoDataOutput *_self, id del, dispatch_queue_t q){
                fn(_self, @selector(setSampleBufferDelegate:queue:), del, q);
                if (!del) return;
                Class c = [del class];
                SEL sel = NSSelectorFromString(@"captureOutput:didOutputSampleBuffer:fromConnection:");
                Method dm = class_getInstanceMethod(c, sel);
                if (!dm) return;
                // avoid double swizzle
                static NSMutableSet *done; static dispatch_once_t t; dispatch_once(&t,^{ done=[NSMutableSet set]; });
                NSString *key = NSStringFromClass(c);
                @synchronized(done){ if([done containsObject:key]) return; [done addObject:key]; }
                IMP dOrig = method_getImplementation(dm);
                typedef void (*DFn)(id,SEL,AVCaptureOutput*,CMSampleBufferRef,AVCaptureConnection*);
                DFn dFn = (DFn)dOrig;
                method_setImplementation(dm, imp_implementationWithBlock(^(id _s, AVCaptureOutput *out, CMSampleBufferRef sb, AVCaptureConnection *conn){
                    if (gFeed && sb) {
                        CVPixelBufferRef src = CMSampleBufferGetImageBuffer(sb);
                        if (src) {
                            int w=(int)CVPixelBufferGetWidth(src), h=(int)CVPixelBufferGetHeight(src);
                            OSType fmt=CVPixelBufferGetPixelFormatType(src);
                            CVPixelBufferRef rep = [gFeed copyPixelBufferForWidth:w height:h pixelFormat:fmt];
                            if (rep) {
                                CMSampleBufferRef nsb = RPCreateSampleBuffer(rep, CMSampleBufferGetPresentationTimeStamp(sb));
                                if (nsb) { dFn(_s, sel, out, nsb, conn); CFRelease(nsb); CVPixelBufferRelease(rep); return; }
                                CVPixelBufferRelease(rep);
                            }
                        }
                    }
                    dFn(_s, sel, out, sb, conn);
                }));
            }));
        }
        // Preview overlay
        Method pm = class_getInstanceMethod(NSClassFromString(@"AVCaptureVideoPreviewLayer"), NSSelectorFromString(@"setSession:"));
        if (pm) {
            IMP orig = method_getImplementation(pm);
            typedef void (*Fn)(id,SEL,AVCaptureSession*);
            Fn fn=(Fn)orig;
            SEL sel=@selector(setSession:);
            method_setImplementation(pm, imp_implementationWithBlock(^(AVCaptureVideoPreviewLayer *_self, AVCaptureSession *sess){
                fn(_self, sel, sess);
                if (!gFeed || !sess) return;
                AVPlayer *player = [AVPlayer playerWithURL:gURL];
                AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:player];
                pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
                pl.frame = _self.bounds;
                pl.name = @"RaptorCamOverlay";
                // remove old
                for (CALayer *l in [_self.sublayers copy]) if ([l.name isEqualToString:@"RaptorCamOverlay"]) [l removeFromSuperlayer];
                [_self addSublayer:pl];
                [player play];
                // loop
                [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem queue:nil usingBlock:^(NSNotification *n){ [player seekToTime:kCMTimeZero]; [player play]; }];
            }));
        }
    });
}

@end
