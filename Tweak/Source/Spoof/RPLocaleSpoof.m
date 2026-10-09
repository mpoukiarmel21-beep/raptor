#import "RPLocaleSpoof.h"
#import "RPContainer.h"
#import "RPContainerStore.h"
#import "fishhook.h"
#import <objc/runtime.h>

static NSLocale *gFixedLocale = nil;
static NSArray *gPreferredLanguages = nil;
static NSTimeZone *gFixedTZ = nil;

static NSString *RPTimeZoneForRegion(NSString *region) {
    NSDictionary *m = @{@"US":@"America/New_York",@"FR":@"Europe/Paris",@"GB":@"Europe/London",@"DE":@"Europe/Berlin",@"IT":@"Europe/Rome",@"ES":@"Europe/Madrid",@"PT":@"Europe/Lisbon",@"NL":@"Europe/Amsterdam",@"BE":@"Europe/Brussels",@"CH":@"Europe/Zurich",@"CA":@"America/Toronto",@"AU":@"Australia/Sydney",@"JP":@"Asia/Tokyo",@"CN":@"Asia/Shanghai",@"BR":@"America/Sao_Paulo",@"MX":@"America/Mexico_City",@"IN":@"Asia/Kolkata",@"RU":@"Europe/Moscow",@"TR":@"Europe/Istanbul",@"AE":@"Asia/Dubai",@"SA":@"Asia/Riyadh",@"ZA":@"Africa/Johannesburg",@"SE":@"Europe/Stockholm",@"PL":@"Europe/Warsaw",@"TH":@"Asia/Bangkok",@"VN":@"Asia/Ho_Chi_Minh",@"ID":@"Asia/Jakarta",@"KR":@"Asia/Seoul"};
    return m[region];
}

static CFLocaleRef (*orig_CFLocaleCopyCurrent)(void) = NULL;
static CFTimeZoneRef (*orig_CFTimeZoneCopySystem)(void) = NULL;
static CFTimeZoneRef (*orig_CFTimeZoneCopyDefault)(void) = NULL;

static CFLocaleRef rp_CFLocaleCopyCurrent(void) {
    if (gFixedLocale) {
        // Derive CFLocale from gFixedLocale identifier
        CFLocaleRef loc = CFLocaleCreate(kCFAllocatorDefault, (__bridge CFStringRef)gFixedLocale.localeIdentifier);
        return loc ?: orig_CFLocaleCopyCurrent();
    }
    return orig_CFLocaleCopyCurrent();
}
static CFTimeZoneRef rp_CFTimeZoneCopySystem(void) {
    if (gFixedTZ) return (__bridge_retained CFTimeZoneRef)[gFixedTZ copy];
    return orig_CFTimeZoneCopySystem();
}
static CFTimeZoneRef rp_CFTimeZoneCopyDefault(void) {
    if (gFixedTZ) return (__bridge_retained CFTimeZoneRef)[gFixedTZ copy];
    return orig_CFTimeZoneCopyDefault();
}

@interface RPLocalizedBundle : NSBundle @end
@implementation RPLocalizedBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName {
    NSString *r = [super localizedStringForKey:key value:@"__RP_LPROJ_MISS__" table:tableName];
    if ([r isEqualToString:@"__RP_LPROJ_MISS__"]) return [super localizedStringForKey:key value:value table:tableName];
    return r;
}
@end

static void RPSwizzleClassMethod(Class cls, SEL sel, id (^block)(id)) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^id(id _self){ return block(_self); });
    method_setImplementation(m, imp);
}

@implementation RPLocaleSpoof

