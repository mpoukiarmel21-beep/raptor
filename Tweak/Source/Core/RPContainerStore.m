#import "RPContainerStore.h"
#import "RPPaths.h"
#import <Security/Security.h>

NSString * const kRPContainersChanged = @"kRPContainersChanged";
NSString * const kRPActiveChanged     = @"kRPActiveChanged";

@interface RPContainerStore ()
@property (nonatomic, strong) NSMutableArray<RPContainer *> *mutableContainers;
@property (nonatomic, strong) NSRecursiveLock *lock;
@property (nonatomic, copy) NSString *internalActiveCID;
@end

@implementation RPContainerStore

+ (instancetype)shared {
    static RPContainerStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        _mutableContainers = [NSMutableArray array];
        _internalActiveCID = [kRPDefaultCID copy];
        _isolationDegraded = NO;
    }
    return self;
}

- (instancetype)init {
    // Enforce singleton
    return [[self class] shared];
}

// MARK: - Accessors

- (NSArray<RPContainer *> *)containers {
    [self.lock lock];
    NSArray *copy = [self.mutableContainers copy];
    [self.lock unlock];
    return copy;
}

- (NSString *)activeCID {
    [self.lock lock];
    NSString *cid = [self.internalActiveCID copy];
    [self.lock unlock];
    return cid;
}

- (void)setActiveCID:(NSString *)activeCID {
    NSError *err = nil;
    [self setActiveCID:activeCID error:&err];
    // setter ignores error for property syntax
    (void)err;
}

// MARK: - Notifications helper

- (void)postOnMain:(NSString *)name {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
    });
}

// MARK: - Load

- (void)load {
    [self.lock lock];

    [RPPaths ensureControlDir];

    NSString *containersFile = [RPPaths containersFile];
    NSString *activeFile = [RPPaths activeFile];

    NSMutableArray<RPContainer *> *loaded = [NSMutableArray array];

    NSData *cData = [NSData dataWithContentsOfFile:containersFile];
    if (cData.length) {
        NSError *plistErr = nil;
        NSPropertyListFormat fmt;
        id plist = [NSPropertyListSerialization propertyListWithData:cData options:NSPropertyListImmutable format:&fmt error:&plistErr];
        if ([plist isKindOfClass:[NSArray class]]) {
            for (id obj in (NSArray *)plist) {
                if (![obj isKindOfClass:[NSDictionary class]]) continue;
                RPContainer *c = [[RPContainer alloc] initWithDict:obj];
                [loaded addObject:c];
            }
        }
    }

    // Ensure one default at index 0
    RPContainer *defaultContainer = nil;
    for (RPContainer *c in loaded) {
        if ([c.cid isEqualToString:kRPDefaultCID]) {
            defaultContainer = c;
            break;
        }
    }
    if (!defaultContainer) {
        defaultContainer = [RPContainer defaultContainer];
        [loaded insertObject:defaultContainer atIndex:0];
    } else {
        // Move default to index 0 if not already
        if ([loaded indexOfObject:defaultContainer] != 0) {
            [loaded removeObject:defaultContainer];
            [loaded insertObject:defaultContainer atIndex:0];
        }
        defaultContainer.isDefault = YES;
        if (![defaultContainer.name length]) defaultContainer.name = @"Default";
    }
    // Ensure only the default has isDefault YES
    for (RPContainer *c in loaded) {
        if (c != defaultContainer) c.isDefault = NO;
    }

    // Load activeCID
    NSString *activeCID = kRPDefaultCID;
    NSData *aData = [NSData dataWithContentsOfFile:activeFile];
    if (aData.length) {
        NSError *plistErr = nil;
        NSPropertyListFormat fmt;
        id plist = [NSPropertyListSerialization propertyListWithData:aData options:NSPropertyListImmutable format:&fmt error:&plistErr];
        if ([plist isKindOfClass:[NSDictionary class]]) {
            NSString *candidate = ((NSDictionary *)plist)[@"activeCID"];
            if ([candidate isKindOfClass:[NSString class]] && candidate.length) {
                activeCID = candidate;
            }
        }
    }

    // Validate activeCID exists
    BOOL found = NO;
    for (RPContainer *c in loaded) {
        if ([c.cid isEqualToString:activeCID]) { found = YES; break; }
    }
    if (!found) {
        self.isolationDegraded = YES;
        activeCID = kRPDefaultCID;
    } else {
        self.isolationDegraded = NO;
    }

    self.mutableContainers = loaded;
    self.internalActiveCID = [activeCID copy];

    // Persist back to ensure files exist and default is stored
    NSError *persistErr = nil;
    [self persistLockedWithError:&persistErr];

    [self.lock unlock];

    [self postOnMain:kRPContainersChanged];
    [self postOnMain:kRPActiveChanged];
}

