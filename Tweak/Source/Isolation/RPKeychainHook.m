#import "RPKeychainHook.h"
#import "fishhook.h"
#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *gPrefix = nil; // e.g. "RP:<cid>:" — mutable after first install (switch without relaunch edge)
static inline void RPSetPrefix(NSString *p) { gPrefix = p; }
static BOOL gHideMode = NO;
static BOOL gBound = NO; // guards rebind_symbols only

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef) = NULL;
static SecKeyRef (*orig_SecKeyCreateRandomKey)(CFDictionaryRef, CFErrorRef *) = NULL;

static NSString * const kRPMarker = @"RP:";

// ── helpers ──────────────────────────────────────────────────────────

static NSString *RPNamespaceFieldForClass(id secClass) {
    if ([(__bridge id)kSecClassGenericPassword isEqual:secClass]) return (__bridge NSString *)kSecAttrService;
    if ([(__bridge id)kSecClassInternetPassword isEqual:secClass]) return (__bridge NSString *)kSecAttrServer;
    if ([(__bridge id)kSecClassKey isEqual:secClass]) return (__bridge NSString *)kSecAttrApplicationTag;
    return nil;
}

static BOOL RPIsTagField(NSString *field) {
    return [field isEqual:(__bridge NSString *)kSecAttrApplicationTag];
}

