#import "RPContainer.h"

NSString * const kRPDefaultCID = @"default";

@implementation RPContainer

+ (instancetype)containerWithName:(NSString *)name {
    RPContainer *c = [[self alloc] init];
    c.cid = [[NSUUID UUID] UUIDString];
    c.name = name.length ? name : @"Untitled";
    c.isDefault = NO;
    c.createdAt = [NSDate date];
    c.lastUsedAt = [NSDate date];
    return c;
}

+ (instancetype)defaultContainer {
    RPContainer *c = [[self alloc] init];
    c.cid = kRPDefaultCID;
    c.name = @"Default";
    c.isDefault = YES;
    c.createdAt = [NSDate date];
    c.lastUsedAt = [NSDate date];
    return c;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cid = [[NSUUID UUID] UUIDString];
        _name = @"Untitled";
        _isDefault = NO;
        _createdAt = [NSDate date];
        _lastUsedAt = [NSDate date];
    }
    return self;
}

- (instancetype)initWithDict:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        NSString *cid = dict[@"cid"];
        if ([cid isKindOfClass:[NSString class]] && cid.length) {
            _cid = [cid copy];
        } else {
            _cid = [[NSUUID UUID] UUIDString];
        }
        NSString *name = dict[@"name"];
        if ([name isKindOfClass:[NSString class]] && name.length) {
            _name = [name copy];
        } else {
            _name = @"Untitled";
        }
        _isDefault = [dict[@"isDefault"] boolValue];
        // Canonical default cid always marked isDefault
        if ([_cid isEqualToString:kRPDefaultCID]) {
            _isDefault = YES;
        }

        id lat = dict[@"latitude"];
        if ([lat isKindOfClass:[NSNumber class]]) _latitude = lat;
        id lng = dict[@"longitude"];
        if ([lng isKindOfClass:[NSNumber class]]) _longitude = lng;

        id locName = dict[@"locationName"];
        if ([locName isKindOfClass:[NSString class]]) _locationName = [locName copy];

        id deviceModel = dict[@"deviceModel"];
        if ([deviceModel isKindOfClass:[NSString class]]) _deviceModel = [deviceModel copy];
        id marketingName = dict[@"marketingName"];
        if ([marketingName isKindOfClass:[NSString class]]) _marketingName = [marketingName copy];
        id iosVersion = dict[@"iosVersion"];
        if ([iosVersion isKindOfClass:[NSString class]]) _iosVersion = [iosVersion copy];

        id appLanguage = dict[@"appLanguage"];
        if ([appLanguage isKindOfClass:[NSString class]]) _appLanguage = [appLanguage copy];
        id regionCountry = dict[@"regionCountry"];
        if ([regionCountry isKindOfClass:[NSString class]]) _regionCountry = [regionCountry copy];

        id cameraVideoPath = dict[@"cameraVideoPath"];
        if ([cameraVideoPath isKindOfClass:[NSString class]]) _cameraVideoPath = [cameraVideoPath copy];

        id createdAt = dict[@"createdAt"];
        if ([createdAt isKindOfClass:[NSDate class]]) {
            _createdAt = createdAt;
        } else if ([createdAt isKindOfClass:[NSNumber class]]) {
            _createdAt = [NSDate dateWithTimeIntervalSince1970:[createdAt doubleValue]];
        } else if ([createdAt isKindOfClass:[NSString class]]) {
            // Try ISO8601
            NSDateFormatter *f = [[NSDateFormatter alloc] init];
            f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
            NSDate *d = [f dateFromString:createdAt];
            if (d) _createdAt = d;
        }
        if (!_createdAt) _createdAt = [NSDate date];

        id lastUsedAt = dict[@"lastUsedAt"];
        if ([lastUsedAt isKindOfClass:[NSDate class]]) {
            _lastUsedAt = lastUsedAt;
        } else if ([lastUsedAt isKindOfClass:[NSNumber class]]) {
            _lastUsedAt = [NSDate dateWithTimeIntervalSince1970:[lastUsedAt doubleValue]];
        } else if ([lastUsedAt isKindOfClass:[NSString class]]) {
            NSDateFormatter *f = [[NSDateFormatter alloc] init];
            f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
            NSDate *d = [f dateFromString:lastUsedAt];
            if (d) _lastUsedAt = d;
        }
        if (!_lastUsedAt) _lastUsedAt = [NSDate date];
    }
    return self;
}

- (NSDictionary *)toDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"cid"] = self.cid ?: kRPDefaultCID;
    d[@"name"] = self.name ?: @"Untitled";
    d[@"isDefault"] = @(self.isDefault);
    if (self.latitude) d[@"latitude"] = self.latitude;
    if (self.longitude) d[@"longitude"] = self.longitude;
    if (self.locationName) d[@"locationName"] = self.locationName;
    if (self.deviceModel) d[@"deviceModel"] = self.deviceModel;
    if (self.marketingName) d[@"marketingName"] = self.marketingName;
    if (self.iosVersion) d[@"iosVersion"] = self.iosVersion;
    if (self.appLanguage) d[@"appLanguage"] = self.appLanguage;
    if (self.regionCountry) d[@"regionCountry"] = self.regionCountry;
    if (self.cameraVideoPath) d[@"cameraVideoPath"] = self.cameraVideoPath;
    if (self.createdAt) d[@"createdAt"] = self.createdAt;
    if (self.lastUsedAt) d[@"lastUsedAt"] = self.lastUsedAt;
    return [d copy];
}

- (BOOL)hasLocation {
    return self.latitude != nil && self.longitude != nil;
}

- (NSString *)displayLocationName {
    if (self.locationName.length) return self.locationName;
    if ([self hasLocation]) {
        return [NSString stringWithFormat:@"%@, %@", self.latitude, self.longitude];
    }
    return @"No location";
}

- (id)copyWithZone:(nullable NSZone *)zone {
    RPContainer *copy = [[[self class] allocWithZone:zone] init];
    copy.cid = self.cid;
    copy.name = self.name;
    copy.isDefault = self.isDefault;
    copy.latitude = self.latitude;
    copy.longitude = self.longitude;
    copy.locationName = self.locationName;
    copy.deviceModel = self.deviceModel;
    copy.marketingName = self.marketingName;
    copy.iosVersion = self.iosVersion;
    copy.appLanguage = self.appLanguage;
    copy.regionCountry = self.regionCountry;
    copy.cameraVideoPath = self.cameraVideoPath;
    copy.createdAt = self.createdAt;
    copy.lastUsedAt = self.lastUsedAt;
    return copy;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[RPContainer class]]) return NO;
    RPContainer *other = (RPContainer *)object;
    return [self.cid isEqualToString:other.cid];
}

- (NSUInteger)hash {
    return self.cid.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<RPContainer cid=%@ name=%@ isDefault=%d>", self.cid, self.name, self.isDefault];
}

@end
