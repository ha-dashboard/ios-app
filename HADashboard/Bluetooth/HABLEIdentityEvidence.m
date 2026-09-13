#import "HABLEIdentityEvidence.h"
#import "HABLEProto.h"
#import <math.h>
#import <float.h>
#import <CommonCrypto/CommonDigest.h>

static const NSTimeInterval HABLEEvidenceWindow = 900;
static const NSUInteger HABLEEvidenceEvents = 256;
static NSString *HABLEPayloadToken(NSString *channel, NSData *bytes) {
    if (bytes.length < 4 || bytes.length > 2048) return nil;
    return [NSString stringWithFormat:@"%@%lu:%@",channel,(unsigned long)bytes.length,[bytes base64EncodedStringWithOptions:0]];
}
static void HABLEAddToken(NSMutableArray *tokens, NSString *channel, NSData *bytes) {
    NSString *token = HABLEPayloadToken(channel, bytes);
    if (token && ![tokens containsObject:token]) [tokens addObject:token];
}
static NSString *HABLELittleEndianUUID(const uint8_t *bytes, NSUInteger length) {
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = length; i > 0; i--) [hex appendFormat:@"%02X", bytes[i - 1]];
    return HABLECanonicalUUID(hex);
}
@interface HABLEIdentityEvidence ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *locals;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *remotes;
@end
// Home Assistant diagnostics encode bytes as a Python repr. Decode only
// the bounded literal grammar; never evaluate diagnostic text as code.
static int HABLEDiagnosticHex(unichar c) {
    if(c>='0' && c<='9')return c-'0';if(c>='a' && c<='f')return c-'a'+10;if(c>='A' && c<='F')return c-'A'+10;return -1;
}
static NSData *HABLEDiagnosticBytes(id value) {
    if(![value isKindOfClass:NSDictionary.class] || ![value[@"__type"] isEqual:@"<class 'bytes'>"])return nil;
    NSString *literal=value[@"repr"];if(![literal isKindOfClass:NSString.class] || literal.length<3 || literal.length>16384 || [literal characterAtIndex:0]!='b')return nil;
    unichar quote=[literal characterAtIndex:1];if((quote!='\'' && quote!='"') || [literal characterAtIndex:literal.length-1]!=quote)return nil;
    NSMutableData *data=NSMutableData.data;
    for(NSUInteger i=2;i<literal.length-1;i++) {
        unichar c=[literal characterAtIndex:i];
        if(c=='\\') {
            if(++i>=literal.length-1)return nil;c=[literal characterAtIndex:i];
            if(c=='x') {
                if(i+2>=literal.length-1)return nil;int high=HABLEDiagnosticHex([literal characterAtIndex:++i]),low=HABLEDiagnosticHex([literal characterAtIndex:++i]);if(high<0 || low<0)return nil;c=(high<<4)|low;
            } else if(c=='n')c='\n';else if(c=='r')c='\r';else if(c=='t')c='\t';
            else if(c!='\\' && c!='\'' && c!='"')return nil;
        } else if(c<32 || c>126 || c==quote)return nil;
        uint8_t byte=(uint8_t)c;[data appendBytes:&byte length:1];if(data.length>4096)return nil;
    }
    return data;
}
static NSString *HABLEStandardIdentifierFormat(NSString *path) {
    NSArray *parts=[path componentsSeparatedByString:@"/"];if(parts.count!=3 || ![parts[0] isEqual:@"s"])return nil;
    NSMutableArray *uuids=NSMutableArray.array;
    for(NSUInteger i=1;i<3;i++) {
        NSArray *attribute=[parts[i] componentsSeparatedByString:@"#"];
        if(attribute.count!=2 || ![attribute[1] length] || [attribute[1] rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound)return nil;
        NSString *uuid=HABLECanonicalUUID(attribute[0]);if(!uuid)return nil;[uuids addObject:uuid];
    }
    if(![uuids[0] isEqual:HABLECanonicalUUID(@"180A")])return nil;
    if([uuids[1] isEqual:HABLECanonicalUUID(@"2A25")])return @"gatt_serial";
    if([uuids[1] isEqual:HABLECanonicalUUID(@"2A23")])return @"gatt_system_id";
    return nil;
}
@implementation HABLEIdentityEvidence
+ (NSArray *)nativeObservationsFromDiagnostics:(id)diagnostics requestedAt:(NSTimeInterval)time {
    if(!isfinite(time) || ![diagnostics isKindOfClass:NSDictionary.class])return @[];
    id data=diagnostics[@"data"],manager=[data isKindOfClass:NSDictionary.class] ? data[@"manager"] : nil;
    id scanners=[manager isKindOfClass:NSDictionary.class] ? manager[@"scanners"] : nil;
    if(![scanners isKindOfClass:NSArray.class] || [scanners count]>64)return @[];
    NSMutableArray *result=NSMutableArray.array;
    for(id scanner in scanners) {
        if(![scanner isKindOfClass:NSDictionary.class])continue;
        NSString *source=scanner[@"source"];uint64_t addressValue;
        if(![source isKindOfClass:NSString.class] || !HABLEParseAddress(source,&addressValue) || ![scanner[@"monotonic_time"] isKindOfClass:NSNumber.class])continue;
        double monotonic=[scanner[@"monotonic_time"] doubleValue];if(!isfinite(monotonic))continue;
        id devices=scanner[@"discovered_devices_and_advertisement_data"],timestamps=scanner[@"discovered_device_timestamps"],raw=scanner[@"raw_advertisement_data"];
        if(![devices isKindOfClass:NSArray.class] || [devices count]>2048 || ![timestamps isKindOfClass:NSDictionary.class] || ![raw isKindOfClass:NSDictionary.class])continue;
        for(id device in devices) {
            if(![device isKindOfClass:NSDictionary.class])continue;NSString *address=device[@"address"];
            if(![address isKindOfClass:NSString.class] || !HABLEParseAddress(address,&addressValue) || ![timestamps[address] isKindOfClass:NSNumber.class])continue;
            double age=monotonic-[timestamps[address] doubleValue];if(!isfinite(age) || age<0 || age>120)continue;
            NSData *bytes=HABLEDiagnosticBytes(raw[address]);if(!bytes.length)continue;
            id advertisement=device[@"advertisement_data"];if(![advertisement isKindOfClass:NSArray.class] || [advertisement count]<4 || ![advertisement[3] isKindOfClass:NSArray.class] || [advertisement[3] count]>64)continue;
            NSString *name=[device[@"name"] isKindOfClass:NSString.class] ? device[@"name"] : @"";if(name.length>256)continue;
            NSMutableString *hex=NSMutableString.string;const uint8_t *b=bytes.bytes;for(NSUInteger i=0;i<bytes.length;i++)[hex appendFormat:@"%02x",b[i]];
            [result addObject:@{@"address":address.uppercaseString,@"source":source.uppercaseString,@"name":name,@"time":@(time-age),@"raw":hex,@"service_uuids":[self canonicalServices:advertisement[3]]}];
            if(result.count>=512)return result;
        }
    }
    return result;
}

+ (NSDictionary *)fingerprintsForValue:(NSData *)data path:(NSString *)path {
    if(!data.length || data.length>512 || !path.length)return @{};
    NSDictionary *(^fingerprint)(NSData *,NSString *)=^NSDictionary *(NSData *bytes,NSString *kind) {
        uint8_t hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,hash);NSMutableString *hex=NSMutableString.string;
        for(NSUInteger i=0;i<sizeof(hash);i++)[hex appendFormat:@"%02x",hash[i]];
        return @{@"sha256":hex,@"length":@(bytes.length),@"kind":kind};
    };
    NSString *standard=HABLEStandardIdentifierFormat(path);
    if(standard) {
        NSData *normalized=data;
        if([standard isEqual:@"gatt_serial"]) {
            NSString *serial=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if(serial.length<6 || [serial rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound || [@[@"unknown",@"default",@"not available",@"serial number",@"serialnumber"] containsObject:serial.lowercaseString])return @{};
            BOOL varies=NO;for(NSUInteger i=1;i<serial.length;i++)if([serial characterAtIndex:i]!=[serial characterAtIndex:0])varies=YES;
            normalized=[serial dataUsingEncoding:NSUTF8StringEncoding];if(!varies || normalized.length>128)return @{};
        } else {
            if(data.length!=8)return @{};BOOL allZero=YES,allFF=YES;const uint8_t *bytes=data.bytes;
            for(NSUInteger i=0;i<data.length;i++){allZero=allZero && bytes[i]==0;allFF=allFF && bytes[i]==255;}
            if(allZero || allFF)return @{};
        }
        NSMutableDictionary *value=[fingerprint(normalized,@"standard_identifier") mutableCopy];value[@"format"]=standard;return @{path:value};
    }
    id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![object isKindOfClass:NSDictionary.class] && ![object isKindOfClass:NSArray.class])return @{path:fingerprint(data,@"opaque")};
    NSSet *sensitive=[NSSet setWithArray:@[@"password",@"passwd",@"pwd",@"psk",@"secret",@"token",@"accesstoken",@"refreshtoken",@"apikey",@"privatekey",@"key",@"credential",@"credentials",@"authorization",@"auth",@"pin",@"pairingcode"]];
    NSMutableDictionary *result=NSMutableDictionary.dictionary;
    NSMutableArray *queue=[NSMutableArray arrayWithObject:@{@"value":object,@"path":[path stringByAppendingString:@"/json"],@"depth":@0}];
    while(queue.count && result.count<32) {
        NSDictionary *node=queue.firstObject;[queue removeObjectAtIndex:0];id value=node[@"value"];NSString *key=node[@"path"];NSUInteger depth=[node[@"depth"] unsignedIntegerValue];
        if([value isKindOfClass:NSDictionary.class] && depth<4) {
            for(NSString *field in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
                NSString *normalized=[[[field lowercaseString] componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
                BOOL privateField=[sensitive containsObject:normalized];
                for(NSString *fragment in @[@"password",@"secret",@"token",@"credential",@"authorization",@"privatekey",@"apikey",@"pairingcode",@"passcode"])if([normalized rangeOfString:fragment].location!=NSNotFound)privateField=YES;
                if(privateField)continue;
                NSString *escaped=[[field stringByReplacingOccurrencesOfString:@"~" withString:@"~0"] stringByReplacingOccurrencesOfString:@"/" withString:@"~1"];
                if(queue.count<64)[queue addObject:@{@"value":value[field],@"path":[key stringByAppendingFormat:@"/%@",escaped],@"depth":@(depth+1)}];
            }
        } else if([value isKindOfClass:NSArray.class] && depth<4) {
            for(NSUInteger i=0;i<MIN(16,[value count]) && queue.count<64;i++)[queue addObject:@{@"value":value[i],@"path":[key stringByAppendingFormat:@"/%lu",(unsigned long)i],@"depth":@(depth+1)}];
        } else if(([value isKindOfClass:NSString.class] && [value length]) || [value isKindOfClass:NSNumber.class]) {
            NSString *format=@"scalar";id normalized=value;
            if([value isKindOfClass:NSString.class]) {
                uint64_t address;NSUUID *uuid=[[NSUUID alloc] initWithUUIDString:value];
                if(HABLEParseAddress(value,&address)){format=@"mac";normalized=HABLEAddressString(address);}
                else if(uuid && ![uuid.UUIDString isEqual:@"00000000-0000-0000-0000-000000000000"]){format=@"uuid";normalized=uuid.UUIDString;}
            }
            NSData *encoded=[NSJSONSerialization dataWithJSONObject:@[normalized] options:0 error:nil];
            NSMutableDictionary *entry=[fingerprint(encoded,@"json_scalar") mutableCopy];entry[@"format"]=format;result[key]=entry;
        }
    }
    return result;
}
+ (BOOL)isIdentifierFingerprint:(NSDictionary *)value path:(NSString *)path {
    if(![value isKindOfClass:NSDictionary.class] || ![value[@"stable_across_sessions"] isKindOfClass:NSNumber.class] || ![value[@"varying"] isKindOfClass:NSNumber.class] || ![value[@"sessions"] isKindOfClass:NSNumber.class] || ![value[@"stable_across_sessions"] boolValue] || [value[@"varying"] boolValue] || [value[@"sessions"] unsignedIntegerValue]<2 || ![@[@"mac",@"uuid",@"gatt_serial",@"gatt_system_id"] containsObject:value[@"format"]])return NO;
    if([@[@"gatt_serial",@"gatt_system_id"] containsObject:value[@"format"]]) {
        if(![HABLEStandardIdentifierFormat(path) isEqual:value[@"format"]] || ![value[@"length"] isKindOfClass:NSNumber.class])return NO;
        NSUInteger length=[value[@"length"] unsignedIntegerValue];return [value[@"format"] isEqual:@"gatt_serial"] ? length>=6 && length<=128 : length==8;
    }
    NSUInteger expected=[value[@"format"] isEqual:@"mac"] ? 21 : 40;
    if(![value[@"length"] isKindOfClass:NSNumber.class] || [value[@"length"] unsignedIntegerValue]!=expected)return NO;
    NSRange json=[path rangeOfString:@"/json/"];if(json.location==NSNotFound)return NO;
    NSString *fields=[[path substringFromIndex:json.location+json.length] lowercaseString];
    for(NSString *part in [fields componentsSeparatedByString:@"/"]) {
        NSString *key=[[part componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
        if([@[@"bssid",@"ssid",@"gateway",@"router",@"server",@"client",@"peer",@"remote",@"model",@"firmware",@"version",@"service",@"serviceuuid",@"serviceid",@"networkid",@"groupid",@"request",@"requestid",@"session",@"sessionid",@"nonce"] containsObject:key])return NO;
        for(NSString *context in @[@"bssid",@"gateway",@"router",@"server",@"client",@"peer",@"remote",@"model",@"firmware",@"version",@"service",@"vendor",@"manufacturer",@"product",@"networkid",@"request",@"session",@"nonce",@"token",@"secret",@"password",@"household",@"account",@"group"])if([key rangeOfString:context].location!=NSNotFound)return NO;
    }
    return YES;
}
+ (BOOL)identifierFingerprints:(NSDictionary *)a conflictWith:(NSDictionary *)b {
    for(NSString *path in a)if([self isIdentifierFingerprint:a[path] path:path] && [self isIdentifierFingerprint:b[path] path:path] && ![a[path][@"sha256"] isEqual:b[path][@"sha256"]])return YES;
    return NO;
}
+ (NSDictionary *)mergeFingerprintReads:(NSDictionary *)reads previous:(NSDictionary *)previous session:(NSString *)session atTime:(NSTimeInterval)time {
    NSMutableDictionary *result=[previous mutableCopy] ?: NSMutableDictionary.dictionary;
    for(NSString *path in reads) {
        NSDictionary *read=reads[path],*old=previous[path];
        if(![read[@"sha256"] isKindOfClass:NSString.class] || ![read[@"length"] unsignedIntegerValue])continue;
        if([old[@"session"] isEqual:session])continue;
        BOOL same=[old[@"sha256"] isEqual:read[@"sha256"]] && [old[@"length"] isEqual:read[@"length"]];
        NSUInteger sessions=old ? MIN(255,[old[@"sessions"] unsignedIntegerValue]+1) : 1;
        BOOL varying=[old[@"varying"] boolValue] || (old && !same);
        NSMutableDictionary *value=[read mutableCopy];value[@"session"]=session;value[@"sessions"]=@(sessions);value[@"varying"]=@(varying);value[@"stable_across_sessions"]=@(same && sessions>=2 && !varying);value[@"last_seen"]=@(time);
        if(result.count<64 || result[path])result[path]=value;
    }
    return result;
}
- (instancetype)init { if ((self = [super init])) { _locals = [NSMutableDictionary dictionary]; _remotes = [NSMutableDictionary dictionary]; } return self; }
+ (NSArray *)canonicalServices:(NSArray *)values {
    NSMutableSet *services = [NSMutableSet set];
    if (![values isKindOfClass:NSArray.class]) return @[];
    for (id value in values) if ([value isKindOfClass:[NSString class]]) { NSString *uuid = HABLECanonicalUUID(value); if (uuid) [services addObject:uuid]; }
    return [services.allObjects sortedArrayUsingSelector:@selector(compare:)];
}
+ (NSArray *)tokensForObservation:(NSDictionary *)observation {
    NSMutableArray *tokens = [NSMutableArray array];
    NSString *manufacturer = observation[@"manufacturer_data"];
    if ([manufacturer isKindOfClass:[NSString class]]) HABLEAddToken(tokens, @"m:", [[NSData alloc] initWithBase64EncodedString:manufacturer options:0]);
    NSDictionary *services = observation[@"service_data"];
    if ([services isKindOfClass:[NSDictionary class]]) for (NSString *uuid in services) {
        NSString *canonical = HABLECanonicalUUID(uuid); id encoded = services[uuid];
        if (canonical && [encoded isKindOfClass:[NSString class]]) HABLEAddToken(tokens, [NSString stringWithFormat:@"s:%@:", canonical], [[NSData alloc] initWithBase64EncodedString:encoded options:0]);
    }
    return tokens;
}
+ (NSArray *)tokensForRawAdvertisement:(NSData *)raw {
    if (!raw.length || raw.length > 4096) return @[];
    NSMutableArray *tokens = [NSMutableArray array]; const uint8_t *bytes = raw.bytes;
    for (NSUInteger offset = 0; offset < raw.length;) {
        NSUInteger length = bytes[offset++]; if (!length) break;
        if (length > raw.length - offset) return @[]; // Truncated frame is not evidence.
        uint8_t type = bytes[offset]; NSUInteger count = length - 1; const uint8_t *data = bytes + offset + 1;
        if (type == 0xff) HABLEAddToken(tokens, @"m:", [NSData dataWithBytes:data length:count]);
        NSUInteger uuidBytes = type == 0x16 ? 2 : type == 0x20 ? 4 : type == 0x21 ? 16 : 0;
        if (uuidBytes && count >= uuidBytes) {
            NSString *uuid = HABLELittleEndianUUID(data, uuidBytes);
            if (uuid) HABLEAddToken(tokens, [NSString stringWithFormat:@"s:%@:", uuid], [NSData dataWithBytes:data + uuidBytes length:count - uuidBytes]);
        }
        offset += length;
    }
    return tokens;
}
// Compare complete reference fields, never an arbitrary common prefix.
// Used only for reversible passive associations, not verified identity proof.
+ (BOOL)tokens:(NSArray *)local extendCompleteTokens:(NSArray *)remote {
    if(!local.count || local.count!=remote.count)return NO;
    NSDictionary *(^parts)(NSString *)=^NSDictionary *(NSString *token) {
        if(![token isKindOfClass:NSString.class])return nil;
        NSRange separator=[token rangeOfString:@":" options:NSBackwardsSearch];if(separator.location==NSNotFound)return nil;
        NSString *prefix=[token substringToIndex:separator.location];NSRange lengthSeparator=[prefix rangeOfString:@":" options:NSBackwardsSearch];if(lengthSeparator.location==NSNotFound)return nil;
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[token substringFromIndex:separator.location+1] options:0];
        return bytes.length ? @{@"channel":[prefix substringToIndex:lengthSeparator.location+1],@"bytes":bytes} : nil;
    };
    NSMutableSet *used=NSMutableSet.set;
    for(NSString *token in remote) {
        NSDictionary *reference=parts(token);if(!reference)return NO;NSUInteger matches=0;NSString *selected=nil;
        for(NSString *candidate in local) {
            NSDictionary *value=parts(candidate);NSData *a=value[@"bytes"],*b=reference[@"bytes"];
            if([value[@"channel"] isEqual:reference[@"channel"]] && a.length>=b.length && [[a subdataWithRange:NSMakeRange(0,b.length)] isEqual:b]){matches++;selected=candidate;}
        }
        if(matches!=1 || [used containsObject:selected])return NO;[used addObject:selected];
    }
    return used.count==local.count;
}
 + (BOOL)tokens:(NSArray *)local agreeWith:(NSArray *)remote {
    // Length describes a value, not its channel. Otherwise a conflicting
    // shorter/longer value disappears when another channel happens to agree.
    NSMutableDictionary *left=NSMutableDictionary.dictionary,*right=NSMutableDictionary.dictionary;
    for(NSUInteger side=0;side<2;side++) {
        NSMutableDictionary *channels=side ? right : left;
        for(id token in (side ? remote : local)) {
            if(![token isKindOfClass:NSString.class])return NO;
            NSRange valueSeparator=[token rangeOfString:@":" options:NSBackwardsSearch];
            if(valueSeparator.location==NSNotFound)return NO;
            NSString *prefix=[token substringToIndex:valueSeparator.location];
            NSRange lengthSeparator=[prefix rangeOfString:@":" options:NSBackwardsSearch];
            if(lengthSeparator.location==NSNotFound)return NO;
            NSString *channel=[prefix substringToIndex:lengthSeparator.location+1];
            NSMutableSet *values=channels[channel];if(!values){values=NSMutableSet.set;channels[channel]=values;}
            [values addObject:token];
        }
    }
    BOOL common=NO;
    for(NSString *channel in left) {
        if(!right[channel])continue;
        if(![left[channel] isEqual:right[channel]])return NO;
        common=YES;
    }
    return common;
}
+ (BOOL)tokens:(NSArray<NSString *> *)local corroborateAddress:(NSString *)address withTokens:(NSArray<NSString *> *)remote {
    NSDictionary *(^parts)(NSString *)=^NSDictionary *(NSString *token) {
        NSRange last=[token rangeOfString:@":" options:NSBackwardsSearch];if(last.location==NSNotFound)return nil;
        NSString *prefix=[token substringToIndex:last.location];NSRange lengthSeparator=[prefix rangeOfString:@":" options:NSBackwardsSearch];
        if(lengthSeparator.location==NSNotFound)return nil;
        NSData *data=[[NSData alloc] initWithBase64EncodedString:[token substringFromIndex:last.location+1] options:0];
        return data ? @{@"channel":[prefix substringToIndex:lengthSeparator.location+1],@"bytes":data} : nil;
    };
    BOOL addressed=NO;
    for(NSString *token in local) {
        NSDictionary *a=parts(token);if(!a)continue;BOOL comparable=NO,agrees=NO;
        for(NSString *other in remote) {
            NSDictionary *b=parts(other);if(![a[@"channel"] isEqual:b[@"channel"]])continue;comparable=YES;
            NSData *left=a[@"bytes"],*right=b[@"bytes"],*shorter=left.length<=right.length ? left : right,*longer=left.length<=right.length ? right : left;
            BOOL contains=shorter.length>=8 && [self observation:@{@"manufacturer_data":[shorter base64EncodedStringWithOptions:0]} containsAddress:address];
            BOOL prefix=shorter.length && [[longer subdataWithRange:NSMakeRange(0,shorter.length)] isEqual:shorter];
            if([left isEqual:right] || (contains && shorter.length>=10 && prefix)){agrees=YES;if(contains)addressed=YES;}
        }
        if(comparable && !agrees)return NO;
    }
    return addressed;
}
 + (BOOL)observation:(NSDictionary *)observation containsUUID:(NSString *)uuid {
    NSString *hex=[HABLECanonicalUUID(uuid) stringByReplacingOccurrencesOfString:@"-" withString:@""];if(hex.length!=32)return NO;
    uint8_t bytes[16],reverse[16];for(NSUInteger i=0;i<16;i++){unsigned n=0;[[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i*2,2)]]scanHexInt:&n];bytes[i]=n;reverse[15-i]=n;}
    for(NSString *token in [self tokensForObservation:observation]) {
        NSData *data=[[NSData alloc]initWithBase64EncodedString:[token substringFromIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location+1] options:0];
        if(data.length>=16 && ([data rangeOfData:[NSData dataWithBytes:bytes length:16] options:0 range:NSMakeRange(0,data.length)].location!=NSNotFound || [data rangeOfData:[NSData dataWithBytes:reverse length:16] options:0 range:NSMakeRange(0,data.length)].location!=NSNotFound))return YES;
    }return NO;
}
+ (BOOL)observation:(NSDictionary *)observation containsAddress:(NSString *)address {
    uint64_t value; if (!HABLEParseAddress(address, &value)) return NO;
    uint8_t forward[6], reverse[6];
    for (NSUInteger i = 0; i < 6; i++) { forward[i] = (uint8_t)(value >> ((5-i)*8)); reverse[5-i] = forward[i]; }
    NSMutableArray *payloads = [NSMutableArray array];
    for (NSString *token in [self tokensForObservation:observation]) {
        NSString *encoded = [token substringFromIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location + 1];
        NSData *payload = [[NSData alloc] initWithBase64EncodedString:encoded options:0]; if (payload) [payloads addObject:payload];
    }
    for (NSString *field in @[@"system_id", @"serial_number"]) {
        id text = observation[field]; if (![text isKindOfClass:NSString.class]) continue;
        NSString *hex = [[[text stringByReplacingOccurrencesOfString:@":" withString:@""] stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
        if ((hex.length != 12 && hex.length != 16) || [hex rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet]].location != NSNotFound) continue;
        NSMutableData *data = [NSMutableData data];
        for (NSUInteger i=0;i<hex.length;i+=2) { unsigned n=0; [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n]; uint8_t byte=n; [data appendBytes:&byte length:1]; }
        [payloads addObject:data];
        const uint8_t *bytes=data.bytes;
        if (data.length==8 && bytes[3]==0xff && bytes[4]==0xfe) { NSMutableData *eui=[NSMutableData dataWithBytes:bytes length:3]; [eui appendBytes:bytes+5 length:3]; [payloads addObject:eui]; }
    }
    for (NSData *payload in payloads) if (payload.length >= 6 && ([payload rangeOfData:[NSData dataWithBytes:forward length:6] options:0 range:NSMakeRange(0,payload.length)].location != NSNotFound ||
        [payload rangeOfData:[NSData dataWithBytes:reverse length:6] options:0 range:NSMakeRange(0,payload.length)].location != NSNotFound)) return YES;
    return NO;
}
- (void)append:(NSArray *)tokens key:(NSString *)key to:(NSMutableDictionary *)storage source:(NSString *)source atTime:(NSTimeInterval)time {
    if (!tokens.count || !key.length || !isfinite(time)) return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;if(time<now-HABLEEvidenceWindow || time>now+5)return;
    NSMutableArray *events=storage[key];
    if(!events) {
        // Rotating addresses must not permanently fill the observation window.
        if(storage.count>=256) {
            NSString *oldest=nil;NSTimeInterval oldestTime=DBL_MAX;
            for(NSString *other in storage) {
                NSTimeInterval last=0;for(NSDictionary *event in storage[other])last=MAX(last,[event[@"last_seen"] doubleValue]);
                if(last<oldestTime){oldest=other;oldestTime=last;}
            }
            // An out-of-order snapshot must not evict more recent evidence.
            if(time<=oldestTime)return;
            [storage removeObjectForKey:oldest];
        }
        events=NSMutableArray.array;storage[key]=events;
    }
    NSIndexSet *expired=[events indexesOfObjectsPassingTest:^BOOL(NSDictionary *event,NSUInteger index,BOOL *stop){return [event[@"last_seen"] doubleValue]<now-HABLEEvidenceWindow;}];[events removeObjectsAtIndexes:expired];
    for(NSString *token in tokens) {
        NSString *channel=[token substringToIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location+1];
        NSInteger latest=-1;
        for(NSUInteger i=0;i<events.count;i++)if([events[i][@"channel"] isEqual:channel] && [events[i][@"source"] isEqual:source ?: @""])latest=i;
        if(latest>=0 && [events[latest][@"token"] isEqual:token] && time>=[events[latest][@"time"] doubleValue]) {
            NSMutableDictionary *updated=[events[latest] mutableCopy];updated[@"last_seen"]=@(MAX(time,[updated[@"last_seen"] doubleValue]));events[latest]=updated;continue;
        }
        BOOL duplicate=NO;
        for(NSDictionary *old in events)if([old[@"token"] isEqual:token] && [old[@"source"] isEqual:source ?: @""] && time>=[old[@"time"] doubleValue]-1 && time<=[old[@"last_seen"] doubleValue]+1)duplicate=YES;
        if(!duplicate)[events addObject:@{@"time":@(time),@"last_seen":@(time),@"token":token,@"tokens":@[token],@"channel":channel,@"source":source ?: @""}];
    }
    [events sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"time"] compare:b[@"time"]];}];
    while(events.count>HABLEEvidenceEvents)[events removeObjectAtIndex:0];
}
- (void)recordLocal:(NSDictionary *)observation identifier:(NSString *)identifier atTime:(NSTimeInterval)time {
    [self append:[[self class] tokensForObservation:observation] key:identifier to:self.locals source:nil atTime:time];
}
- (void)recordRemoteTokens:(NSArray *)tokens address:(NSString *)address source:(NSString *)source atTime:(NSTimeInterval)time {
    [self append:tokens key:address to:self.remotes source:source atTime:time];
}
- (void)recordRemoteTokens:(NSArray *)tokens address:(NSString *)address source:(NSString *)source atTime:(NSTimeInterval)time lastSeen:(NSTimeInterval)lastSeen {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(!isfinite(lastSeen) || lastSeen<time || lastSeen>now+5 || lastSeen<now-HABLEEvidenceWindow)return;
    [self append:tokens key:address to:self.remotes source:source atTime:MAX(time,now-HABLEEvidenceWindow)];
    [self append:tokens key:address to:self.remotes source:source atTime:lastSeen];
}
- (NSDictionary *)correlationForIdentifier:(NSString *)identifier address:(NSString *)address now:(NSTimeInterval)now {
    NSArray *local=self.locals[identifier],*remote=self.remotes[address];
    // Learn recurring same-length packet families from their leading byte.
    // No byte value has a predefined meaning. Require a small, recurrent
    // alphabet; changing measurement bytes must not create one channel/state.
    NSMutableDictionary *prefixCounts=NSMutableDictionary.dictionary;
    for (NSDictionary *event in local) {
        if ([event[@"last_seen"] doubleValue]<now-HABLEEvidenceWindow)continue;
        NSString *token=event[@"token"];NSRange colon=[token rangeOfString:@":" options:NSBackwardsSearch];
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[token substringFromIndex:colon.location+1] options:0];
        if(bytes.length<4)continue;
        NSString *channel=event[@"channel"];NSMutableDictionary *counts=prefixCounts[channel];
        if(!counts){counts=NSMutableDictionary.dictionary;prefixCounts[channel]=counts;}
        NSNumber *prefix=@(((const uint8_t *)bytes.bytes)[0]);counts[prefix]=@([counts[prefix] unsignedIntegerValue]+1);
    }
    NSMutableSet *partitioned=NSMutableSet.set;
    for(NSString *channel in prefixCounts) {
        NSDictionary *counts=prefixCounts[channel];if(counts.count<2 || counts.count>4)continue;
        BOOL recurrent=YES;for(NSNumber *count in counts.allValues)if(count.unsignedIntegerValue<3)recurrent=NO;
        if(recurrent)[partitioned addObject:channel];
    }
    NSMutableArray *(^partition)(NSArray *)=^NSMutableArray *(NSArray *events) {
        NSMutableArray *result=NSMutableArray.array;
        for(NSDictionary *event in events) {
            if(![partitioned containsObject:event[@"channel"]]){[result addObject:event];continue;}
            NSString *token=event[@"token"];NSRange colon=[token rangeOfString:@":" options:NSBackwardsSearch];
            NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[token substringFromIndex:colon.location+1] options:0];
            if(!bytes.length)continue;
            NSMutableDictionary *copy=[event mutableCopy];copy[@"channel"]=[NSString stringWithFormat:@"%@/prefix:%u",event[@"channel"],((const uint8_t *)bytes.bytes)[0]];[result addObject:copy];
        }return result;
    };
    if(partitioned.count){local=partition(local);remote=partition(remote);}
    NSMutableSet *channels=NSMutableSet.set;
    for(NSDictionary *event in local)if([event[@"last_seen"] doubleValue]>=now-HABLEEvidenceWindow)[channels addObject:event[@"channel"]];
    NSDictionary *best=@{@"qualified":@NO,@"distinct_packets":@0,@"matched_events":@0,@"compared_events":@0,@"span":@0,@"median_skew":@0,@"sources":@[]};
    BOOL qualified=NO,contradiction=NO;
    for(NSString *channel in channels) {
        NSMutableSet *values=NSMutableSet.set,*buckets=NSMutableSet.set,*sources=NSMutableSet.set,*localValues=NSMutableSet.set,*remoteValues=NSMutableSet.set;
        NSMutableArray *skews=NSMutableArray.array;NSUInteger compared=0,matched=0;double first=now,last=0,lastReference=0;
        for(NSDictionary *event in remote)if([event[@"channel"] isEqual:channel] && [event[@"last_seen"] doubleValue]>=now-HABLEEvidenceWindow)[remoteValues addObject:event[@"token"]];
        for(NSDictionary *event in local) {
            if(![event[@"channel"] isEqual:channel] || [event[@"last_seen"] doubleValue]<now-HABLEEvidenceWindow)continue;
            [localValues addObject:event[@"token"]];double at=[event[@"time"] doubleValue],end=[event[@"last_seen"] doubleValue];BOOL comparable=NO;NSDictionary *closest=nil;double distance=DBL_MAX;
            for(NSDictionary *other in remote) {
                if(![other[@"channel"] isEqual:channel])continue;double start=[other[@"time"] doubleValue],finish=[other[@"last_seen"] doubleValue];
                if(at>finish+15 || start>end+15)continue;comparable=YES;
                if([event[@"token"] isEqual:other[@"token"]] && fabs(at-start)<distance){closest=other;distance=fabs(at-start);}
            }
            if(!comparable)continue;compared++;
            if(closest){matched++;first=MIN(first,at);last=MAX(last,end);lastReference=MAX(lastReference,[closest[@"last_seen"] doubleValue]);[skews addObject:@(at-[closest[@"time"] doubleValue])];[sources addObject:closest[@"source"]];if(![values containsObject:event[@"token"]]){[values addObject:event[@"token"]];[buckets addObject:@((NSInteger)floor(at/5))];}}
        }
        double agreement=compared ? (double)matched/compared : 0;[skews sortUsingSelector:@selector(compare:)];double skew=skews.count ? [skews[skews.count/2] doubleValue] : INFINITY;
        BOOL passes=values.count>=12 && buckets.count>=6 && matched>=12 && agreement>=.9 && last-first>=30 && fabs(skew)<=3 && now-last<=120 && now-lastReference<=120;
        if((compared>=3 && agreement<.5) || (compared && !matched && localValues.count==1 && remoteValues.count==1))contradiction=YES;
        NSDictionary *result=@{@"qualified":@(passes),@"distinct_packets":@(values.count),@"matched_events":@(matched),@"compared_events":@(compared),@"span":@(MAX(0,last-first)),@"median_skew":@(isfinite(skew)?skew:0),@"agreement":@(agreement),@"time_buckets":@(buckets.count),@"local_age":@(now-last),@"reference_age":@(now-lastReference),@"sources":sources.allObjects};
        if([result[@"distinct_packets"] unsignedIntegerValue]>[best[@"distinct_packets"] unsignedIntegerValue] || (![best[@"compared_events"] unsignedIntegerValue] && compared))best=result;
        qualified=qualified || passes;
    }
    NSMutableDictionary *result=[best mutableCopy];result[@"qualified"]=@(qualified && !contradiction);result[@"contradictory_channel"]=@(contradiction);return result;
}
- (BOOL)hasCompetingLocalIdentifier:(NSString *)identifier address:(NSString *)address now:(NSTimeInterval)now {
    for (NSString *other in self.locals) if (![other isEqual:identifier]) { NSDictionary *e=[self correlationForIdentifier:other address:address now:now]; if ([e[@"compared_events"] unsignedIntegerValue] && [e[@"matched_events"] doubleValue] / [e[@"compared_events"] doubleValue] >= .9) return YES; }
    return NO;
}
- (NSArray *)recentLocalEventsForIdentifier:(NSString *)identifier now:(NSTimeInterval)now {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *event in self.locals[identifier]) if ([event[@"last_seen"] doubleValue] >= now - HABLEEvidenceWindow) [result addObject:event];
    return result;
}
- (void)removeIdentifier:(NSString *)identifier { [self.locals removeObjectForKey:identifier]; }
- (void)reset { [self.locals removeAllObjects]; [self.remotes removeAllObjects]; }
@end
