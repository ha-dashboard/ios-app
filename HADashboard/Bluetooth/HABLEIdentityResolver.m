#import "HABLEIdentityResolver.h"
#import "HABLEIdentityEvidence.h"
#import "HABLEProto.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import <CommonCrypto/CommonDigest.h>
#import <fnmatch.h>

static NSString *const HABLECatalogKey = @"ha_dashboard.ble_identity.v2";
static NSString *const HABLELocalBindingsKey = @"ha_ble_identity_bindings_v2";
static NSData *HABLEHexData(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] % 2 || [value length] > 8192) return nil;
    if ([value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound) return nil;
    NSMutableData *data = NSMutableData.data;
    for (NSUInteger i = 0; i < [value length]; i += 2) { unsigned byte = 0; [[NSScanner scannerWithString:[value substringWithRange:NSMakeRange(i,2)]] scanHexInt:&byte]; uint8_t b = byte; [data appendBytes:&b length:1]; }
    return data;
}
static NSString *HABLEHash(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding]; uint8_t bytes[32]; CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *hash = NSMutableString.string; for (NSUInteger i=0;i<32;i++) [hash appendFormat:@"%02x",bytes[i]]; return hash;
}
static NSString *HABLEString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static BOOL HABLEUnitIdentifier(NSString *value) {
    if (value.length < 8 || value.length > 128) return NO;
    return [value rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound && [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;
}
static NSDictionary *HABLEProfile(NSDictionary *observation) {
    NSData *manufacturer = [[NSData alloc] initWithBase64EncodedString:HABLEString(observation[@"manufacturer_data"]) options:0];
    if (!manufacturer.length) manufacturer = [[NSData alloc] initWithBase64EncodedString:HABLEString(observation[@"identity_manufacturer_data"]) options:0];
    return @{@"name":HABLEString(observation[@"name"]), @"services":[HABLEIdentityEvidence canonicalServices:observation[@"identity_service_uuids"] ?: observation[@"service_uuids"]], @"manufacturer_length":@(manufacturer.length), @"manufacturer_prefix":manufacturer.length>=2 ? [[manufacturer subdataWithRange:NSMakeRange(0,2)] base64EncodedStringWithOptions:0] : @""};
}
static BOOL HABLEProfilesCompatible(NSDictionary *a, NSDictionary *b) {
    if ([b[@"required_prefix"] isKindOfClass:NSString.class]) return [a[@"manufacturer_prefix"] isEqual:b[@"required_prefix"]] && [HABLEString(a[@"name"]) caseInsensitiveCompare:HABLEString(b[@"name"])]==NSOrderedSame;
    NSArray *as = [a[@"services"] isKindOfClass:NSArray.class] ? a[@"services"] : @[], *bs = [b[@"services"] isKindOfClass:NSArray.class] ? b[@"services"] : @[];
    if (as.count && bs.count) {
        for (NSString *uuid in as) if ([bs containsObject:uuid]) return YES;
        return NO;
    }
    NSString *an = HABLEString(a[@"name"]), *bn = HABLEString(b[@"name"]);
    return an.length && bn.length && ![an isEqual:@"Unnamed device"] && [an caseInsensitiveCompare:bn] == NSOrderedSame &&
        [a[@"manufacturer_length"] isKindOfClass:NSNumber.class] && [a[@"manufacturer_length"] unsignedIntegerValue] && [b[@"manufacturer_length"] isKindOfClass:NSNumber.class] && [b[@"manufacturer_length"] unsignedIntegerValue];
}

@interface HABLEIdentityResolver ()
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *knownDevices;
@property (nonatomic, copy, readwrite) NSString *status;
@property (nonatomic, assign, readwrite) BOOL needsRegistryRefresh;
@property (nonatomic, strong) HABLEIdentityEvidence *evidence;
@property (nonatomic, strong) NSMutableDictionary *remoteInfo;
@property (nonatomic, strong) NSMutableDictionary *localObservations;
@property (nonatomic, strong) NSMutableDictionary *lastEvidence;
@property (nonatomic, strong) NSMutableSet *potentialKnownIdentifiers;
@property (nonatomic, strong) NSMutableDictionary *localBindings;
@property (nonatomic, strong) NSMutableDictionary *catalog;
@property (nonatomic, strong) NSMutableDictionary *peerValues;
@property (nonatomic, strong) NSMutableDictionary *discoveryMatchers;
@property (nonatomic, strong) NSMutableSet *proxySources;
@property (nonatomic, strong) NSMutableSet *writesInFlight;
@property (nonatomic, strong) NSMutableDictionary *pendingPublications;
@property (nonatomic, assign) BOOL publicationInFlight;
@property (nonatomic, assign) NSTimeInterval nextPublication;
@property (nonatomic, strong) NSMutableSet *legacyReads;
@property (nonatomic, copy) NSArray *registryDevices;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *subscriptions;
@property (nonatomic, copy) NSString *sourceAddress;
@property (nonatomic, copy) NSString *sourceServer;
@property (nonatomic, copy) NSString *scope;
@property (nonatomic, assign) NSUInteger sourceRevision;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL publishing;
@property (nonatomic, assign) NSTimeInterval nextPublish;
@property (nonatomic, assign) NSTimeInterval peerLearningUntil;
@property (nonatomic, assign) BOOL previouslyLearning;
@end

@implementation HABLEIdentityResolver
- (HAConnectionManager *)connection { return [HAConnectionManager sharedManager]; }
- (instancetype)init {
    if ((self=[super init])) {
        _knownDevices=@[]; _registryDevices=@[]; _status=@"Waiting for automatic synchronization"; _evidence=[HABLEIdentityEvidence new];
        _remoteInfo=NSMutableDictionary.dictionary; _localObservations=NSMutableDictionary.dictionary; _lastEvidence=NSMutableDictionary.dictionary; _potentialKnownIdentifiers=NSMutableSet.set; _localBindings=NSMutableDictionary.dictionary;
        _catalog=NSMutableDictionary.dictionary; _discoveryMatchers=NSMutableDictionary.dictionary; _peerValues=NSMutableDictionary.dictionary; _proxySources=NSMutableSet.set; _writesInFlight=NSMutableSet.set; _pendingPublications=NSMutableDictionary.dictionary; _legacyReads=NSMutableSet.set; _subscriptions=NSMutableArray.array;
    } return self;
}
- (void)dealloc { [self cancel]; }
- (BOOL)sourceIsCurrent {
    HAAuthManager *auth=HAAuthManager.sharedManager;
    return self.sourceServer.length && [auth.serverURL isEqual:self.sourceServer] && auth.authenticationRevision==self.sourceRevision;
}
- (void)cancel {
    self.generation++;
    if ([self sourceIsCurrent] && self.connection.connected) for (NSNumber *subscription in self.subscriptions) [self.connection unsubscribeFromEventWithId:subscription.integerValue];
    [self.subscriptions removeAllObjects]; [self.writesInFlight removeAllObjects]; self.publicationInFlight=NO; self.publishing=NO;
}
- (void)loadRegistry:(NSArray *)devices entries:(NSArray *)entries excludingSource:(NSString *)source {
    self.sourceAddress=source.uppercaseString; [self.proxySources removeAllObjects]; [self.potentialKnownIdentifiers removeAllObjects];
    NSMutableSet *adapters=NSMutableSet.set; NSMutableDictionary *domains=NSMutableDictionary.dictionary; NSMutableArray *records=NSMutableArray.array;
    for(NSDictionary *entry in entries)if([entry[@"entry_id"] isKindOfClass:NSString.class] && [entry[@"domain"] isKindOfClass:NSString.class])domains[entry[@"entry_id"]]=entry[@"domain"];
    for (NSDictionary *entry in entries) if ([entry[@"domain"] isEqual:@"bluetooth"]) [adapters addObject:entry[@"entry_id"]];
    for (NSDictionary *device in devices) {
        NSString *manufacturer=[HABLEString(device[@"manufacturer"]) lowercaseString];
        // Recognize our own transport nodes, never a list of sensor vendors.
        BOOL proxy=[manufacturer isEqual:@"ha-dashboard"] || [manufacturer isEqual:@"ha dashboard"] || [device[@"model"] isEqual:@"iOS CoreBluetooth proxy"];
        BOOL adapter=NO; for (NSString *entry in device[@"config_entries"]) if ([adapters containsObject:entry]) adapter=YES;
        if (proxy) for (NSArray *pair in device[@"connections"]) if (pair.count==2 && [pair[1] isKindOfClass:NSString.class]) [self.proxySources addObject:[pair[1] uppercaseString]];
        if (proxy || adapter || [device[@"entry_type"] isEqual:@"service"]) continue;
        NSMutableDictionary *record=NSMutableDictionary.dictionary;
        for (NSString *key in @[@"manufacturer",@"model",@"serial_number",@"name",@"name_by_user",@"id"]) if ([device[key] isKindOfClass:NSString.class]) record[key]=device[key];
        record[@"device_id"]=record[@"id"] ?: @""; record[@"label"]=record[@"name_by_user"] ?: record[@"name"] ?: record[@"device_id"];
        NSMutableArray *addresses=NSMutableArray.array,*identifiers=NSMutableArray.array;
        for (NSArray *pair in device[@"connections"]) { uint64_t address; if (pair.count==2 && [pair[0] isEqual:@"bluetooth"] && HABLEParseAddress(HABLEString(pair[1]),&address)) [addresses addObject:HABLEAddressString(address)]; }
        for (NSArray *pair in device[@"identifiers"]) if (pair.count==2 && [pair[0] isKindOfClass:NSString.class] && [pair[1] isKindOfClass:NSString.class]) [identifiers addObject:pair];
        NSMutableSet *recordDomains=NSMutableSet.set;for(NSString *entryID in device[@"config_entries"])if(domains[entryID])[recordDomains addObject:domains[entryID]];record[@"domains"]=recordDomains.allObjects;
        record[@"addresses"]=addresses; record[@"identifiers"]=identifiers; [records addObject:record]; if (records.count>=2048) break;
    }
    self.registryDevices=records; [self rebuildKnownDevices];
}
- (void)rebuildKnownDevices {
    NSMutableArray *known=NSMutableArray.array;
    for (NSDictionary *record in self.registryDevices) {
        NSMutableSet *addresses=[NSMutableSet setWithArray:record[@"addresses"]];
        for (NSString *address in self.catalog) if ([self.catalog[address][@"device_id"] isEqual:record[@"device_id"]]) [addresses addObject:address];
        for (NSString *address in self.remoteInfo) {
            NSString *name=HABLEString(self.remoteInfo[address][@"name"]);
            for (NSArray *pair in record[@"identifiers"]) if (name.length && HABLEUnitIdentifier(pair[1]) && [name caseInsensitiveCompare:pair[1]]==NSOrderedSame) [addresses addObject:address];
        }
        BOOL hasUnit=NO;for(NSArray *pair in record[@"identifiers"])if(HABLEUnitIdentifier(pair[1]))hasUnit=YES;
        if (!addresses.count && ![record[@"serial_number"] length] && !hasUnit) continue;
        for (NSString *address in addresses.count ? addresses.allObjects : @[@""]) { NSMutableDictionary *item=[record mutableCopy];item[@"address"]=address;[known addObject:item]; }
    }
    // An advertised Bluetooth identity does not require an HA device entry.
    // Keep the radio anchor separate from optional HA registration metadata.
    NSMutableSet *covered=NSMutableSet.set;
    for(NSDictionary *record in known)if([record[@"address"] length])[covered addObject:record[@"address"]];
    NSMutableSet *observed=[NSMutableSet setWithArray:self.remoteInfo.allKeys];
    for(NSString *address in self.catalog)if([self.catalog[address][@"identity_kind"] isEqual:@"observed_native"])[observed addObject:address];
    for(NSString *address in observed) {
        if([covered containsObject:address])continue;
        NSDictionary *remote=self.remoteInfo[address],*shared=self.catalog[address];
        NSDictionary *anchor=remote[@"native_anchor"] ?: shared[@"native_anchor"];
        if(!anchor)continue;
        NSString *name=HABLEString(remote[@"name"]);if(!name.length)name=HABLEString(shared[@"name"]);
        [known addObject:@{@"identity_kind":@"observed_native",@"device_id":[@"bluetooth:" stringByAppendingString:address],@"address":address,@"addresses":@[address],@"identifiers":@[],@"domains":@[],@"name":name,@"label":name.length ? name : address,@"native_anchor":anchor}];
    }
    self.knownDevices=[known sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"label"] localizedCaseInsensitiveCompare:b[@"label"]];}];
}
- (BOOL)validBinding:(NSDictionary *)binding {
    uint64_t address;
    if (![binding isKindOfClass:NSDictionary.class] || ![binding[@"profile"] isKindOfClass:NSDictionary.class] || ![binding[@"lineage"] isKindOfClass:NSArray.class] || [binding[@"lineage"] count]>32 || ![binding[@"schema"] isEqual:@2] || !HABLEParseAddress(HABLEString(binding[@"address"]),&address) || ![binding[@"proof_id"] isKindOfClass:NSString.class]) return NO;
    if (![@[@"embedded_address",@"serial",@"named_identifier",@"packet_sequence",@"confirmed"] containsObject:binding[@"method"]]) return NO;
    if([binding[@"identity_kind"] isEqual:@"observed_native"]) {
        NSDictionary *anchor=binding[@"native_anchor"];
        if(![anchor isKindOfClass:NSDictionary.class] || ![anchor[@"address"] isEqual:binding[@"address"]] || ![binding[@"device_id"] isEqual:[@"bluetooth:" stringByAppendingString:binding[@"address"]]])return NO;
        NSString *source=HABLEString(anchor[@"source"]);
        if(!source.length || [source isEqual:self.sourceAddress] || [self.proxySources containsObject:source] || !HABLEHexData(anchor[@"raw"]).length)return NO;
        return [@[@"embedded_address",@"packet_sequence",@"confirmed"] containsObject:binding[@"method"]];
    }
    for (NSDictionary *record in self.registryDevices) if ([record[@"device_id"] isEqual:binding[@"device_id"]]) {
        if ([binding[@"method"] isEqual:@"serial"] && ![record[@"serial_number"] isEqual:binding[@"unit_identifier"]]) return NO;
        if ([binding[@"method"] isEqual:@"named_identifier"] && ![self registeredIdentifierForName:HABLEString(binding[@"unit_identifier"]) record:record]) return NO;
        if ([record[@"addresses"] containsObject:HABLEAddressString(address)]) return YES;
        for (NSArray *pair in record[@"identifiers"]) if ([pair[1] isEqual:binding[@"unit_identifier"]] && HABLEUnitIdentifier(pair[1])) return YES;
    }
    return NO;
}
- (void)loadCatalog:(id)value {
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"schema"] isEqual:@2] || ![value[@"bindings"] isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *valid=NSMutableDictionary.dictionary;
    for (NSString *address in value[@"bindings"]) { NSDictionary *binding=value[@"bindings"][address];if ([self validBinding:binding] && [binding[@"address"] isEqual:address]) valid[address]=binding;if(valid.count>=512)break; }
    self.catalog=valid;
    // HA's shared store has no compare-and-swap operation. Repair additions
    // lost to concurrent publishers from this peer's still-valid local proofs.
    // An existing address is never overwritten by this reconciliation.
    for (NSDictionary *binding in self.localBindings.allValues) {
        NSString *address=binding[@"address"];
        if ([self validBinding:binding] && !self.catalog[address] && self.pendingPublications.count<512) self.pendingPublications[address]=binding;
    }
    [self rebuildKnownDevices];
}
- (void)loadLocalBindings {
    NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:HABLELocalBindingsKey];
    [self.localBindings removeAllObjects];
    if (![saved[@"scope"] isEqual:self.scope] || ![saved[@"bindings"] isKindOfClass:NSDictionary.class]) return;
    for (NSString *identifier in saved[@"bindings"]) {
        NSDictionary *binding=saved[@"bindings"][identifier]; NSDictionary *shared=self.catalog[binding[@"address"]];
        if ([self validBinding:binding] && (!shared || [shared[@"proof_id"] isEqual:binding[@"proof_id"]])) {
            self.localBindings[identifier]=binding;
            if (!shared && self.pendingPublications.count<512) self.pendingPublications[binding[@"address"]]=binding;
        }
        if(self.localBindings.count>=256)break;
    }
}
- (void)saveLocalBindings { if(self.scope.length) [NSUserDefaults.standardUserDefaults setObject:@{@"scope":self.scope,@"bindings":self.localBindings} forKey:HABLELocalBindingsKey]; }
- (void)observeAdvertisements:(NSArray *)advertisements {
    for (NSDictionary *ad in advertisements) {
        NSString *address=HABLEString(ad[@"address"]).uppercaseString,*source=HABLEString(ad[@"source"]).uppercaseString;uint64_t numeric;
        if (!HABLEParseAddress(address,&numeric) || !source.length || [self.proxySources containsObject:source] || [source isEqual:self.sourceAddress]) continue;
        if(self.remoteInfo.count>=256 && !self.remoteInfo[address])continue;
        NSData *raw=HABLEHexData(ad[@"raw"]); NSArray *tokens=[HABLEIdentityEvidence tokensForRawAdvertisement:raw];
        NSMutableDictionary *info=[ad mutableCopy];info[@"tokens"]=tokens;
        NSUInteger length=0;for(NSString *token in tokens)if([token hasPrefix:@"m:"])length=[[[NSData alloc]initWithBase64EncodedString:[token substringFromIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location+1] options:0]length];
        info[@"profile"]=@{@"name":HABLEString(ad[@"name"]),@"services":[HABLEIdentityEvidence canonicalServices:ad[@"service_uuids"]],@"manufacturer_length":@(length)};
        NSDictionary *anchor=HABLEHexData(ad[@"raw"]).length ? @{@"address":address,@"source":source,@"raw":ad[@"raw"]} : self.remoteInfo[address][@"native_anchor"];
        if(anchor)info[@"native_anchor"]=anchor;
        self.remoteInfo[address]=info;
        // A merged manufacturer-data dictionary is metadata, not a packet trace.
        if (tokens.count && [ad[@"time"] isKindOfClass:NSNumber.class]) [self.evidence recordRemoteTokens:tokens address:address source:source atTime:[ad[@"time"] doubleValue]];
    }
    [self rebuildKnownDevices];
}
- (NSString *)peerKey:(NSString *)source { return [@"ha_dashboard.ble_observations.v2." stringByAppendingString:source]; }
- (void)observePeer:(id)value source:(NSString *)source {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"time"] isKindOfClass:NSNumber.class] || ![value[@"schema"] isEqual:@2] || ![value[@"source"] isEqual:source] || [source isEqual:self.sourceAddress]) return;
    NSTimeInterval at=[value[@"time"] doubleValue]; if(at<now-30 || at>now+5)return;
    double learning=[value[@"learning_until"] isKindOfClass:NSNumber.class] ? MIN(now+30,[value[@"learning_until"] doubleValue]) : 0;
    NSMutableArray *requested=NSMutableArray.array; if([value[@"requested_profiles"] isKindOfClass:NSArray.class]) for(id profile in value[@"requested_profiles"]) if([profile isKindOfClass:NSDictionary.class] && requested.count<16)[requested addObject:profile];
    self.peerValues[source]=@{@"learning_until":@(learning),@"requested_profiles":requested};
    self.peerLearningUntil=MAX(self.peerLearningUntil,learning);
    if (![value[@"records"] isKindOfClass:NSArray.class])return;
    NSUInteger count=0;
    for(NSDictionary *record in value[@"records"]) {
        if(++count>128)break; if(![record isKindOfClass:NSDictionary.class] || ![record[@"address"] isKindOfClass:NSString.class] || ![record[@"time"] isKindOfClass:NSNumber.class])continue; NSDictionary *proof=self.catalog[record[@"address"]];
        if(!proof || ![proof[@"proof_id"] isEqual:record[@"proof_id"]] || ![record[@"lineage"] isKindOfClass:NSArray.class] || [record[@"lineage"] containsObject:self.sourceAddress])continue;
        if(record[@"last_seen"] && ![record[@"last_seen"] isKindOfClass:NSNumber.class])continue;
        if(![record[@"tokens"] isKindOfClass:NSArray.class] || [record[@"tokens"] count]>16)continue;
        BOOL valid=YES; for(id token in record[@"tokens"]) {
            if(![token isKindOfClass:NSString.class] || [token length]>4096 || (![(NSString *)token hasPrefix:@"m:"] && ![(NSString *)token hasPrefix:@"s:"])) { valid=NO; continue; }
            NSRange colon=[token rangeOfString:@":" options:NSBackwardsSearch]; NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[token substringFromIndex:colon.location+1] options:0];
            if(bytes.length<4 || bytes.length>2048)valid=NO;
        }
        if(!valid)continue;
        NSString *address=record[@"address"];
        self.remoteInfo[address]=@{@"name":HABLEString(proof[@"profile"][@"name"]),@"profile":proof[@"profile"] ?: @{},@"source":source,@"lineage":record[@"lineage"],@"tokens":record[@"tokens"],@"time":record[@"time"]};
        [self.evidence recordRemoteTokens:record[@"tokens"] address:address source:source atTime:[record[@"time"] doubleValue] lastSeen:[(record[@"last_seen"] ?: record[@"time"]) doubleValue]];
    }
    [self rebuildKnownDevices];
}
- (void)loadDiscoveryMatchers:(void (^)(void))completion {
    NSMutableSet *domains=NSMutableSet.set;for(NSDictionary *record in self.registryDevices)for(NSString *domain in record[@"domains"])if(domains.count<128)[domains addObject:domain];
    if(!domains.count){completion();return;}
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    [self.connection sendCommand:@{@"type":@"manifest/list",@"integrations":domains.allObjects} completion:^(id result,NSError *error){
        HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
        if(!error && [result isKindOfClass:NSArray.class])for(NSDictionary *manifest in result)if([manifest[@"domain"] isKindOfClass:NSString.class] && [manifest[@"bluetooth"] isKindOfClass:NSArray.class])self.discoveryMatchers[manifest[@"domain"]]=manifest[@"bluetooth"];
        completion();
    }];
}
- (BOOL)observation:(NSDictionary *)observation matchesDiscoveryRule:(NSDictionary *)rule {
    if(![rule isKindOfClass:NSDictionary.class] || !rule.count)return NO;
    if(!rule[@"local_name"] && !rule[@"service_uuid"] && !rule[@"manufacturer_id"] && !rule[@"manufacturer_data_start"])return NO;
    NSSet *supported=[NSSet setWithArray:@[@"local_name",@"service_uuid",@"manufacturer_id",@"manufacturer_data_start",@"connectable"]];
    for(NSString *key in rule)if(![supported containsObject:key])return NO;
    BOOL positive=NO;NSString *observedName=HABLEString(observation[@"name"]);BOOL named=observedName.length && ![observedName isEqual:@"Unnamed device"];
    NSString *pattern=rule[@"local_name"];
    if(pattern && (![pattern isKindOfClass:NSString.class] || pattern.length>128))return NO;
    if(pattern && named && fnmatch(pattern.UTF8String,observedName.UTF8String,0)!=0)return NO;
    if(pattern && named)positive=YES;
    if(rule[@"service_uuid"]) {NSString *uuid=HABLECanonicalUUID(rule[@"service_uuid"]);if(!uuid || (![[HABLEIdentityEvidence canonicalServices:observation[@"identity_service_uuids"] ?: observation[@"service_uuids"]] containsObject:uuid] && ![HABLEIdentityEvidence observation:observation containsUUID:uuid]))return NO;positive=YES;}
    NSData *manufacturer=[[NSData alloc]initWithBase64EncodedString:HABLEString(observation[@"manufacturer_data"]) options:0];
    if(!manufacturer.length)manufacturer=[[NSData alloc]initWithBase64EncodedString:HABLEString(observation[@"identity_manufacturer_data"]) options:0];
    const uint8_t *bytes=manufacturer.bytes;
    if(rule[@"manufacturer_id"] && manufacturer.length>=2 && ( ![rule[@"manufacturer_id"] isKindOfClass:NSNumber.class] || [rule[@"manufacturer_id"] unsignedIntegerValue]!=(bytes[0]|(bytes[1]<<8))))return NO;
    if(rule[@"manufacturer_id"] && manufacturer.length>=2)positive=YES;
    if(rule[@"manufacturer_data_start"]) {NSData *prefix=HABLEHexData(rule[@"manufacturer_data_start"]);if(!prefix || manufacturer.length<2+prefix.length || ![[manufacturer subdataWithRange:NSMakeRange(2,prefix.length)] isEqual:prefix])return NO;positive=YES;}
    if(rule[@"connectable"] && ![rule[@"connectable"] isKindOfClass:NSNumber.class])return NO;
    if([rule[@"connectable"] boolValue] && ![observation[@"connectable"] boolValue])return NO;
    return positive;
}
- (void)loadLegacyAssociations:(void (^)(void))completion {
    dispatch_group_t group=dispatch_group_create();NSUInteger count=0,generation=self.generation;__weak typeof(self) weakSelf=self;
    for(NSDictionary *record in self.registryDevices) {
        NSString *unit=[self registeredIdentifierForName:HABLEString(record[@"name"]) record:record];
        if(!unit || ![record[@"device_id"] length])continue;if(++count>32)break;
        BOOL present=NO;for(NSDictionary *binding in self.catalog.allValues)if([binding[@"device_id"] isEqual:record[@"device_id"]])present=YES;if(present)continue;
        dispatch_group_enter(group);
        [self.connection sendCommand:@{@"type":@"frontend/get_system_data",@"key":[@"ha_dashboard.ble_identity.v1." stringByAppendingString:record[@"device_id"]]} completion:^(id result,NSError *error){
            HABLEIdentityResolver *self=weakSelf;
            if(self && generation==self.generation && [self sourceIsCurrent] && !error && [result isKindOfClass:NSDictionary.class]) {
                id old=result[@"value"];uint64_t address;
                if([old isKindOfClass:NSDictionary.class] && [old[@"schema"] isEqual:@1] && [old[@"device_id"] isEqual:record[@"device_id"]] && [old[@"identifier"] isEqual:unit] && [old[@"evidence_kind"] isEqual:@"independent_scanner"] && HABLEParseAddress(HABLEString(old[@"address"]),&address) && [old[@"manufacturer_id"] isKindOfClass:NSNumber.class] && [old[@"manufacturer_id"] unsignedLongLongValue]<=65535) {
                    uint16_t number=[old[@"manufacturer_id"] unsignedIntValue];uint8_t bytes[]={number&255,number>>8};
                    NSDictionary *binding=@{@"schema":@2,@"address":HABLEAddressString(address),@"device_id":record[@"device_id"],@"method":@"named_identifier",@"unit_identifier":unit,@"proof_id":HABLEHash([NSString stringWithFormat:@"legacy|%@|%@",record[@"device_id"],old[@"address"]]),@"lineage":@[],@"profile":@{@"name":unit,@"services":@[],@"manufacturer_length":@0,@"required_prefix":[[NSData dataWithBytes:bytes length:2] base64EncodedStringWithOptions:0]}};
                    [self publishBinding:binding];self.catalog[binding[@"address"]]=binding;[self rebuildKnownDevices];
                }
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group,dispatch_get_main_queue(),^{HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent])completion();});
}
- (void)startSubscriptions {
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;HAConnectionManager *connection=self.connection;
    if(![NSUserDefaults.standardUserDefaults boolForKey:@"HABLEIdentitySharedOnly"]) {
        NSInteger n=[connection subscribeWithCommand:@{@"type":@"bluetooth/subscribe_advertisements"} handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent] && [event[@"add"] isKindOfClass:NSArray.class])[self observeAdvertisements:event[@"add"]];}];[self.subscriptions addObject:@(n)];
    }
    NSInteger n=[connection subscribeWithCommand:@{@"type":@"frontend/subscribe_system_data",@"key":HABLECatalogKey} handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent])[self loadCatalog:event[@"value"]];}];[self.subscriptions addObject:@(n)];
    n=[connection subscribeToEventType:@"device_registry_updated" handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation)self.needsRegistryRefresh=YES;}];[self.subscriptions addObject:@(n)];
    NSUInteger count=0;for(NSString *source in self.proxySources) {
        if([source isEqual:self.sourceAddress])continue;if(++count>16)break;
        n=[connection subscribeWithCommand:@{@"type":@"frontend/subscribe_system_data",@"key":[self peerKey:source]} handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent])[self observePeer:event[@"value"] source:source];}];[self.subscriptions addObject:@(n)];
    }
}
- (void)refreshExcludingSource:(NSString *)source completion:(void (^)(NSError *))completion {
    [self cancel];self.needsRegistryRefresh=NO; self.status=@"Synchronizing HA identities automatically";
    HAAuthManager *auth=HAAuthManager.sharedManager;self.sourceServer=auth.serverURL;self.sourceRevision=auth.authenticationRevision;
    HAConnectionManager *connection=self.connection;NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    if(!connection.connected){completion([NSError errorWithDomain:@"HABLEIdentity" code:1 userInfo:@{NSLocalizedDescriptionKey:@"HA is not connected"}]);return;}
    [connection sendCommand:@{@"type":@"auth/current_user"} completion:^(id user,NSError *error){
        HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
        if(error || ![user isKindOfClass:NSDictionary.class] || ![user[@"id"] isKindOfClass:NSString.class]){completion(error ?: [NSError errorWithDomain:@"HABLEIdentity" code:2 userInfo:nil]);return;}
        self.scope=HABLEHash([NSString stringWithFormat:@"%@|%@",self.sourceServer,user[@"id"]]);
        [connection sendCommand:@{@"type":@"config_entries/get"} completion:^(id entries,NSError *error){
            HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
            if(error || ![entries isKindOfClass:NSArray.class]){completion(error ?: [NSError errorWithDomain:@"HABLEIdentity" code:3 userInfo:nil]);return;}
            [connection sendCommand:@{@"type":@"config/device_registry/list"} completion:^(id devices,NSError *error){
                HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
                if(error || ![devices isKindOfClass:NSArray.class]){completion(error ?: [NSError errorWithDomain:@"HABLEIdentity" code:4 userInfo:nil]);return;}
                [self loadRegistry:devices entries:entries excludingSource:source];
                [connection sendCommand:@{@"type":@"frontend/get_system_data",@"key":HABLECatalogKey} completion:^(id data,NSError *error){
                    HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
                    if(!error && [data isKindOfClass:NSDictionary.class])[self loadCatalog:data[@"value"]];
                    [self loadDiscoveryMatchers:^{
                    [self loadLegacyAssociations:^{
                    HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
                    if(!self.loaded)[self loadLocalBindings]; self.loaded=YES;[self startSubscriptions];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;self.status=@"Automatically watching HA identities and peer evidence";completion(nil);});
                    }];
                    }];
                }];
            }];
        }];
    }];
}
- (void)recordObservation:(NSDictionary *)observation identifier:(NSString *)identifier {
    if(!identifier.length)return;if(self.localObservations.count>=256 && !self.localObservations[identifier])return;
    self.localObservations[identifier]=observation;[self.evidence recordLocal:observation identifier:identifier atTime:[observation[@"last_seen"] doubleValue]];
}
- (NSString *)evidenceForIdentifier:(NSString *)identifier { return self.lastEvidence[identifier] ?: @"Waiting for sufficient identity evidence"; }
- (void)removeIdentifier:(NSString *)identifier { [self.potentialKnownIdentifiers removeObject:identifier]; [self.lastEvidence removeObjectForKey:identifier]; [self.localObservations removeObjectForKey:identifier];[self.evidence removeIdentifier:identifier]; }
- (NSString *)registeredIdentifierForName:(NSString *)name record:(NSDictionary *)record {
    if(!HABLEUnitIdentifier(name))return nil;
    for(NSArray *pair in record[@"identifiers"])if([name caseInsensitiveCompare:pair[1]]==NSOrderedSame)return pair[1];
    return nil;
}
- (BOOL)proof:(NSDictionary *)proof matches:(NSDictionary *)observation {
    NSString *method=proof[@"method"];
    if([method isEqual:@"embedded_address"] && [proof[@"identity_kind"] isEqual:@"observed_native"])return [HABLEIdentityEvidence observation:observation containsAddress:proof[@"address"]] && HABLEProfilesCompatible(HABLEProfile(observation),proof[@"profile"]) && [HABLEIdentityEvidence tokens:[HABLEIdentityEvidence tokensForObservation:observation] agreeWith:[HABLEIdentityEvidence tokensForRawAdvertisement:HABLEHexData(proof[@"native_anchor"][@"raw"])]];
    if([method isEqual:@"embedded_address"])return [HABLEIdentityEvidence observation:observation containsAddress:proof[@"address"]];
    if([method isEqual:@"serial"])return [observation[@"serial_number"] isEqual:proof[@"unit_identifier"]];
    if([method isEqual:@"named_identifier"])return [HABLEString(observation[@"name"]) caseInsensitiveCompare:HABLEString(proof[@"unit_identifier"])]==NSOrderedSame && [HABLEIdentityEvidence tokensForObservation:observation].count && HABLEProfilesCompatible(HABLEProfile(observation),proof[@"profile"]);
    return NO;
}
- (NSArray *)candidatesForObservation:(NSDictionary *)observation {
    NSMutableArray *result=NSMutableArray.array;NSString *identifier=observation[@"identifier"],*name=HABLEString(observation[@"name"]),*serial=HABLEString(observation[@"serial_number"]);NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSDictionary *profile=HABLEProfile(observation);NSArray *tokens=[HABLEIdentityEvidence tokensForObservation:observation];
    for(NSDictionary *known in self.knownDevices) {
        NSString *address=known[@"address"];NSDictionary *remote=self.remoteInfo[address],*shared=self.catalog[address];NSMutableDictionary *candidate=[known mutableCopy];NSMutableArray *reasons=NSMutableArray.array;
        NSInteger score=0;NSString *method=nil,*unit=nil;NSArray *lineage=remote[@"lineage"] ?: @[];
        BOOL embedded=address.length && [HABLEIdentityEvidence observation:observation containsAddress:address];
        if(embedded){score+=60;[reasons addObject:@"Known HA address appears in the observed payload"];}
        if(address.length && serial.length>=6 && [serial rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location!=NSNotFound && [serial rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"]].location!=NSNotFound && ![serial.lowercaseString isEqual:@"unknown"] && [serial isEqual:known[@"serial_number"]]){method=@"serial";unit=serial;score+=200;[reasons addObject:@"Standard serial matches HA"];}
        NSString *named=[self registeredIdentifierForName:name record:known];
        if(named){score+=40;[reasons addObject:@"Name matches a registered unit identifier"];}else if(name.length && [name caseInsensitiveCompare:HABLEString(known[@"name"])]==NSOrderedSame){score+=10;[reasons addObject:@"Name matches"];}
        BOOL compatible=remote && HABLEProfilesCompatible(profile,remote[@"profile"]);
        if(compatible){score+=5;[reasons addObject:@"Observed BLE profile is compatible"];}
        BOOL payload=[HABLEIdentityEvidence tokens:tokens agreeWith:remote[@"tokens"]];
        BOOL sameName=!name.length || [name isEqual:@"Unnamed device"] || ![HABLEString(remote[@"name"]) length] || [name caseInsensitiveCompare:HABLEString(remote[@"name"])]==NSOrderedSame;
        if(embedded && sameName && payload && compatible && fabs(now-[remote[@"time"] doubleValue])<=120 && ![self.proxySources containsObject:remote[@"source"]]){method=@"embedded_address";score+=160;[reasons addObject:@"Address occurrence corroborated by an independent radio"];}
        if(named && [HABLEString(remote[@"name"]) caseInsensitiveCompare:named]==NSOrderedSame && payload && compatible && fabs(now-[remote[@"time"] doubleValue])<=120 && ![self.proxySources containsObject:remote[@"source"]]){method=@"named_identifier";unit=named;score+=160;[reasons addObject:@"Unit identifier and current payload agree with an independent scanner"];}
        if([self validBinding:shared] && [self proof:shared matches:observation]){method=shared[@"method"];unit=shared[@"unit_identifier"];score+=180;[reasons addObject:@"Verified generic HA association matches"];}
        NSDictionary *saved=self.localBindings[identifier];
        if([saved[@"address"] isEqual:address] && [self validBinding:saved] && HABLEProfilesCompatible(profile,saved[@"profile"])){method=saved[@"method"];unit=saved[@"unit_identifier"];lineage=saved[@"lineage"] ?: @[];score+=180;[reasons addObject:@"Previously verified binding for this Apple peripheral"];}
        NSDictionary *correlation=identifier.length && compatible ? [self.evidence correlationForIdentifier:identifier address:address now:now] : nil;
        if([correlation[@"distinct_packets"] unsignedIntegerValue]) [reasons addObject:[NSString stringWithFormat:@"Learning: %lu / 12 distinct payload changes agree",(unsigned long)[correlation[@"distinct_packets"] unsignedIntegerValue]]];
        if(!method && [correlation[@"distinct_packets"] unsignedIntegerValue]>=12 && ![correlation[@"qualified"] boolValue]) {
            if([correlation[@"contradictory_channel"] boolValue])[reasons addObject:@"Unresolved: another payload channel contradicts this match"];
            if([correlation[@"agreement"] doubleValue]<.9)[reasons addObject:@"Unresolved: too many payload changes disagree"];
            if(fabs([correlation[@"median_skew"] doubleValue])>3)[reasons addObject:@"Unresolved: observation timing does not align"];
            if([correlation[@"time_buckets"] unsignedIntegerValue]<6 || [correlation[@"span"] doubleValue]<30)[reasons addObject:@"Unresolved: changes need a longer observation period"];
            if([correlation[@"local_age"] doubleValue]>120 || [correlation[@"reference_age"] doubleValue]>120)[reasons addObject:@"Unresolved: recent corroborating evidence is missing"];
        }
        BOOL competingLocal=[correlation[@"qualified"] boolValue] && [self.evidence hasCompetingLocalIdentifier:identifier address:address now:now];
        if(competingLocal && !method)[reasons addObject:@"Ambiguous: another local peripheral has matching observations"];
        if([correlation[@"qualified"] boolValue] && !competingLocal){method=method ?: @"packet_sequence";unit=unit ?: named;score+=120;[reasons addObject:[NSString stringWithFormat:@"%lu distinct payloads agree in time",(unsigned long)[correlation[@"distinct_packets"] unsignedIntegerValue]]];}
        candidate[@"automatic_match"]=@(address.length && method!=nil);candidate[@"score"]=@(score);candidate[@"method"]=method ?: @"";candidate[@"unit_identifier"]=unit ?: @"";candidate[@"profile"]=profile;candidate[@"lineage"]=lineage;candidate[@"local_identifier"]=identifier ?: @"";
        candidate[@"reference_sources"]=correlation[@"sources"] ?: (remote[@"source"] ? @[remote[@"source"]] : @[]);
        candidate[@"evidence"]=reasons.count ? [reasons componentsJoinedByString:@" · "] : @"Identity unresolved";[result addObject:candidate];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"score"] compare:a[@"score"]];}];
}
- (NSDictionary *)automaticMatchForObservation:(NSDictionary *)observation {
    NSDictionary *match=nil;NSArray *candidates=[self candidatesForObservation:observation];
    if([observation[@"identifier"] length] && (self.lastEvidence.count<256 || self.lastEvidence[observation[@"identifier"]]))self.lastEvidence[observation[@"identifier"]]=candidates.firstObject[@"evidence"] ?: @"No known candidate yet";
    for(NSDictionary *candidate in candidates)if([candidate[@"automatic_match"] boolValue]){if(match){if([observation[@"identifier"] length])self.lastEvidence[observation[@"identifier"]]=@"Ambiguous: multiple known devices satisfy the identity evidence";return nil;}match=candidate;}
    if(!match)return nil;
    NSString *identifier=observation[@"identifier"];
    if([match[@"identity_kind"] isEqual:@"observed_native"] && [self.evidence hasCompetingLocalIdentifier:identifier address:match[@"address"] now:NSDate.date.timeIntervalSince1970]) {
        self.lastEvidence[identifier]=@"Ambiguous: another local peripheral shares this observed identity evidence";return nil;
    }
    if([match[@"identity_kind"] isEqual:@"observed_native"]) for(NSString *other in self.remoteInfo) {
        NSDictionary *remote=self.remoteInfo[other];
        if([other isEqual:match[@"address"]] || !remote[@"native_anchor"] || fabs(NSDate.date.timeIntervalSince1970-[remote[@"time"] doubleValue])>120)continue;
        if(HABLEProfilesCompatible(HABLEProfile(observation),remote[@"profile"]) && [HABLEIdentityEvidence tokens:[HABLEIdentityEvidence tokensForObservation:observation] agreeWith:remote[@"tokens"]]) {
            self.lastEvidence[identifier]=@"Ambiguous: multiple radio addresses carry the same observed payload";return nil;
        }
    }
    if([match[@"method"] isEqual:@"packet_sequence"]) for(NSString *other in self.remoteInfo) {
        if([other isEqual:match[@"address"]] || !HABLEProfilesCompatible(HABLEProfile(observation),self.remoteInfo[other][@"profile"]))continue;
        NSDictionary *e=[self.evidence correlationForIdentifier:identifier address:other now:NSDate.date.timeIntervalSince1970];
        if([e[@"compared_events"] unsignedIntegerValue] && [e[@"matched_events"] doubleValue]/[e[@"compared_events"] doubleValue]>=.9){self.lastEvidence[identifier]=@"Ambiguous: another remote address has matching observations";return nil;}
    }
    return match;
}
- (BOOL)hasKnownIdentityForObservation:(NSDictionary *)observation {
    NSString *identifier=observation[@"identifier"];
    if(identifier.length && [self.potentialKnownIdentifiers containsObject:identifier])return YES;
    BOOL known=NO;NSDictionary *profile=HABLEProfile(observation);
    // Each integration's rules are evaluated once, not once per registry device.
    for(NSArray *rules in self.discoveryMatchers.allValues) {
        for(NSDictionary *rule in rules)if([self observation:observation matchesDiscoveryRule:rule]){known=YES;break;}
        if(known)break;
    }
    if(!known)for(NSDictionary *record in self.knownDevices) {
        if([self registeredIdentifierForName:HABLEString(observation[@"name"]) record:record] || ([observation[@"serial_number"] length]>=6 && [observation[@"serial_number"] isEqual:record[@"serial_number"]])){known=YES;break;}
        NSDictionary *remote=self.remoteInfo[record[@"address"]];NSDictionary *otherProfile=remote[@"profile"] ?: self.catalog[record[@"address"]][@"profile"];
        if(otherProfile && HABLEProfilesCompatible(profile,otherProfile)){known=YES;break;}
    }
    if(known && identifier.length && self.potentialKnownIdentifiers.count<256)[self.potentialKnownIdentifiers addObject:identifier];
    return known;
}
- (void)rememberAutomaticMatch:(NSDictionary *)match {
    if(![match[@"automatic_match"] boolValue] || ![self sourceIsCurrent])return;
    NSString *address=match[@"address"],*identifier=match[@"local_identifier"];if(!address.length || !identifier.length)return;
    NSMutableDictionary *binding=[match mutableCopy];binding[@"schema"]=@2;
    NSDictionary *existing=self.catalog[address];binding[@"proof_id"]=existing[@"proof_id"] ?: HABLEHash([NSString stringWithFormat:@"%@|%@|%@|%@",address,match[@"device_id"],match[@"method"],match[@"unit_identifier"]]);
    NSMutableOrderedSet *lineage=[NSMutableOrderedSet orderedSetWithArray:match[@"lineage"] ?: @[]];if(self.sourceAddress.length)[lineage addObject:self.sourceAddress];binding[@"lineage"]=lineage.array;
    if(![self validBinding:binding])return;
    self.localBindings[identifier]=binding;[self saveLocalBindings];
    [self publishBinding:binding];
}
- (void)publishBinding:(NSDictionary *)binding {
    NSString *address=binding[@"address"];
    if(![self validBinding:binding] || self.catalog[address])return;
    if(self.pendingPublications.count<512)self.pendingPublications[address]=binding;
    [self pumpPublications];
}
- (void)pumpPublications {
    if(self.publicationInFlight || !self.pendingPublications.count || ![self sourceIsCurrent] || !self.connection.connected || NSDate.date.timeIntervalSince1970<self.nextPublication)return;
    NSString *address=self.pendingPublications.allKeys.firstObject;NSDictionary *binding=self.pendingPublications[address];
    if(![self validBinding:binding]){[self.pendingPublications removeObjectForKey:address];return;}
    self.publicationInFlight=YES;NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;HAConnectionManager *connection=self.connection;
    [connection sendCommand:@{@"type":@"frontend/get_system_data",@"key":HABLECatalogKey} completion:^(id result,NSError *error){
        HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
        id value=[result isKindOfClass:NSDictionary.class] ? result[@"value"] : nil;
        if(error || (value && value!=NSNull.null && (![value isKindOfClass:NSDictionary.class] || ![value[@"schema"] isEqual:@2]))) {self.publicationInFlight=NO;self.nextPublication=NSDate.date.timeIntervalSince1970+60;return;}
        if(!value || value==NSNull.null)value=@{};
        NSMutableDictionary *updated=[value mutableCopy];NSMutableDictionary *bindings=[value[@"bindings"] isKindOfClass:NSDictionary.class] ? [value[@"bindings"] mutableCopy] : NSMutableDictionary.dictionary;
        if(bindings[address]){[self loadCatalog:value];[self.pendingPublications removeObjectForKey:address];self.publicationInFlight=NO;[self pumpPublications];return;}
        if(bindings.count>=512){self.publicationInFlight=NO;self.nextPublication=NSDate.date.timeIntervalSince1970+60;return;}
        bindings[address]=binding;updated[@"schema"]=@2;updated[@"bindings"]=bindings;
        [connection sendCommand:@{@"type":@"frontend/set_system_data",@"key":HABLECatalogKey,@"value":updated} completion:^(id result,NSError *error){
            HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
            self.publicationInFlight=NO;
            if(error){self.nextPublication=NSDate.date.timeIntervalSince1970+60;return;}
            [self.pendingPublications removeObjectForKey:address];self.catalog[address]=binding;[self rebuildKnownDevices];[self pumpPublications];
        }];
    }];
}
- (void)rememberConfirmedAddress:(NSString *)address observation:(NSDictionary *)observation {
    NSString *identifier=observation[@"identifier"];
    if(!identifier.length || [self.localBindings[identifier][@"address"] isEqual:address])return;
    NSDictionary *selected=nil;
    for(NSDictionary *record in self.knownDevices) if([record[@"address"] isEqual:address] || [self registeredIdentifierForName:HABLEString(observation[@"name"]) record:record]) {
        if(selected)return;selected=record;
    }
    if(!selected)return;
    NSMutableDictionary *match=[selected mutableCopy];match[@"address"]=address;match[@"local_identifier"]=identifier;match[@"automatic_match"]=@YES;match[@"method"]=@"confirmed";
    match[@"unit_identifier"]=[self registeredIdentifierForName:HABLEString(observation[@"name"]) record:selected] ?: @"";match[@"profile"]=HABLEProfile(observation);match[@"lineage"]=@[];
    [self rememberAutomaticMatch:match];
}
- (void)maintainSynchronization {
    if(!self.loaded || ![self sourceIsCurrent] || !self.connection.connected)return;
    [self pumpPublications];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;if(now<self.nextPublish || self.publishing)return;self.nextPublish=now+8;
    BOOL learning=NO;NSMutableArray *requested=NSMutableArray.array;
    for(NSString *identifier in self.localObservations) {NSDictionary *observation=self.localObservations[identifier];if(now-[observation[@"last_seen"] doubleValue]<=120 && !self.localBindings[identifier] && [self hasKnownIdentityForObservation:observation]) {
        BOOL nativeAvailable=NO;for(NSDictionary *remote in self.remoteInfo.allValues)if(![self.proxySources containsObject:remote[@"source"]] && now-[remote[@"time"] doubleValue]<120 && HABLEProfilesCompatible(HABLEProfile(observation),remote[@"profile"]))nativeAvailable=YES;
        if(!nativeAvailable && requested.count<16){learning=YES;[requested addObject:HABLEProfile(observation)];}
    }}
    BOOL provide=learning || self.peerLearningUntil>now;
    if(!provide && !self.previouslyLearning)return;
    self.nextPublish=now+8;self.previouslyLearning=provide;NSMutableArray *records=NSMutableArray.array;
    NSMutableArray *wanted=NSMutableArray.array;for(NSDictionary *peer in self.peerValues.allValues)if([peer[@"learning_until"] doubleValue]>now && [peer[@"requested_profiles"] isKindOfClass:NSArray.class])for(NSDictionary *profile in peer[@"requested_profiles"])if([profile isKindOfClass:NSDictionary.class] && wanted.count<64)[wanted addObject:profile];
    if(provide)for(NSString *identifier in self.localBindings) {
        NSDictionary *binding=self.localBindings[identifier];BOOL relevant=NO;for(NSDictionary *profile in wanted)if(HABLEProfilesCompatible(binding[@"profile"],profile))relevant=YES;if(!relevant)continue;
        if(![self.catalog[binding[@"address"]][@"proof_id"] isEqual:binding[@"proof_id"]])continue;
        for(NSDictionary *event in [self.evidence recentLocalEventsForIdentifier:identifier now:now]) {
            if(records.count>=128)break;[records addObject:@{@"address":binding[@"address"],@"proof_id":binding[@"proof_id"],@"lineage":binding[@"lineage"],@"time":event[@"time"],@"last_seen":event[@"last_seen"],@"tokens":event[@"tokens"]}];
        }
        if(records.count>=128)break;
    }
    NSDictionary *value=@{@"schema":@2,@"source":self.sourceAddress ?: @"",@"time":@(now),@"learning_until":@(learning ? now+24 : 0),@"requested_profiles":requested,@"records":records};
    self.publishing=YES;NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    [self.connection sendCommand:@{@"type":@"frontend/set_system_data",@"key":[self peerKey:self.sourceAddress],@"value":value} completion:^(id result,NSError *error){HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation)return;self.publishing=NO;if(error)self.nextPublish=NSDate.date.timeIntervalSince1970+60;}];
}
@end
