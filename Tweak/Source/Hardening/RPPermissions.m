#import "RPPermissions.h"
#import "RPContainer.h"
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <Photos/PHPhotoLibrary.h>
#import <AVFoundation/AVFoundation.h>

@implementation RPPermissions
+ (void)installForContainer:(RPContainer *)container {
    if (!container || container.isDefault) return;
    // Location: synthesize NotDetermined until user grants per-container.
    // We store per-cid decision in NSUserDefaults (already redirected via RPPrefsHook)
    // For V1, always return NotDetermined so the app re-prompts. Real grant would need TCC.db write (impossible in sandbox).
    Class lm = [CLLocationManager class];
    Method m0 = class_getClassMethod(lm, @selector(authorizationStatus));
    if (m0) method_setImplementation(m0, imp_implementationWithBlock(^NSInteger(id _s){ return kCLAuthorizationStatusNotDetermined; }));
    Method m1 = class_getClassMethod(lm, NSSelectorFromString(@"authorizationStatusForBundleIdentifier:"));
    if (m1) method_setImplementation(m1, imp_implementationWithBlock(^NSInteger(id _s, NSString *bid){ (void)bid; return kCLAuthorizationStatusNotDetermined; }));
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
