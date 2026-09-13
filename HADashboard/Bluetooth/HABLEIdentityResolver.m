#import "HABLEIdentityResolver.h"
#import "HABLEProto.h"
#import "HAConnectionManager.h"

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
@end

@implementation HABLEIdentityResolver
- (instancetype)init {
    if ((self = [super init])) { _knownDevices = @[]; _advertisements = [NSMutableDictionary dictionary]; _subscription = -1; _status = @"Not synchronised"; }
    return self;
}
- (void)dealloc { [self cancel]; }
- (void)cancel {
    self.generation++;
    if (self.subscription >= 0) [[HAConnectionManager sharedManager] unsubscribeFromEventWithId:self.subscription];
    self.subscription = -1;
}
- (void)refreshExcludingSource:(NSString *)source completion:(void (^)(NSError *))completion {
    [self cancel]; self.knownDevices = @[]; [self.advertisements removeAllObjects];
    self.excludedSources = [NSMutableSet setWithObject:source.uppercaseString ?: @""];
    NSUInteger generation = self.generation;
    HAConnectionManager *connection = [HAConnectionManager sharedManager];
    if (!connection.connected) {
        self.status = @"Connect to Home Assistant to import known devices";
        completion([NSError errorWithDomain:@"HABLEIdentity" code:1 userInfo:@{NSLocalizedDescriptionKey:self.status}]); return;
    }
    self.status = @"Reading Home Assistant's device registry";
    __weak typeof(self) weakSelf = self;
    [connection sendCommand:@{@"type":@"config_entries/get"} completion:^(id entries, NSError *entryError) {
        HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
        NSMutableSet *adapterEntries = [NSMutableSet set];
        if ([entries isKindOfClass:[NSArray class]]) for (NSDictionary *entry in entries) if ([entry[@"domain"] isEqual:@"bluetooth"] && [entry[@"entry_id"] isKindOfClass:[NSString class]]) [adapterEntries addObject:entry[@"entry_id"]];
    [connection sendCommand:@{@"type":@"config/device_registry/list"} completion:^(id result, NSError *error) {
        HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
        if (error || ![result isKindOfClass:[NSArray class]]) { self.status = error.localizedDescription ?: @"Could not read Home Assistant devices"; completion(error ?: [NSError errorWithDomain:@"HABLEIdentity" code:2 userInfo:@{NSLocalizedDescriptionKey:self.status}]); return; }
        NSMutableDictionary *known = [NSMutableDictionary dictionary];
        for (NSDictionary *device in result) {
            BOOL adapter = NO;
            for (NSString *entryID in device[@"config_entries"]) if ([adapterEntries containsObject:entryID]) adapter = YES;
            if (adapter) {
                for (NSArray *pair in device[@"connections"]) if (pair.count == 2 && [pair[1] isKindOfClass:[NSString class]]) [self.excludedSources addObject:[pair[1] uppercaseString]];
                continue;
            }
            if ([device[@"manufacturer"] isEqual:@"HA Dashboard"]) {
                for (NSArray *pair in device[@"connections"]) if (pair.count == 2 && [pair[1] isKindOfClass:[NSString class]]) [self.excludedSources addObject:[pair[1] uppercaseString]];
            }
            for (NSArray *pair in device[@"connections"]) {
                uint64_t address;
                if (pair.count != 2 || ![pair[0] isEqual:@"bluetooth"] || ![pair[1] isKindOfClass:[NSString class]] || !HABLEParseAddress(pair[1], &address)) continue;
                NSString *mac = HABLEAddressString(address);
                NSString *label = [device[@"name_by_user"] isKindOfClass:[NSString class]] ? device[@"name_by_user"] : device[@"name"];
                NSMutableDictionary *item = [@{@"address":mac, @"label":[label isKindOfClass:[NSString class]] ? label : mac, @"device_id":device[@"id"] ?: @""} mutableCopy];
                for (NSString *key in @[@"manufacturer", @"model", @"serial_number", @"name"]) if ([device[key] isKindOfClass:[NSString class]]) item[key] = device[key];
                known[mac] = item;
                if (known.count >= 512) break;
            }
            if (known.count >= 512) break;
        }
        self.knownDevices = [known.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"label"] localizedCaseInsensitiveCompare:b[@"label"]]; }];
        self.status = [NSString stringWithFormat:@"Comparing advertisements for %lu known devices", (unsigned long)self.knownDevices.count];
        self.subscription = [connection subscribeWithCommand:@{@"type":@"bluetooth/subscribe_advertisements"} handler:^(NSDictionary *event) {
            HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
            for (NSDictionary *advertisement in event[@"add"]) {
                NSString *address = [advertisement[@"address"] isKindOfClass:[NSString class]] ? [advertisement[@"address"] uppercaseString] : nil;
                if (!address || !known[address] || [self.excludedSources containsObject:[advertisement[@"source"] uppercaseString]]) continue;
                self.advertisements[address] = advertisement;
            }
        } completion:^(BOOL success, NSError *error) {
            HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
            if (!success) { [self cancel]; self.status = @"Known addresses imported; advertisement comparison requires HA administrator access"; completion(nil); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                HABLEIdentityResolver *self = weakSelf; if (!self || generation != self.generation) return;
                [self cancel]; self.status = [NSString stringWithFormat:@"Imported %lu devices · observed %lu through other scanners", (unsigned long)self.knownDevices.count, (unsigned long)self.advertisements.count]; completion(nil);
            });
        }];
    }];
    }];
}
- (NSArray *)candidatesForObservation:(NSDictionary *)observation {
    NSMutableArray *result = [NSMutableArray array];
    NSData *manufacturer = [[NSData alloc] initWithBase64EncodedString:observation[@"manufacturer_data"] ?: @"" options:0];
    NSDictionary *services = observation[@"service_data"] ?: @{};
    for (NSDictionary *known in self.knownDevices) {
        NSInteger score = 0; NSMutableArray *evidence = [NSMutableArray array];
        NSString *address = known[@"address"]; NSDictionary *advertisement = self.advertisements[address];
        if (![observation[@"identity"] isEqual:@"local_alias"] && [observation[@"address"] caseInsensitiveCompare:address] == NSOrderedSame) { score += 200; [evidence addObject:@"Hardware address matches"]; }
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
        NSMutableSet *uuids = [NSMutableSet set]; for (NSString *uuid in observation[@"service_uuids"]) [uuids addObject:HABLEFullUUID(uuid)];
        for (NSString *uuid in observation[@"gatt_service_uuids"]) [uuids addObject:HABLEFullUUID(uuid)];
        for (NSString *uuid in advertisement[@"service_uuids"]) if ([uuids containsObject:HABLEFullUUID(uuid)]) { score += 5; [evidence addObject:@"Advertised service matches"]; break; }
        NSMutableDictionary *candidate = [known mutableCopy]; candidate[@"score"] = @(score);
        candidate[@"evidence"] = evidence.count ? [evidence componentsJoinedByString:@" · "] : @"Known to HA; identity has not been matched";
        [result addObject:candidate];
    }
    // These are suggestions. Even an identical sensor payload can be shared by
    // two devices; a name, RSSI, or generic service is never an automatic match.
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSComparisonResult score = [b[@"score"] compare:a[@"score"]]; return score == NSOrderedSame ? [a[@"label"] localizedCaseInsensitiveCompare:b[@"label"]] : score; }];
}
@end
