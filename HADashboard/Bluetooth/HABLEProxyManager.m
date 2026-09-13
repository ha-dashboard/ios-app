#import "HABLEIdentityEvidence.h"
#import "HABLEProxyManager.h"
#import "HABLEAPIServer.h"
#import "HABLEProto.h"
#import "HABLEProxyRegistration.h"
#import "HAConnectionManager.h"
#import "HADeviceIntegrationManager.h"
#import "HAAuthManager.h"
#import "HABLEIdentityResolver.h"
#import "HALog.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>

NSString *const HABLEProxyDidChangeNotification = @"HABLEProxyDidChangeNotification";
static NSString *const HABLEEnabledKey = @"ha_ble_proxy_enabled";
static NSString *const HABLEMappingKey = @"ha_ble_proxy_address_mapping";
static NSString *const HABLEScanModeKey = @"ha_ble_proxy_scan_mode";
static NSString *const HABLEImportedServicesKey = @"ha_ble_proxy_imported_services";
static NSString *const HABLEAdditionalServicesKey = @"ha_ble_proxy_additional_services";
static const NSUInteger HABLESlots = 3;

@interface HABLEPeripheralSession : NSObject
@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, weak) HABLEAPIConnection *owner;
@property (nonatomic, strong) NSNumber *address;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id> *handles;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *operations;
@property (nonatomic, strong) NSDictionary *pending;
@property (nonatomic, assign) CFAbsoluteTime deadline;
@property (nonatomic, assign) NSUInteger discoveryWork;
@property (nonatomic, assign) BOOL discovering;
@property (nonatomic, assign) BOOL preparingConnection;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *handleIDs;
@property (nonatomic, assign) NSUInteger nextHandle;
@property (nonatomic, strong) NSArray<NSData *> *serializedServices;
@property (nonatomic, copy) void (^identityCompletion)(NSDictionary *, NSError *);
@property (nonatomic, strong) NSMutableDictionary *identityValues;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *identityFields;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *identityReadPaths;
@end
@implementation HABLEPeripheralSession
@end

static uint64_t HABLEAlias(NSString *value) {
    NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding]; uint8_t hash[32];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, hash);
    // A locally administered, unicast alias. Never described as a radio MAC.
    uint64_t result = (hash[0] & 0xFC) | 2;
    for (NSUInteger index = 1; index < 6; index++) result = (result << 8) | hash[index];
    return result;
}
static NSString *HABLELocalHost(void) {
    struct ifaddrs *interfaces = NULL; NSString *fallback = nil, *wifi = nil;
    if (getifaddrs(&interfaces)) return nil;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET || !(item->ifa_flags & IFF_UP) || (item->ifa_flags & IFF_LOOPBACK)) continue;
        struct sockaddr_in *addr = (struct sockaddr_in *)item->ifa_addr;
        uint32_t ip = ntohl(addr->sin_addr.s_addr);
        if ((ip & 0xff000000) != 0x0a000000 && (ip & 0xfff00000) != 0xac100000 && (ip & 0xffff0000) != 0xc0a80000) continue;
        char buffer[INET_ADDRSTRLEN]; if (!inet_ntop(AF_INET, &addr->sin_addr, buffer, sizeof(buffer))) continue;
        NSString *host = @(buffer); if (!fallback) fallback = host;
        if (!strcmp(item->ifa_name, "en0")) wifi = host;
    }
    freeifaddrs(interfaces); return wifi ?: fallback;
}
static void HABLEPutUUID(NSMutableData *data, CBUUID *uuid) {
    NSString *hex = [uuid.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (hex.length == 4) hex = [NSString stringWithFormat:@"0000%@00001000800000805F9B34FB", hex];
    else if (hex.length == 8) hex = [hex stringByAppendingString:@"00001000800000805F9B34FB"];
    if (hex.length != 32) return;
    unsigned long long upper = 0, lower = 0;
    [[NSScanner scannerWithString:[hex substringToIndex:16]] scanHexLongLong:&upper];
    [[NSScanner scannerWithString:[hex substringFromIndex:16]] scanHexLongLong:&lower];
    HABLEPutInteger(data, 1, upper); HABLEPutInteger(data, 1, lower);
}
static NSString *HABLEAdvertisementUUID(CBUUID *uuid) {
    NSString *value = uuid.UUIDString.lowercaseString;
    // The legacy ESPHome decoder expects 0x-prefixed short UUIDs or a full
    // 128-bit UUID. Forwarding Apple's bare "FD3D" loses its first two digits.
    if (value.length == 4) return [NSString stringWithFormat:@"0000%@-0000-1000-8000-00805f9b34fb", value];
    if (value.length == 8) return [value stringByAppendingString:@"-0000-1000-8000-00805f9b34fb"];
    return value;
}

@interface HABLEProxyManager () <CBCentralManagerDelegate, CBPeripheralDelegate, HABLEAPIServerDelegate>
@property (nonatomic, assign, readwrite) BOOL running;
@property (nonatomic, copy, readwrite) NSString *status;
@property (nonatomic, copy, readwrite) NSString *host;
@property (nonatomic, copy, readwrite) NSString *nodeName;
@property (nonatomic, copy, readwrite) NSString *adapterAddress;
@property (nonatomic, assign, readwrite) NSUInteger advertisementCount;
@property (nonatomic, assign, readwrite) NSUInteger forwardedCount;
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) HABLEAPIServer *server;
@property (nonatomic, strong) NSNetService *bonjour;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *observations;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *peripherals;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *mappings;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *identityMetadata;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, HABLEPeripheralSession *> *sessions;
@property (nonatomic, copy) NSString *installationID;
@property (nonatomic, assign) NSUInteger tickCount;
@property (nonatomic, strong) HABLEProxyRegistration *registration;
@property (nonatomic, assign) CFAbsoluteTime nextRegistrationAttempt;
@property (nonatomic, copy) NSString *registeredContext;
@property (nonatomic, assign) BOOL integrationRegistrationWasEnabled;
@property (nonatomic, assign) BOOL automaticRegistrationInFlight;
@property (nonatomic, strong) HABLEIdentityResolver *identityResolver;
@property (nonatomic, strong) HABLEIdentityResolver *identityImportResolver;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *automaticMappings;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *identityLabels;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *identityCheckTimes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *identityProbeTimes;
@property (nonatomic, strong) NSMutableDictionary *identityProbeAttempts;
@property (nonatomic, assign) NSTimeInterval nextIdentityProbeAt;
@property (nonatomic, copy) NSString *identityScope;
@property (nonatomic, assign) NSUInteger identityGeneration;
@property (nonatomic, assign) BOOL importingIdentities;
@property (nonatomic, assign) BOOL identitiesReady;
@property (nonatomic, assign) CFAbsoluteTime nextIdentityRefresh;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pendingIdentityAdvertisements;
@property (nonatomic, assign) NSUInteger identityPacketsDropped;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *handleTables;
@property (nonatomic, assign) NSUInteger gattReads;
@property (nonatomic, assign) NSUInteger gattWrites;
@property (nonatomic, assign) NSUInteger gattNotifications;
@property (nonatomic, assign) NSUInteger discoveryCallbacks;
@property (nonatomic, assign) NSUInteger unknownRSSICount;
@property (nonatomic, assign) BOOL initializing;
@property (nonatomic, assign, readwrite) BOOL usingServiceFilters;
@property (nonatomic, copy, readwrite) NSString *scanServiceStatus;
@property (nonatomic, copy) NSArray<NSString *> *importedScanServiceUUIDs;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *additionalScanServiceUUIDs;
@property (nonatomic, assign) NSUInteger scanStartGeneration;
@property (nonatomic, assign) NSUInteger scanImportGeneration;
@property (nonatomic, assign) NSUInteger scanStartCallbacks;
@property (nonatomic, assign) NSInteger scanSubscription;
@property (nonatomic, assign) BOOL importingScanServices;
@property (nonatomic, assign) CFAbsoluteTime scanStartedAt;
@property (nonatomic, assign) CFAbsoluteTime nextScanImport;
- (void)startScanUsingServices:(BOOL)services;
- (void)updateScanPolicy;
- (void)cancelScanImport;
- (void)pump:(HABLEPeripheralSession *)session;
@end

