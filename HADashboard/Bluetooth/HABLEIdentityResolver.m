#import "HABLEIdentityResolver.h"
#import "HABLEProto.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"

static NSData *HABLEHexData(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length % 2 || value.length > 4096) return nil;
    if ([value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound) return nil;
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i < value.length; i += 2) { unsigned v = 0; [[NSScanner scannerWithString:[value substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&v]; uint8_t b = v; [data appendBytes:&b length:1]; }
    return data;
}
static NSString *HABLEFullUUID(NSString *value) {
    NSString *uuid = value.lowercaseString;
    if (uuid.length == 4) return [NSString stringWithFormat:@"0000%@-0000-1000-8000-00805f9b34fb", uuid];
    if (uuid.length == 8) return [uuid stringByAppendingString:@"-0000-1000-8000-00805f9b34fb"];
    return uuid;
}

@interface HABLEIdentityResolver ()
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *knownDevices;
@property (nonatomic, copy, readwrite) NSString *status;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *advertisements;
@property (nonatomic, strong) NSMutableSet<NSString *> *excludedSources;
@property (nonatomic, assign) NSInteger subscription;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, copy) NSArray<NSDictionary *> *registryDevices;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *sharedBindings;
@property (nonatomic, strong) NSMutableSet<NSString *> *occupiedBindingKeys;
@property (nonatomic, strong) NSMutableSet<NSString *> *publishingBindings;
@property (nonatomic, copy) NSString *sourceServer;
@property (nonatomic, assign) NSUInteger sourceRevision;
@end

