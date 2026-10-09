#import "RPGeoIdentity.h"
#import "RPContainer.h"
#import "RPContainerStore.h"

// Maps region → { timezone, language, localeId } for auto-adaptation when user picks a location.
// Only applies if the container has no explicit language/region override (keeps manual choice).

static NSDictionary *RPGeoTable(void) {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"FR": @{@"tz": @"Europe/Paris",       @"lang": @"fr", @"locale": @"fr_FR", @"country": @"FR"},
            @"US": @{@"tz": @"America/New_York",   @"lang": @"en", @"locale": @"en_US", @"country": @"US"},
            @"GB": @{@"tz": @"Europe/London",      @"lang": @"en", @"locale": @"en_GB", @"country": @"GB"},
            @"DE": @{@"tz": @"Europe/Berlin",      @"lang": @"de", @"locale": @"de_DE", @"country": @"DE"},
            @"IT": @{@"tz": @"Europe/Rome",        @"lang": @"it", @"locale": @"it_IT", @"country": @"IT"},
            @"ES": @{@"tz": @"Europe/Madrid",      @"lang": @"es", @"locale": @"es_ES", @"country": @"ES"},
            @"PT": @{@"tz": @"Europe/Lisbon",      @"lang": @"pt", @"locale": @"pt_PT", @"country": @"PT"},
            @"NL": @{@"tz": @"Europe/Amsterdam",   @"lang": @"nl", @"locale": @"nl_NL", @"country": @"NL"},
            @"BE": @{@"tz": @"Europe/Brussels",    @"lang": @"fr", @"locale": @"fr_BE", @"country": @"BE"},
            @"CH": @{@"tz": @"Europe/Zurich",      @"lang": @"de", @"locale": @"de_CH", @"country": @"CH"},
            @"CA": @{@"tz": @"America/Toronto",    @"lang": @"en", @"locale": @"en_CA", @"country": @"CA"},
            @"AU": @{@"tz": @"Australia/Sydney",   @"lang": @"en", @"locale": @"en_AU", @"country": @"AU"},
            @"JP": @{@"tz": @"Asia/Tokyo",         @"lang": @"ja", @"locale": @"ja_JP", @"country": @"JP"},
            @"CN": @{@"tz": @"Asia/Shanghai",      @"lang": @"zh-Hans", @"locale": @"zh_CN", @"country": @"CN"},
            @"BR": @{@"tz": @"America/Sao_Paulo",  @"lang": @"pt", @"locale": @"pt_BR", @"country": @"BR"},
            @"MX": @{@"tz": @"America/Mexico_City",@"lang": @"es", @"locale": @"es_MX", @"country": @"MX"},
            @"IN": @{@"tz": @"Asia/Kolkata",       @"lang": @"en", @"locale": @"en_IN", @"country": @"IN"},
            @"RU": @{@"tz": @"Europe/Moscow",      @"lang": @"ru", @"locale": @"ru_RU", @"country": @"RU"},
            @"TR": @{@"tz": @"Europe/Istanbul",    @"lang": @"tr", @"locale": @"tr_TR", @"country": @"TR"},
            @"AE": @{@"tz": @"Asia/Dubai",         @"lang": @"ar", @"locale": @"ar_AE", @"country": @"AE"},
            @"SA": @{@"tz": @"Asia/Riyadh",        @"lang": @"ar", @"locale": @"ar_SA", @"country": @"SA"},
            @"ZA": @{@"tz": @"Africa/Johannesburg",@"lang": @"en", @"locale": @"en_ZA", @"country": @"ZA"},
            @"SE": @{@"tz": @"Europe/Stockholm",   @"lang": @"sv", @"locale": @"sv_SE", @"country": @"SE"},
            @"PL": @{@"tz": @"Europe/Warsaw",      @"lang": @"pl", @"locale": @"pl_PL", @"country": @"PL"},
            @"TH": @{@"tz": @"Asia/Bangkok",       @"lang": @"th", @"locale": @"th_TH", @"country": @"TH"},
            @"VN": @{@"tz": @"Asia/Ho_Chi_Minh",   @"lang": @"vi", @"locale": @"vi_VN", @"country": @"VN"},
            @"ID": @{@"tz": @"Asia/Jakarta",       @"lang": @"id", @"locale": @"id_ID", @"country": @"ID"},
            @"KR": @{@"tz": @"Asia/Seoul",         @"lang": @"ko", @"locale": @"ko_KR", @"country": @"KR"},
            @"AR": @{@"tz": @"America/Argentina/Buenos_Aires", @"lang": @"es", @"locale": @"es_AR", @"country": @"AR"},
        };
    });
    return t;
}

