#import <Foundation/Foundation.h>

// A bounded subset of protobuf wire encoding used by the ESPHome native API.
BOOL HABLEReadVarint(NSData *data, NSUInteger *offset, uint64_t *value);
NSDictionary<NSNumber *, NSArray *> *HABLEDecode(NSData *data);
uint64_t HABLEInteger(NSDictionary *fields, NSUInteger field);
NSData *HABLEBytes(NSDictionary *fields, NSUInteger field);
void HABLEPutVarint(NSMutableData *data, uint64_t value);
void HABLEPutInteger(NSMutableData *data, NSUInteger field, uint64_t value);
void HABLEPutBytes(NSMutableData *data, NSUInteger field, NSData *value);
void HABLEPutString(NSMutableData *data, NSUInteger field, NSString *value);
NSString *HABLEAddressString(uint64_t address);
BOOL HABLEParseAddress(NSString *string, uint64_t *address);
NSString *HABLECanonicalUUID(NSString *value);