+ (void)installForContainer:(RPContainer *)container {
    if (!container || container.isDefault) return;
    BOOL hasLang = container.appLanguage.length > 0;
    BOOL hasRegion = container.regionCountry.length > 0;
    if (!hasLang && !hasRegion) return;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.burbn.instagram";
    if (hasLang) {
        NSString *tag = container.appLanguage; // e.g. fr
        NSString *localeId = [NSString stringWithFormat:@"%@_%@", tag, hasRegion ? container.regionCountry : @"US"];
        // Seed app-domain AppleLanguages / AppleLocale so NSUserDefaults readers see it
        CFPreferencesSetValue(CFSTR("AppleLanguages"), (__bridge CFPropertyListRef)@[tag], (__bridge CFStringRef)bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSetValue(CFSTR("AppleLocale"), (__bridge CFPropertyListRef)localeId, (__bridge CFStringRef)bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize((__bridge CFStringRef)bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        gPreferredLanguages = @[ [NSString stringWithFormat:@"%@-%@", tag, hasRegion ? container.regionCountry : @"US"], tag ];
        gFixedLocale = [[NSLocale alloc] initWithLocaleIdentifier:localeId];
    } else if (hasRegion) {
        NSString *locId = [NSString stringWithFormat:@"en_%@", container.regionCountry];
        gFixedLocale = [[NSLocale alloc] initWithLocaleIdentifier:locId];
    }

    if (hasRegion) {
        NSString *tzName = RPTimeZoneForRegion(container.regionCountry);
        if (tzName) gFixedTZ = [NSTimeZone timeZoneWithName:tzName];
    }

    if (gFixedLocale) {
        NSLocale *(^locBlock)(id) = ^NSLocale*(id _self){ return gFixedLocale; };
        RPSwizzleClassMethod([NSLocale class], @selector(currentLocale), ^id(id _s){ return locBlock(_s); });
        RPSwizzleClassMethod([NSLocale class], @selector(autoupdatingCurrentLocale), ^id(id _s){ return locBlock(_s); });
        // NSLocale alloc path: swizzle instance? simplest: currentLocale is enough for most
        if (gPreferredLanguages) {
            RPSwizzleClassMethod([NSLocale class], @selector(preferredLanguages), ^id(id _s){ return gPreferredLanguages; });
        }
        // NSUserDefaults readers
        Method m1 = class_getInstanceMethod([NSUserDefaults class], @selector(objectForKey:));
        if (m1) {
            IMP orig = method_getImplementation(m1);
            typedef id (*Fn)(id,SEL,NSString*);
            Fn fn = (Fn)orig;
            method_setImplementation(m1, imp_implementationWithBlock(^id(id _self, NSString *k){
                if ([k isEqualToString:@"AppleLanguages"] && gPreferredLanguages) return gPreferredLanguages;
                if ([k isEqualToString:@"AppleLocale"] && gFixedLocale) return gFixedLocale.localeIdentifier;
                return fn(_self, @selector(objectForKey:), k);
            }));
        }
    }
    if (gFixedTZ) {
        NSTimeZone *(^tz)(id) = ^NSTimeZone*(id _s){ return gFixedTZ; };
        RPSwizzleClassMethod([NSTimeZone class], @selector(systemTimeZone), ^id(id _s){ return tz(_s); });
        RPSwizzleClassMethod([NSTimeZone class], @selector(localTimeZone), ^id(id _s){ return tz(_s); });
        RPSwizzleClassMethod([NSTimeZone class], @selector(defaultTimeZone), ^id(id _s){ return tz(_s); });
    }
    // fishhook — guard against double rebind (second call would make orig point to shim → recursion)
    static BOOL gLocaleHooked = NO;
    if (!gLocaleHooked) {
        struct rebinding rbs[] = {
            {"CFLocaleCopyCurrent", rp_CFLocaleCopyCurrent, (void**)&orig_CFLocaleCopyCurrent},
            {"CFTimeZoneCopySystem", rp_CFTimeZoneCopySystem, (void**)&orig_CFTimeZoneCopySystem},
            {"CFTimeZoneCopyDefault", rp_CFTimeZoneCopyDefault, (void**)&orig_CFTimeZoneCopyDefault},
        };
        rebind_symbols(rbs, 3);
        gLocaleHooked = YES;
    }
}

+ (NSArray<NSString *> *)supportedLanguageCodes { return @[@"en",@"fr",@"es",@"pt",@"de",@"it",@"nl",@"ar",@"ru",@"tr",@"hi",@"id",@"th",@"vi",@"pl",@"sv",@"ja",@"ko",@"zh-Hans",@"zh-Hant"]; }
+ (NSArray<NSString *> *)supportedRegionCodes { return @[@"US",@"FR",@"GB",@"DE",@"IT",@"ES",@"PT",@"NL",@"BE",@"CH",@"CA",@"AU",@"JP",@"CN",@"BR",@"MX",@"IN",@"RU",@"TR",@"AE",@"SA",@"ZA",@"SE",@"PL",@"TH",@"VN",@"ID",@"KR",@"AR"]; }
+ (NSString *)deviceLanguage {
    NSString *pref = [NSLocale preferredLanguages].firstObject ?: @"en";
    NSString *base = [[pref componentsSeparatedByString:@"-"].firstObject lowercaseString] ?: @"en";
    return base;
}
+ (NSString *)deviceRegion {
    return [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode] ?: @"US";
}
+ (NSString *)displayNameForLanguage:(NSString *)lang {
    NSDictionary *m = @{@"en":@"English",@"fr":@"Français",@"es":@"Español",@"pt":@"Português",@"de":@"Deutsch",@"it":@"Italiano",@"nl":@"Nederlands",@"ar":@"العربية",@"ru":@"Русский",@"tr":@"Türkçe",@"hi":@"हिन्दी",@"id":@"Indonesia",@"th":@"ไทย",@"vi":@"Tiếng Việt",@"pl":@"Polski",@"sv":@"Svenska",@"ja":@"日本語",@"ko":@"한국어",@"zh-Hans":@"中文(简体)",@"zh-Hant":@"中文(繁體)"};
    return m[lang] ?: lang;
}
+ (NSString *)displayNameForRegion:(NSString *)r {
    NSDictionary *m = @{@"US":@"United States",@"FR":@"France",@"GB":@"United Kingdom",@"DE":@"Deutschland",@"IT":@"Italia",@"ES":@"España",@"PT":@"Portugal",@"NL":@"Nederland",@"BE":@"Belgique",@"CH":@"Suisse",@"CA":@"Canada",@"AU":@"Australia",@"JP":@"日本",@"CN":@"中国",@"BR":@"Brasil",@"MX":@"México",@"IN":@"India",@"RU":@"Россия",@"TR":@"Türkiye",@"AE":@"UAE",@"SA":@"السعودية",@"ZA":@"South Africa",@"SE":@"Sverige",@"PL":@"Polska",@"TH":@"ไทย",@"VN":@"Việt Nam",@"ID":@"Indonesia",@"KR":@"대한민국",@"AR":@"Argentina"};
    return m[r] ?: r;
}
@end
