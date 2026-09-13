#import "HABLEIdentityEvidence.h"
#import "HABLEProto.h"
#import <math.h>

static const NSTimeInterval HABLEEvidenceWindow = 900;
static const NSUInteger HABLEEvidenceEvents = 96;
static NSString *HABLEPayloadToken(NSString *channel, NSData *bytes) {
    if (bytes.length < 4 || bytes.length > 2048) return nil;
    return [channel stringByAppendingString:[bytes base64EncodedStringWithOptions:0]];
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
@implementation HABLEIdentityEvidence
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
 + (BOOL)tokens:(NSArray *)local agreeWith:(NSArray *)remote {
    BOOL common=NO;
    for (NSString *token in local) {
        NSString *channel=[token substringToIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location+1];BOOL comparable=NO,equal=NO;
        for (NSString *other in remote) if ([other hasPrefix:channel]) { comparable=YES;if([other isEqual:token])equal=YES; }
        if(comparable && !equal)return NO;if(equal)common=YES;
    }
    return common;
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
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (time < now - HABLEEvidenceWindow || time > now + 5) return;
    NSMutableArray *events = storage[key];
    if (!events) { if (storage.count >= 256) return; events = [NSMutableArray array]; storage[key] = events; }
    while (events.count && [events.firstObject[@"last_seen"] doubleValue] < now - HABLEEvidenceWindow) [events removeObjectAtIndex:0];
    NSDictionary *last=events.lastObject;
    if ([last[@"tokens"] isEqual:tokens] && [last[@"source"] isEqual:source ?: @""] && time >= [last[@"time"] doubleValue]) {
        NSMutableDictionary *updated=[last mutableCopy];updated[@"last_seen"]=@(MAX(time,[last[@"last_seen"] doubleValue]));events[events.count-1]=updated;return;
    }
    for (NSDictionary *old in events) if ([old[@"source"] isEqual:source ?: @""] && [old[@"tokens"] isEqual:tokens] && time >= [old[@"time"] doubleValue]-1 && time <= [old[@"last_seen"] doubleValue]+1) return;
    [events addObject:@{@"time":@(time), @"last_seen":@(time), @"tokens":tokens, @"source":source ?: @""}];
    [events sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"time"] compare:b[@"time"]]; }];
    if (events.count > HABLEEvidenceEvents) [events removeObjectAtIndex:0];
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
    NSArray *local = self.locals[identifier], *remote = self.remotes[address];
    NSMutableDictionary *valuesByChannel = [NSMutableDictionary dictionary], *bucketsByChannel = [NSMutableDictionary dictionary];
    NSMutableSet *sources = [NSMutableSet set]; NSMutableArray *skews = [NSMutableArray array]; NSUInteger eligible = 0, matched = 0; NSTimeInterval first = now, last = 0, lastReference = 0;
    for (NSDictionary *event in local) {
        NSTimeInterval at = [event[@"time"] doubleValue]; NSTimeInterval end=[event[@"last_seen"] doubleValue]; if (end < now-HABLEEvidenceWindow) continue;
        BOOL overlaps = NO, found = NO; NSArray *matchedTokens = nil; NSTimeInterval matchedRemoteEnd = 0, matchedRemoteStart = 0;
        for (NSDictionary *other in remote) {
            NSTimeInterval remoteStart=[other[@"time"] doubleValue],remoteEnd=[other[@"last_seen"] doubleValue];
            if (at>remoteEnd+15 || remoteStart>end+15) continue;
            overlaps = YES; BOOL conflict = NO; NSMutableArray *common = [NSMutableArray array];
            for (NSString *token in event[@"tokens"]) {
                NSString *channel = [token substringToIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location + 1];
                BOOL comparable = NO, equal = NO;
                for (NSString *remoteToken in other[@"tokens"]) if ([remoteToken hasPrefix:channel]) { comparable = YES; if ([remoteToken isEqual:token]) equal = YES; }
                if (comparable && !equal) conflict = YES;
                if (equal) [common addObject:token];
            }
            if (!conflict && common.count) { found = YES; matchedTokens = common; matchedRemoteEnd = remoteEnd; matchedRemoteStart = remoteStart; [sources addObject:other[@"source"]]; break; }
        }
        if (!overlaps) continue;
        eligible++;
        if (found) {
            matched++; first = MIN(first,at); last = MAX(last,end); lastReference = MAX(lastReference,matchedRemoteEnd); [skews addObject:@(at-matchedRemoteStart)];
            for (NSString *token in matchedTokens) {
                NSString *channel = [token substringToIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location + 1];
                NSMutableSet *values = valuesByChannel[channel], *buckets = bucketsByChannel[channel];
                if (!values) { values = [NSMutableSet set]; buckets = [NSMutableSet set]; valuesByChannel[channel] = values; bucketsByChannel[channel] = buckets; }
                if (![values containsObject:token]) { [values addObject:token]; [buckets addObject:@((NSInteger)floor(at / 5))]; }
            }
        }
    }
    NSUInteger distinct = 0, temporalBuckets = 0;
    for (NSString *channel in valuesByChannel) if ([valuesByChannel[channel] count] > distinct) { distinct = [valuesByChannel[channel] count]; temporalBuckets = [bucketsByChannel[channel] count]; }
    [skews sortUsingSelector:@selector(compare:)]; double skew = skews.count ? [skews[skews.count/2] doubleValue] : INFINITY;
    // Static channels and partial-packet combinations cannot manufacture diversity.
    BOOL qualified = fabs(skew)<=3 && distinct >= 12 && temporalBuckets >= 6 && matched >= 12 && eligible && (double)matched / eligible >= .9 && last - first >= 30 && now - last <= 120 && now - lastReference <= 120;
    return @{@"qualified":@(qualified), @"distinct_packets":@(distinct), @"matched_events":@(matched), @"compared_events":@(eligible), @"span":@(MAX(0,last-first)), @"median_skew":@(isfinite(skew)?skew:0), @"sources":sources.allObjects};
}
- (BOOL)hasCompetingLocalIdentifier:(NSString *)identifier address:(NSString *)address now:(NSTimeInterval)now {
    for (NSString *other in self.locals) if (![other isEqual:identifier]) { NSDictionary *e=[self correlationForIdentifier:other address:address now:now]; if ([e[@"compared_events"] unsignedIntegerValue] && [e[@"matched_events"] doubleValue] / [e[@"compared_events"] doubleValue] >= .9) return YES; }
    return NO;
}
- (NSArray *)recentLocalEventsForIdentifier:(NSString *)identifier now:(NSTimeInterval)now {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *event in self.locals[identifier]) if ([event[@"last_seen"] doubleValue] >= now - 60) [result addObject:event];
    return result;
}
- (void)removeIdentifier:(NSString *)identifier { [self.locals removeObjectForKey:identifier]; }
- (void)reset { [self.locals removeAllObjects]; [self.remotes removeAllObjects]; }
@end
