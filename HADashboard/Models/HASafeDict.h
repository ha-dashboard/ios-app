#import <Foundation/Foundation.h>

/// Safe type-checked extraction functions for NSDictionary values.
/// These handle NSNull (from JSON null), type mismatches, and nil —
/// preventing crashes from unexpected JSON types.

#pragma mark - Safe Extraction Functions

/// Returns the value for key if it is an NSString, otherwise returns fallback.
NS_INLINE NSString *HASafeDictString(NSDictionary *dict, NSString *key, NSString *fallback) {
    id val = dict[key];
    return ([val isKindOfClass:[NSString class]]) ? val : fallback;
}

/// Returns the value for key if it is an NSString, otherwise nil.
NS_INLINE NSString *HASafeDictStringOrNil(NSDictionary *dict, NSString *key) {
    id val = dict[key];
    return ([val isKindOfClass:[NSString class]]) ? val : nil;
}

/// Returns the value for key if it is an NSNumber, otherwise returns fallback.
NS_INLINE NSInteger HASafeDictInteger(NSDictionary *dict, NSString *key, NSInteger fallback) {
    id val = dict[key];
    return ([val isKindOfClass:[NSNumber class]]) ? [val integerValue] : fallback;
}

/// Returns the value for key if it is an NSNumber, otherwise nil.
NS_INLINE NSNumber *HASafeDictNumberOrNil(NSDictionary *dict, NSString *key) {
    id val = dict[key];
    return ([val isKindOfClass:[NSNumber class]]) ? val : nil;
}

/// Returns the value for key if it is an NSNumber, otherwise returns fallback.
NS_INLINE BOOL HASafeDictBool(NSDictionary *dict, NSString *key, BOOL fallback) {
    id val = dict[key];
    return ([val isKindOfClass:[NSNumber class]]) ? [val boolValue] : fallback;
}

/// Returns the value for key if it is an NSArray, otherwise nil.
NS_INLINE NSArray *HASafeDictArrayOrNil(NSDictionary *dict, NSString *key) {
    id val = dict[key];
    return ([val isKindOfClass:[NSArray class]]) ? val : nil;
}

/// Returns the value for key if it is an NSDictionary, otherwise nil.
NS_INLINE NSDictionary *HASafeDictDictOrNil(NSDictionary *dict, NSString *key) {
    id val = dict[key];
    return ([val isKindOfClass:[NSDictionary class]]) ? val : nil;
}
