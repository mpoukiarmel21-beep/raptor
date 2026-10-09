#import "RPPaths.h"
#import <Foundation/Foundation.h>

static NSString *gRealHome = nil;

@implementation RPPaths

+ (void)captureRealHome {
    if (gRealHome) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *env = getenv("HOME");
        NSString *home = nil;
        if (env && env[0] != '\0') home = [NSString stringWithUTF8String:env];
        if (!home.length) home = NSHomeDirectory();
        gRealHome = [home copy];
        if (gRealHome.length) setenv("ORIGINAL_HOME_PATH", [gRealHome UTF8String], 1);
    });
}

+ (NSString *)realHome {
    if (gRealHome.length) return gRealHome;
    NSString *home = NSHomeDirectory();
    return home ?: @"/var/mobile";
}

+ (NSString *)controlDir { return [[self realHome] stringByAppendingPathComponent:@"Documents/Raptor"]; }
+ (NSString *)containersFile { return [[self controlDir] stringByAppendingPathComponent:@"containers.plist"]; }
+ (NSString *)activeFile { return [[self controlDir] stringByAppendingPathComponent:@"active.plist"]; }
+ (NSString *)containerRootForCID:(NSString *)cid {
    NSString *safe = cid.length ? cid : @"default";
    return [[[self controlDir] stringByAppendingPathComponent:@"Instances"] stringByAppendingPathComponent:safe];
}
+ (NSString *)cameraDir { return [[self controlDir] stringByAppendingPathComponent:@"Cameras"]; }
+ (NSString *)globalCameraVideoPath { return [[self cameraDir] stringByAppendingPathComponent:@"global.mp4"]; }
+ (NSString *)logDirectory { return [[self controlDir] stringByAppendingPathComponent:@"Logs"]; }

// Control plane must survive before-first-unlock. Instances use CompleteUntilFirstUserAuthentication.
+ (BOOL)ensureControlDir {
    NSString *dir = [self controlDir];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:dir]) return YES;
    // NSFileProtectionNone for control plists — readable before first unlock (push launch)
    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionNone};
    NSError *err = nil;
    BOOL ok = [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:attrs error:&err];
    if (!ok) ok = [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return ok;
}

+ (BOOL)ensureSkeletonAtRoot:(NSString *)root error:(NSError **)error {
    if (!root.length) { if (error) *error=[NSError errorWithDomain:@"RPPaths" code:1 userInfo:@{NSLocalizedDescriptionKey:@"root is empty"}]; return NO; }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    if (![fm fileExistsAtPath:root]) {
        if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:attrs error:error]) return NO;
    }
    for (NSString *sub in @[@"Documents",@"Library",@"Library/Caches",@"Library/Preferences",@"tmp"]) {
        NSString *full=[root stringByAppendingPathComponent:sub];
        if ([fm fileExistsAtPath:full]) continue;
        if (![fm createDirectoryAtPath:full withIntermediateDirectories:YES attributes:attrs error:error]) return NO;
    }
    return YES;
}

+ (void)reapplyProtectionRecursivelyAtRoot:(NSString *)root {
    if (!root.length) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:root]) return;
    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    @autoreleasepool {
        [fm setAttributes:attrs ofItemAtPath:root error:nil];
        NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
        NSString *rel=nil; NSUInteger count=0;
        while ((rel=[e nextObject])) {
            @autoreleasepool {
                NSString *full=[root stringByAppendingPathComponent:rel];
                [fm setAttributes:attrs ofItemAtPath:full error:nil];
            }
            if ((++count % 500)==0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        }
    }
}

+ (void)wipeRealSessionFiles {
    NSString *home=[self realHome]; if(!home.length) return;
    NSFileManager *fm=[NSFileManager defaultManager];
    // Move to trash instead of unlink while mmap may be open — prevents SIGBUS on WebKit checkpoint
    NSString *trash=[home stringByAppendingPathComponent:@"Library/.RaptorTrash"];
    [fm createDirectoryAtPath:trash withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *rel in @[@"Library/Cookies",@"Library/HTTPStorages",@"Library/WebKit",@"Library/Caches",@"Library/Application Support"]) {
        NSString *p=[home stringByAppendingPathComponent:rel];
        if (![fm fileExistsAtPath:p]) continue;
        NSString *dst=[trash stringByAppendingPathComponent:[rel lastPathComponent]];
        [fm removeItemAtPath:dst error:nil];
        // rename is atomic and doesn't break open mmap as badly as unlink
        [fm moveItemAtPath:p toPath:dst error:nil];
        // schedule trash cleanup on next launch (or leave — cheap)
    }
    NSString *prefsDir=[home stringByAppendingPathComponent:@"Library/Preferences"];
    for (NSString *f in [fm contentsOfDirectoryAtPath:prefsDir error:nil]) {
        if (![f hasSuffix:@".plist"] || [f hasPrefix:@"com.apple."]) continue;
        NSString *full=[prefsDir stringByAppendingPathComponent:f];
        NSString *dst=[trash stringByAppendingPathComponent:f];
        [fm removeItemAtPath:dst error:nil];
        [fm moveItemAtPath:full toPath:dst error:nil];
    }
}

+ (BOOL)ensureControlDirExistsWithError:(NSError **)error { return [self ensureControlDir]; }

@end