@implementation HABLEProxyManager
+ (instancetype)sharedManager { static HABLEProxyManager *manager; static dispatch_once_t once; dispatch_once(&once, ^{ manager = [[self alloc] init]; }); return manager; }
- (instancetype)init {
    if ((self = [super init])) {
        _initializing = YES;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _installationID = [defaults stringForKey:@"ha_ble_proxy_installation"];
        if (!_installationID) { _installationID = [NSUUID UUID].UUIDString; [defaults setObject:_installationID forKey:@"ha_ble_proxy_installation"]; }
        _adapterAddress = HABLEAddressString(HABLEAlias(_installationID));
        NSString *suffix = [[_adapterAddress stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString];
        _nodeName = [@"ha-dash-" stringByAppendingString:suffix];
        _observations = [NSMutableDictionary dictionary]; _peripherals = [NSMutableDictionary dictionary]; _sessions = [NSMutableDictionary dictionary];
        _identityMetadata = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"ha_ble_proxy_identity_metadata"] mutableCopy] ?: [NSMutableDictionary dictionary];
        _mappings = [[defaults dictionaryForKey:HABLEMappingKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        _status = @"Off";
        id launch = [defaults objectForKey:@"HABLEProxyEnabled"];
        if (launch) [defaults setBool:[launch boolValue] forKey:HABLEEnabledKey];
        [defaults removeObjectForKey:@"HABLEProxyEnabled"];
        if ([defaults objectForKey:@"HABLEProxyRegister"]) [defaults setBool:[defaults boolForKey:@"HABLEProxyRegister"] forKey:@"ha_ble_proxy_auto_register"];
        [defaults removeObjectForKey:@"HABLEProxyRegister"];
        _registration = [[HABLEProxyRegistration alloc] init];
        _identityResolver = [[HABLEIdentityResolver alloc] init];
        _automaticMappings = [NSMutableDictionary dictionary]; _identityLabels = [NSMutableDictionary dictionary]; _identityCheckTimes = [NSMutableDictionary dictionary]; _identityProbeTimes = [NSMutableDictionary dictionary]; _identityProbeAttempts = NSMutableDictionary.dictionary;
        _pendingIdentityAdvertisements = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(integrationRegistrationDidChange:) name:HADeviceIntegrationEnabledDidChangeNotification object:nil];
        for (NSString *name in @[HAConnectionManagerDidConnectNotification, HAConnectionManagerHADidStartNotification, HAConnectionManagerDidReceiveRegistriesNotification]) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(identityConnectionDidChange:) name:name object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(identityConnectionDidDisconnect:) name:HAConnectionManagerDidDisconnectNotification object:nil];
        _handleTables = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"ha_ble_proxy_handle_tables"] mutableCopy] ?: [NSMutableDictionary dictionary];
        _scanSubscription = -1; _scanServiceStatus = @"Services can be imported from Home Assistant";
        NSMutableArray *imported = [NSMutableArray array], *additional = [NSMutableArray array];
        for (NSString *value in [defaults arrayForKey:HABLEImportedServicesKey]) { NSString *uuid = HABLECanonicalUUID(value); if (uuid && imported.count < 128 && ![imported containsObject:uuid]) [imported addObject:uuid]; }
        for (NSString *value in [defaults arrayForKey:HABLEAdditionalServicesKey]) { NSString *uuid = HABLECanonicalUUID(value); if (uuid && additional.count < 128 && ![additional containsObject:uuid]) [additional addObject:uuid]; }
        _importedScanServiceUUIDs = imported; _additionalScanServiceUUIDs = additional;
        NSString *launchServices = [defaults stringForKey:@"HABLEProxyServiceUUIDs"];
        if (launchServices) { [self setAdditionalScanServiceUUIDs:[launchServices componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",; \n"]] error:nil]; [defaults removeObjectForKey:@"HABLEProxyServiceUUIDs"]; }
        if ([defaults objectForKey:@"HABLEProxyScanMode"]) { self.scanMode = [defaults integerForKey:@"HABLEProxyScanMode"]; [defaults removeObjectForKey:@"HABLEProxyScanMode"]; }
        _initializing = NO;
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (BOOL)isEnabled {
    id preference = [[NSUserDefaults standardUserDefaults] objectForKey:HABLEEnabledKey];
    return preference ? [preference boolValue] : [HADeviceIntegrationManager sharedManager].enabled;
}
- (HABLEScanMode)scanMode {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:HABLEScanModeKey];
    return value >= HABLEScanModeAutomatic && value <= HABLEScanModeServices ? (HABLEScanMode)value : HABLEScanModeAutomatic;
}
- (void)setScanMode:(HABLEScanMode)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode <= HABLEScanModeServices ? mode : HABLEScanModeAutomatic forKey:HABLEScanModeKey];
    if (self.running) [self startScanUsingServices:self.scanMode == HABLEScanModeServices];
    [self changed];
}
- (NSArray<NSString *> *)scanServiceUUIDs {
    NSMutableOrderedSet *values = [NSMutableOrderedSet orderedSet];
    for (NSString *uuid in self.additionalScanServiceUUIDs) if (values.count < 128) [values addObject:uuid];
    for (NSString *uuid in self.importedScanServiceUUIDs) if (values.count < 128) [values addObject:uuid];
    return values.array;
}
- (BOOL)setAdditionalScanServiceUUIDs:(NSArray<NSString *> *)values error:(NSError **)error {
    NSMutableOrderedSet *normal = [NSMutableOrderedSet orderedSet]; BOOL valid = [values isKindOfClass:[NSArray class]];
    if (valid) for (id value in values) {
        if ([value isKindOfClass:[NSString class]] && ![value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) continue;
        NSString *uuid = HABLECanonicalUUID(value);
        if (!uuid) { valid = NO; break; }
        [normal addObject:uuid]; if (normal.count > 128) { valid = NO; break; }
    }
    if (!valid) {
        if (error) *error = [NSError errorWithDomain:@"HABLEScanServices" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Enter up to 128 valid Bluetooth service UUIDs, separated by commas."}];
        return NO;
    }
    self.additionalScanServiceUUIDs = normal.array;
    [[NSUserDefaults standardUserDefaults] setObject:self.additionalScanServiceUUIDs forKey:HABLEAdditionalServicesKey];
    if (self.running && (self.usingServiceFilters || self.scanMode == HABLEScanModeServices)) [self startScanUsingServices:YES];
    [self changed]; return YES;
}
- (void)startScanUsingServices:(BOOL)services {
    if (!self.running || self.central.state != CBCentralManagerStatePoweredOn) return;
    NSUInteger generation = ++self.scanStartGeneration;
    BOOL wasScanning = self.central.isScanning; if (wasScanning) [self.central stopScan];
    self.usingServiceFilters = services; self.scanStartedAt = CFAbsoluteTimeGetCurrent(); self.scanStartCallbacks = self.discoveryCallbacks;
    NSMutableArray *filters = [NSMutableArray array];
    if (services) for (NSString *uuid in self.scanServiceUUIDs) [filters addObject:[CBUUID UUIDWithString:uuid]];
    if (services && !filters.count) return;
    void (^start)(void) = ^{
        if (!self.running || generation != self.scanStartGeneration || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
        self.scanStartedAt = CFAbsoluteTimeGetCurrent(); self.scanStartCallbacks = self.discoveryCallbacks;
        [self.central scanForPeripheralsWithServices:services ? filters : nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@YES}];
        HALogI(@"bleproxy", @"Scanning %@ (%lu known services)", services ? @"known services" : @"broadly", (unsigned long)self.scanServiceUUIDs.count);
    };
    if (wasScanning) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), start); else start();
}
- (void)updateScanPolicy {
    if (!self.running) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent(); HABLEScanMode mode = self.scanMode;
    if (!self.central.isScanning && now - self.scanStartedAt > 2 && (mode != HABLEScanModeServices || self.scanServiceUUIDs.count)) {
        [self startScanUsingServices:mode == HABLEScanModeServices || (mode == HABLEScanModeAutomatic && self.usingServiceFilters)];
    }
    BOOL broadIsQuiet = !self.usingServiceFilters && self.discoveryCallbacks == self.scanStartCallbacks && now - self.scanStartedAt >= 10;
    if ((mode == HABLEScanModeServices || self.usingServiceFilters || (mode == HABLEScanModeAutomatic && broadIsQuiet)) && !self.importingScanServices && now >= self.nextScanImport && [HAConnectionManager sharedManager].connected) [self refreshScanServices];
    if (mode == HABLEScanModeBroad && self.usingServiceFilters) [self startScanUsingServices:NO];
    else if (mode == HABLEScanModeServices && !self.usingServiceFilters) [self startScanUsingServices:YES];
    else if (mode == HABLEScanModeAutomatic) {
        if (broadIsQuiet && self.scanServiceUUIDs.count) [self startScanUsingServices:YES];
        // Periodically try broad discovery again so a quiet initial environment
        // does not permanently hide devices outside the learned service set.
        else if (self.usingServiceFilters && now - self.scanStartedAt >= 60) [self startScanUsingServices:NO];
    }
}
- (void)cancelScanImport {
    self.scanImportGeneration++;
    if (self.importingScanServices) { self.nextScanImport = 0; self.scanServiceStatus = @"Service import paused"; }
    if (self.scanSubscription >= 0) [[HAConnectionManager sharedManager] unsubscribeFromEventWithId:self.scanSubscription];
    self.scanSubscription = -1; self.importingScanServices = NO;
}
- (void)refreshScanServices {
    [self cancelScanImport];
    HAConnectionManager *connection = [HAConnectionManager sharedManager];
    if (!connection.connected) { self.scanServiceStatus = @"Connect to Home Assistant to import services"; [self changed]; return; }
    NSUInteger generation = self.scanImportGeneration; self.importingScanServices = YES;
    self.nextScanImport = CFAbsoluteTimeGetCurrent() + 300;
    self.scanServiceStatus = @"Reading services observed by Home Assistant"; [self changed];
    NSMutableSet *received = [NSMutableSet set]; __weak typeof(self) weakSelf = self;
    self.scanSubscription = [connection subscribeWithCommand:@{@"type":@"bluetooth/subscribe_advertisements"} handler:^(NSDictionary *event) {
        HABLEProxyManager *self = weakSelf; if (!self || generation != self.scanImportGeneration) return;
        NSArray *advertisements = [event[@"add"] isKindOfClass:[NSArray class]] ? event[@"add"] : @[];
        for (id advertisement in advertisements) {
            if (![advertisement isKindOfClass:[NSDictionary class]]) continue;
            NSMutableArray *values = [NSMutableArray array];
            if ([advertisement[@"service_uuids"] isKindOfClass:[NSArray class]]) [values addObjectsFromArray:advertisement[@"service_uuids"]];
            if ([advertisement[@"service_data"] isKindOfClass:[NSDictionary class]]) [values addObjectsFromArray:[advertisement[@"service_data"] allKeys]];
            for (id value in values) { NSString *uuid = HABLECanonicalUUID(value); if (uuid && received.count < 128) [received addObject:uuid]; }
            if (received.count >= 128) break;
        }
    } completion:^(BOOL success, NSError *error) {
        HABLEProxyManager *self = weakSelf; if (!self || generation != self.scanImportGeneration) return;
        if (!success) { [self cancelScanImport]; self.nextScanImport = CFAbsoluteTimeGetCurrent() + 60; self.scanServiceStatus = @"HA administrator access is required to import scan services"; [self changed]; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            HABLEProxyManager *self = weakSelf; if (!self || generation != self.scanImportGeneration) return;
            NSArray *values = [received.allObjects sortedArrayUsingSelector:@selector(compare:)];
            BOOL changed = ![values isEqualToArray:self.importedScanServiceUUIDs];
            [self cancelScanImport]; self.nextScanImport = CFAbsoluteTimeGetCurrent() + 300; self.importedScanServiceUUIDs = values;
            [[NSUserDefaults standardUserDefaults] setObject:values forKey:HABLEImportedServicesKey];
            self.scanServiceStatus = values.count ? [NSString stringWithFormat:@"%lu services imported from Home Assistant", (unsigned long)values.count] : @"HA has no advertised services to import; add a service UUID manually";
            if (changed && self.running && (self.usingServiceFilters || self.scanMode == HABLEScanModeServices)) [self startScanUsingServices:YES];
            [self updateScanPolicy]; [self changed];
        });
    }];
}
- (void)setEnabled:(BOOL)enabled {
    if (enabled && ![[NSUserDefaults standardUserDefaults] stringForKey:@"ha_ble_proxy_installation"]) [[NSUserDefaults standardUserDefaults] setObject:self.installationID forKey:@"ha_ble_proxy_installation"];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:HABLEEnabledKey];
    if (enabled) [self resume]; else [self suspend];
    [self changed];
}
- (NSString *)encryptionKey {
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"org.hadashboard.ble-proxy", (__bridge id)kSecAttrAccount:@"noise-key"};
    NSMutableDictionary *read = [query mutableCopy]; read[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL; OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)read, &result);
    if (status == errSecSuccess) { NSData *data = CFBridgingRelease(result); return data.length == 32 ? [data base64EncodedStringWithOptions:0] : nil; }
    if (status != errSecItemNotFound) return nil;
    uint8_t bytes[32]; if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;
    NSData *data = [NSData dataWithBytes:bytes length:32]; NSMutableDictionary *create = [query mutableCopy];
    create[(__bridge id)kSecValueData] = data; create[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    if (SecItemAdd((__bridge CFDictionaryRef)create, NULL) != errSecSuccess) return nil;
    return [data base64EncodedStringWithOptions:0];
}
- (void)resume {
    if (!self.enabled || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (!self.central) { self.status = @"Waiting for Bluetooth permission"; self.central = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:@{CBCentralManagerOptionShowPowerAlertKey:@NO}]; }
    if (!self.timer) { self.timer = [NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES]; [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes]; }
    [self updateRadio];
}
- (void)centralManagerDidUpdateState:(CBCentralManager *)central { [self updateRadio]; }
- (void)updateRadio {
    if (!self.enabled || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (self.central.state != CBCentralManagerStatePoweredOn) {
        [self stopTransport];
        switch ((NSInteger)self.central.state) {
            case CBCentralManagerStateUnsupported: self.status = @"Bluetooth LE is not supported on this device"; break;
            case CBCentralManagerStateUnauthorized: self.status = @"Allow Bluetooth access in Settings"; break;
            case CBCentralManagerStatePoweredOff: self.status = @"Bluetooth is switched off"; break;
            default: self.status = @"Waiting for Bluetooth"; break;
        }
        [self changed]; return;
    }
    NSString *host = HABLELocalHost();
    if (!host) { [self stopTransport]; self.status = @"Connect to a local Wi-Fi network"; [self changed]; return; }
    if (self.running && [host isEqualToString:self.host]) { [self updateScanPolicy]; return; }
    [self stopTransport];
    NSData *key = [[NSData alloc] initWithBase64EncodedString:[self encryptionKey] ?: @"" options:0];
    if (key.length != 32) { self.status = @"Could not access the proxy encryption key"; [self changed]; return; }
    self.server = [[HABLEAPIServer alloc] initWithName:self.nodeName address:self.adapterAddress key:key]; self.server.delegate = self;
    NSError *error;
    if (![self.server startWithHost:host port:6053 error:&error]) { self.status = error.localizedDescription; self.server = nil; [self changed]; return; }
    self.host = host; self.running = YES;
    self.bonjour = [[NSNetService alloc] initWithDomain:@"local." type:@"_esphomelib._tcp." name:self.nodeName port:6053];
    NSMutableDictionary *txt = [NSMutableDictionary dictionary];
    NSDictionary *values = @{@"version":@"2026.8.2", @"mac":[self.adapterAddress stringByReplacingOccurrencesOfString:@":" withString:@""], @"platform":@"HA Dashboard", @"board":@"CoreBluetooth", @"network":@"wifi", @"api_encryption":@"Noise_NNpsk0_25519_ChaChaPoly_SHA256"};
    for (NSString *key in values) txt[key] = [values[key] dataUsingEncoding:NSUTF8StringEncoding];
    [self.bonjour setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txt]]; [self.bonjour publish];
    [self startScanUsingServices:self.scanMode == HABLEScanModeServices];
    self.status = @"Scanning · waiting for Home Assistant"; HALogI(@"bleproxy", @"Encrypted BLE proxy listening on %@:6053 as %@", host, self.nodeName); [self changed];
}
- (void)stopTransport {
    self.scanStartGeneration++; [self cancelScanImport];
    [self.registration cancel];
    self.automaticRegistrationInFlight = NO;
    [self.identityResolver cancel]; [self.identityImportResolver cancel]; self.identityImportResolver = nil;
    self.identityGeneration++; self.importingIdentities = NO; self.nextIdentityRefresh = 0;
    [self.pendingIdentityAdvertisements removeAllObjects];
    if (self.central.state == CBCentralManagerStatePoweredOn) [self.central stopScan];
    for (HABLEPeripheralSession *session in [self.sessions.allValues copy]) {
        if (session.identityCompletion) [self finishIdentity:session error:@"Bluetooth proxy paused"];
        [self.central cancelPeripheralConnection:session.peripheral];
    }
    [self.sessions removeAllObjects];
    self.server.delegate = nil; [self.server stop]; self.server = nil;
    [self.bonjour stop]; self.bonjour = nil; self.running = NO; self.host = nil;
}
- (void)suspend {
    [self stopTransport]; [self.timer invalidate]; self.timer = nil;
    self.status = self.enabled ? @"Paused · keep HA Dashboard open" : @"Off"; [self writeDiagnostics]; [self changed];
}
- (void)reset {
    self.enabled = NO;
    self.central.delegate = nil; self.central = nil;
    [self.observations removeAllObjects]; [self.peripherals removeAllObjects]; [self.mappings removeAllObjects]; [self.handleTables removeAllObjects]; [self.identityMetadata removeAllObjects];
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService:@"org.hadashboard.ble-proxy", (__bridge id)kSecAttrAccount:@"noise-key"};
    SecItemDelete((__bridge CFDictionaryRef)query);
    for (NSString *key in @[@"ha_ble_proxy_enabled", @"ha_ble_proxy_installation", @"ha_ble_proxy_address_mapping", @"ha_ble_proxy_handle_tables", @"ha_ble_proxy_identity_metadata", @"ha_ble_proxy_auto_register", HABLEScanModeKey, HABLEImportedServicesKey, HABLEAdditionalServicesKey, @"HABLEProxyEnabled", @"HABLEProxyRegister", @"HABLEProxyServiceUUIDs", @"HABLEProxyScanMode", @"ha_ble_identity_bindings_v2"]) [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    self.importedScanServiceUUIDs = @[]; self.additionalScanServiceUUIDs = @[]; self.usingServiceFilters = NO; self.nextScanImport = 0;
    self.scanServiceStatus = @"Services can be imported from Home Assistant";
    self.installationID = [NSUUID UUID].UUIDString; self.adapterAddress = HABLEAddressString(HABLEAlias(self.installationID));
    self.nodeName = [@"ha-dash-" stringByAppendingString:[[self.adapterAddress stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString]];
    self.registration = [[HABLEProxyRegistration alloc] init]; self.nextRegistrationAttempt = 0;
    self.registeredContext = nil; self.integrationRegistrationWasEnabled = NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:HABLEEnabledKey];
    [self.automaticMappings removeAllObjects]; [self.identityLabels removeAllObjects]; [self.identityCheckTimes removeAllObjects]; [self.identityProbeTimes removeAllObjects]; [self.identityProbeAttempts removeAllObjects]; self.nextIdentityProbeAt = 0;
    self.identityResolver = [[HABLEIdentityResolver alloc] init]; self.identityScope = nil; self.identitiesReady = NO; self.identityPacketsDropped = 0;
    self.advertisementCount = self.forwardedCount = self.discoveryCallbacks = self.unknownRSSICount = 0;
    self.gattReads = self.gattWrites = self.gattNotifications = 0;
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:@"ble-proxy-diagnostics.json"] error:nil];
    [self changed];
}
- (void)changed { if (!self.initializing) [[NSNotificationCenter defaultCenter] postNotificationName:HABLEProxyDidChangeNotification object:self]; }
- (uint64_t)addressForIdentifier:(NSString *)identifier {
    uint64_t address;
    if (HABLEParseAddress(self.mappings[identifier], &address)) return address;
    if (HABLEParseAddress(self.automaticMappings[identifier][@"address"], &address)) return address;
    return HABLEAlias([self.installationID stringByAppendingString:identifier]);
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisement RSSI:(NSNumber *)RSSI {
    self.discoveryCallbacks++;
    if (RSSI.integerValue == 127) self.unknownRSSICount++;
    if (!self.running || RSSI.integerValue == 127) return;
    NSString *identifier = peripheral.identifier.UUIDString;
    NSDictionary *previous = self.observations[identifier];
    if (!self.observations[identifier] && self.observations.count >= 256) {
        NSString *oldest;
        for (NSString *candidate in self.observations) if (!self.sessions[@([self addressForIdentifier:candidate])] && (!oldest || [self.observations[candidate][@"last_seen"] doubleValue] < [self.observations[oldest][@"last_seen"] doubleValue])) oldest = candidate;
        if (!oldest) return;
        [self.observations removeObjectForKey:oldest]; [self.peripherals removeObjectForKey:oldest];
        [self.automaticMappings removeObjectForKey:oldest]; [self.identityLabels removeObjectForKey:oldest]; [self.identityCheckTimes removeObjectForKey:oldest]; [self.identityResolver removeIdentifier:oldest];
    }
    NSData *manufacturer = advertisement[CBAdvertisementDataManufacturerDataKey];
    NSData *identityManufacturer = manufacturer.length ? manufacturer : [[NSData alloc] initWithBase64EncodedString:previous[@"identity_manufacturer_data"] ?: previous[@"manufacturer_data"] ?: @"" options:0];
    uint64_t address = [self addressForIdentifier:identifier];
    NSString *name = advertisement[CBAdvertisementDataLocalNameKey] ?: peripheral.name ?: @"Unnamed device";
    NSData *previousManufacturer = [[NSData alloc] initWithBase64EncodedString:previous[@"identity_manufacturer_data"] ?: previous[@"manufacturer_data"] ?: @"" options:0];
    if (![previous[@"name"] isEqual:name] || (previousManufacturer.length < 2 && identityManufacturer.length >= 2)) [self.identityCheckTimes removeObjectForKey:identifier];
    self.peripherals[identifier] = peripheral; self.advertisementCount++;
    NSMutableData *packet = [NSMutableData data]; HABLEPutString(packet, 2, name);
    int64_t rssi = RSSI.longLongValue; HABLEPutInteger(packet, 3, ((uint64_t)rssi << 1) ^ (uint64_t)(rssi >> 63));
    NSMutableArray *uuids = [NSMutableArray array];
    NSMutableOrderedSet *advertisedServices = [NSMutableOrderedSet orderedSetWithArray:advertisement[CBAdvertisementDataServiceUUIDsKey] ?: @[]];
    [advertisedServices addObjectsFromArray:advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] ?: @[]];
    for (CBUUID *uuid in advertisedServices) { [uuids addObject:uuid.UUIDString]; HABLEPutString(packet, 4, HABLEAdvertisementUUID(uuid)); }
    NSDictionary *services = advertisement[CBAdvertisementDataServiceDataKey]; NSMutableDictionary *serviceDump = [NSMutableDictionary dictionary];
    for (CBUUID *uuid in services) {
        NSData *value = services[uuid]; if (value.length > 2048) continue;
        NSMutableData *entry = [NSMutableData data]; HABLEPutString(entry, 1, HABLEAdvertisementUUID(uuid)); HABLEPutBytes(entry, 3, value); HABLEPutBytes(packet, 5, entry);
        serviceDump[uuid.UUIDString] = [value base64EncodedStringWithOptions:0];
    }
    if (manufacturer.length >= 2 && manufacturer.length <= 2048) {
        const uint8_t *bytes = manufacturer.bytes;
        NSMutableData *entry = [NSMutableData data]; HABLEPutString(entry, 1, [NSString stringWithFormat:@"%04x", bytes[0] | (bytes[1] << 8)]);
        HABLEPutBytes(entry, 3, [manufacturer subdataWithRange:NSMakeRange(2, manufacturer.length - 2)]); HABLEPutBytes(packet, 6, entry);
    }
    self.observations[identifier] = [@{@"identifier":identifier, @"name":name, @"address":HABLEAddressString(address), @"identity":self.mappings[identifier] ? @"user_associated_mac" : @"local_alias", @"rssi":RSSI, @"connectable":advertisement[CBAdvertisementDataIsConnectable] ?: @NO, @"last_seen":@([[NSDate date] timeIntervalSince1970]), @"service_uuids":uuids, @"service_data":serviceDump, @"manufacturer_data":[manufacturer base64EncodedStringWithOptions:0] ?: @""} mutableCopy];
    if (self.identityMetadata[identifier]) [self.observations[identifier] addEntriesFromDictionary:self.identityMetadata[identifier]];
    self.observations[identifier][@"local_address"] = HABLEAddressString(HABLEAlias([self.installationID stringByAppendingString:identifier]));
    self.observations[identifier][@"first_seen"] = previous[@"first_seen"] ?: @([[NSDate date] timeIntervalSince1970]);
    NSMutableOrderedSet *identityServices = [NSMutableOrderedSet orderedSetWithArray:previous[@"identity_service_uuids"] ?: previous[@"service_uuids"] ?: @[]]; [identityServices addObjectsFromArray:uuids];
    self.observations[identifier][@"identity_service_uuids"] = identityServices.array;
    if (![previous[@"identity_service_uuids"] isEqual:identityServices.array]) [self.identityCheckTimes removeObjectForKey:identifier];
    self.observations[identifier][@"identity_manufacturer_data"] = [identityManufacturer base64EncodedStringWithOptions:0] ?: @"";
    [self updateIdentityResolution];
    [self.identityResolver recordObservation:self.observations[identifier] identifier:identifier];
    [self matchIdentifier:identifier];
    BOOL trusted = self.mappings[identifier] || self.automaticMappings[identifier];
    BOOL potentialKnown = self.identitiesReady && [self.identityResolver hasKnownIdentityForObservation:self.observations[identifier]];
    if (trusted || (self.identitiesReady && !potentialKnown)) [self flushIdentityAdvertisementsForIdentifier:identifier];
    if (!trusted && (!self.identitiesReady || potentialKnown)) {
        self.observations[identifier][@"identity_pending"] = @YES;
        if (self.pendingIdentityAdvertisements.count >= 256) { [self.pendingIdentityAdvertisements removeObjectAtIndex:0]; self.identityPacketsDropped++; }
        [self.pendingIdentityAdvertisements addObject:@{@"identifier":identifier, @"packet":packet, @"queued_at":@(CFAbsoluteTimeGetCurrent())}];
    } else [self forwardPacket:packet identifier:identifier];
}
- (void)forwardPacket:(NSData *)packet identifier:(NSString *)identifier {
    if (!self.observations[identifier]) return;
    NSMutableData *encoded = [packet mutableCopy]; HABLEPutInteger(encoded, 1, [self addressForIdentifier:identifier]);
    HABLEPutInteger(encoded, 7, (self.mappings[identifier] || self.automaticMappings[identifier]) ? 0 : 1);
    if ([self.server broadcastAdvertisement:encoded]) self.forwardedCount++;
}
- (void)matchIdentifier:(NSString *)identifier {
    NSMutableDictionary *observation = self.observations[identifier];
    if (!observation) return;
    if (self.mappings[identifier]) [observation removeObjectForKey:@"identity_pending"];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (self.mappings[identifier]) {
        if (self.identitiesReady && now >= [self.identityCheckTimes[identifier] doubleValue]) {
            self.identityCheckTimes[identifier] = @(now + (self.automaticMappings[identifier] ? 10 : 2));
            NSString *address = HABLEAddressString([self addressForIdentifier:identifier]); NSDictionary *match = nil;
            for (NSDictionary *known in self.identityResolver.knownDevices) if ([known[@"address"] isEqual:address]) {
                if (match) { match = nil; break; }
                match = known;
            }
            if (match) self.identityLabels[identifier] = match; else [self.identityLabels removeObjectForKey:identifier];
        }
        [self.identityResolver rememberConfirmedAddress:self.mappings[identifier] observation:observation];
        NSDictionary *known = self.identityLabels[identifier];
        if (known) { observation[@"ha_name"] = known[@"label"]; observation[@"identity_evidence"] = @"Address matches Home Assistant"; }
        return;
    }
    if (self.identitiesReady && now >= [self.identityCheckTimes[identifier] doubleValue]) {
        self.identityCheckTimes[identifier] = @(now + (self.automaticMappings[identifier] ? 10 : 2));
        NSDictionary *match = [self.identityResolver automaticMatchForObservation:observation];
        uint64_t address = 0; BOOL available = match && HABLEParseAddress(match[@"address"], &address);
        if (self.sessions[@([self addressForIdentifier:identifier])] || (available && self.sessions[@(address)])) return;
        for (NSString *other in self.observations) if (available && ![other isEqual:identifier] &&
            [self addressForIdentifier:other] == address && [[NSDate date] timeIntervalSince1970] - [self.observations[other][@"last_seen"] doubleValue] < 300) available = NO;
        if (available) { self.automaticMappings[identifier] = match; [self.identityResolver rememberAutomaticMatch:match]; }
        else [self.automaticMappings removeObjectForKey:identifier];
    }
    NSDictionary *match = self.automaticMappings[identifier];
    observation[@"address"] = HABLEAddressString([self addressForIdentifier:identifier]);
    observation[@"identity"] = match ? ([match[@"identity_kind"] isEqual:@"observed_native"] ? @"shared_observed_address" : [match[@"identity_kind"] isEqual:@"observed_shared"] ? @"shared_alias" : @"ha_matched_mac") : @"local_alias";
    if (match) { [observation removeObjectForKey:@"identity_pending"]; observation[@"ha_name"] = match[@"label"]; observation[@"identity_evidence"] = match[@"evidence"]; }
    else { [observation removeObjectForKey:@"ha_name"]; observation[@"identity_evidence"] = [self.identityResolver evidenceForIdentifier:identifier]; if (!self.identitiesReady || [self.identityResolver hasKnownIdentityForObservation:observation]) observation[@"identity_pending"] = @YES; else [observation removeObjectForKey:@"identity_pending"]; }
}
- (void)identityConnectionDidChange:(NSNotification *)note { self.nextIdentityRefresh = 0; }
- (void)identityConnectionDidDisconnect:(NSNotification *)note {
    [self.identityResolver cancel]; self.identityGeneration++; self.importingIdentities = NO; self.nextIdentityRefresh = 0;
}
- (void)refreshIdentityInformation { self.nextIdentityRefresh = 0; [self updateIdentityResolution]; }
- (NSArray *)identityCandidatesForObservation:(NSDictionary *)observation { return [self.identityResolver candidatesForObservation:observation]; }
- (void)updateIdentityResolution {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    NSString *scope = [NSString stringWithFormat:@"%@|%lu", auth.serverURL ?: @"", (unsigned long)auth.authenticationRevision];
    if (![scope isEqual:self.identityScope]) {
        [self.identityResolver cancel]; [self.identityImportResolver cancel]; self.identityImportResolver = nil;
        self.identityGeneration++; self.importingIdentities = NO;
        self.identityResolver = [[HABLEIdentityResolver alloc] init]; self.identityScope = scope;
        [self.automaticMappings removeAllObjects]; [self.identityLabels removeAllObjects]; [self.identityCheckTimes removeAllObjects]; [self.pendingIdentityAdvertisements removeAllObjects];
        self.identitiesReady = NO; self.nextIdentityRefresh = 0;
    }
    if (!self.running) return;
    if (self.identityResolver.needsRegistryRefresh) self.nextIdentityRefresh = 0;
    if (!self.importingIdentities && [HAConnectionManager sharedManager].connected && CFAbsoluteTimeGetCurrent() >= self.nextIdentityRefresh) {
        self.importingIdentities = YES; self.nextIdentityRefresh = CFAbsoluteTimeGetCurrent() + 300;
        HABLEIdentityResolver *resolver = self.identityResolver; self.identityImportResolver = resolver;
        NSUInteger generation = self.identityGeneration; __weak typeof(self) weakSelf = self;
        [resolver refreshExcludingSource:self.adapterAddress completion:^(NSError *error) {
            HABLEProxyManager *self = weakSelf; if (!self || self.identityGeneration != generation) return;
            self.importingIdentities = NO; self.identitiesReady = self.identitiesReady || !error;
            if (!error) self.identityResolver = resolver;
            self.identityImportResolver = nil;
            if (error) self.nextIdentityRefresh = CFAbsoluteTimeGetCurrent() + 60;
            [self.identityCheckTimes removeAllObjects];
            for (NSString *identifier in self.observations) [self matchIdentifier:identifier];
            HALogI(@"bleproxy", @"HA identity import %@; %lu matches, %lu buffered advertisements", error ? @"failed" : @"completed", (unsigned long)self.automaticMappings.count, (unsigned long)self.pendingIdentityAdvertisements.count);
            [self flushIdentityAdvertisements]; [self changed];
        }];
    }
}
- (void)flushIdentityAdvertisementsForIdentifier:(NSString *)identifier {
    if (!self.pendingIdentityAdvertisements.count) return;
    NSMutableArray *waiting=[NSMutableArray array];
    for(NSDictionary *item in self.pendingIdentityAdvertisements) {
        if(![item[@"identifier"] isEqual:identifier]){[waiting addObject:item];continue;}
        if(CFAbsoluteTimeGetCurrent()-[item[@"queued_at"] doubleValue]>30){self.identityPacketsDropped++;continue;}
        [self forwardPacket:item[@"packet"] identifier:identifier];
    }
    self.pendingIdentityAdvertisements=waiting;
}
- (void)flushIdentityAdvertisements {
    NSMutableArray *waiting = [NSMutableArray array];
    for (NSDictionary *item in self.pendingIdentityAdvertisements) {
        NSString *identifier = item[@"identifier"];
        if (CFAbsoluteTimeGetCurrent() - [item[@"queued_at"] doubleValue] > 30) { self.identityPacketsDropped++; continue; }
        BOOL trusted = self.mappings[identifier] || self.automaticMappings[identifier];
        BOOL unknown = self.identitiesReady && !trusted && ![self.identityResolver hasKnownIdentityForObservation:self.observations[identifier]];
        if (trusted || unknown) [self forwardPacket:item[@"packet"] identifier:identifier];
        else [waiting addObject:item];
    }
    self.pendingIdentityAdvertisements = waiting;
}
- (NSArray *)devices { return [self.observations.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"rssi"] compare:a[@"rssi"]]; }]; }
- (NSString *)registrationStatus { return self.registration.status; }
- (void)inspectIdentifier:(NSString *)identifier completion:(void (^)(NSDictionary *, NSError *))completion {
    NSNumber *address = @([self addressForIdentifier:identifier]);
    NSString *error;
    if (!self.running || !self.peripherals[identifier]) error = @"Enable the proxy and refresh the nearby device list first.";
    else if (![self.observations[identifier][@"connectable"] boolValue]) error = @"This device is only advertising; it does not offer a connection for identification.";
    else if (self.sessions[address] || self.sessions.count >= HABLESlots) error = @"The device or connection slots are busy. Try again after Home Assistant disconnects.";
    if (error) { completion(nil, [NSError errorWithDomain:@"HABLEIdentity" code:1 userInfo:@{NSLocalizedDescriptionKey:error}]); return; }
    [self deviceRequest:@{@1:@[address], @2:@[@5]} connection:nil];
    HABLEPeripheralSession *session = self.sessions[address];
    if (!session) { completion(nil, [NSError errorWithDomain:@"HABLEIdentity" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Could not start the identification connection."}]); return; }
    session.identityCompletion = completion; session.identityValues = [NSMutableDictionary dictionary]; session.identityFields = [NSMutableDictionary dictionary]; session.identityReadPaths = NSMutableDictionary.dictionary; session.identityValues[@"gatt_probe_session"] = NSUUID.UUID.UUIDString;
}
- (void)finishIdentity:(HABLEPeripheralSession *)session error:(NSString *)message {
    void (^completion)(NSDictionary *, NSError *) = session.identityCompletion;
    session.identityCompletion = nil;
    if (!completion) return;
    session.identityValues[@"identification_read_at"] = @([[NSDate date] timeIntervalSince1970]);
    NSString *peripheralID=session.peripheral.identifier.UUIDString;
    BOOL sameSchema=[self.identityMetadata[peripheralID][@"gatt_fingerprint_schema"] isEqual:@3];
    session.identityValues[@"gatt_fingerprint_schema"]=@3;
    session.identityValues[@"gatt_probe_attempts"]=@(sameSchema ? MIN(255,[self.identityMetadata[peripheralID][@"gatt_probe_attempts"] unsignedIntegerValue]+1) : 1);
    session.identityValues[@"gatt_fingerprints"]=[HABLEIdentityEvidence mergeFingerprintReads:session.identityValues[@"gatt_fingerprint_reads"] ?: @{} previous:sameSchema ? self.identityMetadata[peripheralID][@"gatt_fingerprints"] : @{} session:session.identityValues[@"gatt_probe_session"] atTime:NSDate.date.timeIntervalSince1970];
    [session.identityValues removeObjectForKey:@"gatt_fingerprint_reads"];
    NSDictionary *identity = [session.identityValues copy];
    if (!message) {
        NSString *identifier = session.peripheral.identifier.UUIDString;
        [self.observations[identifier] addEntriesFromDictionary:identity];
        if (self.identityMetadata.count < 256 || self.identityMetadata[identifier]) {
            self.identityMetadata[identifier] = identity;
            [[NSUserDefaults standardUserDefaults] setObject:self.identityMetadata forKey:@"ha_ble_proxy_identity_metadata"];
        }
    }
    [self.central cancelPeripheralConnection:session.peripheral];
    completion(message ? nil : identity, message ? [NSError errorWithDomain:@"HABLEIdentity" code:3 userInfo:@{NSLocalizedDescriptionKey:message}] : nil);
}
- (void)registerWithHomeAssistant {
    [self registerWithHomeAssistantAutomatically:NO];
}
- (NSString *)registrationContext {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    return [NSString stringWithFormat:@"%@|%@|%lu", auth.serverURL ?: @"", self.host ?: @"", (unsigned long)auth.authenticationRevision];
}
- (void)updateAutomaticRegistration {
    [self updateAutomaticRegistrationWithIntegrationEnabled:[HADeviceIntegrationManager sharedManager].enabled
                                                connected:[HAConnectionManager sharedManager].connected
                                                  context:[self registrationContext]];
}
- (void)integrationRegistrationDidChange:(NSNotification *)note {
    if (self.enabled) [self resume]; else [self suspend];
    [self updateAutomaticRegistration];
}
- (void)updateAutomaticRegistrationWithIntegrationEnabled:(BOOL)enabled connected:(BOOL)connected context:(NSString *)context {
    BOOL requested = [[NSUserDefaults standardUserDefaults] boolForKey:@"ha_ble_proxy_auto_register"];
    if (enabled != self.integrationRegistrationWasEnabled) {
        self.integrationRegistrationWasEnabled = enabled;
        self.registeredContext = nil; self.nextRegistrationAttempt = 0;
    }
    if (!enabled && !requested) {
        if (self.automaticRegistrationInFlight) {
            [self.registration cancel]; self.automaticRegistrationInFlight = NO; [self changed];
        }
        return;
    }
    if (self.running && connected && !self.registration.registering &&
        (requested || ![self.registeredContext isEqual:context]) && CFAbsoluteTimeGetCurrent() >= self.nextRegistrationAttempt) {
        [self registerWithHomeAssistantAutomatically:YES];
    }
}
- (void)registerWithHomeAssistantAutomatically:(BOOL)automatic {
    if (!self.running || self.registration.registering) return;
    self.automaticRegistrationInFlight = automatic;
    self.nextRegistrationAttempt = CFAbsoluteTimeGetCurrent() + 60;
    NSString *context = [self registrationContext];
    __weak typeof(self) weakSelf = self;
    [self.registration registerHost:self.host key:[self encryptionKey] completion:^(BOOL success) {
        weakSelf.automaticRegistrationInFlight = NO;
        if (success) {
            weakSelf.registeredContext = context;
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ha_ble_proxy_auto_register"];
        }
        [weakSelf changed];
    }]; [self changed];
}
- (BOOL)setRealAddress:(NSString *)address forIdentifier:(NSString *)identifier error:(NSError **)error {
    uint64_t value = 0; NSString *reason;
    if (!self.observations[identifier]) reason = @"This device is no longer in the scan history.";
    else if (address.length && !HABLEParseAddress(address, &value)) reason = @"Enter the sensor's verified address as AA:BB:CC:DD:EE:FF.";
    else if (self.sessions[@([self addressForIdentifier:identifier])] || (address.length && self.sessions[@(value)])) reason = @"Disconnect this device before changing its identity.";
    else if (address.length && !self.mappings[identifier] && self.mappings.count >= 512) reason = @"The saved address limit has been reached.";
    else if (address.length) for (NSString *other in self.mappings) if (![other isEqualToString:identifier] && [self.mappings[other] caseInsensitiveCompare:address] == NSOrderedSame) reason = @"That address is already associated with another device.";
    if (!reason && address.length) for (NSString *other in self.observations) {
        if (![other isEqualToString:identifier] && [self addressForIdentifier:other] == value && [[NSDate date] timeIntervalSince1970] - [self.observations[other][@"last_seen"] doubleValue] < 300) reason = @"Another recently seen device already uses that address.";
    }
    if (reason) { if (error) *error = [NSError errorWithDomain:@"HABLEProxy" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}]; return NO; }
    if (address.length) self.mappings[identifier] = HABLEAddressString(value); else [self.mappings removeObjectForKey:identifier];
    [self.automaticMappings removeObjectForKey:identifier]; [self.identityLabels removeObjectForKey:identifier]; [self.identityCheckTimes removeObjectForKey:identifier];
    [[NSUserDefaults standardUserDefaults] setObject:self.mappings forKey:HABLEMappingKey];
    self.observations[identifier][@"address"] = HABLEAddressString([self addressForIdentifier:identifier]);
    self.observations[identifier][@"identity"] = self.mappings[identifier] ? @"user_associated_mac" : @"local_alias";
    [self flushIdentityAdvertisements];
    [self changed]; return YES;
}
- (NSDictionary *)diagnostics {
    return @{@"schema":@1, @"time":@([[NSDate date] timeIntervalSince1970]), @"enabled":@(self.enabled), @"running":@(self.running), @"status":self.status ?: @"", @"node":self.nodeName, @"adapter_alias":self.adapterAddress, @"host":self.host ?: @"", @"port":@6053, @"clients":@(self.server.authenticatedClients), @"advertisements":@(self.advertisementCount), @"forwarded":@(self.forwardedCount), @"active_connections":@(self.sessions.count), @"devices":self.devices, @"backend":@"public_core_bluetooth", @"transport":@"noise_nnpsk0", @"discovery_callbacks":@(self.discoveryCallbacks), @"unknown_rssi_callbacks":@(self.unknownRSSICount), @"central_state":@((NSInteger)self.central.state), @"scanning":@(self.central.isScanning), @"application_state":@((NSInteger)[UIApplication sharedApplication].applicationState), @"app_build":[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"", @"scan_mode":@(self.scanMode), @"using_service_filters":@(self.usingServiceFilters), @"scan_service_uuids":self.scanServiceUUIDs, @"scan_service_status":self.scanServiceStatus ?: @"", @"registration_status":self.registrationStatus ?: @"", @"registration_requested":@([[NSUserDefaults standardUserDefaults] boolForKey:@"ha_ble_proxy_auto_register"]), @"registration_automatic":@([HADeviceIntegrationManager sharedManager].enabled), @"identity_status":self.identityResolver.status ?: @"", @"identity_importing":@(self.importingIdentities),@"peer_inventory":[self.identityResolver inventoryDiagnostics], @"identity_matches":@(self.automaticMappings.count), @"identity_packets_dropped":@(self.identityPacketsDropped), @"gatt_reads":@(self.gattReads), @"gatt_writes":@(self.gattWrites), @"gatt_notifications":@(self.gattNotifications)};
}
- (void)tick:(NSTimer *)timer {
    self.tickCount++;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (HABLEPeripheralSession *session in [self.sessions.allValues copy]) {
        if (now > session.deadline && (session.pending || session.discovering || session.peripheral.state == CBPeripheralStateConnecting)) {
            if (session.identityCompletion) [self finishIdentity:session error:@"The device did not complete identification in time."];
            [self connectionResponse:session connected:NO error:8]; [self.central cancelPeripheralConnection:session.peripheral]; [self.sessions removeObjectForKey:session.address]; [self slotsChanged];
        }
    }
    if (!(self.tickCount % 4)) {
        [self updateRadio];
        [self updateAutomaticRegistration];
        [self updateIdentityResolution];
        [self.identityResolver maintainSynchronization];
        [self probePendingIdentity];
        [self flushIdentityAdvertisements];
        if (self.running) self.status = self.usingServiceFilters && !self.scanServiceUUIDs.count ? @"Import or enter Bluetooth service UUIDs to scan" : [NSString stringWithFormat:@"%@ · %lu client(s) · %lu devices · %lu connections", self.usingServiceFilters ? @"Scanning known services" : @"Scanning", (unsigned long)self.server.authenticatedClients, (unsigned long)self.observations.count, (unsigned long)self.sessions.count];
        [self changed];
    }
    if (!(self.tickCount % 20)) [self writeDiagnostics];
}
- (NSTimeInterval)identityProbeIntervalForObservation:(NSDictionary *)observation {
    NSString *identifier=observation[@"identifier"];
    if(identifier.length && [self.identityProbeAttempts[identifier] unsignedIntegerValue]>=2)return 3600;
    if([observation[@"gatt_probe_attempts"] unsignedIntegerValue]>=2)return 3600;
    for(NSDictionary *value in [observation[@"gatt_fingerprints"] allValues])if([value[@"sessions"] unsignedIntegerValue]==1)return 60;
    return 3600;
}
- (void)probePendingIdentity {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!self.identitiesReady || now < self.nextIdentityProbeAt || self.sessions.count >= HABLESlots) return;
    for (HABLEPeripheralSession *session in self.sessions.allValues) if (session.identityCompletion) return;
    NSArray *probeOrder=[self.observations.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b) {
        BOOL verifyA=[self identityProbeIntervalForObservation:self.observations[a]]==60,verifyB=[self identityProbeIntervalForObservation:self.observations[b]]==60;
        if(verifyA!=verifyB)return verifyA ? NSOrderedAscending : NSOrderedDescending;
        return [self.observations[b][@"rssi"] compare:self.observations[a][@"rssi"]];
    }];
    for (NSString *identifier in probeOrder) {
        NSDictionary *observation = self.observations[identifier];
        if (self.mappings[identifier] || self.automaticMappings[identifier] || ![observation[@"connectable"] boolValue] || now-[observation[@"last_seen"] doubleValue]>15 || now-[observation[@"first_seen"] doubleValue]<60 || now-[self.identityProbeTimes[identifier] doubleValue]<[self identityProbeIntervalForObservation:observation] || ![self.identityResolver hasKnownIdentityForObservation:observation]) continue;
        self.identityProbeAttempts[identifier]=@(MIN(255,[self.identityProbeAttempts[identifier] unsignedIntegerValue]+1));
        self.identityProbeTimes[identifier] = @(now); self.nextIdentityProbeAt = now + 60;
        __weak typeof(self) weakSelf = self;
        [self inspectIdentifier:identifier completion:^(NSDictionary *identity, NSError *error) {
            HABLEProxyManager *self = weakSelf; if (!self) return;
            [self.identityCheckTimes removeObjectForKey:identifier];
            if (identity) [self matchIdentifier:identifier];
        }];
        return;
    }
}
- (void)writeDiagnostics {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self diagnostics] options:NSJSONWritingPrettyPrinted error:nil];
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:[directory stringByAppendingPathComponent:@"ble-proxy-diagnostics.json"] atomically:YES];
}