// MARK: - Lookups

- (RPContainer *)containerForCID:(NSString *)cid {
    if (!cid.length) return nil;
    [self.lock lock];
    RPContainer *found = nil;
    for (RPContainer *c in self.mutableContainers) {
        if ([c.cid isEqualToString:cid]) { found = c; break; }
    }
    [self.lock unlock];
    return found;
}

- (RPContainer *)activeContainer {
    return [self containerForCID:self.activeCID];
}

// MARK: - Persist

- (BOOL)persistLockedWithError:(NSError **)error {
    return [self persistLockedError:error];
}

- (BOOL)persistLockedError:(NSError **)error {
    // Must be called with lock held
    NSMutableArray *dicts = [NSMutableArray arrayWithCapacity:self.mutableContainers.count];
    for (RPContainer *c in self.mutableContainers) {
        [dicts addObject:[c toDict]];
    }
    NSError *plistErr = nil;
    NSData *containersData = [NSPropertyListSerialization dataWithPropertyList:dicts format:NSPropertyListBinaryFormat_v1_0 options:0 error:&plistErr];
    if (!containersData) {
        if (error) *error = plistErr;
        return NO;
    }
    NSDictionary *activeDict = @{ @"activeCID": self.internalActiveCID ?: kRPDefaultCID };
    NSData *activeData = [NSPropertyListSerialization dataWithPropertyList:activeDict format:NSPropertyListBinaryFormat_v1_0 options:0 error:&plistErr];
    if (!activeData) {
        if (error) *error = plistErr;
        return NO;
    }

    [RPPaths ensureControlDir];
    NSString *containersFile = [RPPaths containersFile];
    NSString *activeFile = [RPPaths activeFile];

    // Control plane must be readable before first unlock (push launch) → None
    NSDataWritingOptions opts = NSDataWritingAtomic | NSDataWritingFileProtectionNone;

    BOOL ok1 = [containersData writeToFile:containersFile options:opts error:error];
    if (!ok1) return NO;
    BOOL ok2 = [activeData writeToFile:activeFile options:opts error:error];
    if (!ok2) return NO;
    return YES;
}

// Public alias expected by spec naming is persistLocked error:
- (BOOL)persistLocked:(NSError **)error {
    return [self persistLockedError:error];
}

// MARK: - Create

