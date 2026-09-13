#import "HABLEProto.h"

NSString *HABLECanonicalUUID(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length > 64) return nil;
    NSString *uuid = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([uuid hasPrefix:@"0x"]) uuid = [uuid substringFromIndex:2];
    if ([uuid containsString:@"-"]) {
        if (uuid.length != 36 || [uuid characterAtIndex:8] != '-' || [uuid characterAtIndex:13] != '-' || [uuid characterAtIndex:18] != '-' || [uuid characterAtIndex:23] != '-') return nil;
        uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
    }
    if (uuid.length != 4 && uuid.length != 8 && uuid.length != 32) return nil;
    if ([uuid rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound) return nil;
    if (uuid.length == 4) uuid = [@"0000" stringByAppendingString:uuid];
    if (uuid.length == 8) uuid = [uuid stringByAppendingString:@"00001000800000805f9b34fb"];
    return [NSString stringWithFormat:@"%@-%@-%@-%@-%@", [uuid substringToIndex:8], [uuid substringWithRange:NSMakeRange(8,4)], [uuid substringWithRange:NSMakeRange(12,4)], [uuid substringWithRange:NSMakeRange(16,4)], [uuid substringFromIndex:20]];
}

BOOL HABLEReadVarint(NSData *data, NSUInteger *offset, uint64_t *value) {
    const uint8_t *bytes = data.bytes;
    NSUInteger position = *offset;
    uint64_t result = 0;
    for (NSUInteger index = 0; index < 10; index++) {
        if (position >= data.length) return NO;
        uint8_t byte = bytes[position++];
        if (index == 9 && byte > 1) return NO;
        result |= (uint64_t)(byte & 127) << (index * 7);
        if (!(byte & 128)) { *offset = position; *value = result; return YES; }
    }
    return NO;
}

NSDictionary *HABLEDecode(NSData *data) {
    if (data.length > 16384) return nil;
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    NSUInteger offset = 0, count = 0;
    while (offset < data.length) {
        uint64_t tag, value;
        if (++count > 1024 || !HABLEReadVarint(data, &offset, &tag) || !(tag >> 3) || (tag >> 3) > 0x1fffffff) return nil;
        id item;
        switch (tag & 7) {
            case 0:
                if (!HABLEReadVarint(data, &offset, &value)) return nil;
                item = @(value); break;
            case 1: case 5: {
                NSUInteger length = (tag & 7) == 1 ? 8 : 4;
                if (data.length - offset < length) return nil;
                item = [data subdataWithRange:NSMakeRange(offset, length)]; offset += length; break;
            }
            case 2:
                if (!HABLEReadVarint(data, &offset, &value) || value > data.length - offset) return nil;
                item = [data subdataWithRange:NSMakeRange(offset, (NSUInteger)value)]; offset += (NSUInteger)value; break;
            default: return nil;
        }
        NSNumber *key = @(tag >> 3);
        if (!fields[key]) fields[key] = [NSMutableArray array];
        [fields[key] addObject:item];
    }
    return fields;
}

uint64_t HABLEInteger(NSDictionary *fields, NSUInteger field) {
    id value = [fields[@(field)] lastObject];
    return [value isKindOfClass:[NSNumber class]] ? [value unsignedLongLongValue] : 0;
}
NSData *HABLEBytes(NSDictionary *fields, NSUInteger field) {
    id value = [fields[@(field)] lastObject];
    return [value isKindOfClass:[NSData class]] ? value : nil;
}
void HABLEPutVarint(NSMutableData *data, uint64_t value) {
    do { uint8_t byte = value & 127; value >>= 7; if (value) byte |= 128; [data appendBytes:&byte length:1]; } while (value);
}
void HABLEPutInteger(NSMutableData *data, NSUInteger field, uint64_t value) {
    HABLEPutVarint(data, field << 3); HABLEPutVarint(data, value);
}
void HABLEPutBytes(NSMutableData *data, NSUInteger field, NSData *value) {
    if (!value) return;
    HABLEPutVarint(data, (field << 3) | 2); HABLEPutVarint(data, value.length); [data appendData:value];
}
void HABLEPutString(NSMutableData *data, NSUInteger field, NSString *value) {
    HABLEPutBytes(data, field, [value dataUsingEncoding:NSUTF8StringEncoding]);
}
NSString *HABLEAddressString(uint64_t address) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSInteger shift = 40; shift >= 0; shift -= 8) [parts addObject:[NSString stringWithFormat:@"%02X", (unsigned)((address >> shift) & 255)]];
    return [parts componentsJoinedByString:@":"];
}
BOOL HABLEParseAddress(NSString *string, uint64_t *address) {
    NSArray *parts = [string componentsSeparatedByString:@":"];
    if (parts.count != 6) return NO;
    uint64_t result = 0;
    for (NSString *part in parts) {
        if (part.length != 2 || [part rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound) return NO;
        unsigned value = 0;
        if (![[NSScanner scannerWithString:part] scanHexInt:&value]) return NO;
        result = (result << 8) | value;
    }
    if (!result || result == 0xffffffffffffULL) return NO;
    if (address) *address = result;
    return YES;
}
