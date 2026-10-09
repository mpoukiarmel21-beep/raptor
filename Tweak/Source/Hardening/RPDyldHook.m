#import "RPDyldHook.h"
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>
#import "fishhook.h"

// Hide raptor.dylib and jailbreak artifacts from dyld enumeration

static uint32_t (*orig_dyld_image_count)(void) = NULL;
static const char* (*orig_dyld_get_image_name)(uint32_t) = NULL;
static const struct mach_header* (*orig_dyld_get_image_header)(uint32_t) = NULL;

static BOOL RPIsHiddenImage(const char *name) {
    if (!name) return NO;
    // Hide our own dylib + common jailbreak paths
    if (strstr(name, "raptor.dylib")) return YES;
    if (strstr(name, "MobileSubstrate")) return YES;
    if (strstr(name, "libhooker")) return YES;
    if (strstr(name, "SubstrateLoader")) return YES;
    if (strstr(name, "/procursus/")) return YES;
    if (strstr(name, "FridaGadget")) return YES;
    if (strstr(name, "Crane")) return YES;
    if (strstr(name, "libSandy")) return YES;
    return NO;
}

static uint32_t rp_dyld_image_count(void) {
    uint32_t real = orig_dyld_image_count ? orig_dyld_image_count() : _dyld_image_count();
    uint32_t hidden = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *name = orig_dyld_get_image_name ? orig_dyld_get_image_name(i) : _dyld_get_image_name(i);
        if (RPIsHiddenImage(name)) hidden++;
    }
    return real > hidden ? real - hidden : real;
}

static const char* rp_dyld_get_image_name(uint32_t idx) {
    uint32_t real = orig_dyld_image_count ? orig_dyld_image_count() : _dyld_image_count();
    uint32_t visible = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *name = orig_dyld_get_image_name ? orig_dyld_get_image_name(i) : _dyld_get_image_name(i);
        if (RPIsHiddenImage(name)) continue;
        if (visible == idx) return name;
        visible++;
    }
    return NULL;
}

static const struct mach_header* rp_dyld_get_image_header(uint32_t idx) {
    uint32_t real = orig_dyld_image_count ? orig_dyld_image_count() : _dyld_image_count();
    uint32_t visible = 0;
    for (uint32_t i = 0; i < real; i++) {
        const char *name = orig_dyld_get_image_name ? orig_dyld_get_image_name(i) : _dyld_get_image_name(i);
        if (RPIsHiddenImage(name)) continue;
        if (visible == idx) {
            return orig_dyld_get_image_header ? orig_dyld_get_image_header(i) : _dyld_get_image_header(i);
        }
        visible++;
    }
    return NULL;
}

@implementation RPDyldHook

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct rebinding rebs[] = {
            {"_dyld_image_count", rp_dyld_image_count, (void **)&orig_dyld_image_count},
            {"_dyld_get_image_name", rp_dyld_get_image_name, (void **)&orig_dyld_get_image_name},
            {"_dyld_get_image_header", rp_dyld_get_image_header, (void **)&orig_dyld_get_image_header},
        };
        rebind_symbols(rebs, sizeof(rebs)/sizeof(rebs[0]));
        // Second pass: rebind _dyld_get_image_name for already-bound images needs image-specific rebinding
        // fishhook already handles re-binding all images, so single call suffices.
    });
}

@end