- (RPContainer *)createWithName:(NSString *)name cid:(NSString *)cid error:(NSError **)error {
    [self.lock lock];

    NSString *proposedCID = nil;
    BOOL useSupplied = (cid.length && ![cid isEqualToString:kRPDefaultCID]);
    if (useSupplied) {
        // Check collision
        BOOL collision = NO;
        for (RPContainer *c in self.mutableContainers) {
            if ([c.cid isEqualToString:cid]) { collision = YES; break; }
        }
        if (collision) {
            useSupplied = NO;
        } else {
            proposedCID = cid;
        }
    }
    if (!proposedCID) {
        proposedCID = [[NSUUID UUID] UUIDString];
    }

    // Ensure skeleton FIRST
    NSString *root = [RPPaths containerRootForCID:proposedCID];
    NSError *skelErr = nil;
    BOOL skelOK = [RPPaths ensureSkeletonAtRoot:root error:&skelErr];
    if (!skelOK) {
        if (error) *error = skelErr;
        [self.lock unlock];
        return nil;
    }

    RPContainer *container = [[RPContainer alloc] init];
    container.cid = proposedCID;
    container.name = name.length ? name : @"Untitled";
    container.isDefault = NO;
    container.createdAt = [NSDate date];
    container.lastUsedAt = [NSDate date];

    [self.mutableContainers addObject:container];

    NSError *persistErr = nil;
    BOOL persistOK = [self persistLockedError:&persistErr];
    if (!persistOK) {
        // Revert
        [self.mutableContainers removeObject:container];
        [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
        if (error) *error = persistErr;
        [self.lock unlock];
        return nil;
    }

    [self.lock unlock];
    [self postOnMain:kRPContainersChanged];
    return container;
}

// MARK: - Rename

- (BOOL)renameContainer:(RPContainer *)c to:(NSString *)newName error:(NSError **)error {
    if (!c || !newName.length) {
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:10 userInfo:@{NSLocalizedDescriptionKey: @"Invalid container or name"}];
        return NO;
    }
    [self.lock lock];
    // Find canonical instance
    RPContainer *found = nil;
    for (RPContainer *obj in self.mutableContainers) {
        if ([obj.cid isEqualToString:c.cid]) { found = obj; break; }
    }
    if (!found) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:11 userInfo:@{NSLocalizedDescriptionKey: @"Container not found"}];
        return NO;
    }
    NSString *oldName = found.name;
    found.name = [newName copy];
    NSError *persistErr = nil;
    BOOL ok = [self persistLockedError:&persistErr];
    if (!ok) {
        found.name = oldName;
        if (error) *error = persistErr;
        [self.lock unlock];
        return NO;
    }
    [self.lock unlock];
    [self postOnMain:kRPContainersChanged];
    return YES;
}

// MARK: - Remove

- (BOOL)removeContainer:(RPContainer *)c error:(NSError **)error {
    if (!c) {
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:20 userInfo:@{NSLocalizedDescriptionKey: @"Container is nil"}];
        return NO;
    }
    [self.lock lock];
    RPContainer *found = nil;
    for (RPContainer *obj in self.mutableContainers) {
        if ([obj.cid isEqualToString:c.cid]) { found = obj; break; }
    }
    if (!found) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:21 userInfo:@{NSLocalizedDescriptionKey: @"Container not found"}];
        return NO;
    }
    if (found.isDefault || [found.cid isEqualToString:kRPDefaultCID]) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:22 userInfo:@{NSLocalizedDescriptionKey: @"Cannot remove default container"}];
        return NO;
    }
    if ([found.cid isEqualToString:self.internalActiveCID]) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:23 userInfo:@{NSLocalizedDescriptionKey: @"Cannot remove active container"}];
        return NO;
    }

    // Wipe disk BEFORE list removal: Instances/<cid> + keychain purge + camera
    NSString *root = [RPPaths containerRootForCID:found.cid];
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];

    // Keychain purge for marker "RP:"
    [self purgeKeychainWithMarker:@"RP:" containerCID:found.cid];

    // Camera file for this container
    if (found.cameraVideoPath.length) {
        [[NSFileManager defaultManager] removeItemAtPath:found.cameraVideoPath error:nil];
    }
    // Also try conventional path: controlDir/Cameras/<cid>.mp4
    NSString *cameraPerCID = [[[RPPaths cameraDir] stringByAppendingPathComponent:found.cid] stringByAppendingPathExtension:@"mp4"];
    [[NSFileManager defaultManager] removeItemAtPath:cameraPerCID error:nil];

    [self.mutableContainers removeObject:found];
    NSError *persistErr = nil;
    BOOL ok = [self persistLockedError:&persistErr];
    if (!ok) {
        if (error) *error = persistErr;
        [self.lock unlock];
        return NO;
    }
    [self.lock unlock];
    [self postOnMain:kRPContainersChanged];
    return YES;
}

// MARK: - setActiveCID:error:

- (BOOL)setActiveCID:(NSString *)cid error:(NSError **)error {
    if (!cid.length) {
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:30 userInfo:@{NSLocalizedDescriptionKey: @"cid is empty"}];
        return NO;
    }
    [self.lock lock];
    BOOL exists = NO;
    RPContainer *target = nil;
    for (RPContainer *c in self.mutableContainers) {
        if ([c.cid isEqualToString:cid]) { exists = YES; target = c; break; }
    }
    if (!exists) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:31 userInfo:@{NSLocalizedDescriptionKey: @"Container not found"}];
        return NO;
    }
    NSString *oldCID = self.internalActiveCID;
    self.internalActiveCID = [cid copy];
    target.lastUsedAt = [NSDate date];
    NSError *persistErr = nil;
    BOOL ok = [self persistLockedError:&persistErr];
    if (!ok) {
        self.internalActiveCID = oldCID;
        if (error) *error = persistErr;
        [self.lock unlock];
        return NO;
    }
    self.isolationDegraded = NO;
    [self.lock unlock];
    [self postOnMain:kRPActiveChanged];
    return YES;
}