@implementation RPGeoIdentity

+ (NSDictionary *)profileForRegion:(NSString *)region {
    if (!region.length) return nil;
    return RPGeoTable()[region];
}

+ (void)autoAdaptContainer:(RPContainer *)c {
    if (!c || c.isDefault) return;
    if (!c.hasLocation || !c.locationName.length) return;
    // Don't overwrite explicit user choice — only auto-fill if empty
    BOOL hasLang = c.appLanguage.length > 0;
    BOOL hasRegion = c.regionCountry.length > 0;
    if (hasLang && hasRegion) return;

    // Infer region from reverse-geocoded locationName (contains country)
    // locationName is "City, Country" from CLGeocoder
    NSString *locName = c.locationName.lowercaseString;
    NSString *inferredRegion = nil;

    // Try to match country name in locationName
    NSDictionary *countryToRegion = @{
        @"france": @"FR", @"united states": @"US", @"usa": @"US", @"united kingdom": @"GB", @"england": @"GB",
        @"germany": @"DE", @"deutschland": @"DE", @"italy": @"IT", @"italia": @"IT", @"spain": @"ES", @"españa": @"ES",
        @"japan": @"JP", @"japon": @"JP", @"china": @"CN", @"chine": @"CN", @"brazil": @"BR", @"brésil": @"BR",
        @"canada": @"CA", @"australia": @"AU", @"australie": @"AU", @"russia": @"RU", @"russie": @"RU",
        @"turkey": @"TR", @"turquie": @"TR", @"india": @"IN", @"inde": @"IN", @"mexico": @"MX", @"mexique": @"MX",
        @"netherlands": @"NL", @"pays-bas": @"NL", @"belgium": @"BE", @"belgique": @"BE",
        @"switzerland": @"CH", @"suisse": @"CH", @"portugal": @"PT", @"poland": @"PL", @"pologne": @"PL",
        @"sweden": @"SE", @"suède": @"SE", @"thailand": @"TH", @"thaïlande": @"TH",
        @"vietnam": @"VN", @"indonesia": @"ID", @"indonésie": @"ID", @"korea": @"KR", @"corée": @"KR",
        @"united arab emirates": @"AE", @"émirats": @"AE", @"saudi": @"SA", @"arabie": @"SA",
        @"south africa": @"ZA", @"afrique du sud": @"ZA", @"argentina": @"AR", @"argentine": @"AR",
    };
    for (NSString *country in countryToRegion) {
        if ([locName containsString:country]) { inferredRegion = countryToRegion[country]; break; }
    }
    // Also check ISO code directly in locationName
    if (!inferredRegion) {
        for (NSString *code in RPGeoTable()) {
            if ([locName containsString:[code lowercaseString]]) { inferredRegion = code; break; }
        }
    }
    if (!inferredRegion) return;

    NSDictionary *profile = RPGeoTable()[inferredRegion];
    if (!profile) return;

    NSString *newLang = hasLang ? c.appLanguage : profile[@"lang"];
    NSString *newRegion = hasRegion ? c.regionCountry : inferredRegion;

    // Only write if inferred differs
    if ([newLang isEqualToString:c.appLanguage] && [newRegion isEqualToString:c.regionCountry]) return;

    NSError *err = nil;
    [[RPContainerStore shared] setAppLanguage:newLang region:newRegion forContainer:c error:&err];
}

@end
