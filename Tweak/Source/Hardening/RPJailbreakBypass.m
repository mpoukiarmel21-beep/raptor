#import "RPJailbreakBypass.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>
#import <dlfcn.h>
#import "fishhook.h"

static BOOL RPIsJailbreakPath(NSString *path) {
    if (!path.length) return NO;
    NSString *lower = path.lowercaseString;
    NSArray *needles = @[
        @"/applications/cydia.app",
        @"/applications/sileo.app",
        @"/library/mobilesubstrate",
        @"/var/jb",
        @"/private/var/lib/apt",
        @"/etc/apt",
        @"/usr/libexec/cranehelperd",
        @"/library/preferenceloader",
        @"com.opa334.crane",
        @"crane.dylib",
        @"raptor.dylib",
        @"/bin/bash",
        @"/usr/bin/ssh",
    ];
    for (NSString *n in needles) if ([lower containsString:n]) return YES;
    return NO;
}

static BOOL RPIsJailbreakURL(NSURL *url) {
    if (!url) return NO;
    NSString *s = url.absoluteString.lowercaseString;
    return [s hasPrefix:@"cydia://"] || [s hasPrefix:@"sileo://"] || [s hasPrefix:@"zbra://"] || [s hasPrefix:@"filza://"];
}

// Originals
static int (*orig_stat)(const char *, struct stat *) = NULL;
static int (*orig_access)(const char *, int) = NULL;
static int (*orig_lstat)(const char *, struct stat *) = NULL;
static FILE* (*orig_fopen)(const char *, const char *) = NULL;
static pid_t (*orig_fork)(void) = NULL;

static int rp_stat(const char *path, struct stat *sb) {
    if (path && RPIsJailbreakPath([NSString stringWithUTF8String:path])) { errno = ENOENT; return -1; }
    return orig_stat ? orig_stat(path, sb) : stat(path, sb);
}
static int rp_access(const char *path, int mode) {
    if (path && RPIsJailbreakPath([NSString stringWithUTF8String:path])) { errno = ENOENT; return -1; }
    return orig_access ? orig_access(path, mode) : access(path, mode);
}
static int rp_lstat(const char *path, struct stat *sb) {
    if (path && RPIsJailbreakPath([NSString stringWithUTF8String:path])) { errno = ENOENT; return -1; }
    return orig_lstat ? orig_lstat(path, sb) : lstat(path, sb);
}
static FILE* rp_fopen(const char *path, const char *mode) {
    if (path && RPIsJailbreakPath([NSString stringWithUTF8String:path])) { errno = ENOENT; return NULL; }
    return orig_fopen ? orig_fopen(path, mode) : fopen(path, mode);
}
static pid_t rp_fork(void) { errno = ENOSYS; return -1; }

@implementation RPJailbreakBypass

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // C-level via fishhook
        struct rebinding rebs[] = {
            {"stat", rp_stat, (void **)&orig_stat},
            {"access", rp_access, (void **)&orig_access},
            {"lstat", rp_lstat, (void **)&orig_lstat},
            {"fopen", rp_fopen, (void **)&orig_fopen},
            {"fork", rp_fork, (void **)&orig_fork},
        };
        rebind_symbols(rebs, sizeof(rebs)/sizeof(rebs[0]));

        // ObjC-level: NSFileManager fileExistsAtPath:
        Method m = class_getInstanceMethod([NSFileManager class], @selector(fileExistsAtPath:));
        if (m) {
            IMP orig = method_getImplementation(m);
            typedef BOOL (*Fn)(id, SEL, NSString *);
            Fn fn = (Fn)orig;
            method_setImplementation(m, imp_implementationWithBlock(^BOOL(id _self, NSString *path){
                if (RPIsJailbreakPath(path)) return NO;
                return fn(_self, @selector(fileExistsAtPath:), path);
            }));
        }

        // UIApplication canOpenURL: for cydia:// etc
        Method canOpen = class_getInstanceMethod([UIApplication class], @selector(canOpenURL:));
        if (canOpen) {
            IMP orig = method_getImplementation(canOpen);
            typedef BOOL (*Fn)(id, SEL, NSURL *);
            Fn fn = (Fn)orig;
            method_setImplementation(canOpen, imp_implementationWithBlock(^BOOL(id _self, NSURL *url){
                if (RPIsJailbreakURL(url)) return NO;
                return fn(_self, @selector(canOpenURL:), url);
            }));
        }
    });
}

@end