// MARK: - Setters

- (BOOL)setLocation:(NSNumber *)lat lng:(NSNumber *)lng name:(NSString *)locName forContainer:(RPContainer *)c error:(NSError **)error {
    [self.lock lock];
    RPContainer *found = nil;
    for (RPContainer *obj in self.mutableContainers) {
        if ([obj.cid isEqualToString:c.cid]) { found = obj; break; }
    }
    if (!found) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:40 userInfo:@{NSLocalizedDescriptionKey: @"Container not found"}];
        return NO;
    }
    NSNumber *oldLat = found.latitude;
    NSNumber *oldLng = found.longitude;
    NSString *oldName = found.locationName;
    found.latitude = lat;
    found.longitude = lng;
    found.locationName = [locName copy];
    NSError *persistErr = nil;
    BOOL ok = [self persistLockedError:&persistErr];
    if (!ok) {
        found.latitude = oldLat;
        found.longitude = oldLng;
        found.locationName = oldName;
        if (error) *error = persistErr;
        [self.lock unlock];
        return NO;
    }
    [self.lock unlock];
    [self postOnMain:kRPContainersChanged];
    return YES;
}

- (BOOL)setDeviceModel:(NSString *)model iosVersion:(NSString *)ios marketingName:(NSString *)mName forContainer:(RPContainer *)c error:(NSError **)error {
    [self.lock lock];
    RPContainer *found = nil;
    for (RPContainer *obj in self.mutableContainers) {
        if ([obj.cid isEqualToString:c.cid]) { found = obj; break; }
    }
    if (!found) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:41 userInfo:@{NSLocalizedDescriptionKey: @"Container not found"}];
        return NO;
    }
    NSString *oldModel = found.deviceModel;
    NSString *oldIOS = found.iosVersion;
    NSString *oldMName = found.marketingName;
    found.deviceModel = [model copy];
    found.iosVersion = [ios copy];
    found.marketingName = [mName copy];
    NSError *persistErr = nil;
    BOOL ok = [self persistLockedError:&persistErr];
    if (!ok) {
        found.deviceModel = oldModel;
        found.iosVersion = oldIOS;
        found.marketingName = oldMName;
        if (error) *error = persistErr;
        [self.lock unlock];
        return NO;
    }
    [self.lock unlock];
    [self postOnMain:kRPContainersChanged];
    return YES;
}

- (BOOL)setAppLanguage:(NSString *)lang region:(NSString *)region forContainer:(RPContainer *)c error:(NSError **)error {
    [self.lock lock];
    RPContainer *found = nil;
    for (RPContainer *obj in self.mutableContainers) {
        if ([obj.cid isEqualToString:c.cid]) { found = obj; break; }
    }
    if (!found) {
        [self.lock unlock];
        if (error) *error = [NSError errorWithDomain:@"RPContainerStore" code:42 userInfo:@{NSLocalizedDescriptionKey: @"Container not found"}];
        return NO;
    }
    NSString *oldLang = found.appLanguage;
    NSString *oldRegion = found.regionCountry;
    found.appLanguage = [lang copy];
    found.regionCountry = [region copy];
    NSError *persistErr = nil;
    BOOL ok = [self persistLockedError:&persistErr];
    if (!ok) {
        found.appLanguage = oldLang;
        found.regionCountry = oldRegion;
        if (error) *error = persistErr;
        [self.lock unlock];
        return NO;
    }
    [self.lock unlock];
    [self postOnMain:kRPContainersChanged];
    return YES;
}

// MARK: - resetAll

