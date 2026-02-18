#import "HAKeychainHelper.h"
#import <Security/Security.h>

static NSString *const kHAKeychainService = @"com.hadashboard.app.keychain";

@implementation HAKeychainHelper

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key {
    if (!value || !key) {
        return NO;
    }

    // Delete any existing item first
    [self removeItemForKey:key];

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kHAKeychainService,
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecValueData:   data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
    };

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

+ (NSString *)stringForKey:(NSString *)key {
    if (!key) {
        return nil;
    }

    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kHAKeychainService,
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecReturnData:  @YES,
        (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitOne,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status != errSecSuccess || !result) {
        return nil;
    }

    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)removeItemForKey:(NSString *)key {
    if (!key) {
        return NO;
    }

    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kHAKeychainService,
        (__bridge id)kSecAttrAccount: key,
    };

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

@end