static NSData *RPPrefixedData(NSData *orig) {
    if (!gPrefix || !orig) return orig;
    NSData *pre = [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *m = [NSMutableData dataWithCapacity:pre.length + orig.length];
    [m appendData:pre];
    [m appendData:orig];
    return m;
}

static NSData *RPStrippedData(NSData *d) {
    if (!gPrefix || !d) return d;
    NSData *pre = [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
    if (d.length >= pre.length && memcmp(d.bytes, pre.bytes, pre.length) == 0) {
        return [d subdataWithRange:NSMakeRange(pre.length, d.length - pre.length)];
    }
    return d;
}

static BOOL RPDataHasNamespace(NSData *d) {
    if (!gPrefix || !d) return NO;
    NSData *pre = [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
    return d.length >= pre.length && memcmp(d.bytes, pre.bytes, pre.length) == 0;
}

static BOOL RPValueHasMarker(id v) {
    if ([v isKindOfClass:[NSString class]]) return [(NSString*)v containsString:kRPMarker];
    if ([v isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:v encoding:NSUTF8StringEncoding];
        return s && [s containsString:kRPMarker];
    }
    return NO;
}

static BOOL RPQueryHasExplicitRef(CFDictionaryRef q) {
    if (!q) return NO;
    NSDictionary *d = (__bridge NSDictionary *)q;
    return d[(__bridge id)kSecValuePersistentRef] || d[(__bridge id)kSecValueRef] || d[(__bridge id)kSecUseItemList];
}

static void RPUpgradeAccessibilityInPlace(NSMutableDictionary *dict) {
    id v = dict[(__bridge id)kSecAttrAccessible];
    if ([v isEqual:(__bridge id)kSecAttrAccessibleWhenUnlocked]) dict[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    else if ([v isEqual:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) dict[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
}

static BOOL RPItemMatchesPrefix(NSDictionary *attrs, NSString *prefix) {
    for (NSString *k in @[ (__bridge NSString *)kSecAttrService, (__bridge NSString *)kSecAttrAccount, (__bridge NSString *)kSecAttrServer ]) {
        id v = attrs[k];
        if (v && RPValueHasMarker(v)) {
            if ([v isKindOfClass:[NSString class]] && [(NSString*)v hasPrefix:prefix]) return YES;
        }
        // check tag data
        NSData *tag = attrs[(__bridge NSString *)kSecAttrApplicationTag];
        if ([tag isKindOfClass:[NSData class]] && RPDataHasNamespace(tag)) return YES;
    }
    NSData *tag = attrs[(__bridge NSString *)kSecAttrApplicationTag];
    if ([tag isKindOfClass:[NSData class]] && RPDataHasNamespace(tag)) return YES;
    return NO;
}

static void RPStripFieldsInPlace(NSMutableDictionary *attrs) {
    for (NSString *k in @[ (__bridge NSString *)kSecAttrService, (__bridge NSString *)kSecAttrServer, (__bridge NSString *)kSecAttrAccount ]) {
        id v = attrs[k];
        if ([v isKindOfClass:[NSString class]] && [(NSString*)v hasPrefix:gPrefix]) {
            attrs[k] = [(NSString*)v substringFromIndex:gPrefix.length];
        }
    }
    NSData *tag = attrs[(__bridge NSString *)kSecAttrApplicationTag];
    if ([tag isKindOfClass:[NSData class]]) {
        NSData *stripped = RPStrippedData(tag);
        if (stripped != tag) attrs[(__bridge NSString *)kSecAttrApplicationTag] = stripped;
    }
}

// ── fishhook shims ───────────────────────────────────────────────────

static OSStatus rp_SecItemAdd(CFDictionaryRef attrs, CFTypeRef *result) {
    if (!gPrefix && !gHideMode) return orig_SecItemAdd(attrs, result);
    NSMutableDictionary *m = [(__bridge NSDictionary *)attrs mutableCopy] ?: [NSMutableDictionary dictionary];
    id secClass = m[(__bridge id)kSecClass];
    NSString *field = RPNamespaceFieldForClass(secClass);
    if (field && !gHideMode) {
        RPUpgradeAccessibilityInPlace(m);
        if (RPIsTagField(field)) {
            NSData *orig = m[field];
            if (orig) m[field] = RPPrefixedData(orig);
            else m[field] = [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
            // also handle kSecPrivateKeyAttrs / kSecPublicKeyAttrs subdicts
            for (NSString *sub in @[ (__bridge NSString *)kSecPrivateKeyAttrs, (__bridge NSString *)kSecPublicKeyAttrs ]) {
                NSMutableDictionary *sd = [m[sub] mutableCopy];
                if (sd) {
                    NSData *t = sd[(__bridge id)kSecAttrApplicationTag];
                    if (t) sd[(__bridge id)kSecAttrApplicationTag] = RPPrefixedData(t);
                    else sd[(__bridge id)kSecAttrApplicationTag] = [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
                    m[sub] = sd;
                }
            }
        } else {
            NSString *orig = m[field];
            if (orig.length) m[field] = [gPrefix stringByAppendingString:orig];
            else m[field] = gPrefix;
        }
    }
    return orig_SecItemAdd((__bridge CFDictionaryRef)m, result);
}

static OSStatus rp_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (!gPrefix && !gHideMode) return orig_SecItemCopyMatching(query, result);
    if (RPQueryHasExplicitRef(query)) return orig_SecItemCopyMatching(query, result);
    NSMutableDictionary *m = [(__bridge NSDictionary *)query mutableCopy] ?: [NSMutableDictionary dictionary];
    id secClass = m[(__bridge id)kSecClass];
    NSString *field = RPNamespaceFieldForClass(secClass);

    if (gHideMode) {
        // hide mode: passthrough but filter out RP: items
        OSStatus st = orig_SecItemCopyMatching((__bridge CFDictionaryRef)m, result);
        if (st != errSecSuccess || !result || !*result) return st;
        id res = (__bridge id)(*result);
        // If result is array, filter
        if ([res isKindOfClass:[NSArray class]]) {
            NSMutableArray *filtered = [NSMutableArray array];
            for (NSDictionary *attrs in (NSArray*)res) {
                if ([attrs isKindOfClass:[NSDictionary class]] && RPItemMatchesPrefix(attrs, kRPMarker)) continue;
                [filtered addObject:attrs];
            }
            if (filtered.count == 0) { CFRelease(*result); *result = NULL; return errSecItemNotFound; }
            CFRelease(*result);
            *result = (__bridge_retained CFTypeRef)[filtered copy];
        } else if ([res isKindOfClass:[NSDictionary class]]) {
            if (RPItemMatchesPrefix((NSDictionary*)res, kRPMarker)) { CFRelease(*result); *result = NULL; return errSecItemNotFound; }
        } else if ([res isKindOfClass:[NSData class]]) {
            if (RPDataHasNamespace((NSData*)res) || RPValueHasMarker(res)) { CFRelease(*result); *result = NULL; return errSecItemNotFound; }
        }
        return st;
    }

    // namespace mode — field-less query would scan entire keychain (Safari included) → ANR watchdog
    if (field) {
        if (RPIsTagField(field)) {
            NSData *orig = m[field];
            if (orig) m[field] = RPPrefixedData(orig);
        } else {
            NSString *orig = m[field];
            if (orig.length) m[field] = [gPrefix stringByAppendingString:orig];
            else {
                // Field-less + kSecMatchLimitAll would enumerate everything → ANR. Fail fast.
                id limit = m[(__bridge id)kSecMatchLimit];
                if ([limit isEqual:(__bridge id)kSecMatchLimitAll]) return errSecItemNotFound;
                m[field] = gPrefix;
            }
        }
    }
    OSStatus st = orig_SecItemCopyMatching((__bridge CFDictionaryRef)m, result);
    if (st == errSecSuccess && result && *result) {
        id res = (__bridge id)(*result);
        if ([res isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *mu = [(NSDictionary*)res mutableCopy];
            RPStripFieldsInPlace(mu);
            CFRelease(*result);
            *result = (__bridge_retained CFTypeRef)[mu copy];
        } else if ([res isKindOfClass:[NSArray class]]) {
            NSMutableArray *out = [NSMutableArray array];
            for (NSDictionary *attrs in (NSArray*)res) {
                NSMutableDictionary *mu = [attrs mutableCopy];
                RPStripFieldsInPlace(mu);
                [out addObject:[mu copy]];
            }
            CFRelease(*result);
            *result = (__bridge_retained CFTypeRef)[out copy];
        }
    }
    return st;
}

static OSStatus rp_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attrs) {
    if (!gPrefix && !gHideMode) return orig_SecItemUpdate(query, attrs);
    NSMutableDictionary *mq = [(__bridge NSDictionary *)query mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *ma = [(__bridge NSDictionary *)attrs mutableCopy] ?: [NSMutableDictionary dictionary];
    id secClass = mq[(__bridge id)kSecClass] ?: ma[(__bridge id)kSecClass];
    NSString *field = RPNamespaceFieldForClass(secClass);
    if (field && !gHideMode) {
        RPUpgradeAccessibilityInPlace(ma);
        if (RPIsTagField(field)) {
            NSData *orig = mq[field];
            if (orig) mq[field] = RPPrefixedData(orig);
            NSData *av = ma[field];
            if (av) ma[field] = RPPrefixedData(av);
        } else {
            NSString *orig = mq[field];
            if (orig.length) mq[field] = [gPrefix stringByAppendingString:orig];
            NSString *av = ma[field];
            if (av.length) ma[field] = [gPrefix stringByAppendingString:av];
        }
    }
    return orig_SecItemUpdate((__bridge CFDictionaryRef)mq, (__bridge CFDictionaryRef)ma);
}

static OSStatus rp_SecItemDelete(CFDictionaryRef query) {
    if (!gPrefix && !gHideMode) return orig_SecItemDelete(query);
    if (RPQueryHasExplicitRef(query)) return orig_SecItemDelete(query);
    NSMutableDictionary *m = [(__bridge NSDictionary *)query mutableCopy] ?: [NSMutableDictionary dictionary];
    id secClass = m[(__bridge id)kSecClass];
    NSString *field = RPNamespaceFieldForClass(secClass);
    if (gHideMode) {
        // hide mode: if class-wide delete, scope to real items only
        if (!field && secClass) {
            // enumerate and delete one by one only real items
            NSDictionary *q = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll, (__bridge id)kSecReturnPersistentRef: @YES };
            CFTypeRef res = NULL;
            if (orig_SecItemCopyMatching((__bridge CFDictionaryRef)q, &res) == errSecSuccess && res) {
                for (id ref in (__bridge NSArray *)res) {
                    NSDictionary *dq = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecValuePersistentRef: ref };
                    // check if item is RP: — skip
                    // we need attrs to decide; fetch
                    NSDictionary *aq = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecValuePersistentRef: ref, (__bridge id)kSecReturnAttributes: @YES };
                    CFTypeRef ar = NULL;
                    if (orig_SecItemCopyMatching((__bridge CFDictionaryRef)aq, &ar) == errSecSuccess && ar) {
                        NSDictionary *attrs = (__bridge NSDictionary *)ar;
                        BOOL isRP = RPItemMatchesPrefix(attrs, kRPMarker);
                        CFRelease(ar);
                        if (!isRP) orig_SecItemDelete((__bridge CFDictionaryRef)dq);
                    }
                }
                CFRelease(res);
            }
            return errSecSuccess;
        }
        return orig_SecItemDelete((__bridge CFDictionaryRef)m);
    }
    if (field) {
        if (RPIsTagField(field)) {
            NSData *orig = m[field];
            if (orig) m[field] = RPPrefixedData(orig);
            else m[field] = [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            NSString *orig = m[field];
            if (orig.length) m[field] = [gPrefix stringByAppendingString:orig];
            else m[field] = gPrefix;
        }
    }
    return orig_SecItemDelete((__bridge CFDictionaryRef)m);
}

static SecKeyRef rp_SecKeyCreateRandomKey(CFDictionaryRef params, CFErrorRef *err) {
    if (!gPrefix || gHideMode) return orig_SecKeyCreateRandomKey(params, err);
    NSMutableDictionary *m = [(__bridge NSDictionary *)params mutableCopy] ?: [NSMutableDictionary dictionary];
    // tag lives in kSecPrivateKeyAttrs / kSecPublicKeyAttrs
    for (NSString *sub in @[ (__bridge NSString *)kSecPrivateKeyAttrs, (__bridge NSString *)kSecPublicKeyAttrs ]) {
        NSMutableDictionary *sd = [m[sub] mutableCopy];
        if (sd) {
            NSData *t = sd[(__bridge id)kSecAttrApplicationTag];
            if (t) sd[(__bridge id)kSecAttrApplicationTag] = RPPrefixedData(t);
            else sd[(__bridge id)kSecAttrApplicationTag] = [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
            m[sub] = sd;
        }
    }
    // also top-level tag
    NSData *top = m[(__bridge id)kSecAttrApplicationTag];
    if (top) m[(__bridge id)kSecAttrApplicationTag] = RPPrefixedData(top);
    return orig_SecKeyCreateRandomKey((__bridge CFDictionaryRef)m, err);
}

// ── public ───────────────────────────────────────────────────────────

@implementation RPKeychainHook

+ (BOOL)installWithPrefix:(NSString *)prefix {
    // Allow prefix update without rebind — critical for switch without relaunch edge case
    if (gBound) { RPSetPrefix([prefix copy]); gHideMode = NO; return YES; }
    RPSetPrefix([prefix copy]);
    gHideMode = NO;
    struct rebinding rebs[] = {
        {"SecItemAdd", rp_SecItemAdd, (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", rp_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate", rp_SecItemUpdate, (void **)&orig_SecItemUpdate},
        {"SecItemDelete", rp_SecItemDelete, (void **)&orig_SecItemDelete},
        {"SecKeyCreateRandomKey", rp_SecKeyCreateRandomKey, (void **)&orig_SecKeyCreateRandomKey},
    };
    rebind_symbols(rebs, sizeof(rebs)/sizeof(rebs[0]));
    gBound = YES;
    return YES;
}

+ (BOOL)installDefaultHideMode {
    if (gBound) { RPSetPrefix(nil); gHideMode = YES; return YES; }
    RPSetPrefix(nil);
    gHideMode = YES;
    struct rebinding rebs[] = {
        {"SecItemAdd", rp_SecItemAdd, (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", rp_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate", rp_SecItemUpdate, (void **)&orig_SecItemUpdate},
        {"SecItemDelete", rp_SecItemDelete, (void **)&orig_SecItemDelete},
        {"SecKeyCreateRandomKey", rp_SecKeyCreateRandomKey, (void **)&orig_SecKeyCreateRandomKey},
    };
    rebind_symbols(rebs, sizeof(rebs)/sizeof(rebs[0]));
    gBound = YES;
    return YES;
}

+ (void)purgeItemsWithPrefix:(NSString *)prefix {
    if (!prefix.length) return;
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword, (__bridge id)kSecClassInternetPassword, (__bridge id)kSecClassKey ];
    for (id secClass in classes) {
        NSDictionary *q = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll, (__bridge id)kSecReturnAttributes: @YES, (__bridge id)kSecReturnPersistentRef: @YES };
        CFTypeRef res = NULL;
        // use RAW orig to bypass our hook filtering
        OSStatus (*rawCopy)(CFDictionaryRef, CFTypeRef *) = orig_SecItemCopyMatching ?: SecItemCopyMatching;
        if (rawCopy((__bridge CFDictionaryRef)q, &res) != errSecSuccess || !res) continue;
        for (NSDictionary *item in (__bridge NSArray *)res) {
            NSDictionary *attrs = item;
            // item may be NSDictionary with persistent ref inside?
            // When both ReturnAttributes and ReturnPersistentRef, result is array of dicts each with attributes + persistent ref
            // Simpler: check service/server/tag
            BOOL matches = RPItemMatchesPrefix(attrs, prefix);
            // also check if persistent ref item matches by fetching attrs via persistent ref?
            if (!matches) continue;
            id ref = attrs[(__bridge id)kSecValuePersistentRef];
            if (!ref) continue;
            NSDictionary *dq = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecValuePersistentRef: ref };
            OSStatus (*rawDel)(CFDictionaryRef) = orig_SecItemDelete ?: SecItemDelete;
            rawDel((__bridge CFDictionaryRef)dq);
        }
        CFRelease(res);
    }
}

+ (NSUInteger)countItemsWithPrefix:(NSString *)prefix {
    if (!prefix.length) return 0;
    NSUInteger n = 0;
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword, (__bridge id)kSecClassInternetPassword ];
    for (id secClass in classes) {
        NSDictionary *q = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll, (__bridge id)kSecReturnAttributes: @YES };
        CFTypeRef res = NULL;
        OSStatus (*rawCopy)(CFDictionaryRef, CFTypeRef *) = orig_SecItemCopyMatching ?: SecItemCopyMatching;
        if (rawCopy((__bridge CFDictionaryRef)q, &res) != errSecSuccess || !res) continue;
        for (NSDictionary *attrs in (__bridge NSArray *)res) {
            if (RPItemMatchesPrefix(attrs, prefix)) n++;
        }
        CFRelease(res);
    }
    return n;
}

+ (void)purgeRealPasswordItems {
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword, (__bridge id)kSecClassInternetPassword ];
    for (id secClass in classes) {
        NSDictionary *q = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll, (__bridge id)kSecReturnAttributes: @YES, (__bridge id)kSecReturnPersistentRef: @YES };
        CFTypeRef res = NULL;
        OSStatus (*rawCopy)(CFDictionaryRef, CFTypeRef *) = orig_SecItemCopyMatching ?: SecItemCopyMatching;
        if (rawCopy((__bridge CFDictionaryRef)q, &res) != errSecSuccess || !res) continue;
        for (NSDictionary *item in (__bridge NSArray *)res) {
            if (RPItemMatchesPrefix(item, kRPMarker)) continue;
            id ref = item[(__bridge id)kSecValuePersistentRef];
            if (!ref) continue;
            NSDictionary *dq = @{ (__bridge id)kSecClass: secClass, (__bridge id)kSecValuePersistentRef: ref };
            OSStatus (*rawDel)(CFDictionaryRef) = orig_SecItemDelete ?: SecItemDelete;
            rawDel((__bridge CFDictionaryRef)dq);
        }
        CFRelease(res);
    }
}

@end