- (void)resetAll {
    [self.lock lock];
    // Collect non-defaults
    NSMutableArray<RPContainer *> *toDelete = [NSMutableArray array];
    RPContainer *defaultC = nil;
    for (RPContainer *c in self.mutableContainers) {
        if ([c.cid isEqualToString:kRPDefaultCID] || c.isDefault) {
            if (!defaultC) defaultC = c;
        } else {
            [toDelete addObject:c];
        }
    }
    if (!defaultC && self.mutableContainers.count) {
        defaultC = self.mutableContainers.firstObject;
        defaultC.cid = kRPDefaultCID;
        defaultC.isDefault = YES;
    }
    if (!defaultC) {
        defaultC = [RPContainer defaultContainer];
    }

    // Purge disk + keychain + camera for each non-default
    for (RPContainer *c in toDelete) {
        NSString *root = [RPPaths containerRootForCID:c.cid];
        [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
        [self purgeKeychainWithMarker:@"RP:" containerCID:c.cid];
        if (c.cameraVideoPath.length) {
            [[NSFileManager defaultManager] removeItemAtPath:c.cameraVideoPath error:nil];
        }
        NSString *cameraPerCID = [[[RPPaths cameraDir] stringByAppendingPathComponent:c.cid] stringByAppendingPathExtension:@"mp4"];
        [[NSFileManager defaultManager] removeItemAtPath:cameraPerCID error:nil];
    }

    // Also purge global RP: keychain entries
    [self purgeKeychainWithMarker:@"RP:" containerCID:nil];

    // Wipe real session files
    [RPPaths wipeRealSessionFiles];

    // Cookie jar
    NSHTTPCookieStorage *jar = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [[jar cookies] copy]) {
        [jar deleteCookie:cookie];
    }

    // removePersistentDomain for app bundle id
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID.length) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleID];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    // Keep only default
    self.mutableContainers = [NSMutableArray arrayWithObject:defaultC];
    defaultC.isDefault = YES;
    defaultC.cid = kRPDefaultCID;
    self.internalActiveCID = kRPDefaultCID;
    self.isolationDegraded = NO;

    // Clear location/device overrides on default? keep as-is per spec: just deletes non-defaults.
    // Persist
    NSError *err = nil;
    [self persistLockedError:&err];

    [self.lock unlock];
    [self postOnMain:kRPContainersChanged];
    [self postOnMain:kRPActiveChanged];
}

// MARK: - Keychain purge

- (void)purgeKeychainWithMarker:(NSString *)marker containerCID:(nullable NSString *)cid {
    // Best-effort: iterate generic password + internet password items.
    // Filter by service/account containing marker and optionally cid.
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword, (__bridge id)kSecClassInternetPassword ];
    for (id secClass in classes) {
        NSDictionary *query = @{
            (__bridge id)kSecClass : secClass,
            (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes : @YES,
        };
        CFTypeRef result = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (st != errSecSuccess || !result) {
            if (result) CFRelease(result);
            continue;
        }
        NSArray *items = (__bridge NSArray *)result;
        for (NSDictionary *attrs in items) {
            NSString *service = attrs[(__bridge id)kSecAttrService];
            NSString *account = attrs[(__bridge id)kSecAttrAccount];
            BOOL matches = NO;
            if ([service containsString:marker]) matches = YES;
            if ([account containsString:marker]) matches = YES;
            // Legacy fallback: service/account may contain cid directly
            if (cid.length) {
                if ([service containsString:cid]) matches = YES;
                if ([account containsString:cid]) matches = YES;
            } else {
                // global purge: any RP: matches
                if ([service hasPrefix:@"RP:"] || [account hasPrefix:@"RP:"]) matches = YES;
            }
            if (!matches) continue;
            NSMutableDictionary *delQuery = [NSMutableDictionary dictionary];
            delQuery[(__bridge id)kSecClass] = secClass;
            if (service) delQuery[(__bridge id)kSecAttrService] = service;
            if (account) delQuery[(__bridge id)kSecAttrAccount] = account;
            // Also include server/securityDomain if present for internet passwords
            id server = attrs[(__bridge id)kSecAttrServer];
            if (server) delQuery[(__bridge id)kSecAttrServer] = server;
            SecItemDelete((__bridge CFDictionaryRef)delQuery);
        }
        CFRelease(result);
    }
}

@end
