#import "RPLocationSpoof.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

static CLLocation* (*orig_location)(id,SEL) = NULL;
static void (*orig_start)(id,SEL) = NULL;
static void (*orig_request)(id,SEL) = NULL;
static BOOL gInstalled = NO;
static BOOL gInDelivery = NO;

static CLLocation *RPCurrentFake(void) {
    RPContainer *c = [RPContainerStore shared].activeContainer;
    if (!c.hasLocation) return nil;
    double jLat = ((double)arc4random_uniform(2000)-1000.0)/1e8;
    double jLng = ((double)arc4random_uniform(2000)-1000.0)/1e8;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(c.latitude.doubleValue + jLat, c.longitude.doubleValue + jLng);
    return [[CLLocation alloc] initWithCoordinate:coord altitude:12 horizontalAccuracy:5 verticalAccuracy:8 course:-1 speed:0 timestamp:[NSDate date]];
}

// Delivery: must NEVER drop a request. The old dispatch_async broke Instagram's
// signup NAME validation which fires startUpdatingLocation + requestLocation
// back-to-back on the same runloop — the second async arrived after timeout → hang.
static void RPDeliverFake(CLLocationManager *mgr) {
    if (![NSThread isMainThread]) {
        // Caller off-main may be blocked — sync hop
        dispatch_sync(dispatch_get_main_queue(), ^{ RPDeliverFake(mgr); });
        return;
    }
    if (gInDelivery) {
        // Re-entrant (didUpdateLocations → startUpdatingLocation). Don't recurse,
        // but don't drop: schedule one deferred delivery.
        CLLocation *fake = RPCurrentFake();
        id<CLLocationManagerDelegate> del = mgr.delegate;
        if (fake && [del respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [del locationManager:mgr didUpdateLocations:@[fake]];
            });
        }
        return;
    }
    id<CLLocationManagerDelegate> del = mgr.delegate;
    CLLocation *fake = RPCurrentFake();
    gInDelivery = YES;
    @try {
        if (fake && [del respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            [del locationManager:mgr didUpdateLocations:@[fake]];
        } else if (fake && [del respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
            [del locationManager:mgr didUpdateToLocation:fake fromLocation:nil];
        } else if ([del respondsToSelector:@selector(locationManager:didFailWithError:)]) {
            NSError *e = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorLocationUnknown userInfo:nil];
            [del locationManager:mgr didFailWithError:e];
        }
    } @finally { gInDelivery = NO; }
}

@implementation RPLocationSpoof
+ (BOOL)isActive { return [RPContainerStore shared].activeContainer.hasLocation; }
+ (void)install {
    if (gInstalled) return; gInstalled = YES;
    Class mgr = [CLLocationManager class];
    Method mLoc = class_getInstanceMethod(mgr, @selector(location));
    if (mLoc) {
        orig_location = (CLLocation*(*)(id,SEL))method_getImplementation(mLoc);
        method_setImplementation(mLoc, imp_implementationWithBlock(^CLLocation*(id _self){ CLLocation *f=RPCurrentFake(); return f ?: orig_location(_self,@selector(location)); }));
    }
    Method mStart = class_getInstanceMethod(mgr, @selector(startUpdatingLocation));
    if (mStart) {
        orig_start = (void(*)(id,SEL))method_getImplementation(mStart);
        method_setImplementation(mStart, imp_implementationWithBlock(^(id _self){
            if ([self isActive]) RPDeliverFake((CLLocationManager*)_self);
            else orig_start(_self,@selector(startUpdatingLocation));
        }));
    }
    Method mReq = class_getInstanceMethod(mgr, @selector(requestLocation));
    if (mReq) {
        orig_request = (void(*)(id,SEL))method_getImplementation(mReq);
        method_setImplementation(mReq, imp_implementationWithBlock(^(id _self){
            if ([self isActive]) RPDeliverFake((CLLocationManager*)_self);
            else orig_request(_self,@selector(requestLocation));
        }));
    }
}
@end
