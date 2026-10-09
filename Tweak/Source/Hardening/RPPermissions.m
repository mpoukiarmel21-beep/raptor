#import "RPPermissions.h"
#import "RPContainer.h"
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

@implementation RPPermissions
+ (void)installForContainer:(RPContainer *)container {
    if (!container || container.isDefault) return;
    // Location: synthesize NotDetermined until user grants per-container.
    // We store per-cid decision in NSUserDefaults (already redirected via RPPrefsHook)
    // For V1, always return NotDetermined so the app re-prompts. Real grant would need TCC.db write (impossible in sandbox).
    Class lm = [CLLocationManager class];
    for (NSString *name in @[@"authorizationStatus", @"authorizationStatusForBundleIdentifier:"]) {
        SEL sel = NSSelectorFromString(name);
        Method m = class_getClassMethod(lm, sel);
        if (!m) continue;
        method_setImplementation(m, imp_implementationWithBlock(^NSInteger(id _self, NSString *bid){
            // Per-container: always NotDetermined to force re-prompt; after user would tap Allow, fake GPS still answers.
            return kCLAuthorizationStatusNotDetermined;
        }));
    }
    // Photos
    Class ph = NSClassFromString(@"PHPhotoLibrary");
    SEL phSel = NSSelectorFromString(@"authorizationStatus");
    Method phM = class_getClassMethod(ph, phSel);
    if (phM) method_setImplementation(phM, imp_implementationWithBlock(^NSInteger(id _s){ return 0; })); // NotDetermined
    // Camera/Mic
    Class av = NSClassFromString(@"AVCaptureDevice");
    SEL avSel = NSSelectorFromString(@"authorizationStatusForMediaType:");
    Method avM = class_getClassMethod(av, avSel);
    if (avM) method_setImplementation(avM, imp_implementationWithBlock(^NSInteger(id _s, NSString *t){ return 0; })); // NotDetermined
}
@end
