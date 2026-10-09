#import "RPLocationSpoof.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

static CLLocation* (*orig_location)(id,SEL) = NULL;
static void (*orig_start)(id,SEL) = NULL;
static void (*orig_request)(id,SEL) = NULL;
static BOOL gInstalled = NO;
// Depth guard only — never use a time-based rate limit (build-14 hang).

static CLLocation *RPCurrentFake(void) {
    RPContainer *c = [RPContainerStore shared].activeContainer;
    // Even if the user didn't pick a city, synthesize a fallback near Paris so
    // the signup flow always gets a location. A missing fake makes
    // requestLocation fall through to the real GPS (nil in sideload) → hang.
    if (!c.hasLocation) {
        return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(48.8566, 2.3522)
                                             altitude:12 horizontalAccuracy:65
                                       verticalAccuracy:65 course:-1 speed:0 timestamp:[NSDate date]];
    }
    double jLat = ((double)arc4random_uniform(2000)-1000.0)/1e8;
    double jLng = ((double)arc4random_uniform(2000)-1000.0)/1e8;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(c.latitude.doubleValue + jLat, c.longitude.doubleValue + jLng);
    return [[CLLocation alloc] initWithCoordinate:coord altitude:12 horizontalAccuracy:5 verticalAccuracy:8 course:-1 speed:0 timestamp:[NSDate date]];
}

static void RPDeliverFakeSync(CLLocationManager *mgr) {
    id<CLLocationManagerDelegate> del = mgr.delegate;
    CLLocation *fake = RPCurrentFake();
    if (fake && [del respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [del locationManager:mgr didUpdateLocations:@[fake]];
    } else if (fake && [del respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        CLLocation *empty = [[CLLocation alloc] initWithLatitude:0 longitude:0];
        [del locationManager:mgr didUpdateToLocation:fake fromLocation:empty];
    } else if ([del respondsToSelector:@selector(locationManager:didFailWithError:)]) {
        NSError *e = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorLocationUnknown userInfo:nil];
        [del locationManager:mgr didFailWithError:e];
    }
}

@implementation RPLocationSpoof
+ (BOOL)isActive { return YES; } // always answer — fallback prevents hang when no city picked
+ (void)install {
    if (gInstalled) return; gInstalled = YES;
    Class mgr = [CLLocationManager class];
    Method mLoc = class_getInstanceMethod(mgr, @selector(location));
    if (mLoc) {
        orig_location = (CLLocation*(*)(id,SEL))method_getImplementation(mLoc);
        method_setImplementation(mLoc, imp_implementationWithBlock(^CLLocation*(id _self){ CLLocation *f=RPCurrentFake(); return f ?: orig_location(_self,@selector(location)); }));
    }
    // One-shot state: Instagram polls location during signup name → must not block
    Method mStart = class_getInstanceMethod(mgr, @selector(startUpdatingLocation));
    if (mStart) {
        orig_start = (void(*)(id,SEL))method_getImplementation(mStart);
        method_setImplementation(mStart, imp_implementationWithBlock(^(id _self){
            CLLocationManager *lm = (CLLocationManager*)_self;
            // Always deliver a fake synchronously. Never call the real GPS — sideload has no fix → hang.
            // Deliver on the calling thread (Instagram expects callback before its timeout).
            RPDeliverFakeSync(lm);
        }));
    }
    Method mReq = class_getInstanceMethod(mgr, @selector(requestLocation));
    if (mReq) {
        orig_request = (void(*)(id,SEL))method_getImplementation(mReq);
        method_setImplementation(mReq, imp_implementationWithBlock(^(id _self){
            RPDeliverFakeSync((CLLocationManager*)_self);
        }));
    }
    // Also answer newer API: requestLocationWithCompletion, CLLocationUpdate (iOS 17+)
    SEL updSel = NSSelectorFromString(@"requestLocationWithCompletionHandler:");
    Method mUpd = class_getInstanceMethod(mgr, updSel);
    if (mUpd) {
        method_setImplementation(mUpd, imp_implementationWithBlock(^(id _self, void(^cb)(CLLocation*,NSError*)){
            CLLocation *f = RPCurrentFake();
            if (cb) cb(f, nil);
            // Also deliver to delegate for compat
            RPDeliverFakeSync((CLLocationManager*)_self);
        }));
    }
}
@end
