#import "RPPaths.h"
#import <Foundation/Foundation.h>

static NSString *gRealHome = nil;

@implementation RPPaths

+ (void)captureRealHome {
    static dispatch_once_t onceToken;
    // Use dispatch_once for true idempotence but also allow manual re-entrancy check for gRealHome
    // We keep explicit check so multiple calls remain no-op even without dispatch_once semantics if needed.
    if (gRealHome) return;
    dispatch_once(&onceToken, ^{
        const char *env = getenv("HOME");
        NSString *home = nil;
        if (env && env[0] != '\0') {
            home = [NSString stringWithUTF8String:env];
        }
        if (!home.length) {
            home = NSHomeDirectory();
        }
        gRealHome = [home copy];
        if (gRealHome.length) {
            setenv("ORIGINAL_HOME_PATH", [gRealHome UTF8String], 1);
        }
    });
}

+ (NSString *)realHome {
    if (gRealHome.length) return gRealHome;
    NSString *home = NSHomeDirectory();
    return home ?: @"/var/mobile";
}

+ (NSString *)controlDir {
    return [[self realHome] stringByAppendingPathComponent:@"Documents/Raptor"];
}

+ (NSString *)containersFile {
    return [[self controlDir] stringByAppendingPathComponent:@"containers.plist"];
}

+ (NSString *)activeFile {
    return [[self controlDir] stringByAppendingPathComponent:@"active.plist"];
}

+ (NSString *)containerRootForCID:(NSString *)cid {
    NSString *safeCID = cid.length ? cid : @"default";
    return [[[self controlDir] stringByAppendingPathComponent:@"Instances"] stringByAppendingPathComponent:safeCID];
}

+ (NSString *)cameraDir {
    return [[self controlDir] stringByAppendingPathComponent:@"Cameras"];
}

+ (NSString *)globalCameraVideoPath {
    return [[self cameraDir] stringByAppendingPathComponent:@"global.mp4"];
}

+ (NSString *)logDirectory {
    return [[self controlDir] stringByAppendingPathComponent:@"Logs"];
}

+ (BOOL)ensureControlDir {
    NSString *dir = [self controlDir];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:dir]) return YES;
    NSError *err = nil;
    NSDictionary *attrs = @{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication };
    BOOL ok = [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:attrs error:&err];
    if (!ok) {
        // fallback without protection attrs
        ok = [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        if (ok) {
            [fm setAttributes:attrs ofItemAtPath:dir error:nil];
        }
    }
    return ok;
}

+ (BOOL)ensureSkeletonAtRoot:(NSString *)root error:(NSError **)error {
    if (!root.length) {
        if (error) *error = [NSError errorWithDomain:@"RPPaths" code:1 userInfo:@{NSLocalizedDescriptionKey: @"root is empty"}];
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = @{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication };
    NSArray<NSString *> *subpaths = @[
        @"Documents",
        @"Library",
        @"Library/Caches",
        @"Library/Preferences",
        @"tmp"
    ];
    // Ensure root itself exists first
    if (![fm fileExistsAtPath:root]) {
        BOOL ok = [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:attrs error:error];
        if (!ok) return NO;
    } else {
        [fm setAttributes:attrs ofItemAtPath:root error:nil];
    }
    for (NSString *sub in subpaths) {
        NSString *full = [root stringByAppendingPathComponent:sub];
        if ([fm fileExistsAtPath:full]) {
            [fm setAttributes:attrs ofItemAtPath:full error:nil];
            continue;
        }
        BOOL ok = [fm createDirectoryAtPath:full withIntermediateDirectories:YES attributes:attrs error:error];
        if (!ok) return NO;
    }
    return YES;
}

+ (void)reapplyProtectionRecursivelyAtRoot:(NSString *)root {
    if (!root.length) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:root]) return;
    NSDictionary *attrs = @{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication };
    [fm setAttributes:attrs ofItemAtPath:root error:nil];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
    NSString *relative = nil;
    while ((relative = [enumerator nextObject])) {
        NSString *full = [root stringByAppendingPathComponent:relative];
        [fm setAttributes:attrs ofItemAtPath:full error:nil];
    }
}

+ (void)wipeRealSessionFiles {
    NSString *home = [self realHome];
    if (!home.length) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *pathsToRemove = @[
        [home stringByAppendingPathComponent:@"Library/Cookies"],
        [home stringByAppendingPathComponent:@"Library/HTTPStorages"],
        [home stringByAppendingPathComponent:@"Library/WebKit"],
        [home stringByAppendingPathComponent:@"Library/Caches"],
        [home stringByAppendingPathComponent:@"Library/Application Support"]
    ];
    for (NSString *p in pathsToRemove) {
        if ([fm fileExistsAtPath:p]) {
            [fm removeItemAtPath:p error:nil];
        }
    }
    // Remove non-Apple preferences: Library/Preferences/*.plist not starting with com.apple.
    NSString *prefsDir = [home stringByAppendingPathComponent:@"Library/Preferences"];
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:prefsDir error:nil];
    for (NSString *file in contents) {
        if (![file hasSuffix:@".plist"]) continue;
        if ([file hasPrefix:@"com.apple."]) continue;
        NSString *full = [prefsDir stringByAppendingPathComponent:file];
        [fm removeItemAtPath:full error:nil];
    }
}

+ (BOOL)ensureControlDirExistsWithError:(NSError **)error {
    // internal helper not exposed, but ensureControlDir uses this logic
    return [self ensureControlDir];
}

@end