#pragma mark - ESPHome API
- (NSData *)slotData {
    NSMutableData *data = [NSMutableData data]; HABLEPutInteger(data, 1, HABLESlots - MIN(HABLESlots, self.sessions.count)); HABLEPutInteger(data, 2, HABLESlots);
    for (NSNumber *address in self.sessions) HABLEPutInteger(data, 3, address.unsignedLongLongValue); return data;
}
- (void)slotsChanged { [self.server broadcastSlots:[self slotData]]; }
- (void)bleServer:(HABLEAPIServer *)server receivedType:(NSUInteger)type data:(NSData *)data connection:(HABLEAPIConnection *)connection {
    NSDictionary *fields = HABLEDecode(data); if (!fields) return;
    NSMutableData *reply = [NSMutableData data];
    switch (type) {
        case 1: HABLEPutInteger(reply, 1, 1); HABLEPutInteger(reply, 2, 12); HABLEPutString(reply, 3, @"HA Dashboard BLE proxy"); HABLEPutString(reply, 4, self.nodeName); [server sendType:2 data:reply to:connection]; break;
        case 3: [server sendType:4 data:reply to:connection]; break;
        case 5: [server sendType:6 data:reply to:connection]; break;
        case 7: [server sendType:8 data:reply to:connection]; break;
        case 9:
            HABLEPutString(reply, 2, self.nodeName); HABLEPutString(reply, 3, self.adapterAddress);
            HABLEPutString(reply, 4, @"2026.8.2"); HABLEPutString(reply, 6, @"iOS CoreBluetooth proxy");
            HABLEPutString(reply, 8, @"ha-dashboard.ble-proxy"); HABLEPutString(reply, 9, @"0.1.0");
            HABLEPutString(reply, 12, @"HA Dashboard"); HABLEPutString(reply, 13, [NSString stringWithFormat:@"%@ Bluetooth Proxy", [[NSUserDefaults standardUserDefaults] stringForKey:@"ha_device_name_override"] ?: [UIDevice currentDevice].name]);
            HABLEPutInteger(reply, 15, 7); HABLEPutString(reply, 18, self.adapterAddress);
            [server sendType:10 data:reply to:connection]; break;
        case 11: [server sendType:19 data:reply to:connection]; break;
        case 28: connection.logs = YES; [server broadcastLog:[NSString stringWithFormat:@"Public CoreBluetooth proxy; %@; %@:%d", self.status, self.host, 6053]]; break;
        case 66: connection.advertisements = YES; break;
        case 87: connection.advertisements = NO; break;
        case 80: connection.connectionSlots = YES; [server sendType:81 data:[self slotData] to:connection]; break;
        case 68: [self deviceRequest:fields connection:connection]; break;
        case 70: case 73: case 75: case 76: case 77: case 78: [self gattRequest:fields type:type connection:connection]; break;
        default: break;
    }
}
- (void)bleServer:(HABLEAPIServer *)server closedConnection:(HABLEAPIConnection *)connection {
    for (HABLEPeripheralSession *session in [self.sessions.allValues copy]) if (session.owner == connection) { [self.central cancelPeripheralConnection:session.peripheral]; [self.sessions removeObjectForKey:session.address]; }
    [self slotsChanged];
}
- (void)connectionResponse:(HABLEPeripheralSession *)session connected:(BOOL)connected error:(NSUInteger)error {
    NSMutableData *data = [NSMutableData data]; HABLEPutInteger(data, 1, session.address.unsignedLongLongValue); HABLEPutInteger(data, 2, connected); HABLEPutInteger(data, 3, connected ? MAX(23, [session.peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse] + 3) : 23); HABLEPutInteger(data, 4, error);
    [self.server sendType:69 data:data to:session.owner];
}
- (void)deviceRequest:(NSDictionary *)fields connection:(HABLEAPIConnection *)connection {
    NSNumber *address = @(HABLEInteger(fields, 1)); NSUInteger type = (NSUInteger)HABLEInteger(fields, 2);
    HABLEPeripheralSession *session = self.sessions[address];
    if (type == 1) {
        if (session && session.owner == connection) [self.central cancelPeripheralConnection:session.peripheral];
        else {
            // A disconnect is idempotent for this client. Do not cancel another
            // client's session, but always complete this client's state waiter.
            HABLEPeripheralSession *response = [[HABLEPeripheralSession alloc] init];
            response.address = address; response.owner = connection;
            [self connectionResponse:response connected:NO error:session ? 132 : 0];
        }
        return;
    }
    if (type != 0 && type != 4 && type != 5) { [self gattError:address handle:0 error:6 connection:connection]; return; }
    if (session || self.sessions.count >= HABLESlots) {
        // aioesphomeapi subscribes to connection responses (69), not GATT
        // errors (82), while connecting. Complete failures through that API.
        HABLEPeripheralSession *response = [[HABLEPeripheralSession alloc] init];
        response.address = address; response.owner = connection;
        [self connectionResponse:response connected:NO error:132]; return;
    }
    CBPeripheral *peripheral;
    for (NSString *identifier in self.peripherals) if ([self addressForIdentifier:identifier] == address.unsignedLongLongValue) { peripheral = self.peripherals[identifier]; break; }
    session = [[HABLEPeripheralSession alloc] init]; session.address = address; session.owner = connection; session.peripheral = peripheral;
    if (!peripheral) { [self connectionResponse:session connected:NO error:62]; return; }
    session.handles = [NSMutableDictionary dictionary]; session.operations = [NSMutableArray array]; session.deadline = CFAbsoluteTimeGetCurrent() + 25;
    NSString *identifier = peripheral.identifier.UUIDString;
    session.handleIDs = [self.handleTables[identifier] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (session.handleIDs.count > 1024 || (!self.handleTables[identifier] && self.handleTables.count >= 128)) { [self connectionResponse:session connected:NO error:17]; return; }
    session.nextHandle = 1;
    for (id value in session.handleIDs.allValues) {
        if (![value isKindOfClass:[NSNumber class]] || [value unsignedIntegerValue] == 0 || [value unsignedIntegerValue] > 65534) { [self connectionResponse:session connected:NO error:17]; return; }
        session.nextHandle = MAX(session.nextHandle, [value unsignedIntegerValue] + 1);
    }
    self.sessions[address] = session; peripheral.delegate = self; [self slotsChanged]; [self.central connectPeripheral:peripheral options:nil];
}
- (HABLEPeripheralSession *)sessionFor:(CBPeripheral *)peripheral {
    for (HABLEPeripheralSession *session in self.sessions.allValues) if (session.peripheral == peripheral) return session; return nil;
}
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session) return;
    // V3 clients may immediately use their cached handles. Resolve Apple's
    // current objects before announcing a usable connection, on every connect.
    session.preparingConnection = YES;
    [session.operations addObject:@{@"type":@70, @"fields":@{}}]; [self pump:session];
}
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error { [self centralManager:central didDisconnectPeripheral:peripheral error:error]; }
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session) return;
    if (session.identityCompletion) [self finishIdentity:session error:@"The device disconnected before identification completed."];
    [self connectionResponse:session connected:NO error:error ? 8 : 0]; [self.sessions removeObjectForKey:session.address]; [self slotsChanged];
}
- (void)gattError:(NSNumber *)address handle:(NSUInteger)handle error:(NSUInteger)error connection:(HABLEAPIConnection *)connection {
    NSMutableData *data = [NSMutableData data]; HABLEPutInteger(data, 1, address.unsignedLongLongValue); HABLEPutInteger(data, 2, handle); HABLEPutInteger(data, 3, error);
    [self.server sendType:82 data:data to:connection];
}
- (void)gattRequest:(NSDictionary *)fields type:(NSUInteger)type connection:(HABLEAPIConnection *)connection {
    NSNumber *address = @(HABLEInteger(fields, 1)); HABLEPeripheralSession *session = self.sessions[address];
    if (!session || session.owner != connection || session.peripheral.state != CBPeripheralStateConnected) { [self gattError:address handle:(NSUInteger)HABLEInteger(fields, 2) error:2 connection:connection]; return; }
    if (session.operations.count >= 32) { [self gattError:address handle:(NSUInteger)HABLEInteger(fields, 2) error:17 connection:connection]; return; }
    [session.operations addObject:@{@"type":@(type), @"fields":fields}]; [self pump:session];
}
- (void)pump:(HABLEPeripheralSession *)session {
    if (session.pending) return;
    if (!session.operations.count) { if (session.identityCompletion && !session.preparingConnection) [self finishIdentity:session error:nil]; return; }
    session.pending = session.operations.firstObject; [session.operations removeObjectAtIndex:0]; session.deadline = CFAbsoluteTimeGetCurrent() + 20;
    NSUInteger type = [session.pending[@"type"] unsignedIntegerValue]; NSDictionary *fields = session.pending[@"fields"];
    if (type == 70) {
        if (session.serializedServices) { [self sendServices:session]; [self finishOperation:session error:0]; return; }
        session.discovering = YES; session.discoveryWork = 1; [session.handles removeAllObjects]; [session.peripheral discoverServices:nil]; return;
    }
    NSNumber *handle = @(HABLEInteger(fields, 2)); id attribute = session.handles[handle]; NSData *bytes = HABLEBytes(fields, type == 75 ? 4 : 3) ?: [NSData data];
    BOOL characteristic = [attribute isKindOfClass:[CBCharacteristic class]], descriptor = [attribute isKindOfClass:[CBDescriptor class]];
    if ((type == 73 || type == 75 || type == 78) && characteristic) {
        if (type == 73) [session.peripheral readValueForCharacteristic:attribute];
        else if (type == 75) {
            BOOL response = HABLEInteger(fields, 3) != 0;
            if (bytes.length > [session.peripheral maximumWriteValueLengthForType:response ? CBCharacteristicWriteWithResponse : CBCharacteristicWriteWithoutResponse]) { [self finishOperation:session error:13]; return; }
            [session.peripheral writeValue:bytes forCharacteristic:attribute type:response ? CBCharacteristicWriteWithResponse : CBCharacteristicWriteWithoutResponse];
            if (!response) [self finishOperation:session error:0];
        } else {
            BOOL enable = HABLEInteger(fields, 3) != 0;
            if ([(CBCharacteristic *)attribute isNotifying] == enable) [self finishOperation:session error:0];
            else [session.peripheral setNotifyValue:enable forCharacteristic:attribute];
        }
    } else if ((type == 76 || type == 77) && descriptor) {
        if (type == 76) [session.peripheral readValueForDescriptor:attribute];
        else if ([[(CBDescriptor *)attribute UUID] isEqual:[CBUUID UUIDWithString:@"2902"]]) {
            // V3 ESPHome clients explicitly write the CCCD after subscribing.
            // CoreBluetooth owns that descriptor, so translate its value into
            // the public notification API rather than attempting a raw write.
            const uint8_t *value = bytes.bytes;
            if (bytes.length != 2 || value[1] || value[0] > 2) { [self finishOperation:session error:13]; return; }
            CBCharacteristic *characteristic = [(CBDescriptor *)attribute characteristic];
            BOOL enable = value[0] != 0;
            if (characteristic.isNotifying == enable) [self finishOperation:session error:0];
            else [session.peripheral setNotifyValue:enable forCharacteristic:characteristic];
        } else [session.peripheral writeValue:bytes forDescriptor:attribute];
    } else [self finishOperation:session error:1];
}
- (void)finishOperation:(HABLEPeripheralSession *)session error:(NSUInteger)error {
    if (!session.pending) return;
    if(error && session.identityCompletion && [session.pending[@"type"] integerValue]==73) {
        NSNumber *handle=@(HABLEInteger(session.pending[@"fields"],2));NSString *path=session.identityReadPaths[handle];
        NSMutableDictionary *errors=session.identityValues[@"gatt_read_errors"];if(!errors){errors=NSMutableDictionary.dictionary;session.identityValues[@"gatt_read_errors"]=errors;}if(path)errors[path]=@(error);
        session.pending=nil;[self pump:session];return;
    }
    if (error && session.identityCompletion) {
        session.pending = nil; session.discovering = NO; [session.operations removeAllObjects];
        [self finishIdentity:session error:@"The device could not provide its identifying characteristics."]; return;
    }
    if (session.preparingConnection && error) {
        session.preparingConnection = NO; session.discovering = NO; session.pending = nil;
        [self connectionResponse:session connected:NO error:error]; [self.central cancelPeripheralConnection:session.peripheral]; return;
    }
    NSUInteger type = [session.pending[@"type"] unsignedIntegerValue]; NSUInteger handle = (NSUInteger)HABLEInteger(session.pending[@"fields"], 2);
    if (error) [self gattError:session.address handle:handle error:error connection:session.owner];
    else if (type == 75 || type == 77 || type == 78) {
        if (type == 75 || type == 77) self.gattWrites++;
        NSMutableData *data = [NSMutableData data]; HABLEPutInteger(data, 1, session.address.unsignedLongLongValue); HABLEPutInteger(data, 2, handle);
        [self.server sendType:type == 78 ? 84 : 83 data:data to:session.owner];
    }
    session.pending = nil; session.discovering = NO; [self pump:session];
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session.discovering) return;
    if (error) { [self finishOperation:session error:10]; return; }
    if (peripheral.services.count > 64) { [self finishOperation:session error:17]; return; }
    session.discoveryWork += peripheral.services.count;
    for (CBService *service in peripheral.services) [peripheral discoverCharacteristics:nil forService:service];
    [self discoveryPartDone:session];
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session.discovering) return;
    if (error) { [self finishOperation:session error:10]; return; }
    if (service.characteristics.count > 128) { [self finishOperation:session error:17]; return; }
    session.discoveryWork += service.characteristics.count;
    for (CBCharacteristic *characteristic in service.characteristics) [peripheral discoverDescriptorsForCharacteristic:characteristic];
    [self discoveryPartDone:session];
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session.discovering) return;
    if (error) { [self finishOperation:session error:10]; return; } [self discoveryPartDone:session];
}
- (void)discoveryPartDone:(HABLEPeripheralSession *)session {
    if (--session.discoveryWork) return;
    NSMutableArray *responses = [NSMutableArray array];
    NSMutableDictionary *serviceOccurrences = [NSMutableDictionary dictionary];
    for (CBService *service in session.peripheral.services) {
        NSString *serviceKey = [self pathForUUID:service.UUID parent:@"s" occurrences:serviceOccurrences];
        NSUInteger handle = [self handleForPath:serviceKey session:session];
        if (!handle) { [self finishOperation:session error:17]; return; }
        NSMutableData *serviceData = [NSMutableData data]; HABLEPutUUID(serviceData, service.UUID); HABLEPutInteger(serviceData, 2, handle); session.handles[@(handle)] = service;
        NSMutableDictionary *characteristicOccurrences = [NSMutableDictionary dictionary];
        for (CBCharacteristic *characteristic in service.characteristics) {
            NSString *characteristicKey = [self pathForUUID:characteristic.UUID parent:serviceKey occurrences:characteristicOccurrences];
            handle = [self handleForPath:characteristicKey session:session];
            if (!handle || characteristic.descriptors.count > 64) { [self finishOperation:session error:17]; return; }
            NSMutableData *characteristicData = [NSMutableData data]; HABLEPutUUID(characteristicData, characteristic.UUID); HABLEPutInteger(characteristicData, 2, handle); session.handles[@(handle)] = characteristic;
            HABLEPutInteger(characteristicData, 3, characteristic.properties);
            NSMutableDictionary *descriptorOccurrences = [NSMutableDictionary dictionary];
            for (CBDescriptor *descriptor in characteristic.descriptors) {
                NSString *descriptorKey = [self pathForUUID:descriptor.UUID parent:characteristicKey occurrences:descriptorOccurrences];
                handle = [self handleForPath:descriptorKey session:session];
                if (!handle) { [self finishOperation:session error:17]; return; }
                NSMutableData *descriptorData = [NSMutableData data]; HABLEPutUUID(descriptorData, descriptor.UUID); HABLEPutInteger(descriptorData, 2, handle); session.handles[@(handle)] = descriptor;
                HABLEPutBytes(characteristicData, 4, descriptorData);
            }
            HABLEPutBytes(serviceData, 3, characteristicData);
        }
        NSMutableData *response = [NSMutableData data]; HABLEPutInteger(response, 1, session.address.unsignedLongLongValue); HABLEPutBytes(response, 2, serviceData);
        if (response.length > 16384) { [self finishOperation:session error:17]; return; }
        [responses addObject:response];
    }
    session.serializedServices = responses;
    self.handleTables[session.peripheral.identifier.UUIDString] = [session.handleIDs copy];
    [[NSUserDefaults standardUserDefaults] setObject:self.handleTables forKey:@"ha_ble_proxy_handle_tables"];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) { [self finishOperation:session error:17]; return; }
    if (session.preparingConnection && session.identityCompletion) {
        session.preparingConnection = NO; session.discovering = NO; session.pending = nil;
        NSMutableArray *serviceUUIDs = [NSMutableArray array], *characteristicUUIDs = [NSMutableArray array];
        NSDictionary *fields = @{@"2A25":@"serial_number", @"2A24":@"model_number", @"2A29":@"manufacturer_name", @"2A23":@"system_id"};
        for (CBService *service in session.peripheral.services) [serviceUUIDs addObject:HABLEAdvertisementUUID(service.UUID)];
        NSMutableArray *readCandidates=NSMutableArray.array;
        for (NSNumber *handle in session.handles) {
            id attribute = session.handles[handle]; if (![attribute isKindOfClass:[CBCharacteristic class]]) continue;
            CBCharacteristic *characteristic = attribute;
            [characteristicUUIDs addObject:HABLEAdvertisementUUID(characteristic.UUID)];
            NSString *field = fields[characteristic.UUID.UUIDString.uppercaseString];
            if(characteristic.properties & CBCharacteristicPropertyRead) {
                BOOL standard=field && [characteristic.service.UUID isEqual:[CBUUID UUIDWithString:@"180A"]];
                if(standard)session.identityFields[handle]=field;
                NSString *path=[session.handleIDs allKeysForObject:handle].firstObject;
                if(path)[readCandidates addObject:@{@"handle":handle,@"path":path,@"priority":@(standard ? ([field isEqual:@"serial_number"] ? 0 : [field isEqual:@"system_id"] ? 1 : 2) : 3)}];
            }
        }
        [readCandidates sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSComparisonResult order=[a[@"priority"] compare:b[@"priority"]];return order==NSOrderedSame ? [a[@"path"] compare:b[@"path"]] : order;}];
        for(NSDictionary *candidate in readCandidates) {
            if(session.identityReadPaths.count>=16)break;NSNumber *handle=candidate[@"handle"];session.identityReadPaths[handle]=candidate[@"path"];
            [session.operations addObject:@{@"type":@73,@"fields":@{@1:@[session.address],@2:@[handle]}}];
        }
        session.identityValues[@"gatt_readable_characteristic_count"]=@(readCandidates.count);
        session.identityValues[@"gatt_reads_truncated"]=@(readCandidates.count>session.identityReadPaths.count);
        session.identityValues[@"gatt_service_uuids"] = serviceUUIDs;
        session.identityValues[@"gatt_characteristic_uuids"] = characteristicUUIDs;
        [self pump:session]; return;
    } else if (session.preparingConnection) { session.preparingConnection = NO; [self connectionResponse:session connected:YES error:0]; }
    else [self sendServices:session];
    [self finishOperation:session error:0];
}
- (NSString *)pathForUUID:(CBUUID *)uuid parent:(NSString *)parent occurrences:(NSMutableDictionary *)occurrences {
    NSString *name = HABLEAdvertisementUUID(uuid); NSUInteger index = [occurrences[name] unsignedIntegerValue]; occurrences[name] = @(index + 1);
    return [NSString stringWithFormat:@"%@/%@#%lu", parent, name, (unsigned long)index];
}
- (NSUInteger)handleForPath:(NSString *)path session:(HABLEPeripheralSession *)session {
    NSNumber *existing = session.handleIDs[path]; if (existing) return existing.unsignedIntegerValue;
    if (session.handleIDs.count >= 1024 || session.nextHandle >= 65535) return 0;
    NSUInteger handle = session.nextHandle++; session.handleIDs[path] = @(handle); return handle;
}
- (void)sendServices:(HABLEPeripheralSession *)session {
    for (NSData *response in session.serializedServices) [self.server sendType:71 data:response to:session.owner];
    NSMutableData *done = [NSMutableData data]; HABLEPutInteger(done, 1, session.address.unsignedLongLongValue); [self.server sendType:72 data:done to:session.owner];
}
- (void)peripheral:(CBPeripheral *)peripheral didModifyServices:(NSArray<CBService *> *)invalidatedServices {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session) return;
    session.serializedServices = nil; [session.handles removeAllObjects];
    // Never route cached commands through invalidated CoreBluetooth objects.
    [self.central cancelPeripheralConnection:peripheral];
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session) return;
    NSNumber *handle = [[session.handles allKeysForObject:characteristic] firstObject]; if (!handle) return;
    BOOL reading = [session.pending[@"type"] integerValue] == 73 && HABLEInteger(session.pending[@"fields"], 2) == handle.unsignedLongLongValue;
    if (error) { if (reading) [self finishOperation:session error:14]; return; }
    if (reading && session.identityCompletion) {
        NSString *field = session.identityFields[handle]; NSData *value = characteristic.value;
        if (field && value.length <= 1024) {
            NSString *text = [field isEqual:@"system_id"] ? nil : [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
            if (!text) { NSMutableString *hex = [NSMutableString string]; const uint8_t *bytes = value.bytes; for (NSUInteger i = 0; i < value.length; i++) [hex appendFormat:@"%02X", bytes[i]]; text = hex; }
            session.identityValues[field] = [text stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
        }
        NSString *path=session.identityReadPaths[handle];
        if(path && value.length && value.length<=512) {
            NSMutableDictionary *reads=session.identityValues[@"gatt_fingerprint_reads"];if(!reads){reads=NSMutableDictionary.dictionary;session.identityValues[@"gatt_fingerprint_reads"]=reads;}
            NSDictionary *fields=[HABLEIdentityEvidence fingerprintsForValue:value path:path];
            for(NSString *key in fields)if(reads.count<64 || reads[key])reads[key]=fields[key];
        }
        if(field && self.identitiesReady) {
            NSMutableDictionary *candidate=[self.observations[peripheral.identifier.UUIDString] mutableCopy] ?: NSMutableDictionary.dictionary;
            [candidate addEntriesFromDictionary:session.identityValues];
            if([self.identityResolver automaticMatchForObservation:candidate])[session.operations removeAllObjects];
        }
        self.gattReads++; [self finishOperation:session error:0]; return;
    }
    NSMutableData *data = [NSMutableData data]; HABLEPutInteger(data, 1, session.address.unsignedLongLongValue); HABLEPutInteger(data, 2, handle.unsignedLongLongValue); HABLEPutBytes(data, 3, characteristic.value ?: [NSData data]);
    if (reading) { self.gattReads++; [self.server sendType:74 data:data to:session.owner]; [self finishOperation:session error:0]; }
    if (characteristic.isNotifying) { self.gattNotifications++; [self.server sendType:79 data:data to:session.owner]; }
}
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error { [self finishOperation:[self sessionFor:peripheral] error:error ? 14 : 0]; }
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error { [self finishOperation:[self sessionFor:peripheral] error:error ? 14 : 0]; }
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error { [self finishOperation:[self sessionFor:peripheral] error:error ? 14 : 0]; }
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {
    HABLEPeripheralSession *session = [self sessionFor:peripheral]; if (!session.pending) return;
    if (error) { [self finishOperation:session error:14]; return; }
    NSData *value = [descriptor.value isKindOfClass:[NSData class]] ? descriptor.value : nil;
    if ([descriptor.value isKindOfClass:[NSString class]]) value = [descriptor.value dataUsingEncoding:NSUTF8StringEncoding];
    else if ([descriptor.value isKindOfClass:[NSNumber class]]) { uint16_t number = CFSwapInt16HostToLittle([descriptor.value unsignedShortValue]); value = [NSData dataWithBytes:&number length:2]; }
    NSMutableData *data = [NSMutableData data]; HABLEPutInteger(data, 1, session.address.unsignedLongLongValue); HABLEPutInteger(data, 2, HABLEInteger(session.pending[@"fields"], 2)); HABLEPutBytes(data, 3, value ?: [NSData data]);
    [self.server sendType:74 data:data to:session.owner]; [self finishOperation:session error:0];
}
@end
