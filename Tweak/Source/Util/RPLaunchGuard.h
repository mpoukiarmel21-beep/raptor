#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Detects a launch crash-loop (like RyukGram's "3 crashes -> overrides off, values kept").
// State lives in the control plane (real HOME/Documents/Raptor) so it survives HOME redirection.
@interface RPLaunchGuard : NSObject

// Register the didBecomeActive observer: marks the launch as stable and, in safe mode, offers re-enable.
+ (void)install;

// Call once, very early in the constructor (after RPPaths captured the real home).
// Increments the consecutive-crash streak and flips safe mode on at the threshold.
+ (void)noteLaunchBegin;

// NO when safe mode is active: bootstrap must skip isolation/spoof/hardening.
+ (BOOL)shouldRunRiskyStages;
+ (BOOL)safeModeActive;

// User asked to try again: clears safe mode (container values are untouched).
+ (void)clearSafeMode;

@end

NS_ASSUME_NONNULL_END
