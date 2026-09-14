#import "HABLEIdentityResolver.h"
#import "HABLEIdentityEvidence.h"
#import "HABLEProto.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HAAPIClient.h"
#import <CommonCrypto/CommonDigest.h>
#import <fnmatch.h>
#import <math.h>

static NSString *const HABLECatalogKey = @"ha_dashboard.ble_identity.v2";
static NSString *const HABLELocalBindingsKey = @"ha_ble_identity_bindings_v2";
static NSString *const HABLEPeerContinuityKey = @"ha_ble_peer_continuity_v1";
static BOOL HABLEIgnorePeerObservations(void) {
    // Explicit validation launch option, matching HABLEIdentitySharedOnly.
    // Device development bundles are optimized with NDEBUG as well.
    return [NSUserDefaults.standardUserDefaults boolForKey:@"HABLEIdentityIgnorePeerObservations"];
}
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
static NSString *HABLESharedFingerprintAddress(NSString *identity) {
    NSData *hash=HABLEHexData(HABLEHash(identity));const uint8_t *bytes=hash.bytes;uint64_t address=(bytes[0]&0xfc)|2;
    for(NSUInteger i=1;i<6;i++)address=(address<<8)|bytes[i];return HABLEAddressString(address);
}
static NSString *HABLEString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
// Return the oldest observation only when this input is newer than it.
static NSString *HABLEEvictionKey(NSDictionary *storage, NSString *field, NSTimeInterval incoming) {
    NSString *oldest=nil;NSTimeInterval oldestTime=DBL_MAX;
    for(NSString *key in storage) {
        NSTimeInterval time=[storage[key][field] doubleValue];
        if(time<oldestTime){oldest=key;oldestTime=time;}
    }
    return isfinite(incoming) && incoming>oldestTime ? oldest : nil;
}
static BOOL HABLEUnitIdentifier(NSString *value) {
    if (value.length < 8 || value.length > 128) return NO;
    return [value rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound && [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;
}
static NSDictionary *HABLEProfile(NSDictionary *observation) {
    NSData *manufacturer = [[NSData alloc] initWithBase64EncodedString:HABLEString(observation[@"manufacturer_data"]) options:0];
    if (!manufacturer.length) manufacturer = [[NSData alloc] initWithBase64EncodedString:HABLEString(observation[@"identity_manufacturer_data"]) options:0];
    return @{@"name":HABLEString(observation[@"name"]), @"services":[HABLEIdentityEvidence canonicalServices:observation[@"identity_service_uuids"] ?: observation[@"service_uuids"]], @"manufacturer_length":@(manufacturer.length), @"manufacturer_prefix":manufacturer.length>=2 ? [[manufacturer subdataWithRange:NSMakeRange(0,2)] base64EncodedStringWithOptions:0] : @""};
}
// A provisional signature is an observation, not a hardware identifier.
// Require an identifier-shaped name and a substantive payload; names alone
// and generic service/model profiles never qualify.
static NSString *HABLEPassiveSignature(NSDictionary *profile, NSArray *tokens) {
    if(!HABLEUnitIdentifier(profile[@"name"]) || !tokens.count)return nil;
    BOOL substantive=NO;
    for(NSString *token in tokens) {
        NSRange separator=[token rangeOfString:@":" options:NSBackwardsSearch];
        if(separator.location==NSNotFound)return nil;
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[token substringFromIndex:separator.location+1] options:0];
        if(bytes.length>=8)substantive=YES;
    }
    if(!substantive)return nil;
    NSArray *parts=@[profile[@"name"],profile[@"services"] ?: @[],[tokens sortedArrayUsingSelector:@selector(compare:)]];
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:parts options:0 error:nil];
    return encoded ? HABLEHash([[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]) : nil;
}
static void HABLETrackPassiveSignature(NSMutableDictionary *row, NSDictionary *previous, NSString *signature, NSTimeInterval time, NSTimeInterval previousTime) {
    if(!signature || !isfinite(time))return;
    BOOL continues=[previous[@"passive_signature"] isEqual:signature] && time>=previousTime && time-previousTime<=20;
    row[@"passive_signature"]=signature;
    row[@"passive_since"]=continues ? previous[@"passive_since"] : @(time);
    row[@"passive_samples"]=continues ? @([previous[@"passive_samples"] unsignedIntegerValue]+(time>previousTime ? 1 : 0)) : @1;
}
static BOOL HABLEPassiveReady(NSDictionary *row, NSString *timeKey, NSTimeInterval now) {
    NSTimeInterval last=[row[timeKey] doubleValue],first=[row[@"passive_since"] doubleValue];
    return row[@"passive_signature"] && isfinite(last) && last<=now+5 && now-last<=20 && last-first>=30 && [row[@"passive_samples"] unsignedIntegerValue]>=3;
}
static NSString *HABLESerialScope(NSDictionary *profile, NSString *serialPath, NSUInteger minimumSessions) {
    if(![profile isKindOfClass:NSDictionary.class] || !serialPath.length)return nil;
    NSString *parent=[serialPath stringByDeletingLastPathComponent];NSMutableDictionary *context=NSMutableDictionary.dictionary;
    for(NSString *path in profile) {
        if(![[path stringByDeletingLastPathComponent] isEqual:parent])continue;
        NSString *uuid=HABLECanonicalUUID([[path.lastPathComponent componentsSeparatedByString:@"#"] firstObject]);
        NSString *role=[uuid isEqual:HABLECanonicalUUID(@"2A29")] ? @"manufacturer" : [uuid isEqual:HABLECanonicalUUID(@"2A24")] ? @"model" : nil;
        if(!role)continue;NSDictionary *value=profile[path];
        if(![value isKindOfClass:NSDictionary.class] || ![value[@"format"] isEqual:[@"gatt_" stringByAppendingString:role]] || ![value[@"length"] isKindOfClass:NSNumber.class] || [value[@"length"] unsignedIntegerValue]<1 || [value[@"length"] unsignedIntegerValue]>128 || ![value[@"sessions"] isKindOfClass:NSNumber.class] || [value[@"sessions"] unsignedIntegerValue]>255 || ![value[@"varying"] isKindOfClass:NSNumber.class] || [value[@"sessions"] unsignedIntegerValue]<minimumSessions || [value[@"varying"] boolValue] || (minimumSessions>=2 && (![value[@"stable_across_sessions"] isKindOfClass:NSNumber.class] || ![value[@"stable_across_sessions"] boolValue])) || [HABLEString(value[@"sha256"]) length]!=64 || !HABLEHexData(value[@"sha256"]))return nil;
        if(context[role] && ![context[role] isEqual:value[@"sha256"]])return nil;
        context[role]=value[@"sha256"];
    }
    return context.count==2 ? HABLEHash([NSString stringWithFormat:@"%@|%@",context[@"manufacturer"],context[@"model"]]) : nil;
}
static NSString *HABLEFingerprintIdentity(NSDictionary *witness) {
    NSString *material=[NSString stringWithFormat:@"%@|%@",witness[@"path"],witness[@"sha256"]];
    if([witness[@"format"] isEqual:@"gatt_serial"])material=[material stringByAppendingFormat:@"|%@",witness[@"scope_hash"]];
    return [@"gatt:" stringByAppendingString:HABLEHash(material)];
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
@property (nonatomic, strong) NSMutableDictionary *peerPassiveContinuity;
@property (nonatomic, strong) NSDictionary *canonicalProofs;
@property (nonatomic, strong) NSDictionary *canonicalAddresses;
@property (nonatomic) BOOL canonicalCatalogDirty;
@property (nonatomic, strong) NSMutableDictionary *lastEvidence;
@property (nonatomic, strong) NSMutableSet *potentialKnownIdentifiers;
@property (nonatomic, strong) NSMutableDictionary *localBindings;
@property (nonatomic, strong) NSMutableDictionary *catalog;
@property (nonatomic, strong) NSMutableDictionary *peerValues;
@property (nonatomic, strong) NSMutableDictionary *peerInventories;
@property (nonatomic) NSTimeInterval nextInventoryPublish;
@property (nonatomic) NSTimeInterval nextNativeSnapshot;
@property (nonatomic) NSTimeInterval lastNativeSnapshot;
@property (nonatomic) NSInteger nativeSubscription;
@property (nonatomic) NSUInteger nativeSubscriptionEpoch;
@property (nonatomic, strong) HAAPIClient *nativeDiagnosticsClient;
@property (nonatomic, copy) NSString *nativeDiagnosticsEntry;
@property (nonatomic) BOOL nativeDiagnosticsInFlight;
@property (nonatomic) NSTimeInterval nextNativeDiagnostics;
@property (nonatomic) NSTimeInterval lastNativeDiagnostics;
@property (nonatomic) NSInteger nativeDiagnosticsError;
@property (nonatomic) NSUInteger nativeDiagnosticsObservations;
@property (nonatomic) BOOL inventoryPublishing;
@property (nonatomic) NSUInteger inventoryCursor;
@property (nonatomic) BOOL inventoryPartial;
@property (nonatomic) NSTimeInterval lastInventoryPublish;
@property (nonatomic) NSInteger inventoryPublishError;
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
        _remoteInfo=NSMutableDictionary.dictionary; _localObservations=NSMutableDictionary.dictionary; _peerPassiveContinuity=NSMutableDictionary.dictionary; _canonicalCatalogDirty=YES; _lastEvidence=NSMutableDictionary.dictionary; _potentialKnownIdentifiers=NSMutableSet.set; _localBindings=NSMutableDictionary.dictionary;
        _catalog=NSMutableDictionary.dictionary; _discoveryMatchers=NSMutableDictionary.dictionary; _peerValues=NSMutableDictionary.dictionary; _peerInventories=NSMutableDictionary.dictionary; _proxySources=NSMutableSet.set; _writesInFlight=NSMutableSet.set; _pendingPublications=NSMutableDictionary.dictionary; _legacyReads=NSMutableSet.set; _subscriptions=NSMutableArray.array;
    } return self;
}
- (void)dealloc { [self cancel]; }
- (BOOL)sourceIsCurrent {
    HAAuthManager *auth=HAAuthManager.sharedManager;
    return self.sourceServer.length && [auth.serverURL isEqual:self.sourceServer] && auth.authenticationRevision==self.sourceRevision;
}
- (void)cancel {
    [self.nativeDiagnosticsClient cancelAllRequests];self.nativeDiagnosticsClient=nil;self.nativeDiagnosticsInFlight=NO;self.nextNativeDiagnostics=0;
    self.generation++;self.nativeSubscriptionEpoch++;self.nativeSubscription=0;self.nextNativeSnapshot=0;self.lastNativeSnapshot=0;
    if ([self sourceIsCurrent] && self.connection.connected) for (NSNumber *subscription in self.subscriptions) [self.connection unsubscribeFromEventWithId:subscription.integerValue];
    [self.subscriptions removeAllObjects]; [self.writesInFlight removeAllObjects]; self.publicationInFlight=NO; self.publishing=NO; self.inventoryPublishing=NO;
}
- (void)loadRegistry:(NSArray *)devices entries:(NSArray *)entries excludingSource:(NSString *)source {
    self.sourceAddress=source.uppercaseString; [self.proxySources removeAllObjects]; [self.potentialKnownIdentifiers removeAllObjects];
    NSMutableSet *adapters=NSMutableSet.set; NSMutableDictionary *domains=NSMutableDictionary.dictionary; NSMutableArray *records=NSMutableArray.array;
    for(NSDictionary *entry in entries)if([entry[@"entry_id"] isKindOfClass:NSString.class] && [entry[@"domain"] isKindOfClass:NSString.class])domains[entry[@"entry_id"]]=entry[@"domain"];
    self.nativeDiagnosticsEntry=nil;
    for (NSDictionary *entry in entries) if ([entry[@"domain"] isEqual:@"bluetooth"]) {
        NSString *entryID=HABLEString(entry[@"entry_id"]);if(!entryID.length)continue;[adapters addObject:entryID];
        if(!self.nativeDiagnosticsEntry && entryID.length<=128 && [entryID rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet]].location==NSNotFound)self.nativeDiagnosticsEntry=entryID;
    }
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
    self.registryDevices=records;self.canonicalCatalogDirty=YES; [self rebuildKnownDevices];
}
- (NSDictionary *)identifierProfileForProof:(NSDictionary *)proof {
    NSDictionary *values=[self sanitizedFingerprints:proof[@"fingerprint_profile"]];NSMutableDictionary *profile=NSMutableDictionary.dictionary;
    NSDictionary *w=proof[@"fingerprint_witness"];NSString *path=HABLEString(w[@"path"]);
    for(NSString *key in values)if([key isEqual:path] || [@[@"mac",@"uuid",@"gatt_serial",@"gatt_system_id",@"gatt_manufacturer",@"gatt_model"] containsObject:values[key][@"format"]])profile[key]=values[key];
    if(path.length && !profile[path])profile[path]=w;
    return profile;
}
- (BOOL)reconciliationProfile:(NSDictionary *)a conflictsWith:(NSDictionary *)b {
    if([HABLEIdentityEvidence identifierFingerprints:a conflictWith:b])return YES;
    for(NSString *path in a) {
        NSDictionary *left=a[path],*right=b[path];
        if([left[@"kind"] isEqual:@"standard_context"] && [right[@"kind"] isEqual:@"standard_context"] && [left[@"stable_across_sessions"] boolValue] && [right[@"stable_across_sessions"] boolValue] && ![left[@"sha256"] isEqual:right[@"sha256"]])return YES;
    }
    return NO;
}
- (void)rebuildCanonicalCatalog {
    if(!self.canonicalCatalogDirty)return;self.canonicalCatalogDirty=NO;
    NSMutableDictionary *proofs=[self.catalog mutableCopy],*aliases=NSMutableDictionary.dictionary,*profiles=NSMutableDictionary.dictionary,*index=NSMutableDictionary.dictionary,*groups=NSMutableDictionary.dictionary;
    for(NSString *address in [self.catalog.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *proof=self.catalog[address];aliases[address]=address;
        if(![proof[@"identity_kind"] isEqual:@"observed_shared"] || ![proof[@"method"] isEqual:@"gatt_fingerprint"])continue;
        NSDictionary *profile=[self identifierProfileForProof:proof];profiles[address]=profile;groups[address]=[NSMutableSet setWithObject:address];
        for(NSString *path in profile) {
            NSDictionary *value=profile[path];if(![HABLEIdentityEvidence isIdentifierFingerprint:value path:path])continue;
            NSString *scope=[value[@"format"] isEqual:@"gatt_serial"] ? HABLESerialScope(profile,path,2) : @"";if(!scope)continue;
            NSString *key=[NSString stringWithFormat:@"%@|%@|%@|%@|%@",path,value[@"format"],value[@"length"],value[@"sha256"],scope];
            NSMutableArray *addresses=index[key];if(!addresses){addresses=NSMutableArray.array;index[key]=addresses;}[addresses addObject:address];
        }
    }
    // Connected components are considered as a whole. A bridge cannot conceal
    // a contradiction between its endpoints. Very common witnesses are not
    // sufficiently discriminating for automatic reconciliation.
    for(NSString *key in [index.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray *addresses=index[key];if(addresses.count<2 || addresses.count>32)continue;
        NSMutableSet *combined=NSMutableSet.set;
        for(NSString *address in addresses)[combined unionSet:groups[address]];
        for(NSString *address in combined)groups[address]=combined;
    }
    NSMutableSet *visited=NSMutableSet.set;
    for(NSString *address in [groups.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if([visited containsObject:address])continue;NSSet *group=groups[address];[visited unionSet:group];if(group.count<2)continue;
        NSArray *members=[group.allObjects sortedArrayUsingSelector:@selector(compare:)];BOOL conflict=NO;
        for(NSUInteger i=0;i<members.count;i++)for(NSUInteger j=i+1;j<members.count;j++)if([self reconciliationProfile:profiles[members[i]] conflictsWith:profiles[members[j]]])conflict=YES;
        NSMutableSet *registered=NSMutableSet.set;
        for(NSDictionary *device in self.registryDevices)for(NSString *known in device[@"addresses"])if([group containsObject:known])[registered addObject:known];
        if(conflict || registered.count>1)continue;
        NSString *canonical=registered.anyObject ?: members.firstObject;NSMutableDictionary *merged=[self.catalog[canonical] mutableCopy],*fields=NSMutableDictionary.dictionary;NSMutableSet *sources=NSMutableSet.set;
        for(NSString *member in members) {
            [sources addObjectsFromArray:self.catalog[member][@"supporting_sources"] ?: @[]];
            for(NSString *path in profiles[member]) {
                NSDictionary *value=profiles[member][path],*old=fields[path];
                if(!old || [value[@"varying"] boolValue] || (![old[@"varying"] boolValue] && [value[@"sessions"] unsignedIntegerValue]>[old[@"sessions"] unsignedIntegerValue]))fields[path]=value;
            }
        }
        if(fields.count>32 || sources.count>32)continue;
        merged[@"canonical_origin_proof"]=self.catalog[canonical][@"canonical_origin_proof"] ?: self.catalog[canonical];merged[@"fingerprint_profile"]=fields;merged[@"supporting_sources"]=[sources.allObjects sortedArrayUsingSelector:@selector(compare:)];merged[@"lineage"]=merged[@"supporting_sources"];merged[@"canonical_aliases"]=members;
        if(![self validBinding:merged])continue;
        for(NSString *member in members){aliases[member]=canonical;[proofs removeObjectForKey:member];}
        proofs[canonical]=merged;
    }
    self.canonicalProofs=proofs;self.canonicalAddresses=aliases;
}
- (void)rebuildKnownDevices {
    [self rebuildCanonicalCatalog];
    NSMutableArray *known=NSMutableArray.array;
    for (NSDictionary *record in self.registryDevices) {
        NSMutableSet *addresses=[NSMutableSet setWithArray:record[@"addresses"]];
        for (NSString *address in self.catalog) if ([self.catalog[address][@"device_id"] isEqual:record[@"device_id"]]) [addresses addObject:address];
        for (NSString *address in self.remoteInfo) {
            NSString *name=HABLEString(self.remoteInfo[address][@"name"]);
            for (NSArray *pair in record[@"identifiers"]) if (name.length && HABLEUnitIdentifier(pair[1]) && [name caseInsensitiveCompare:pair[1]]==NSOrderedSame) [addresses addObject:address];
        }
        NSMutableSet *normalizedAddresses=NSMutableSet.set;
        for(NSString *address in addresses)[normalizedAddresses addObject:self.canonicalAddresses[address] ?: address];
        addresses=normalizedAddresses;
        BOOL hasUnit=NO;for(NSArray *pair in record[@"identifiers"])if(HABLEUnitIdentifier(pair[1]))hasUnit=YES;
        if (!addresses.count && ![record[@"serial_number"] length] && !hasUnit) continue;
        for (NSString *address in addresses.count ? addresses.allObjects : @[@""]) { NSMutableDictionary *item=[record mutableCopy];item[@"address"]=address;[known addObject:item]; }
    }
    // An advertised Bluetooth identity does not require an HA device entry.
    // Keep the radio anchor separate from optional HA registration metadata.
    NSMutableSet *covered=NSMutableSet.set;
    for(NSDictionary *record in known)if([record[@"address"] length])[covered addObject:record[@"address"]];
    NSMutableSet *observed=[NSMutableSet setWithArray:self.remoteInfo.allKeys];
    for(NSString *address in self.catalog)if([@[@"observed_native",@"observed_shared"] containsObject:self.catalog[address][@"identity_kind"]])[observed addObject:address];
    for(NSString *address in observed) {
        if(self.canonicalAddresses[address] && ![self.canonicalAddresses[address] isEqual:address])continue;
        if([covered containsObject:address])continue;
        NSDictionary *remote=self.remoteInfo[address],*shared=self.canonicalProofs[address] ?: self.catalog[address];
        NSDictionary *anchor=remote[@"native_anchor"] ?: shared[@"native_anchor"];
        if([shared[@"identity_kind"] isEqual:@"observed_shared"]) {
            NSMutableDictionary *row=[shared mutableCopy];row[@"label"]=HABLEString(shared[@"name"]).length ? shared[@"name"] : address;[known addObject:row];continue;
        }
        if(!anchor)continue;
        NSString *name=HABLEString(remote[@"name"]);if(!name.length)name=HABLEString(shared[@"name"]);
        [known addObject:@{@"identity_kind":@"observed_native",@"device_id":[@"bluetooth:" stringByAppendingString:address],@"address":address,@"addresses":@[address],@"identifiers":@[],@"domains":@[],@"name":name,@"label":name.length ? name : address,@"native_anchor":anchor}];
    }
    self.knownDevices=[known sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"label"] localizedCaseInsensitiveCompare:b[@"label"]];}];
}
- (BOOL)validBinding:(NSDictionary *)binding {
    uint64_t address;
    if (![binding isKindOfClass:NSDictionary.class] || ![binding[@"profile"] isKindOfClass:NSDictionary.class] || ![binding[@"lineage"] isKindOfClass:NSArray.class] || [binding[@"lineage"] count]>32 || ![binding[@"schema"] isEqual:@2] || !HABLEParseAddress(HABLEString(binding[@"address"]),&address) || ![binding[@"proof_id"] isKindOfClass:NSString.class]) return NO;
    if (![@[@"embedded_address",@"serial",@"named_identifier",@"packet_sequence",@"confirmed",@"gatt_fingerprint"] containsObject:binding[@"method"]]) return NO;
    if([binding[@"method"] isEqual:@"gatt_fingerprint"]) {
        if(binding[@"fingerprint_profile"] && (![binding[@"fingerprint_profile"] isKindOfClass:NSDictionary.class] || [binding[@"fingerprint_profile"] count]>32))return NO;
        NSDictionary *witness=binding[@"fingerprint_witness"];if(![witness isKindOfClass:NSDictionary.class])return NO;NSString *path=HABLEString(witness[@"path"]),*hash=HABLEString(witness[@"sha256"]);id sources=binding[@"supporting_sources"];
        if(![witness isKindOfClass:NSDictionary.class] || path.length>512 || hash.length!=64 || !HABLEHexData(hash) || ![HABLEIdentityEvidence isIdentifierFingerprint:witness path:path] || ![sources isKindOfClass:NSArray.class] || [sources count]>32 || [sources count]<1)return NO;
        if([witness[@"format"] isEqual:@"gatt_serial"] && ![HABLESerialScope(binding[@"fingerprint_profile"],path,2) isEqual:witness[@"scope_hash"]])return NO;
        NSMutableSet *unique=NSMutableSet.set;for(id source in sources){if(![source isKindOfClass:NSString.class] || ![source length] || [source length]>128)return NO;[unique addObject:source];}if(unique.count!=[sources count])return NO;
    }
    if([binding[@"identity_kind"] isEqual:@"observed_shared"]) {
        if(![binding[@"method"] isEqual:@"gatt_fingerprint"])return NO;
        NSDictionary *w=binding[@"fingerprint_witness"];NSString *identity=HABLEFingerprintIdentity(w);
        return [binding[@"device_id"] isEqual:identity] && [binding[@"address"] isEqual:HABLESharedFingerprintAddress(identity)];
    }
    if([binding[@"identity_kind"] isEqual:@"observed_native"]) {
        NSDictionary *anchor=binding[@"native_anchor"];
        if(![anchor isKindOfClass:NSDictionary.class] || ![anchor[@"address"] isEqual:binding[@"address"]] || ![binding[@"device_id"] isEqual:[@"bluetooth:" stringByAppendingString:binding[@"address"]]])return NO;
        NSString *source=HABLEString(anchor[@"source"]);
        if(!source.length || [source isEqual:self.sourceAddress] || [self.proxySources containsObject:source] || !HABLEHexData(anchor[@"raw"]).length)return NO;
        return [@[@"embedded_address",@"packet_sequence",@"confirmed",@"gatt_fingerprint"] containsObject:binding[@"method"]];
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
    self.catalog=valid;self.canonicalCatalogDirty=YES;
    // HA's shared store has no compare-and-swap operation. Repair additions
    // lost to concurrent publishers from this peer's still-valid local proofs.
    // An existing address is never overwritten by this reconciliation.
    for (NSDictionary *binding in self.localBindings.allValues) {
        NSString *address=binding[@"address"];NSDictionary *repair=binding;
        if(binding[@"canonical_aliases"]) {
            repair=binding[@"canonical_origin_proof"];
            if(![repair isKindOfClass:NSDictionary.class] || ![repair[@"address"] isEqual:address])continue;
        }
        if ([self validBinding:repair] && !self.catalog[address] && self.pendingPublications.count<512) self.pendingPublications[address]=repair;
    }
    [self rebuildKnownDevices];
}
- (void)loadLocalBindings {
    [self loadPeerPassiveContinuity];
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
- (NSString *)peerContinuityContext {
    return HABLEHash([NSString stringWithFormat:@"%@|%@|%@",self.sourceServer ?: @"",self.scope ?: @"",self.sourceAddress ?: @""]);
}
- (void)savePeerPassiveContinuity {
    if(!self.scope.length || ![self sourceIsCurrent])return;
    NSMutableDictionary *entries=NSMutableDictionary.dictionary;
    for(NSString *identifier in self.peerPassiveContinuity) {
        NSDictionary *match=self.peerPassiveContinuity[identifier];
        if(![match[@"continuity_context"] isEqual:[self peerContinuityContext]])continue;
        entries[identifier]=@{@"signature":match[@"passive_signature"],@"sources":match[@"supporting_sources"]};
    }
    [NSUserDefaults.standardUserDefaults setObject:@{@"schema":@1,@"context":[self peerContinuityContext],@"entries":entries} forKey:HABLEPeerContinuityKey];
}
- (void)loadPeerPassiveContinuity {
    [self.peerPassiveContinuity removeAllObjects];
    NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:HABLEPeerContinuityKey];
    if(![saved[@"schema"] isEqual:@1] || ![saved[@"context"] isEqual:[self peerContinuityContext]] || ![saved[@"entries"] isKindOfClass:NSDictionary.class])return;
    for(id identifier in saved[@"entries"]) {
        if(self.peerPassiveContinuity.count>=256)break;
        if(![identifier isKindOfClass:NSString.class] || ![identifier length] || [identifier length]>128)continue;
        id row=saved[@"entries"][identifier];if(![row isKindOfClass:NSDictionary.class])continue;
        NSString *signature=HABLEString(row[@"signature"]);id sources=row[@"sources"];
        if(signature.length!=64 || !HABLEHexData(signature) || ![sources isKindOfClass:NSArray.class] || [sources count]<2 || [sources count]>32)continue;
        NSMutableSet *unique=NSMutableSet.set;BOOL valid=YES;
        for(id source in sources){uint64_t address;if(![source isKindOfClass:NSString.class] || !HABLEParseAddress(source,&address)){valid=NO;break;}[unique addObject:source];}
        if(!valid || unique.count!=[sources count] || ![unique containsObject:self.sourceAddress])continue;
        self.peerPassiveContinuity[identifier]=@{@"continuity_context":[self peerContinuityContext],@"passive_signature":signature,@"supporting_sources":[unique.allObjects sortedArrayUsingSelector:@selector(compare:)]};
    }
}
- (void)forgetPeerPassiveContinuity:(NSString *)identifier {
    if(!self.peerPassiveContinuity[identifier])return;
    [self.peerPassiveContinuity removeObjectForKey:identifier];[self savePeerPassiveContinuity];
}
- (void)observeAdvertisements:(NSArray *)advertisements {
    BOOL inventoryChanged=NO;
    for (NSDictionary *ad in advertisements) {
        NSString *address=HABLEString(ad[@"address"]).uppercaseString,*source=HABLEString(ad[@"source"]).uppercaseString;uint64_t numeric;
        if (!HABLEParseAddress(address,&numeric) || !source.length || [self.proxySources containsObject:source] || [source isEqual:self.sourceAddress]) continue;
        // Retired-subscription deliveries and old snapshots cannot regress
        // the current source timestamp or replace newer payload evidence.
        if(self.remoteInfo[address] && [ad[@"time"] doubleValue]<[self.remoteInfo[address][@"time"] doubleValue])continue;
        if(self.remoteInfo.count>=256 && !self.remoteInfo[address]) {
            NSString *oldest=HABLEEvictionKey(self.remoteInfo,@"time",[ad[@"time"] doubleValue]);
            if(!oldest)continue;[self.remoteInfo removeObjectForKey:oldest];inventoryChanged=YES;
        }
        NSData *raw=HABLEHexData(ad[@"raw"]); NSArray *tokens=[HABLEIdentityEvidence tokensForRawAdvertisement:raw];
        NSMutableDictionary *info=[ad mutableCopy];info[@"tokens"]=tokens;
        NSUInteger length=0;for(NSString *token in tokens)if([token hasPrefix:@"m:"])length=[[[NSData alloc]initWithBase64EncodedString:[token substringFromIndex:[token rangeOfString:@":" options:NSBackwardsSearch].location+1] options:0]length];
        info[@"profile"]=@{@"name":HABLEString(ad[@"name"]),@"services":[HABLEIdentityEvidence canonicalServices:ad[@"service_uuids"]],@"manufacturer_length":@(length)};
        NSDictionary *anchor=HABLEHexData(ad[@"raw"]).length ? @{@"address":address,@"source":source,@"raw":ad[@"raw"]} : self.remoteInfo[address][@"native_anchor"];
        if(anchor)info[@"native_anchor"]=anchor;
        NSDictionary *previous=self.remoteInfo[address];
        if(!previous || ![HABLEString(previous[@"name"]) isEqual:HABLEString(info[@"name"])] || (!previous[@"native_anchor"] && anchor))inventoryChanged=YES;
        if(![previous[@"source"] isEqual:source])previous=nil;
        HABLETrackPassiveSignature(info,previous,HABLEPassiveSignature(info[@"profile"],tokens),[ad[@"time"] doubleValue],[previous[@"time"] doubleValue]);
        self.remoteInfo[address]=info;
        // A merged manufacturer-data dictionary is metadata, not a packet trace.
        if (tokens.count && [ad[@"time"] isKindOfClass:NSNumber.class]) [self.evidence recordRemoteTokens:tokens address:address source:source atTime:[ad[@"time"] doubleValue]];
    }
    if(inventoryChanged)[self rebuildKnownDevices];
}
- (NSString *)inventoryKey:(NSString *)source { return [@"ha_dashboard.ble_inventory.v1." stringByAppendingString:source]; }
- (NSArray *)sanitizedInventoryTokens:(id)value {
    if(![value isKindOfClass:NSArray.class] || [value count]>16)return @[];
    NSMutableArray *result=NSMutableArray.array;
    for(id token in value) {
        if(![token isKindOfClass:NSString.class] || [token length]>4096 || (![token hasPrefix:@"m:"] && ![token hasPrefix:@"s:"]))return @[];
        NSRange colon=[token rangeOfString:@":" options:NSBackwardsSearch];NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[token substringFromIndex:colon.location+1] options:0];
        if(bytes.length<4 || bytes.length>2048)return @[];[result addObject:token];
    }
    return result;
}
- (NSDictionary *)sanitizedFingerprints:(id)input {
    if(![input isKindOfClass:NSDictionary.class])return @{};
    NSMutableDictionary *result=NSMutableDictionary.dictionary;
    for(id key in [[input allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [[a description] compare:[b description]];}]) {
        if(result.count>=32)break;id value=input[key];
        if(![key isKindOfClass:NSString.class] || [key length]>512 || ![value isKindOfClass:NSDictionary.class])continue;
        NSString *hash=HABLEString(value[@"sha256"]);
        if(hash.length!=64 || !HABLEHexData(hash) || ![value[@"length"] isKindOfClass:NSNumber.class] || [value[@"length"] unsignedIntegerValue]>1024 || ![value[@"length"] unsignedIntegerValue])continue;
        result[key]=@{@"sha256":hash.lowercaseString,@"length":value[@"length"],@"format":[@[@"mac",@"uuid",@"gatt_serial",@"gatt_system_id",@"gatt_manufacturer",@"gatt_model"] containsObject:value[@"format"]] ? value[@"format"] : @"scalar",@"kind":[@[@"opaque",@"json_scalar",@"standard_identifier",@"standard_context"] containsObject:value[@"kind"]] ? value[@"kind"] : @"unknown",@"stable_across_sessions":@([value[@"stable_across_sessions"] isKindOfClass:NSNumber.class] && [value[@"stable_across_sessions"] boolValue] && [value[@"sessions"] isKindOfClass:NSNumber.class] && [value[@"sessions"] unsignedIntegerValue]>=2 && [value[@"varying"] isKindOfClass:NSNumber.class] && ![value[@"varying"] boolValue]),@"varying":@(![value[@"varying"] isKindOfClass:NSNumber.class] || [value[@"varying"] boolValue]),@"sessions":@([value[@"sessions"] isKindOfClass:NSNumber.class] ? MIN(255,[value[@"sessions"] unsignedIntegerValue]) : 0)};
    }
    return result;
}
- (NSArray *)localInventoryAtTime:(NSTimeInterval)now {
    NSMutableArray *result=NSMutableArray.array;NSArray *identifiers=[self.localObservations.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger bytes=0,visited=0,count=identifiers.count;
    while(visited<count) {
        NSString *identifier=identifiers[(self.inventoryCursor+visited)%count];visited++;
        NSDictionary *observation=self.localObservations[identifier];NSString *alias=HABLEString(observation[@"local_address"]);uint64_t address;
        if(now-[observation[@"last_seen"] doubleValue]>120 || !HABLEParseAddress(alias,&address))continue;
        NSMutableDictionary *row=[@{@"local_address":alias,@"last_seen":observation[@"last_seen"],@"profile":HABLEProfile(observation),@"tokens":[HABLEIdentityEvidence tokensForObservation:observation],@"fingerprints":[self sanitizedFingerprints:observation[@"gatt_fingerprints"]]} mutableCopy];
        NSDictionary *binding=self.localBindings[identifier];
        if(binding && [self validBinding:binding] && [self.catalog[binding[@"address"]][@"proof_id"] isEqual:binding[@"proof_id"]]) {
            row[@"address"]=binding[@"address"];row[@"proof_id"]=binding[@"proof_id"];row[@"lineage"]=binding[@"lineage"];
        }
        NSData *encoded=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
        if(encoded.length>16384){row[@"fingerprints"]=@{};row[@"fingerprints_truncated"]=@YES;encoded=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];}
        if(encoded.length>16384){row[@"tokens"]=@[];row[@"advertisement_truncated"]=@YES;encoded=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];}
        if(!encoded || encoded.length>16384)continue;
        if(bytes+encoded.length>131072){visited--;break;}
        bytes+=encoded.length;[result addObject:row];
    }
    self.inventoryPartial=visited<count;
    if(count)self.inventoryCursor=(self.inventoryCursor+MAX(1,visited))%count;
    return result;
}
- (void)observeInventory:(id)value source:(NSString *)source {
    if(HABLEIgnorePeerObservations())return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(![self.proxySources containsObject:source] || [source isEqual:self.sourceAddress] || ![value isKindOfClass:NSDictionary.class] || ![value[@"schema"] isEqual:@1] || ![value[@"source"] isEqual:source] || ![value[@"time"] isKindOfClass:NSNumber.class] || ![value[@"observations"] isKindOfClass:NSArray.class] || [value[@"observations"] count]>256)return;
    double time=[value[@"time"] doubleValue];if(!isfinite(time) || time<now-90 || time>now+5)return;
    NSMutableDictionary *inventory=self.peerInventories[source];if(!inventory){inventory=NSMutableDictionary.dictionary;self.peerInventories[source]=inventory;}
    for(NSString *alias in inventory.allKeys)if(now-[inventory[alias][@"last_seen"] doubleValue]>120)[inventory removeObjectForKey:alias];
    for(id item in value[@"observations"]) {
        if(![item isKindOfClass:NSDictionary.class] || ![item[@"last_seen"] isKindOfClass:NSNumber.class] || ![item[@"profile"] isKindOfClass:NSDictionary.class])continue;
        NSString *alias=HABLEString(item[@"local_address"]);uint64_t address;double seen=[item[@"last_seen"] doubleValue];
        if(!HABLEParseAddress(alias,&address) || !isfinite(seen) || seen<now-120 || seen>now+5)continue;
        alias=HABLEAddressString(address);
        NSDictionary *profile=item[@"profile"];NSString *name=HABLEString(profile[@"name"]);if(name.length>128)continue;
        NSArray *services=[HABLEIdentityEvidence canonicalServices:profile[@"services"]];if(services.count>128)continue;
        NSUInteger length=[profile[@"manufacturer_length"] isKindOfClass:NSNumber.class] ? [profile[@"manufacturer_length"] unsignedIntegerValue] : 0;if(length>2048)continue;
        NSMutableDictionary *row=[@{@"source":source,@"local_address":alias,@"last_seen":@(seen),@"profile":@{@"name":name,@"services":services,@"manufacturer_length":@(length)},@"tokens":[self sanitizedInventoryTokens:item[@"tokens"]],@"fingerprints":[self sanitizedFingerprints:item[@"fingerprints"]]} mutableCopy];
        NSDictionary *proof=self.catalog[HABLEString(item[@"address"])];
        if([self validBinding:proof] && [proof[@"proof_id"] isEqual:item[@"proof_id"]] && [item[@"lineage"] isKindOfClass:NSArray.class] && [item[@"lineage"] count]<=32 && ![item[@"lineage"] containsObject:self.sourceAddress]) {
            row[@"address"]=proof[@"address"];row[@"proof_id"]=proof[@"proof_id"];row[@"lineage"]=item[@"lineage"];
        }
        if(inventory.count<256 || inventory[alias])inventory[alias]=row;
    }
}
- (NSArray *)peerObservationsForObservation:(NSDictionary *)observation {
    NSMutableArray *result=NSMutableArray.array;NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSDictionary *profile=HABLEProfile(observation);
    for(NSString *source in self.peerInventories)if([self.proxySources containsObject:source])for(NSDictionary *row in [self.peerInventories[source] allValues])if(now-[row[@"last_seen"] doubleValue]<=120) {
        NSString *name=HABLEString(profile[@"name"]);
        BOOL sameName=name.length && ![name isEqual:@"Unnamed device"] && [name caseInsensitiveCompare:HABLEString(row[@"profile"][@"name"])]==NSOrderedSame;
        if(sameName || HABLEProfilesCompatible(profile,row[@"profile"]))[result addObject:row];
    }
    return result;
}
- (NSDictionary *)inventoryDiagnostics {
    NSUInteger sources=0,observations=0;NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSString *source in self.peerInventories)if([self.proxySources containsObject:source]) {
        NSUInteger count=0;for(NSDictionary *row in [self.peerInventories[source] allValues])if(now-[row[@"last_seen"] doubleValue]<=120)count++;
        if(count){sources++;observations+=count;}
    }
    return @{@"peer_observations_disabled":@(HABLEIgnorePeerObservations()),@"peer_sources":@(sources),@"peer_observations":@(observations),@"last_publish":@(self.lastInventoryPublish),@"publish_error":@(self.inventoryPublishError),@"partial_batch":@(self.inventoryPartial),@"native_snapshot_received_at":@(self.lastNativeSnapshot),@"native_diagnostics_at":@(self.lastNativeDiagnostics),@"native_diagnostics_error":@(self.nativeDiagnosticsError),@"native_diagnostics_observations":@(self.nativeDiagnosticsObservations)};
}
- (void)maintainInventory {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSString *source in self.peerInventories.allKeys) {
        if(![self.proxySources containsObject:source]){[self.peerInventories removeObjectForKey:source];continue;}
        NSMutableDictionary *rows=self.peerInventories[source];
        for(NSString *alias in rows.allKeys)if(now-[rows[alias][@"last_seen"] doubleValue]>120)[rows removeObjectForKey:alias];
        if(!rows.count)[self.peerInventories removeObjectForKey:source];
    }
    if(self.inventoryPublishing || now<self.nextInventoryPublish)return;
    self.nextInventoryPublish=now+30;self.inventoryPublishing=YES;NSUInteger generation=self.generation;
    NSDictionary *value=@{@"schema":@1,@"source":self.sourceAddress ?: @"",@"time":@(now),@"observations":[self localInventoryAtTime:now]};
    if(self.inventoryPartial)self.nextInventoryPublish=now+3;
    __weak typeof(self) weakSelf=self;
    [self.connection sendCommand:@{@"type":@"frontend/set_system_data",@"key":[self inventoryKey:self.sourceAddress],@"value":value} completion:^(id response,NSError *error){HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation)return;self.inventoryPublishing=NO;self.inventoryPublishError=error ? error.code : 0;if(error)self.nextInventoryPublish=NSDate.date.timeIntervalSince1970+60;else self.lastInventoryPublish=NSDate.date.timeIntervalSince1970;}];
}
- (NSString *)peerKey:(NSString *)source { return [@"ha_dashboard.ble_observations.v2." stringByAppendingString:source]; }
- (void)observePeer:(id)value source:(NSString *)source {
    if(HABLEIgnorePeerObservations())return;
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
                    [self publishBinding:binding];self.catalog[binding[@"address"]]=binding;self.canonicalCatalogDirty=YES;[self rebuildKnownDevices];
                }
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group,dispatch_get_main_queue(),^{HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent])completion();});
}
- (HAAPIClient *)nativeDiagnosticsAPIClient {
    if(!self.nativeDiagnosticsClient) {
        HAAuthManager *auth=HAAuthManager.sharedManager;
        if(!auth.restBaseURL || !auth.accessToken.length)return nil;
        self.nativeDiagnosticsClient=[[HAAPIClient alloc] initWithBaseURL:auth.restBaseURL token:auth.accessToken];
    }
    return self.nativeDiagnosticsClient;
}
- (void)refreshNativeScannerDiagnostics {
    if([NSUserDefaults.standardUserDefaults boolForKey:@"HABLEIdentitySharedOnly"] || !self.nativeDiagnosticsEntry.length || self.nativeDiagnosticsInFlight || ![self sourceIsCurrent] || !self.connection.connected)return;
    NSTimeInterval requested=NSDate.date.timeIntervalSince1970;if(requested<self.nextNativeDiagnostics)return;
    self.nextNativeDiagnostics=requested+60;HAAPIClient *client=[self nativeDiagnosticsAPIClient];if(!client)return;
    self.nativeDiagnosticsInFlight=YES;NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    [client getJSONAtPath:[@"diagnostics/config_entry/" stringByAppendingString:self.nativeDiagnosticsEntry] completion:^(id response,NSError *error){
        HABLEIdentityResolver *self=weakSelf;if(!self || generation!=self.generation || ![self sourceIsCurrent])return;
        self.nativeDiagnosticsInFlight=NO;self.nativeDiagnosticsError=error.code;
        if(error){self.nextNativeDiagnostics=NSDate.date.timeIntervalSince1970+120;return;}
        // Retain only BLE observations. The diagnostics envelope, adapter
        // internals and unrelated server data are never stored or published.
        NSMutableArray *observations=NSMutableArray.array;
        for(NSDictionary *row in [HABLEIdentityEvidence nativeObservationsFromDiagnostics:response requestedAt:requested])if(![self.proxySources containsObject:row[@"source"]] && ![row[@"source"] isEqual:self.sourceAddress])[observations addObject:row];
        self.lastNativeDiagnostics=NSDate.date.timeIntervalSince1970;self.nativeDiagnosticsObservations=observations.count;
        [self observeAdvertisements:observations];
    }];
}
- (void)refreshNativeAdvertisements {
    if([NSUserDefaults.standardUserDefaults boolForKey:@"HABLEIdentitySharedOnly"] || ![self sourceIsCurrent] || !self.connection.connected)return;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;if(now<self.nextNativeSnapshot)return;
    self.nextNativeSnapshot=now+30;
    if(self.nativeSubscription) {
        [self.connection unsubscribeFromEventWithId:self.nativeSubscription];
        [self.subscriptions removeObject:@(self.nativeSubscription)];
    }
    NSUInteger generation=self.generation,epoch=++self.nativeSubscriptionEpoch;__weak typeof(self) weakSelf=self;
    self.nativeSubscription=[self.connection subscribeWithCommand:@{@"type":@"bluetooth/subscribe_advertisements"} handler:^(NSDictionary *event){
        HABLEIdentityResolver *self=weakSelf;
        if(!self || generation!=self.generation || epoch!=self.nativeSubscriptionEpoch || ![self sourceIsCurrent])return;
        if([event[@"add"] isKindOfClass:NSArray.class]) {
            self.lastNativeSnapshot=NSDate.date.timeIntervalSince1970;
            [self observeAdvertisements:event[@"add"]];
        }
    }];
    [self.subscriptions addObject:@(self.nativeSubscription)];
}
- (void)startSubscriptions {
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;HAConnectionManager *connection=self.connection;
    [self refreshNativeAdvertisements];
    NSInteger n=[connection subscribeWithCommand:@{@"type":@"frontend/subscribe_system_data",@"key":HABLECatalogKey} handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent])[self loadCatalog:event[@"value"]];}];[self.subscriptions addObject:@(n)];
    n=[connection subscribeToEventType:@"device_registry_updated" handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation)self.needsRegistryRefresh=YES;}];[self.subscriptions addObject:@(n)];
    NSUInteger count=0;for(NSString *source in self.proxySources) {
        if([source isEqual:self.sourceAddress])continue;if(++count>16)break;
        n=[connection subscribeWithCommand:@{@"type":@"frontend/subscribe_system_data",@"key":[self peerKey:source]} handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent])[self observePeer:event[@"value"] source:source];}];[self.subscriptions addObject:@(n)];
        n=[connection subscribeWithCommand:@{@"type":@"frontend/subscribe_system_data",@"key":[self inventoryKey:source]} handler:^(NSDictionary *event){HABLEIdentityResolver *self=weakSelf;if(self && generation==self.generation && [self sourceIsCurrent])[self observeInventory:event[@"value"] source:source];}];[self.subscriptions addObject:@(n)];
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
- (NSString *)passiveSignatureForObservation:(NSDictionary *)observation {
    NSDictionary *profile=HABLEProfile(observation);NSArray *tokens=[HABLEIdentityEvidence tokensForObservation:observation];
    NSString *fullSignature=HABLEPassiveSignature(profile,tokens);if(!fullSignature)return nil;
    NSString *signature=nil;NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSDictionary *remote in self.remoteInfo.allValues) {
        if(!remote[@"native_anchor"] || [self.proxySources containsObject:remote[@"source"]] || now-[remote[@"time"] doubleValue]>120 || [remote[@"time"] doubleValue]>now+5)continue;
        if(![profile[@"name"] isEqual:remote[@"profile"][@"name"]] || ![profile[@"services"] isEqual:remote[@"profile"][@"services"]] || ![HABLEIdentityEvidence tokens:tokens extendCompleteTokens:remote[@"tokens"]])continue;
        NSString *candidate=HABLEPassiveSignature(profile,remote[@"tokens"]);if(!candidate)continue;
        if(signature && ![signature isEqual:candidate])return nil;
        signature=candidate;
    }
    return signature ?: fullSignature;
}
- (void)recordObservation:(NSDictionary *)observation identifier:(NSString *)identifier {
    if(!identifier.length)return;
    if(self.localObservations.count>=256 && !self.localObservations[identifier]) {
        NSString *oldest=HABLEEvictionKey(self.localObservations,@"last_seen",[observation[@"last_seen"] doubleValue]);
        if(!oldest)return;[self removeIdentifier:oldest];
    }
    NSMutableDictionary *record=[observation mutableCopy];NSDictionary *previous=self.localObservations[identifier];
    HABLETrackPassiveSignature(record,previous,[self passiveSignatureForObservation:observation],[observation[@"last_seen"] doubleValue],[previous[@"last_seen"] doubleValue]);
    self.localObservations[identifier]=record;[self.evidence recordLocal:observation identifier:identifier atTime:[observation[@"last_seen"] doubleValue]];
}
- (NSString *)evidenceForIdentifier:(NSString *)identifier { return self.lastEvidence[identifier] ?: @"Waiting for sufficient identity evidence"; }
- (void)removeIdentifier:(NSString *)identifier { [self forgetPeerPassiveContinuity:identifier]; [self.potentialKnownIdentifiers removeObject:identifier]; [self.lastEvidence removeObjectForKey:identifier]; [self.localObservations removeObjectForKey:identifier];[self.evidence removeIdentifier:identifier]; }
- (NSString *)registeredIdentifierForName:(NSString *)name record:(NSDictionary *)record {
    if(!HABLEUnitIdentifier(name))return nil;
    for(NSArray *pair in record[@"identifiers"])if([name caseInsensitiveCompare:pair[1]]==NSOrderedSame)return pair[1];
    return nil;
}
- (NSDictionary *)fingerprintWitnessForProof:(NSDictionary *)proof observation:(NSDictionary *)observation {
    if([HABLEIdentityEvidence identifierFingerprints:observation[@"gatt_fingerprints"] conflictWith:proof[@"fingerprint_profile"]])return nil;
    NSMutableDictionary *profile=[proof[@"fingerprint_profile"] mutableCopy] ?: NSMutableDictionary.dictionary;
    NSDictionary *root=proof[@"fingerprint_witness"];NSString *rootPath=HABLEString(root[@"path"]);
    if(rootPath.length && !profile[rootPath])profile[rootPath]=root;
    for(NSString *path in [profile.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *reference=profile[path],*value=observation[@"gatt_fingerprints"][path];
        if(![HABLEIdentityEvidence isIdentifierFingerprint:reference path:path] || !value || [value[@"varying"] boolValue] || [value[@"sessions"] unsignedIntegerValue]<1)continue;
        if([reference[@"sha256"] isEqual:value[@"sha256"]] && [reference[@"format"] isEqual:value[@"format"]] && [reference[@"length"] isEqual:value[@"length"]]) {
            NSMutableDictionary *witness=[reference mutableCopy];witness[@"path"]=path;
            if([reference[@"format"] isEqual:@"gatt_serial"]) {
                NSString *scope=HABLESerialScope(profile,path,2);
                if(!scope || ![scope isEqual:HABLESerialScope(observation[@"gatt_fingerprints"],path,1)])continue;
                witness[@"scope_hash"]=scope;
            }
            return witness;
        }
    }
    return nil;
}
- (BOOL)proof:(NSDictionary *)proof matches:(NSDictionary *)observation {
    NSString *method=proof[@"method"];
    if([method isEqual:@"gatt_fingerprint"])return [self fingerprintWitnessForProof:proof observation:observation]!=nil;
    if([method isEqual:@"embedded_address"] && [proof[@"identity_kind"] isEqual:@"observed_native"])return [HABLEIdentityEvidence observation:observation containsAddress:proof[@"address"]] && HABLEProfilesCompatible(HABLEProfile(observation),proof[@"profile"]) && [HABLEIdentityEvidence tokens:[HABLEIdentityEvidence tokensForObservation:observation] corroborateAddress:proof[@"address"] withTokens:[HABLEIdentityEvidence tokensForRawAdvertisement:HABLEHexData(proof[@"native_anchor"][@"raw"])]];
    if([method isEqual:@"embedded_address"])return [HABLEIdentityEvidence observation:observation containsAddress:proof[@"address"]];
    if([method isEqual:@"serial"])return [observation[@"serial_number"] isEqual:proof[@"unit_identifier"]];
    if([method isEqual:@"named_identifier"])return [HABLEString(observation[@"name"]) caseInsensitiveCompare:HABLEString(proof[@"unit_identifier"])]==NSOrderedSame && [HABLEIdentityEvidence tokensForObservation:observation].count && HABLEProfilesCompatible(HABLEProfile(observation),proof[@"profile"]);
    return NO;
}
- (BOOL)reconciledBindingIsCurrent:(NSDictionary *)binding address:(NSString *)address {
    id members=binding[@"canonical_aliases"];if(!members)return YES;
    if(![members isKindOfClass:NSArray.class] || [members count]>512)return NO;
    for(id member in members) {
        if(![member isKindOfClass:NSString.class])return NO;
        NSString *canonical=self.canonicalAddresses[member];
        if(canonical && ![canonical isEqual:address])return NO;
    }
    NSDictionary *current=self.canonicalProofs[address];
    return !current || ![self reconciliationProfile:[self identifierProfileForProof:binding] conflictsWith:[self identifierProfileForProof:current]];
}
- (NSArray *)candidatesForObservation:(NSDictionary *)observation {
    NSMutableArray *result=NSMutableArray.array;NSString *identifier=observation[@"identifier"],*name=HABLEString(observation[@"name"]),*serial=HABLEString(observation[@"serial_number"]);NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSDictionary *profile=HABLEProfile(observation);NSArray *tokens=[HABLEIdentityEvidence tokensForObservation:observation];
    for(NSDictionary *known in self.knownDevices) {
        NSString *address=known[@"address"];NSDictionary *remote=self.remoteInfo[address],*shared=self.canonicalProofs[address] ?: self.catalog[address];NSMutableDictionary *candidate=[known mutableCopy];NSMutableArray *reasons=NSMutableArray.array;
        if(remote[@"native_anchor"])candidate[@"native_anchor"]=remote[@"native_anchor"];
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
        if(embedded && sameName && [HABLEIdentityEvidence tokens:tokens corroborateAddress:address withTokens:remote[@"tokens"]] && compatible && fabs(now-[remote[@"time"] doubleValue])<=120 && ![self.proxySources containsObject:remote[@"source"]]){method=@"embedded_address";score+=160;[reasons addObject:@"Address occurrence corroborated by an independent radio"];}
        if(named && [HABLEString(remote[@"name"]) caseInsensitiveCompare:named]==NSOrderedSame && payload && compatible && fabs(now-[remote[@"time"] doubleValue])<=120 && ![self.proxySources containsObject:remote[@"source"]]){method=@"named_identifier";unit=named;score+=160;[reasons addObject:@"Unit identifier and current payload agree with an independent scanner"];}
        if([self validBinding:shared] && [self reconciledBindingIsCurrent:shared address:address] && [self proof:shared matches:observation]){method=shared[@"method"];unit=shared[@"unit_identifier"];score+=180;[reasons addObject:@"Verified generic HA association matches"];}
        NSDictionary *saved=self.localBindings[identifier];
        if([saved[@"address"] isEqual:address] && [self validBinding:saved] && [self reconciledBindingIsCurrent:saved address:address] && HABLEProfilesCompatible(profile,saved[@"profile"]) && (![saved[@"method"] isEqual:@"gatt_fingerprint"] || [self proof:saved matches:observation])){method=saved[@"method"];unit=saved[@"unit_identifier"];lineage=saved[@"lineage"] ?: @[];score+=180;[reasons addObject:@"Previously verified binding for this Apple peripheral"];}
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
        NSDictionary *local=self.localObservations[identifier];
        if(!method && remote[@"native_anchor"] && [name isEqual:remote[@"name"]]) {
            NSTimeInterval referenceAge=now-[remote[@"time"] doubleValue],span=[local[@"last_seen"] doubleValue]-[local[@"passive_since"] doubleValue];
            [reasons addObject:[NSString stringWithFormat:@"Passive evidence: reference %.0fs old, local span %.0fs (%lu samples), signature %@",MAX(0,referenceAge),local[@"passive_since"] ? MAX(0,span) : 0,(unsigned long)[local[@"passive_samples"] unsignedIntegerValue],[local[@"passive_signature"] isEqual:remote[@"passive_signature"]] ? @"agrees" : @"differs"]];
        }
        if(!method && remote[@"native_anchor"] && ![self.proxySources containsObject:remote[@"source"]] && HABLEPassiveReady(local,@"last_seen",now) && isfinite([remote[@"time"] doubleValue]) && [remote[@"time"] doubleValue]<=now+5 && now-[remote[@"time"] doubleValue]<=120 && [local[@"passive_signature"] isEqual:remote[@"passive_signature"]] && [local[@"passive_signature"] isEqual:[self passiveSignatureForObservation:observation]] && !(serial.length && [known[@"serial_number"] length] && ![serial isEqual:known[@"serial_number"]]) && ![HABLEIdentityEvidence identifierFingerprints:observation[@"gatt_fingerprints"] conflictWith:shared[@"fingerprint_profile"]]) {
            method=@"passive_signature";score+=80;candidate[@"passive_signature"]=local[@"passive_signature"];
            [reasons addObject:@"Provisional: exact name, services and payload agree with a fresh independent radio observation after sustained local reception; not a verified hardware identity"];
        }
        if([method isEqual:@"gatt_fingerprint"]) {
            NSDictionary *proof=[shared[@"method"] isEqual:@"gatt_fingerprint"] && [self validBinding:shared] && [self reconciledBindingIsCurrent:shared address:address] && [self proof:shared matches:observation] ? shared : saved;
            if([self validBinding:proof]){candidate[@"fingerprint_witness"]=proof[@"fingerprint_witness"];NSDictionary *witness=[self fingerprintWitnessForProof:proof observation:observation];if(witness)candidate[@"fingerprint_match_witness"]=witness;if(proof[@"fingerprint_profile"])candidate[@"fingerprint_profile"]=proof[@"fingerprint_profile"];candidate[@"supporting_sources"]=proof[@"supporting_sources"];if(proof[@"canonical_aliases"])candidate[@"canonical_aliases"]=proof[@"canonical_aliases"];if(proof[@"canonical_origin_proof"])candidate[@"canonical_origin_proof"]=proof[@"canonical_origin_proof"];}
        }
        candidate[@"automatic_match"]=@(address.length && method!=nil);candidate[@"score"]=@(score);candidate[@"method"]=method ?: @"";candidate[@"unit_identifier"]=unit ?: @"";candidate[@"profile"]=profile;candidate[@"lineage"]=lineage;candidate[@"local_identifier"]=identifier ?: @"";
        candidate[@"reference_sources"]=correlation[@"sources"] ?: (remote[@"source"] ? @[remote[@"source"]] : @[]);
        candidate[@"evidence"]=reasons.count ? [reasons componentsJoinedByString:@" · "] : @"Identity unresolved";[result addObject:candidate];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"score"] compare:a[@"score"]];}];
}
- (BOOL)fingerprintWitnessIsAmbiguous:(NSDictionary *)w observation:(NSDictionary *)observation {
    if(![w isKindOfClass:NSDictionary.class] || ![w[@"path"] isKindOfClass:NSString.class] || ![w[@"sha256"] isKindOfClass:NSString.class])return YES;
    NSString *path=w[@"path"],*hash=w[@"sha256"],*identifier=observation[@"identifier"];NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    BOOL (^sameWitness)(NSDictionary *)=^BOOL(NSDictionary *profile) {
        if(![profile[path][@"sha256"] isEqual:hash])return NO;
        if([w[@"format"] isEqual:@"gatt_serial"]) {
            NSString *scope=HABLESerialScope(profile,path,1);
            if(scope && w[@"scope_hash"] && ![scope isEqual:w[@"scope_hash"]])return NO;
        }
        return YES;
    };
    for(NSString *other in self.localObservations)if(![other isEqual:identifier]) {
        NSDictionary *o=self.localObservations[other];if(now-[o[@"last_seen"] doubleValue]<=120 && sameWitness(o[@"gatt_fingerprints"]))return YES;
    }
    NSMutableSet *references=NSMutableSet.set;
    for(NSString *source in self.peerInventories) {
        if(![self.proxySources containsObject:source])continue;NSUInteger matches=0;
        for(NSDictionary *o in [self.peerInventories[source] allValues])if(now-[o[@"last_seen"] doubleValue]<=120 && sameWitness(o[@"fingerprints"])) {
            matches++;if(o[@"address"])[references addObject:self.canonicalAddresses[o[@"address"]] ?: o[@"address"]];
        }
        if(matches>1)return YES;
    }
    return references.count>1;
}
- (NSDictionary *)sharedFingerprintMatchForObservation:(NSDictionary *)observation {
    if(![observation[@"identifier"] length])return nil;
    NSDictionary *values=[self sanitizedFingerprints:observation[@"gatt_fingerprints"]];
    for(NSString *path in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *value=values[path];if(![HABLEIdentityEvidence isIdentifierFingerprint:value path:path])continue;
        NSMutableDictionary *w=[value mutableCopy];w[@"path"]=path;
        if([value[@"format"] isEqual:@"gatt_serial"]) {
            NSString *scope=HABLESerialScope(values,path,2);
            if(!scope){self.lastEvidence[observation[@"identifier"]]=@"Serial number needs stable manufacturer and model context";continue;}
            w[@"scope_hash"]=scope;
        }
        if([self fingerprintWitnessIsAmbiguous:w observation:observation]){self.lastEvidence[observation[@"identifier"]]=@"Ambiguous: the identifier-shaped field is not unique among observed devices";continue;}
        NSMutableSet *sources=[NSMutableSet setWithObject:self.sourceAddress ?: @""];NSDictionary *reference=nil;BOOL conflictingWitness=NO;
        for(NSDictionary *row in [self peerObservationsForObservation:observation]) {
            NSDictionary *other=row[@"fingerprints"][path];
            if([value[@"format"] isEqual:@"gatt_serial"] && ![w[@"scope_hash"] isEqual:HABLESerialScope(row[@"fingerprints"],path,2)])continue;
            if([HABLEIdentityEvidence identifierFingerprints:values conflictWith:row[@"fingerprints"]]) {
                self.lastEvidence[observation[@"identifier"]]=@"Conflicting stable identifier fields across proxies";
                if([value[@"sha256"] isEqual:other[@"sha256"]]){conflictingWitness=YES;break;}
                continue;
            }
            if([HABLEIdentityEvidence isIdentifierFingerprint:other path:path] && [value[@"sha256"] isEqual:other[@"sha256"]] && [value[@"format"] isEqual:other[@"format"]]) {
                [sources addObject:row[@"source"]];if(row[@"address"] && [self validBinding:self.catalog[row[@"address"]]])reference=self.canonicalProofs[self.canonicalAddresses[row[@"address"]] ?: row[@"address"]] ?: self.catalog[row[@"address"]];
            }
        }
        if(conflictingWitness || !sources.count || [sources containsObject:@""])continue;
        NSString *identity=HABLEFingerprintIdentity(w);
        NSDictionary *existing=self.catalog[HABLESharedFingerprintAddress(identity)];
        if(!reference && existing && (![existing[@"device_id"] isEqual:identity] || [self reconciliationProfile:values conflictsWith:[self identifierProfileForProof:existing]])) {
            self.lastEvidence[observation[@"identifier"]]=@"Conflicting catalog identity; this fingerprint cannot select its address";continue;
        }
        NSMutableDictionary *match=reference ? [reference mutableCopy] : [@{@"identity_kind":@"observed_shared",@"device_id":identity,@"address":HABLESharedFingerprintAddress(identity),@"name":HABLEString(observation[@"name"]),@"label":HABLEString(observation[@"name"]),@"identifiers":@[],@"domains":@[]} mutableCopy];
        match[@"profile"]=HABLEProfile(observation);match[@"method"]=@"gatt_fingerprint";if(!match[@"fingerprint_witness"])match[@"fingerprint_witness"]=w;match[@"fingerprint_match_witness"]=w;NSMutableDictionary *combined=[reference[@"fingerprint_profile"] mutableCopy] ?: NSMutableDictionary.dictionary;[combined addEntriesFromDictionary:values];match[@"fingerprint_profile"]=combined;match[@"supporting_sources"]=[sources.allObjects sortedArrayUsingSelector:@selector(compare:)];match[@"lineage"]=match[@"supporting_sources"];match[@"reference_sources"]=match[@"supporting_sources"];match[@"automatic_match"]=@YES;match[@"local_identifier"]=observation[@"identifier"] ?: @"";match[@"unit_identifier"]=value[@"sha256"];match[@"score"]=@240;match[@"evidence"]=sources.count==1 ? @"Stable identifier-shaped GATT field repeated across read sessions on this proxy" : [NSString stringWithFormat:@"Stable identifier-shaped GATT field agrees across %lu proxies",(unsigned long)sources.count];return match;
    }
    return nil;
}
- (NSDictionary *)peerPassiveMatchForObservation:(NSDictionary *)observation {
    NSString *identifier=observation[@"identifier"];if(!identifier.length)return nil;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSDictionary *local=self.localObservations[identifier];
    NSString *signature=HABLEPassiveSignature(HABLEProfile(observation),[HABLEIdentityEvidence tokensForObservation:observation]);
    NSString *context=[self peerContinuityContext];
    NSDictionary *remembered=self.peerPassiveContinuity[identifier];
    if(remembered && (![remembered[@"continuity_context"] isEqual:context] || ![remembered[@"passive_signature"] isEqual:signature])){[self forgetPeerPassiveContinuity:identifier];remembered=nil;}
    if(!signature || ![signature isEqual:local[@"passive_signature"]] || now-[local[@"last_seen"] doubleValue]>20 || (!remembered && !HABLEPassiveReady(local,@"last_seen",now)))return nil;
    // Do not invent a competing address for an already observed native identity.
    for(NSDictionary *remote in self.remoteInfo.allValues)if(remote[@"native_anchor"] && [signature isEqual:remote[@"passive_signature"]]){[self forgetPeerPassiveContinuity:identifier];return nil;}
    for(NSString *other in self.localObservations)if(![other isEqual:identifier] && now-[self.localObservations[other][@"last_seen"] doubleValue]<=120 && [signature isEqual:HABLEPassiveSignature(HABLEProfile(self.localObservations[other]),[HABLEIdentityEvidence tokensForObservation:self.localObservations[other]])]) {
        [self forgetPeerPassiveContinuity:identifier];self.lastEvidence[identifier]=@"Ambiguous: multiple local devices share the complete peer signature";return nil;
    }
    NSMutableSet *sources=[NSMutableSet setWithObject:self.sourceAddress ?: @""];NSMutableArray *profiles=[NSMutableArray arrayWithObject:observation[@"gatt_fingerprints"] ?: @{}];
    for(NSString *source in self.peerInventories) {
        if(![self.proxySources containsObject:source] || [source isEqual:self.sourceAddress])continue;NSUInteger count=0;
        for(NSDictionary *row in [self.peerInventories[source] allValues]) {
            if(now-[row[@"last_seen"] doubleValue]>120 || ![signature isEqual:HABLEPassiveSignature(row[@"profile"],row[@"tokens"])])continue;
            if(++count>1){[self forgetPeerPassiveContinuity:identifier];self.lastEvidence[identifier]=@"Ambiguous: a peer sees multiple devices with this signature";return nil;}
            // Existing verified roots need their identifier proof, not a new
            // passive address. Never turn a peer's canonical claim into truth.
            if(row[@"address"]){[self forgetPeerPassiveContinuity:identifier];return nil;}
            NSDictionary *fields=row[@"fingerprints"] ?: @{};
            for(NSDictionary *other in profiles)if([HABLEIdentityEvidence identifierFingerprints:fields conflictWith:other]){[self forgetPeerPassiveContinuity:identifier];self.lastEvidence[identifier]=@"Ambiguous: identical advertisements have conflicting identifier fields";return nil;}
            [profiles addObject:fields];[sources addObject:source];
        }
    }
    if([sources containsObject:@""])return nil;
    BOOL peerUnavailable=sources.count<2;
    if(peerUnavailable) {
        if(!remembered)return nil;
        [sources addObjectsFromArray:remembered[@"supporting_sources"]];
    }
    NSString *identity=[@"peer-passive:" stringByAppendingString:signature];
    NSDictionary *match=@{@"continuity_context":context,@"identity_kind":@"observed_shared",@"device_id":identity,@"address":HABLESharedFingerprintAddress(identity),@"name":HABLEString(observation[@"name"]),@"label":HABLEString(observation[@"name"]),@"method":@"peer_passive_signature",@"automatic_match":@YES,@"local_identifier":identifier,@"passive_signature":signature,@"profile":HABLEProfile(observation),@"supporting_sources":[sources.allObjects sortedArrayUsingSelector:@selector(compare:)],@"score":@60,@"evidence":peerUnavailable ? @"Provisional: retaining the same local peripheral and unchanged signature while its peer is unavailable" : @"Provisional: sustained local reception and a fresh peer agree on the complete name, services and payload; not a verified hardware identity"};
    if(self.peerPassiveContinuity.count<256 || self.peerPassiveContinuity[identifier]) {
        BOOL changed=![remembered[@"passive_signature"] isEqual:signature] || ![remembered[@"supporting_sources"] isEqual:match[@"supporting_sources"]];
        self.peerPassiveContinuity[identifier]=match;if(changed)[self savePeerPassiveContinuity];
    }
    return match;
}
- (NSDictionary *)automaticMatchForObservation:(NSDictionary *)observation {
    NSDictionary *match=nil;NSArray *candidates=[self candidatesForObservation:observation];
    if([observation[@"identifier"] length] && (self.lastEvidence.count<256 || self.lastEvidence[observation[@"identifier"]]))self.lastEvidence[observation[@"identifier"]]=candidates.firstObject[@"evidence"] ?: @"No known candidate yet";
    for(NSDictionary *candidate in candidates)if([candidate[@"automatic_match"] boolValue]){if(match){[self forgetPeerPassiveContinuity:observation[@"identifier"] ?: @""];if([observation[@"identifier"] length])self.lastEvidence[observation[@"identifier"]]=@"Ambiguous: multiple known devices satisfy the identity evidence";return nil;}match=candidate;}
    if(!match)match=[self sharedFingerprintMatchForObservation:observation];
    if(match)[self forgetPeerPassiveContinuity:observation[@"identifier"] ?: @""];
    if(!match)match=[self peerPassiveMatchForObservation:observation];
    if(match && [match[@"method"] isEqual:@"gatt_fingerprint"] && [self fingerprintWitnessIsAmbiguous:match[@"fingerprint_match_witness"] ?: match[@"fingerprint_witness"] observation:observation]){if([observation[@"identifier"] length])self.lastEvidence[observation[@"identifier"]]=@"Ambiguous: this identifier fingerprint is shared by multiple devices";return nil;}
    if(!match) {
        NSUInteger peers=[self peerObservationsForObservation:observation].count;
        if(peers && [observation[@"identifier"] length])self.lastEvidence[observation[@"identifier"]]=[NSString stringWithFormat:@"%@ · %lu peer observations available; identity not yet verified",self.lastEvidence[observation[@"identifier"]] ?: @"Identity unresolved",(unsigned long)peers];
        return nil;
    }
    NSString *identifier=observation[@"identifier"];
    if([match[@"method"] isEqual:@"passive_signature"]) {
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSString *signature=match[@"passive_signature"];
        for(NSString *other in self.localObservations)if(![other isEqual:identifier] && now-[self.localObservations[other][@"last_seen"] doubleValue]<=120 && [signature isEqual:[self passiveSignatureForObservation:self.localObservations[other]]]) {
            self.lastEvidence[identifier]=@"Ambiguous: another local device has the same complete passive signature";return nil;
        }
        for(NSString *other in self.remoteInfo)if(![other isEqual:match[@"address"]] && now-[self.remoteInfo[other][@"time"] doubleValue]<=120 && [signature isEqual:self.remoteInfo[other][@"passive_signature"]]) {
            self.lastEvidence[identifier]=@"Ambiguous: another radio address has the same complete passive signature";return nil;
        }
        // Re-evaluate on every normal matching pass. Never persist this as
        // verified proof or republish it as independent radio evidence.
        return match;
    }
    if([match[@"identity_kind"] isEqual:@"observed_native"]) for(NSString *other in self.localObservations) {
        NSDictionary *peer=self.localObservations[other];
        if([other isEqual:identifier] || NSDate.date.timeIntervalSince1970-[peer[@"last_seen"] doubleValue]>120)continue;
        if(HABLEProfilesCompatible(HABLEProfile(observation),HABLEProfile(peer)) && [HABLEIdentityEvidence tokens:[HABLEIdentityEvidence tokensForObservation:observation] corroborateAddress:match[@"address"] withTokens:[HABLEIdentityEvidence tokensForObservation:peer]]) {
            self.lastEvidence[identifier]=@"Ambiguous: multiple local peripherals carry the same address-bearing payload";return nil;
        }
    }
    if([match[@"identity_kind"] isEqual:@"observed_native"] && [self.evidence hasCompetingLocalIdentifier:identifier address:match[@"address"] now:NSDate.date.timeIntervalSince1970]) {
        self.lastEvidence[identifier]=@"Ambiguous: another local peripheral shares this observed identity evidence";return nil;
    }
    if([match[@"identity_kind"] isEqual:@"observed_native"]) for(NSString *other in self.remoteInfo) {
        NSDictionary *remote=self.remoteInfo[other];
        if([other isEqual:match[@"address"]] || !remote[@"native_anchor"] || fabs(NSDate.date.timeIntervalSince1970-[remote[@"time"] doubleValue])>120)continue;
        if(HABLEProfilesCompatible(HABLEProfile(observation),remote[@"profile"]) && ([HABLEIdentityEvidence tokens:[HABLEIdentityEvidence tokensForObservation:observation] agreeWith:remote[@"tokens"]] || [HABLEIdentityEvidence tokens:[HABLEIdentityEvidence tokensForObservation:observation] corroborateAddress:match[@"address"] withTokens:remote[@"tokens"]])) {
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
    if(!known && [self peerObservationsForObservation:observation].count)known=YES;
    if(known && identifier.length && self.potentialKnownIdentifiers.count<256)[self.potentialKnownIdentifiers addObject:identifier];
    return known;
}
- (void)rememberAutomaticMatch:(NSDictionary *)match {
    if([@[@"passive_signature",@"peer_passive_signature"] containsObject:match[@"method"]])return;
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
            [self.pendingPublications removeObjectForKey:address];self.catalog[address]=binding;self.canonicalCatalogDirty=YES;[self rebuildKnownDevices];[self pumpPublications];
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
    [self refreshNativeAdvertisements]; [self refreshNativeScannerDiagnostics]; [self pumpPublications]; [self maintainInventory];
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
