#import "RPLocationSpoof.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import "../Util/RPDiagnostics.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

// ============================================================================
// Minimal, battle-tested location spoof — the EXACT hook set that fixes the
// spinner-at-signup-name hang (ported from whaminsta build-16 / InstaVault).
// Only `location`, `startUpdatingLocation` and `requestLocation` are hooked.
// ============================================================================

// Freshly-synthesized CLLocation at the active container's coordinate,
// or nil when the active container has no location set (real location flows).
static CLLocation *RPCurrentFake(void) {
    RPContainer *c = [RPContainerStore shared].activeContainer;
    if (!c.hasLocation) return nil;

    CLLocationDegrees lat = c.latitude.doubleValue;
    CLLocationDegrees lng = c.longitude.doubleValue;

    // Sub-meter jitter so successive reads aren't byte-identical (looks alive).
    double jLat = ((double)arc4random_uniform(2000) - 1000.0) / 1.0e8;
    double jLng = ((double)arc4random_uniform(2000) - 1000.0) / 1.0e8;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(lat + jLat, lng + jLng);

    return [[CLLocation alloc] initWithCoordinate:coord
                                         altitude:12.0
                               horizontalAccuracy:5.0
                                 verticalAccuracy:8.0
                                           course:-1
                                            speed:0
                                        timestamp:[NSDate date]];
}

// Saved originals.
static CLLocation *(*orig_location)(id, SEL) = NULL;
static void (*orig_start)(id, SEL) = NULL;
static void (*orig_request)(id, SEL) = NULL;
static BOOL gInstalled = NO;

// Delivery guard.
//
// A time-based rate limit (build-14) dropped Instagram's back-to-back
// -startUpdatingLocation + -requestLocation during signup NAME validation,
// so the second request's callback was thrown away and the app spun forever.
//
// A DEPTH guard replaces it: it blocks only genuine re-entrancy (a delegate
// that restarts updates from inside -locationManager:didUpdateLocations:),
// which is the only shape that can actually recurse. Every fresh, independent
// request always gets a callback — a request is never silently dropped.
static BOOL gInDelivery = NO;

// Delivers ONE synthetic fix to the manager's delegate. Synchronous on main
// (CLLocationManager's delegate contract) so the depth guard spans the whole
// nested call; hops to main only when the hook was entered off-main.
static void RPDeliverFakeOnce(CLLocationManager *mgr) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ RPDeliverFakeOnce(mgr); });
        return;
    }
    if (gInDelivery) return;   // re-entrant restart from inside our own delivery

    id<CLLocationManagerDelegate> del = mgr.delegate;
    CLLocation *fake = RPCurrentFake();
    gInDelivery = YES;
    @try {
        if (fake && [del respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            [del locationManager:mgr didUpdateLocations:@[ fake ]];
        } else if (fake && [del respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
            CLLocation *empty = [[CLLocation alloc] initWithLatitude:0 longitude:0];
            [del locationManager:mgr didUpdateToLocation:fake fromLocation:empty];
        } else if ([del respondsToSelector:@selector(locationManager:didFailWithError:)]) {
            // Nothing usable to deliver, but the caller IS waiting on something.
            // Report the benign "location unknown" error so the flow can continue
            // instead of spinning forever. Deliberately NOT a fallback to the real
            // -startUpdatingLocation: that would start the device GPS and leak the
            // true position, defeating the whole point of the container location.
            NSError *err = [NSError errorWithDomain:kCLErrorDomain
                                               code:kCLErrorLocationUnknown
                                           userInfo:nil];
            [del locationManager:mgr didFailWithError:err];
        }
    } @finally {
        gInDelivery = NO;
    }
}

@implementation RPLocationSpoof

+ (BOOL)isActive {
    return [RPContainerStore shared].activeContainer.hasLocation;
}

+ (void)install {
    if (gInstalled) return;
    gInstalled = YES;

    Class mgr = [CLLocationManager class];

    // -location getter: return the fake fix when active, else the real value.
    Method mLoc = class_getInstanceMethod(mgr, @selector(location));
    if (mLoc) {
        orig_location = (CLLocation *(*)(id, SEL))method_getImplementation(mLoc);
        method_setImplementation(mLoc, imp_implementationWithBlock(^CLLocation *(id _self) {
            CLLocation *fake = RPCurrentFake();
            return fake ?: orig_location(_self, @selector(location));
        }));
    }

    // -startUpdatingLocation: one-shot synthetic fix when faking (the real GPS
    // is never started, so no real coordinates can ever leak); otherwise defer
    // to the real implementation so the app still receives genuine fixes.
    Method mStart = class_getInstanceMethod(mgr, @selector(startUpdatingLocation));
    if (mStart) {
        orig_start = (void (*)(id, SEL))method_getImplementation(mStart);
        method_setImplementation(mStart, imp_implementationWithBlock(^(id _self) {
            if ([RPLocationSpoof isActive]) {
                RPDeliverFakeOnce((CLLocationManager *)_self);
            } else {
                orig_start(_self, @selector(startUpdatingLocation));
            }
        }));
    }

    // -requestLocation: one-shot. When faking, synthesize a single fix and never
    // touch the real GPS; otherwise defer to the real implementation.
    Method mReq = class_getInstanceMethod(mgr, @selector(requestLocation));
    if (mReq) {
        orig_request = (void (*)(id, SEL))method_getImplementation(mReq);
        method_setImplementation(mReq, imp_implementationWithBlock(^(id _self) {
            if ([RPLocationSpoof isActive]) {
                RPDeliverFakeOnce((CLLocationManager *)_self);
            } else {
                orig_request(_self, @selector(requestLocation));
            }
        }));
    }

    RPLog(@"LocationSpoof installed (location/start/request — minimal set + depth guard)");
}

@end
