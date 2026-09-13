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
@implementation HABLEIdentityEvidence
+ (NSDictionary *)fingerprintsForValue:(NSData *)data path:(NSString *)path {
    if(!data.length || data.length>512 || !path.length)return @{};
    NSDictionary *(^fingerprint)(NSData *,NSString *)=^NSDictionary *(NSData *bytes,NSString *kind) {
        uint8_t hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,hash);NSMutableString *hex=NSMutableString.string;
        for(NSUInteger i=0;i<sizeof(hash);i++)[hex appendFormat:@"%02x",hash[i]];
        return @{@"sha256":hex,@"length":@(bytes.length),@"kind":kind};
    };
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
            NSData *encoded=[NSJSONSerialization dataWithJSONObject:@[value] options:0 error:nil];
            result[key]=fingerprint(encoded,@"json_scalar");
        }
    }
    return result;
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
 + (BOOL)tokens:(NSArray *)local agreeWith:(NSArray *)remote {
    BOOL common=NO;
    for (NSString *token in local) {
        NSString *channel=[token substringToIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location+1];BOOL comparable=NO,equal=NO;
        for (NSString *other in remote) if ([other hasPrefix:channel]) { comparable=YES;if([other isEqual:token])equal=YES; }
        if(comparable && !equal)return NO;if(equal)common=YES;
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
    NSMutableArray *events=storage[key];if(!events){if(storage.count>=256)return;events=NSMutableArray.array;storage[key]=events;}
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