@implementation HABLEIdentityResolver
- (instancetype)init {
    if ((self = [super init])) { _knownDevices = @[]; _advertisements = [NSMutableDictionary dictionary]; _subscription = -1; _status = @"Not synchronised"; _sharedBindings = [NSMutableDictionary dictionary]; _occupiedBindingKeys = [NSMutableSet set]; _publishingBindings = [NSMutableSet set]; }
    return self;
}
- (void)dealloc { [self cancel]; }
- (void)cancel {
    self.generation++;
    if (self.subscription >= 0) [[HAConnectionManager sharedManager] unsubscribeFromEventWithId:self.subscription];
    self.subscription = -1;
}
// Registry adapters are not sensor candidates. Only our own proxy sources are
// excluded from address evidence; excluding every Bluetooth adapter also hid
// the independent ESP32/native scanners needed to recover real addresses.
- (void)loadRegistry:(NSArray *)devices entries:(NSArray *)entries excludingSource:(NSString *)source {
    self.excludedSources = [NSMutableSet setWithObject:source.uppercaseString ?: @""];
    NSMutableSet *adapters = [NSMutableSet set];
    for (NSDictionary *entry in entries) if ([entry[@"domain"] isEqual:@"bluetooth"] && [entry[@"entry_id"] isKindOfClass:[NSString class]]) [adapters addObject:entry[@"entry_id"]];
    NSMutableArray *records = [NSMutableArray array];
    for (NSDictionary *device in devices) {
        NSString *manufacturer = [device[@"manufacturer"] isKindOfClass:[NSString class]] ? [device[@"manufacturer"] lowercaseString] : @"";
        BOOL proxy = [manufacturer isEqual:@"ha-dashboard"] || [manufacturer isEqual:@"ha dashboard"] || [device[@"model"] isEqual:@"iOS CoreBluetooth proxy"];
        BOOL adapter = NO;
        for (NSString *entry in device[@"config_entries"]) if ([adapters containsObject:entry]) adapter = YES;
        if (proxy) for (NSArray *pair in device[@"connections"]) if (pair.count == 2 && [pair[1] isKindOfClass:[NSString class]]) [self.excludedSources addObject:[pair[1] uppercaseString]];
        if (proxy || adapter) continue;
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"manufacturer", @"model", @"serial_number", @"name", @"name_by_user", @"id"]) if ([device[key] isKindOfClass:[NSString class]]) record[key] = device[key];
        record[@"device_id"] = record[@"id"] ?: @"";
        record[@"label"] = record[@"name_by_user"] ?: record[@"name"] ?: record[@"device_id"];
        NSMutableArray *addresses = [NSMutableArray array], *identifiers = [NSMutableArray array];
        for (NSArray *pair in device[@"connections"]) {
            uint64_t address;
            if (pair.count == 2 && [pair[0] isEqual:@"bluetooth"] && [pair[1] isKindOfClass:[NSString class]] && HABLEParseAddress(pair[1], &address)) [addresses addObject:HABLEAddressString(address)];
        }
        for (NSArray *pair in device[@"identifiers"]) if (pair.count == 2 && [pair[0] isKindOfClass:[NSString class]] && [pair[1] isKindOfClass:[NSString class]]) {
            [identifiers addObject:pair];
            if ([pair[0] isEqual:@"blue_connect"] && [pair[1] rangeOfString:@"^B2[0-9A-F]{8}$" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) record[@"blue_connect_identifier"] = [pair[1] uppercaseString];
        }
        record[@"addresses"] = addresses; record[@"identifiers"] = identifiers;
        if (addresses.count || identifiers.count || record[@"serial_number"]) [records addObject:record];
        if (records.count >= 2048) break;
    }
    self.registryDevices = records;
    [self rebuildKnownDevices];
}
- (void)rebuildKnownDevices {
    NSMutableArray *known = [NSMutableArray array];
    for (NSDictionary *record in self.registryDevices) {
        NSMutableDictionary *addresses = [NSMutableDictionary dictionary];
        for (NSString *address in record[@"addresses"]) addresses[address] = @"registry_bluetooth";
        NSDictionary *binding = self.sharedBindings[record[@"device_id"]];
        if (binding && !addresses[binding[@"address"]]) addresses[binding[@"address"]] = @"shared_identity";
        for (NSString *address in self.advertisements) {
            NSDictionary *ad = self.advertisements[address]; NSString *name = ad[@"name"];
            if (![name isKindOfClass:[NSString class]] || !name.length) continue;
            BOOL match = [name caseInsensitiveCompare:record[@"name"] ?: @""] == NSOrderedSame;
            for (NSArray *pair in record[@"identifiers"]) if ([name caseInsensitiveCompare:pair[1]] == NSOrderedSame) match = YES;
            if (match && !addresses[address]) addresses[address] = @"independent_advertisement";
        }
        if (!addresses.count && ![record[@"blue_connect_identifier"] length] && ![record[@"serial_number"] length]) continue;
        for (NSString *address in addresses.count ? addresses.allKeys : @[@""]) {
            NSMutableDictionary *item = [record mutableCopy]; item[@"address"] = address; item[@"address_provenance"] = addresses[address] ?: @"unresolved"; [known addObject:item];
            if ([binding[@"address"] isEqual:address]) item[@"shared_identity"] = binding;
        }
    }
    self.knownDevices = [known sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"label"] localizedCaseInsensitiveCompare:b[@"label"]]; }];
}
- (NSString *)sharedKeyForDeviceID:(NSString *)deviceID { return [@"ha_dashboard.ble_identity.v1." stringByAppendingString:deviceID]; }
- (BOOL)sourceIsCurrent {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    return self.sourceServer.length && [auth.serverURL isEqual:self.sourceServer] && auth.authenticationRevision == self.sourceRevision;
}
- (void)loadSharedValue:(id)value forRecord:(NSDictionary *)record {
    NSString *deviceID = record[@"device_id"];
    if (!deviceID.length) return;
    if (value && value != [NSNull null]) [self.occupiedBindingKeys addObject:deviceID];
    uint64_t address;
    if (![value isKindOfClass:[NSDictionary class]] || ![value[@"schema"] isKindOfClass:[NSNumber class]] || [value[@"schema"] integerValue] != 1 ||
        ![value[@"profile"] isEqual:@"blue_connect-v1"] || ![value[@"device_id"] isEqual:deviceID] ||
        ![value[@"identifier"] isEqual:record[@"blue_connect_identifier"]] ||
        ![value[@"manufacturer_id"] isEqual:@305] || ![value[@"evidence_kind"] isEqual:@"independent_scanner"] ||
        ![value[@"address"] isKindOfClass:[NSString class]] || !HABLEParseAddress(value[@"address"], &address)) return;
    NSMutableDictionary *binding = [value mutableCopy]; binding[@"address"] = HABLEAddressString(address);
    self.sharedBindings[deviceID] = binding;
    [self rebuildKnownDevices];
}
- (void)loadSharedBindingsWithCompletion:(void (^)(void))completion {
    dispatch_group_t group = dispatch_group_create(); NSUInteger count = 0, generation = self.generation;
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *record in self.registryDevices) {
        NSString *deviceID = record[@"device_id"];
        if (![record[@"blue_connect_identifier"] length] || !deviceID.length || deviceID.length > 128) continue;
        if (++count > 32) break;
        dispatch_group_enter(group);
        [[HAConnectionManager sharedManager] sendCommand:@{@"type":@"frontend/get_system_data", @"key":[self sharedKeyForDeviceID:deviceID]} completion:^(id result, NSError *error) {
            HABLEIdentityResolver *self = weakSelf;
            if (self && generation == self.generation && [self sourceIsCurrent] && !error && [result isKindOfClass:[NSDictionary class]]) [self loadSharedValue:result[@"value"] forRecord:record];
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ HABLEIdentityResolver *self = weakSelf; if (self && generation == self.generation && [self sourceIsCurrent]) completion(); });
}
- (void)rememberAutomaticMatch:(NSDictionary *)match {
    NSString *deviceID = match[@"device_id"], *identifier = match[@"blue_connect_identifier"], *address = match[@"address"];
    if (!deviceID.length || deviceID.length > 128 || !identifier.length || !address.length || ![match[@"automatic_match"] boolValue] || ![self sourceIsCurrent] ||
        [self.occupiedBindingKeys containsObject:deviceID] || [self.publishingBindings containsObject:deviceID]) return;
    NSDictionary *advertisement = self.advertisements[address];
    if (![advertisement[@"name"] isKindOfClass:[NSString class]] || [advertisement[@"name"] caseInsensitiveCompare:identifier] != NSOrderedSame ||
        HABLEHexData(advertisement[@"manufacturer_data"][@"305"]).length != 11) return;
    [self.publishingBindings addObject:deviceID];
    NSUInteger generation = self.generation; __weak typeof(self) weakSelf = self;
    NSString *key = [self sharedKeyForDeviceID:deviceID];
    // Recheck before writing. Existing or conflicting records are never
    // overwritten automatically; normal concurrent discoveries are idempotent.
    [[HAConnectionManager sharedManager] sendCommand:@{@"type":@"frontend/get_system_data", @"key":key} completion:^(id result, NSError *error) {
        HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation || ![self sourceIsCurrent]) return;
        if (error || ![result isKindOfClass:[NSDictionary class]]) return;
        id existing = result[@"value"];
        if (existing && existing != [NSNull null]) { [self loadSharedValue:existing forRecord:match]; return; }
        NSDictionary *value = @{@"schema":@1, @"profile":@"blue_connect-v1", @"device_id":deviceID, @"identifier":identifier, @"address":address, @"manufacturer_id":@305,
            @"evidence_kind":@"independent_scanner", @"source":advertisement[@"source"], @"verified_at":@([[NSDate date] timeIntervalSince1970])};
        // HA enforces administrator permission for this system-store write.
        [[HAConnectionManager sharedManager] sendCommand:@{@"type":@"frontend/set_system_data", @"key":key, @"value":value} completion:^(id result, NSError *error) {
            HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation || ![self sourceIsCurrent] || error) return;
            [self loadSharedValue:value forRecord:match];
        }];
    }];
}
- (void)observeAdvertisements:(NSArray *)advertisements {
    for (NSDictionary *advertisement in advertisements) {
        uint64_t value; NSString *address = advertisement[@"address"], *source = advertisement[@"source"];
        if (![address isKindOfClass:[NSString class]] || !HABLEParseAddress(address, &value) || ![source isKindOfClass:[NSString class]] || !source.length || [self.excludedSources containsObject:source.uppercaseString]) continue;
        if (self.advertisements.count < 2048 || self.advertisements[HABLEAddressString(value)]) self.advertisements[HABLEAddressString(value)] = advertisement;
    }
    [self rebuildKnownDevices];
}
- (void)refreshExcludingSource:(NSString *)source completion:(void (^)(NSError *))completion {
    [self cancel]; self.knownDevices = @[]; self.registryDevices = @[]; [self.advertisements removeAllObjects];
    [self.sharedBindings removeAllObjects]; [self.occupiedBindingKeys removeAllObjects]; [self.publishingBindings removeAllObjects];
    HAAuthManager *auth = [HAAuthManager sharedManager]; self.sourceServer = auth.serverURL; self.sourceRevision = auth.authenticationRevision;
    NSUInteger generation = self.generation;
    HAConnectionManager *connection = [HAConnectionManager sharedManager];
    if (!connection.connected) {
        self.status = @"Connect to Home Assistant to import known devices";
        completion([NSError errorWithDomain:@"HABLEIdentity" code:1 userInfo:@{NSLocalizedDescriptionKey:self.status}]); return;
    }
    self.status = @"Reading Home Assistant device identities";
    __weak typeof(self) weakSelf = self;
    [connection sendCommand:@{@"type":@"config_entries/get"} completion:^(id entries, NSError *entryError) {
        HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
        if (entryError || ![entries isKindOfClass:[NSArray class]]) { self.status = @"Could not identify Home Assistant scanner sources"; completion(entryError ?: [NSError errorWithDomain:@"HABLEIdentity" code:2 userInfo:nil]); return; }
        [connection sendCommand:@{@"type":@"config/device_registry/list"} completion:^(id result, NSError *error) {
            HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
            if (error || ![result isKindOfClass:[NSArray class]]) { self.status = @"Could not read Home Assistant devices"; completion(error ?: [NSError errorWithDomain:@"HABLEIdentity" code:2 userInfo:nil]); return; }
            [self loadRegistry:result entries:entries excludingSource:source];
            [self loadSharedBindingsWithCompletion:^{
            HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"HABLEIdentitySharedOnly"]) {
                self.status = @"Using stored HA identities without scanner comparison"; completion(nil); return;
            }
            self.status = @"Comparing independent Bluetooth observations";
            self.subscription = [connection subscribeWithCommand:@{@"type":@"bluetooth/subscribe_advertisements"} handler:^(NSDictionary *event) {
                HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
                if ([event[@"add"] isKindOfClass:[NSArray class]]) [self observeAdvertisements:event[@"add"]];
            } completion:^(BOOL success, NSError *error) {
                HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
                if (!success) { [self cancel]; self.status = self.sharedBindings.count ? @"Using stored identities; live scanner comparison needs administrator access" : @"Registry imported; advertisement matching needs administrator access"; completion(nil); return; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
                    [self cancel]; self.status = [NSString stringWithFormat:@"Imported %lu identities from HA", (unsigned long)self.knownDevices.count]; completion(nil);
                });
            }];
            }];
        }];
    }];
}
- (NSArray *)candidatesForObservation:(NSDictionary *)observation {
    NSMutableArray *result = [NSMutableArray array];
    NSData *manufacturer = [[NSData alloc] initWithBase64EncodedString:observation[@"manufacturer_data"] ?: @"" options:0];
    if (!manufacturer.length) manufacturer = [[NSData alloc] initWithBase64EncodedString:observation[@"identity_manufacturer_data"] ?: @"" options:0];
    NSDictionary *services = observation[@"service_data"] ?: @{};
    for (NSDictionary *known in self.knownDevices) {
        NSInteger score = 0; NSMutableArray *evidence = [NSMutableArray array];
        NSString *address = known[@"address"]; NSDictionary *advertisement = self.advertisements[address];
        if (address.length && [observation[@"address"] isKindOfClass:[NSString class]] && ![observation[@"identity"] isEqual:@"local_alias"] && [observation[@"address"] caseInsensitiveCompare:address] == NSOrderedSame) { score += 200; [evidence addObject:@"Hardware address matches"]; }
        NSString *serial = observation[@"serial_number"];
        if (serial.length && [known[@"serial_number"] isEqualToString:serial]) { score += 150; [evidence addObject:@"Serial number matches"]; }
        if (manufacturer.length >= 8) {
            const uint8_t *bytes = manufacturer.bytes;
            NSString *company = [NSString stringWithFormat:@"%u", bytes[0] | (bytes[1] << 8)];
            NSData *remote = HABLEHexData(advertisement[@"manufacturer_data"][company]);
            if (remote && [remote isEqualToData:[manufacturer subdataWithRange:NSMakeRange(2, manufacturer.length - 2)]]) { score += 70; [evidence addObject:@"Manufacturer payload matches"]; }
        }
        for (NSString *uuid in services) {
            NSData *local = [[NSData alloc] initWithBase64EncodedString:services[uuid] options:0];
            NSData *remote = HABLEHexData(advertisement[@"service_data"][HABLEFullUUID(uuid)]);
            if (local.length >= 6 && [local isEqualToData:remote]) { score += 50; [evidence addObject:@"Service payload matches"]; break; }
        }
        NSString *name = observation[@"name"];
        if (name.length && ![name isEqualToString:@"Unnamed device"] && ([name caseInsensitiveCompare:known[@"name"] ?: @""] == NSOrderedSame || [name caseInsensitiveCompare:advertisement[@"name"] ?: @""] == NSOrderedSame)) { score += 20; [evidence addObject:@"Device name matches"]; }
        for (NSArray *identifier in known[@"identifiers"]) if (name.length && [name caseInsensitiveCompare:identifier[1]] == NSOrderedSame) { score += 60; [evidence addObject:@"HA integration identifier matches"]; break; }
        NSMutableSet *uuids = [NSMutableSet set]; for (NSString *uuid in observation[@"service_uuids"]) [uuids addObject:HABLEFullUUID(uuid)];
        for (NSString *uuid in observation[@"gatt_service_uuids"]) [uuids addObject:HABLEFullUUID(uuid)];
        for (NSString *uuid in advertisement[@"service_uuids"]) if ([uuids containsObject:HABLEFullUUID(uuid)]) { score += 5; [evidence addObject:@"Advertised service matches"]; break; }
        NSMutableDictionary *candidate = [known mutableCopy]; candidate[@"score"] = @(score);
        BOOL verified = NO;
        // A generic name, service UUID or matching measurement is insufficient.
        // Blue Connect advertises the device ID used by its HA integration.
        // Require the matching vendor envelope on both radios and an address
        // observed independently of every HA Dashboard proxy.
        NSString *blueID = known[@"blue_connect_identifier"];
        NSData *bluePayload = HABLEHexData(advertisement[@"manufacturer_data"][@"305"]);
        if (address.length && blueID.length && name.length && [name caseInsensitiveCompare:blueID] == NSOrderedSame &&
            [advertisement[@"name"] isKindOfClass:[NSString class]] && [advertisement[@"name"] caseInsensitiveCompare:blueID] == NSOrderedSame &&
            manufacturer.length >= 2 && bluePayload.length == 11) {
            const uint8_t *bytes = manufacturer.bytes;
            if (bytes[0] == 0x31 && bytes[1] == 0x01) { verified = YES; score += 150; [evidence addObject:@"Blue Connect ID and vendor match an independent scanner"]; }
        }
        if (address.length && blueID.length && name.length && [name caseInsensitiveCompare:blueID] == NSOrderedSame && manufacturer.length >= 2 && known[@"shared_identity"]) {
            const uint8_t *bytes = manufacturer.bytes;
            if (bytes[0] == 0x31 && bytes[1] == 0x01) { verified = YES; score += 150; [evidence addObject:@"Verified Blue Connect association stored in HA"]; }
        }
        if (address.length && [known[@"address_provenance"] isEqual:@"registry_bluetooth"] && serial.length >= 4 &&
            ![[serial lowercaseString] isEqual:@"unknown"] && [serial rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"]].location != NSNotFound &&
            [known[@"serial_number"] isEqual:serial]) { verified = YES; [evidence addObject:@"GATT serial matches HA's registered Bluetooth address"]; }
        candidate[@"automatic_match"] = @(verified); candidate[@"score"] = @(score);
        candidate[@"evidence"] = evidence.count ? [evidence componentsJoinedByString:@" · "] : @"Known to HA; identity has not been matched";
        [result addObject:candidate];
    }
    // Scores rank suggestions. Automatic matches require separate, explicit
    // identity evidence; equal readings, RSSI and generic names are insufficient.
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSComparisonResult score = [b[@"score"] compare:a[@"score"]]; return score == NSOrderedSame ? [a[@"label"] localizedCaseInsensitiveCompare:b[@"label"]] : score; }];
}
- (NSDictionary *)automaticMatchForObservation:(NSDictionary *)observation {
    NSDictionary *match = nil;
    for (NSDictionary *candidate in [self candidatesForObservation:observation]) if ([candidate[@"automatic_match"] boolValue]) {
        if (match) return nil; // Conflicting HA records or radio addresses need confirmation.
        match = candidate;
    }
    return match;
}
- (BOOL)hasKnownIdentityForObservation:(NSDictionary *)observation {
    NSString *name = observation[@"name"], *serial = observation[@"serial_number"];
    for (NSDictionary *record in self.registryDevices) {
        if (name.length && [record[@"blue_connect_identifier"] length] && [name caseInsensitiveCompare:record[@"blue_connect_identifier"]] == NSOrderedSame) return YES;
        if (serial.length >= 4 && [serial isEqual:record[@"serial_number"]]) return YES;
    }
    return NO;
}
@end
