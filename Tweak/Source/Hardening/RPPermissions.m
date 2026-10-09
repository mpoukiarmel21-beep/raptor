#import "RPPermissions.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <Photos/PHPhotoLibrary.h>
#import <AVFoundation/AVFoundation.h>

@implementation RPPermissions
+ (void)installForContainer:(RPContainer *)container {
    if (!container || container.isDefault) return;
    // For location we MUST report Authorized so Instagram doesn't block at the
    // "nom complet" gate waiting for permission. The fake GPS in RPLocationSpoof
    // delivers synchronously — no real TCC prompt needed.
    BOOL hasFake = [RPContainerStore shared].activeContainer.hasLocation;
    NSInteger locStatus = hasFake ? kCLAuthorizationStatusAuthorizedWhenInUse : kCLAuthorizationStatusNotDetermined;

    Class lm = [CLLocationManager class];
    Method m0 = class_getClassMethod(lm, @selector(authorizationStatus));
    if (m0) method_setImplementation(m0, imp_implementationWithBlock(^NSInteger(id _s){ return locStatus; }));
    Method m1 = class_getClassMethod(lm, NSSelectorFromString(@"authorizationStatusForBundleIdentifier:"));
    if (m1) method_setImplementation(m1, imp_implementationWithBlock(^NSInteger(id _s, NSString *bid){ (void)bid; return locStatus; }));
    // Instance variant (iOS 14+): -authorizationStatus
    Method mi = class_getInstanceMethod(lm, NSSelectorFromString(@"authorizationStatus"));
    if (mi) method_setImplementation(mi, imp_implementationWithBlock(^NSInteger(id _s){ return locStatus; }));

    // Notify delegates that authorization is granted (so Instagram proceeds)
    // Patch requestWhenInUse/requestAlways to immediately callback Authorized
    for (NSString *name in @[@"requestWhenInUseAuthorization", @"requestAlwaysAuthorization"]) {
        SEL sel = NSSelectorFromString(name);
        Method m = class_getInstanceMethod(lm, sel);
        if (!m) continue;
        method_setImplementation(m, imp_implementationWithBlock(^(id _self){
            id del = [((CLLocationManager*)_self) delegate];
            if ([del respondsToSelector:@selector(locationManagerDidChangeAuthorization:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{ [del locationManagerDidChangeAuthorization:(CLLocationManager*)_self]; });
            }
            if ([del respondsToSelector:@selector(locationManager:didChangeAuthorizationStatus:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{ [del locationManager:(CLLocationManager*)_self didChangeAuthorizationStatus:(CLAuthorizationStatus)locStatus]; });
            }
        }));
    }

    // Photos
    Class ph = NSClassFromString(@"PHPhotoLibrary");
    SEL phSel = NSSelectorFromString(@"authorizationStatus");
    Method phM = class_getClassMethod(ph, phSel);
    if (phM) method_setImplementation(phM, imp_implementationWithBlock(^NSInteger(id _s){ return 0; }));
    Class av = NSClassFromString(@"AVCaptureDevice");
    SEL avSel = NSSelectorFromString(@"authorizationStatusForMediaType:");
    Method avM = class_getClassMethod(av, avSel);
    if (avM) method_setImplementation(avM, imp_implementationWithBlock(^NSInteger(id _s, NSString *t){ (void)t; return 0; }));
}
@end
