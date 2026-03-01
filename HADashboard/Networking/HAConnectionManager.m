#import "HAConnectionManager.h"
#import "HAAPIClient.h"
#import "HAWebSocketClient.h"
#import "HAAuthManager.h"
#import "HAEntity.h"
#import "HAFloor.h"
#import "HALovelaceParser.h"
#import "HAStrategyResolver.h"
#import "HADemoDataProvider.h"

NSString *const HAConnectionManagerDidConnectNotification           = @"HAConnectionManagerDidConnect";
NSString *const HAConnectionManagerDidDisconnectNotification        = @"HAConnectionManagerDidDisconnect";
NSString *const HAConnectionManagerEntityDidUpdateNotification      = @"HAConnectionManagerEntityDidUpdate";
NSString *const HAConnectionManagerDidReceiveAllStatesNotification  = @"HAConnectionManagerDidReceiveAllStates";
NSString *const HAConnectionManagerDidReceiveLovelaceNotification   = @"HAConnectionManagerDidReceiveLovelace";
NSString *const HAConnectionManagerDidReceiveDashboardListNotification = @"HAConnectionManagerDidReceiveDashboardList";
NSString *const HAConnectionManagerDidReceiveRegistriesNotification    = @"HAConnectionManagerDidReceiveRegistries";

static const NSTimeInterval kReconnectBaseInterval = 2.0;
static const NSTimeInterval kReconnectMaxInterval  = 60.0;

@interface HAConnectionManager () <HAWebSocketClientDelegate>
@property (nonatomic, strong) HAAPIClient *apiClient;
@property (nonatomic, strong) HAWebSocketClient *wsClient;
@property (nonatomic, strong) NSMutableDictionary<NSString *, HAEntity *> *entityStore;
@property (nonatomic, assign, readwrite, getter=isConnected) BOOL connected;
@property (nonatomic, assign) NSInteger reconnectAttempt;
@property (nonatomic, strong) NSTimer *reconnectTimer;
@property (nonatomic, assign) BOOL intentionalDisconnect;
@property (nonatomic, strong, readwrite) HALovelaceDashboard *lovelaceDashboard;
@property (nonatomic, copy) NSDictionary *pendingStrategyConfig; // stored for re-resolution after states/registries load
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *availableDashboards;
@property (nonatomic, assign) NSInteger lovelaceMessageId;
@property (nonatomic, assign) NSInteger dashboardListMessageId;
@property (nonatomic, assign) NSInteger areaRegistryMessageId;
@property (nonatomic, assign) NSInteger entityRegistryMessageId;
@property (nonatomic, assign) NSInteger deviceRegistryMessageId;
@property (nonatomic, assign) NSInteger floorRegistryMessageId;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *areaNames;      // area_id -> area name
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *entityAreaMap;   // entity_id -> area_id
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *deviceAreaMap;   // device_id -> area_id
@property (nonatomic, copy, readwrite) NSArray<HAFloor *> *floors;
@property (nonatomic, strong) NSDictionary<NSString *, HAFloor *> *floorByAreaId;   // area_id -> HAFloor
@property (nonatomic, assign) BOOL areasLoaded;
@property (nonatomic, assign) BOOL entitiesRegistryLoaded;
@property (nonatomic, assign) BOOL devicesLoaded;
@property (nonatomic, assign) BOOL floorsLoaded;
@property (nonatomic, assign, readwrite) BOOL registriesLoaded;
@property (nonatomic, strong) id rawEntityRegistry; // stored for reprocessing after device registry
@property (nonatomic, strong) id rawAreaRegistry;   // stored for floor-area mapping
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, void (^)(id, NSError *)> *pendingCompletions;
@end

@implementation HAConnectionManager

+ (instancetype)sharedManager {
    static HAConnectionManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HAConnectionManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entityStore = [NSMutableDictionary dictionary];
        _pendingCompletions = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Connection

- (void)connect {
    HAAuthManager *auth = [HAAuthManager sharedManager];

    // Demo mode: load bundled demo data instead of connecting to a real server
    if (auth.isDemoMode) {
        [self loadDemoData];
        return;
    }

    if (!auth.isConfigured) {
        NSLog(@"[HAConnection] Cannot connect — not configured");
        return;
    }

    self.intentionalDisconnect = NO;
    self.reconnectAttempt = 0;

    // Set up REST client
    self.apiClient = [[HAAPIClient alloc] initWithBaseURL:auth.restBaseURL token:auth.accessToken];

    // Set up WebSocket client
    self.wsClient = [[HAWebSocketClient alloc] initWithURL:auth.webSocketURL token:auth.accessToken];
    self.wsClient.delegate = self;
    [self.wsClient connect];
}

- (void)loadDemoData {
    NSLog(@"[HAConnection] Loading demo data");

    HADemoDataProvider *demo = [HADemoDataProvider sharedProvider];

    // Populate entity store with demo entities
    @synchronized(self.entityStore) {
        [self.entityStore removeAllObjects];
        [self.entityStore addEntriesFromDictionary:demo.allEntities];
    }

    // Set demo dashboard — respect previously selected path if available
    NSString *selectedPath = [[HAAuthManager sharedManager] selectedDashboardPath];
    if (selectedPath) {
        self.lovelaceDashboard = [demo dashboardForPath:selectedPath];
    } else {
        self.lovelaceDashboard = demo.demoDashboard;
    }
    self.availableDashboards = demo.availableDashboards;

    // Mark as connected (for UI purposes)
    self.connected = YES;
    self.registriesLoaded = YES;

    // Start state simulation
    [demo startSimulation];

    // Post notifications to update UI
    [self.delegate connectionManagerDidConnect:self];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerDidConnectNotification
                      object:self];

    NSDictionary *entities = [self allEntities];
    [self.delegate connectionManager:self didReceiveAllStates:entities];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerDidReceiveAllStatesNotification
                      object:self
                    userInfo:@{@"entities": entities}];

    if (self.lovelaceDashboard) {
        [self.delegate connectionManager:self didReceiveLovelaceDashboard:self.lovelaceDashboard];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:HAConnectionManagerDidReceiveLovelaceNotification
                          object:self
                        userInfo:@{@"dashboard": self.lovelaceDashboard}];
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerDidReceiveDashboardListNotification
                      object:self
                    userInfo:@{@"dashboards": self.availableDashboards}];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerDidReceiveRegistriesNotification
                      object:self];
}

- (void)disconnect {
    // Stop demo simulation if running
    if ([[HAAuthManager sharedManager] isDemoMode]) {
        [[HADemoDataProvider sharedProvider] stopSimulation];
    }

    self.intentionalDisconnect = YES;
    [self cancelReconnect];
    [self.wsClient disconnect];
    self.wsClient = nil;
    self.apiClient = nil;
    self.connected = NO;

    // Clear all cached data so a subsequent connect() starts fresh
    @synchronized(self.entityStore) {
        [self.entityStore removeAllObjects];
    }
    self.lovelaceDashboard = nil;
    self.pendingStrategyConfig = nil;
    self.availableDashboards = nil;
    self.areaNames = nil;
    self.entityAreaMap = nil;
    self.deviceAreaMap = nil;
    self.floors = nil;
    self.floorByAreaId = nil;
    self.rawEntityRegistry = nil;
    self.rawAreaRegistry = nil;
    self.registriesLoaded = NO;
    self.areasLoaded = NO;
    self.entitiesRegistryLoaded = NO;
    self.devicesLoaded = NO;
    self.floorsLoaded = NO;
    self.lovelaceMessageId = 0;
    self.dashboardListMessageId = 0;
    self.areaRegistryMessageId = 0;
    self.entityRegistryMessageId = 0;
    self.deviceRegistryMessageId = 0;
    self.floorRegistryMessageId = 0;
}

#pragma mark - Data

- (void)fetchAllStates {
    // Demo mode: entities are already in-memory, just re-deliver them
    if ([[HAAuthManager sharedManager] isDemoMode]) {
        NSDictionary *entities = [self allEntities];
        [self.delegate connectionManager:self didReceiveAllStates:entities];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:HAConnectionManagerDidReceiveAllStatesNotification
                          object:self
                        userInfo:@{@"entities": entities}];
        return;
    }
    if (!self.apiClient) return;

    [self.apiClient getStatesWithCompletion:^(id response, NSError *error) {
        if (error) {
            NSLog(@"[HAConnection] Failed to fetch states: %@", error);
            return;
        }

        if (![response isKindOfClass:[NSArray class]]) return;

        NSArray *stateArray = (NSArray *)response;
        @synchronized(self.entityStore) {
            for (NSDictionary *stateDict in stateArray) {
                if (![stateDict isKindOfClass:[NSDictionary class]]) continue;
                NSString *entityId = stateDict[@"entity_id"];
                if (!entityId) continue;

                HAEntity *existing = self.entityStore[entityId];
                if (existing) {
                    [existing updateWithDictionary:stateDict];
                } else {
                    HAEntity *entity = [[HAEntity alloc] initWithDictionary:stateDict];
                    self.entityStore[entityId] = entity;
                }
            }
        }

        NSDictionary *snapshot = [self allEntities];

        // Re-resolve pending strategy dashboard now that entities are available
        if (self.pendingStrategyConfig && snapshot.count > 0) {
            NSLog(@"[HAConnection] Re-resolving strategy dashboard with %lu entities", (unsigned long)snapshot.count);
            HALovelaceDashboard *resolved =
                [HAStrategyResolver resolveDashboardWithStrategy:self.pendingStrategyConfig
                                                       entities:snapshot
                                                      areaNames:self.areaNames ?: @{}
                                                  entityAreaMap:self.entityAreaMap ?: @{}
                                                 deviceAreaMap:self.deviceAreaMap ?: @{}
                                                         floors:self.floors
                                                 entityRegistry:self.entityRegistryEntries];
            if (resolved) {
                self.lovelaceDashboard = resolved;
                if ([self.delegate respondsToSelector:@selector(connectionManager:didReceiveLovelaceDashboard:)]) {
                    [self.delegate connectionManager:self didReceiveLovelaceDashboard:self.lovelaceDashboard];
                }
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:HAConnectionManagerDidReceiveLovelaceNotification
                                  object:self
                                userInfo:@{@"dashboard": self.lovelaceDashboard}];
            }
        }

        [self.delegate connectionManager:self didReceiveAllStates:snapshot];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:HAConnectionManagerDidReceiveAllStatesNotification
                          object:self
                        userInfo:@{@"entities": snapshot}];
    }];
}

- (void)fetchDashboardList {
    // Demo mode: re-deliver the demo dashboard list
    if ([[HAAuthManager sharedManager] isDemoMode]) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:HAConnectionManagerDidReceiveDashboardListNotification
                          object:self
                        userInfo:@{@"dashboards": self.availableDashboards}];
        return;
    }
    if (self.wsClient.isAuthenticated) {
        self.dashboardListMessageId = [self.wsClient fetchDashboardList];
    } else {
        NSLog(@"[HAConnection] Cannot fetch dashboard list — WebSocket not authenticated");
    }
}

- (void)fetchLovelaceConfig:(NSString *)urlPath {
    // Demo mode: look up dashboard from demo provider and deliver via standard pipeline
    if ([[HAAuthManager sharedManager] isDemoMode]) {
        HALovelaceDashboard *dash = [[HADemoDataProvider sharedProvider] dashboardForPath:urlPath];
        if (dash) {
            self.lovelaceDashboard = dash;
            [self.delegate connectionManager:self didReceiveLovelaceDashboard:dash];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:HAConnectionManagerDidReceiveLovelaceNotification
                              object:self
                            userInfo:@{@"dashboard": dash}];
        }
        return;
    }

    if (self.wsClient.isAuthenticated) {
        self.lovelaceMessageId = [self.wsClient fetchLovelaceConfigForDashboard:urlPath];
    } else {
        NSLog(@"[HAConnection] Cannot fetch Lovelace — WebSocket not authenticated");
    }
}

- (void)callService:(NSString *)service
           inDomain:(NSString *)domain
           withData:(NSDictionary *)data
    entityId:(NSString *)entityId {

    if (!service || !domain) {
        NSLog(@"[HAConnection] callService: missing service (%@) or domain (%@), ignoring", service, domain);
        return;
    }

    NSMutableDictionary *serviceData = data ? [data mutableCopy] : [NSMutableDictionary dictionary];
    if (entityId) {
        serviceData[@"entity_id"] = entityId;
    }

    // Apply optimistic state update before sending — UI refreshes immediately
    [self applyOptimisticUpdateForService:service domain:domain data:serviceData entityId:entityId];

    // In demo mode, just log and return (no actual service call)
    if ([[HAAuthManager sharedManager] isDemoMode]) {
        NSLog(@"[HAConnection] Demo mode: simulated %@.%@ for %@", domain, service, entityId);
        return;
    }

    // Prefer WebSocket if connected
    if (self.wsClient.isAuthenticated) {
        [self.wsClient callService:service inDomain:domain withData:serviceData];
    } else if (self.apiClient) {
        [self.apiClient callService:service inDomain:domain withData:serviceData completion:^(id response, NSError *error) {
            if (error) {
                NSLog(@"[HAConnection] Service call failed: %@", error);
            }
        }];
    }
}

#pragma mark - Optimistic Updates

- (void)applyOptimisticUpdateForService:(NSString *)service
                                 domain:(NSString *)domain
                                   data:(NSDictionary *)data
                               entityId:(NSString *)entityId {
    if (!entityId) return;

    HAEntity *entity;
    @synchronized(self.entityStore) {
        entity = self.entityStore[entityId];
    }
    if (!entity) return;

    NSString *optimisticState = nil;
    NSDictionary *attrOverrides = nil;

    // --- On/Off/Toggle for binary-state domains ---
    if ([service isEqualToString:@"turn_on"]) {
        optimisticState = @"on";
        // Light with brightness
        id brightness = data[@"brightness"];
        if (brightness && [domain isEqualToString:HAEntityDomainLight]) {
            attrOverrides = @{HAAttrBrightness: brightness};
        }
    } else if ([service isEqualToString:@"turn_off"]) {
        optimisticState = @"off";
    } else if ([service isEqualToString:@"toggle"]) {
        // Only apply optimistic toggle for domains that support it
        if ([domain isEqualToString:HAEntityDomainLight] ||
            [domain isEqualToString:HAEntityDomainSwitch] ||
            [domain isEqualToString:HAEntityDomainInputBoolean] ||
            [domain isEqualToString:HAEntityDomainFan] ||
            [domain isEqualToString:HAEntityDomainAutomation] ||
            [domain isEqualToString:HAEntityDomainSiren] ||
            [domain isEqualToString:HAEntityDomainHumidifier] ||
            [domain isEqualToString:HAEntityDomainCover]) {
            optimisticState = entity.isOn ? @"off" : @"on";
        }
    }
    // --- Climate ---
    else if ([service isEqualToString:@"set_temperature"] &&
             [domain isEqualToString:HAEntityDomainClimate]) {
        id temp = data[@"temperature"];
        if (temp) attrOverrides = @{@"temperature": temp};
    } else if ([service isEqualToString:@"set_hvac_mode"] &&
               [domain isEqualToString:HAEntityDomainClimate]) {
        id mode = data[@"hvac_mode"];
        if ([mode isKindOfClass:[NSString class]]) {
            optimisticState = mode;
            // Also update hvac_action to match the new mode for UI consistency
            // In real HA, hvac_action reflects actual HVAC activity and may differ
            // from mode (e.g., mode=heat but action=idle when target reached).
            // For optimistic UI, assume the unit is actively working in new mode.
            NSString *action;
            if ([mode isEqualToString:@"heat"]) {
                action = @"heating";
            } else if ([mode isEqualToString:@"cool"]) {
                action = @"cooling";
            } else if ([mode isEqualToString:@"dry"]) {
                action = @"drying";
            } else if ([mode isEqualToString:@"fan_only"]) {
                action = @"fan";
            } else if ([mode isEqualToString:@"off"]) {
                action = @"off";
            } else {
                action = @"idle"; // auto, heat_cool, or unknown
            }
            attrOverrides = @{@"hvac_action": action};
        }
    }
    // --- Cover ---
    else if ([service isEqualToString:@"open_cover"]) {
        optimisticState = @"open";
    } else if ([service isEqualToString:@"close_cover"]) {
        optimisticState = @"closed";
    } else if ([service isEqualToString:@"set_cover_position"]) {
        id position = data[@"position"];
        if (position) attrOverrides = @{@"current_position": position};
    }
    // --- Lock ---
    else if ([service isEqualToString:@"lock"]) {
        optimisticState = @"locked";
    } else if ([service isEqualToString:@"unlock"]) {
        optimisticState = @"unlocked";
    }
    // --- Input number / number ---
    else if ([service isEqualToString:@"set_value"] &&
             ([domain isEqualToString:HAEntityDomainInputNumber] ||
              [domain isEqualToString:HAEntityDomainNumber])) {
        id value = data[@"value"];
        if (value) optimisticState = [NSString stringWithFormat:@"%@", value];
    }
    // --- Input select / select ---
    else if ([service isEqualToString:@"select_option"] &&
             ([domain isEqualToString:HAEntityDomainInputSelect] ||
              [domain isEqualToString:HAEntityDomainSelect])) {
        id option = data[@"option"];
        if ([option isKindOfClass:[NSString class]]) optimisticState = option;
    }
    // --- Vacuum ---
    else if ([service isEqualToString:@"start"] &&
             [domain isEqualToString:HAEntityDomainVacuum]) {
        optimisticState = @"cleaning";
    } else if ([service isEqualToString:@"return_to_base"] &&
               [domain isEqualToString:HAEntityDomainVacuum]) {
        optimisticState = @"returning";
    }
    // --- Fan ---
    else if ([service isEqualToString:@"set_percentage"] &&
             [domain isEqualToString:HAEntityDomainFan]) {
        id pct = data[@"percentage"];
        if (pct) attrOverrides = @{@"percentage": pct};
    }
    // --- Humidifier ---
    else if ([service isEqualToString:@"set_humidity"] &&
             [domain isEqualToString:HAEntityDomainHumidifier]) {
        id humidity = data[@"humidity"];
        if (humidity) attrOverrides = @{@"humidity": humidity};
    }

    if (!optimisticState && !attrOverrides) return;

    @synchronized(self.entityStore) {
        [entity applyOptimisticState:optimisticState attributeOverrides:attrOverrides];
    }

    // Dispatch the standard entity update notification — existing reload pipeline handles the rest
    [self.delegate connectionManager:self didUpdateEntity:entity];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerEntityDidUpdateNotification
                      object:self
                    userInfo:@{@"entity": entity}];
}

- (void)sendCommand:(NSDictionary *)command
         completion:(void (^)(id result, NSError *error))completion {
    if (!self.wsClient.isAuthenticated) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"HAConnectionManager" code:-1
                userInfo:@{NSLocalizedDescriptionKey: @"WebSocket not connected"}];
            completion(nil, err);
        }
        return;
    }
    NSInteger msgId = [self.wsClient sendCommand:command];
    if (completion) {
        self.pendingCompletions[@(msgId)] = [completion copy];
    }
}

- (HAEntity *)entityForId:(NSString *)entityId {
    @synchronized(self.entityStore) {
        return self.entityStore[entityId];
    }
}

- (NSDictionary<NSString *, HAEntity *> *)allEntities {
    @synchronized(self.entityStore) {
        return [self.entityStore copy];
    }
}

#pragma mark - Registry Processing

- (void)processAreaRegistry:(id)result {
    if (![result isKindOfClass:[NSArray class]]) return;
    self.rawAreaRegistry = result;
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSDictionary *area in (NSArray *)result) {
        if (![area isKindOfClass:[NSDictionary class]]) continue;
        NSString *areaId = area[@"area_id"];
        NSString *name = area[@"name"];
        if (areaId && name) {
            map[areaId] = name;
        }
    }
    self.areaNames = [map copy];
    NSLog(@"[HAConnection] Loaded %lu areas", (unsigned long)map.count);
}

- (void)processDeviceRegistry:(id)result {
    if (![result isKindOfClass:[NSArray class]]) return;
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSDictionary *device in (NSArray *)result) {
        if (![device isKindOfClass:[NSDictionary class]]) continue;
        NSString *deviceId = device[@"id"];
        NSString *areaId = device[@"area_id"];
        if (deviceId && [areaId isKindOfClass:[NSString class]] && areaId.length > 0) {
            map[deviceId] = areaId;
        }
    }
    self.deviceAreaMap = [map copy];
    NSLog(@"[HAConnection] Loaded %lu device->area mappings", (unsigned long)map.count);
}

- (void)processEntityRegistry:(id)result {
    // Store raw result for reprocessing if device registry arrives later
    self.rawEntityRegistry = result;
    [self buildEntityAreaMap];
}

- (void)buildEntityAreaMap {
    id result = self.rawEntityRegistry;
    if (![result isKindOfClass:[NSArray class]]) return;
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in (NSArray *)result) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *entityId = entry[@"entity_id"];
        if (!entityId) continue;

        // Enrich the entity with registry fields
        HAEntity *entity;
        @synchronized(self.entityStore) {
            entity = self.entityStore[entityId];
        }
        if (entity) {
            id entityCategory = entry[@"entity_category"];
            if ([entityCategory isKindOfClass:[NSString class]] && [entityCategory length] > 0) {
                entity.entityCategory = entityCategory;
            } else {
                entity.entityCategory = nil;
            }
            id hiddenBy = entry[@"hidden_by"];
            if ([hiddenBy isKindOfClass:[NSString class]] && [hiddenBy length] > 0) {
                entity.hiddenBy = hiddenBy;
            } else {
                entity.hiddenBy = nil;
            }
            id disabledBy = entry[@"disabled_by"];
            if ([disabledBy isKindOfClass:[NSString class]] && [disabledBy length] > 0) {
                entity.disabledBy = disabledBy;
            } else {
                entity.disabledBy = nil;
            }
            id platform = entry[@"platform"];
            if ([platform isKindOfClass:[NSString class]] && [platform length] > 0) {
                entity.platform = platform;
            } else {
                entity.platform = nil;
            }
        }

        // Direct area assignment takes priority
        NSString *areaId = entry[@"area_id"];
        if ([areaId isKindOfClass:[NSString class]] && areaId.length > 0) {
            map[entityId] = areaId;
            continue;
        }
        // Fall back to device's area
        NSString *deviceId = entry[@"device_id"];
        if ([deviceId isKindOfClass:[NSString class]] && deviceId.length > 0) {
            NSString *deviceArea = self.deviceAreaMap[deviceId];
            if (deviceArea) {
                map[entityId] = deviceArea;
            }
        }
    }

    // Second pass: infer area for scene entities from their controlled entities.
    // Scenes typically have no area_id/device_id in the entity registry, but their
    // state attributes contain an "entity_id" array listing the entities they control.
    // If all controlled entities share the same area, assign the scene to that area.
    @synchronized(self.entityStore) {
        for (NSString *entityId in self.entityStore) {
            if (map[entityId]) continue; // Already has area
            HAEntity *entity = self.entityStore[entityId];
            if (![[entity domain] isEqualToString:@"scene"]) continue;

            NSArray *controlledIds = entity.attributes[@"entity_id"];
            if (![controlledIds isKindOfClass:[NSArray class]] || controlledIds.count == 0) continue;

            NSString *inferredArea = nil;
            BOOL consistent = YES;
            for (NSString *cid in controlledIds) {
                if (![cid isKindOfClass:[NSString class]]) continue;
                NSString *cArea = map[cid];
                if (!cArea) continue;
                if (!inferredArea) {
                    inferredArea = cArea;
                } else if (![inferredArea isEqualToString:cArea]) {
                    consistent = NO;
                    break;
                }
            }
            if (consistent && inferredArea) {
                map[entityId] = inferredArea;
            }
        }
    }

    self.entityAreaMap = [map copy];
    NSLog(@"[HAConnection] Built %lu entity->area mappings", (unsigned long)map.count);
}

- (void)checkRegistriesComplete {
    if (!self.areasLoaded || !self.devicesLoaded || !self.entitiesRegistryLoaded) return;

    // Rebuild entity area map now that device registry is available for fallback
    [self buildEntityAreaMap];

    self.registriesLoaded = YES;
    NSLog(@"[HAConnection] All registries loaded (floors: %@)", self.floorsLoaded ? @"yes" : @"pending");

    // Re-resolve pending strategy dashboard with updated area/entity maps
    if (self.pendingStrategyConfig) {
        NSDictionary *currentEntities = [self allEntities];
        if (currentEntities.count > 0) {
            NSLog(@"[HAConnection] Re-resolving strategy dashboard with registries (%lu areas)",
                  (unsigned long)self.areaNames.count);
            HALovelaceDashboard *resolved =
                [HAStrategyResolver resolveDashboardWithStrategy:self.pendingStrategyConfig
                                                       entities:currentEntities
                                                      areaNames:self.areaNames ?: @{}
                                                  entityAreaMap:self.entityAreaMap ?: @{}
                                                 deviceAreaMap:self.deviceAreaMap ?: @{}
                                                         floors:self.floors
                                                 entityRegistry:self.entityRegistryEntries];
            if (resolved) {
                self.lovelaceDashboard = resolved;
                if ([self.delegate respondsToSelector:@selector(connectionManager:didReceiveLovelaceDashboard:)]) {
                    [self.delegate connectionManager:self didReceiveLovelaceDashboard:self.lovelaceDashboard];
                }
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:HAConnectionManagerDidReceiveLovelaceNotification
                                  object:self
                                userInfo:@{@"dashboard": self.lovelaceDashboard}];
            }
        }
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerDidReceiveRegistriesNotification
                      object:self];
}

- (void)processFloorRegistry:(id)result {
    if (![result isKindOfClass:[NSArray class]]) {
        NSLog(@"[HAConnection] Floor registry not available (older HA version)");
        return;
    }

    // Build floor objects from registry response
    NSMutableDictionary<NSString *, HAFloor *> *floorById = [NSMutableDictionary dictionary];
    for (NSDictionary *floorDict in (NSArray *)result) {
        if (![floorDict isKindOfClass:[NSDictionary class]]) continue;
        HAFloor *floor = [[HAFloor alloc] initWithDictionary:floorDict];
        if (floor.floorId) {
            floorById[floor.floorId] = floor;
        }
    }

    // The WebSocket floor registry may not include area lists.
    // Build floor->area mapping from the area registry (rawAreaRegistry)
    // where each area has a floor_id field.
    if ([self.rawAreaRegistry isKindOfClass:[NSArray class]]) {
        NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *floorAreas = [NSMutableDictionary dictionary];
        for (NSDictionary *areaDict in (NSArray *)self.rawAreaRegistry) {
            if (![areaDict isKindOfClass:[NSDictionary class]]) continue;
            NSString *areaId = areaDict[@"area_id"];
            NSString *floorId = areaDict[@"floor_id"];
            if ([areaId isKindOfClass:[NSString class]] && [floorId isKindOfClass:[NSString class]] && floorId.length > 0) {
                if (!floorAreas[floorId]) {
                    floorAreas[floorId] = [NSMutableArray array];
                }
                [floorAreas[floorId] addObject:areaId];
            }
        }
        // Assign area IDs to floors (overrides any existing areaIds if floor didn't come with them)
        for (NSString *floorId in floorAreas) {
            HAFloor *floor = floorById[floorId];
            if (floor && floor.areaIds.count == 0) {
                floor.areaIds = [floorAreas[floorId] copy];
            }
        }
    }

    NSMutableArray<HAFloor *> *floorList = [[floorById allValues] mutableCopy];
    NSMutableDictionary<NSString *, HAFloor *> *areaLookup = [NSMutableDictionary dictionary];
    for (HAFloor *floor in floorList) {
        for (NSString *areaId in floor.areaIds) {
            areaLookup[areaId] = floor;
        }
    }

    self.floors = [floorList copy];
    self.floorByAreaId = [areaLookup copy];
    NSLog(@"[HAConnection] Loaded %lu floors with %lu area mappings",
          (unsigned long)floorList.count, (unsigned long)areaLookup.count);
}

- (HAFloor *)floorForAreaId:(NSString *)areaId {
    if (!areaId) return nil;
    return self.floorByAreaId[areaId];
}

- (NSString *)areaNameForEntityId:(NSString *)entityId {
    NSString *areaId = self.entityAreaMap[entityId];
    if (!areaId) return nil;
    return self.areaNames[areaId];
}

- (NSString *)areaIdForEntityId:(NSString *)entityId {
    return self.entityAreaMap[entityId];
}

- (NSArray *)entityRegistryEntries {
    if ([self.rawEntityRegistry isKindOfClass:[NSArray class]]) {
        return (NSArray *)self.rawEntityRegistry;
    }
    return @[];
}

- (NSDictionary<NSString *, NSString *> *)areaNamesByAreaId {
    return self.areaNames ?: @{};
}

- (NSDictionary<NSString *, NSString *> *)deviceAreaMapping {
    return self.deviceAreaMap ?: @{};
}

#pragma mark - Reconnection

- (void)scheduleReconnect {
    if (self.intentionalDisconnect) return;

    [self cancelReconnect];

    self.reconnectAttempt++;
    NSTimeInterval delay = MIN(kReconnectBaseInterval * pow(2.0, self.reconnectAttempt - 1), kReconnectMaxInterval);

    NSLog(@"[HAConnection] Reconnecting in %.0fs (attempt %ld)", delay, (long)self.reconnectAttempt);

    self.reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                          target:self
                                                        selector:@selector(reconnectTimerFired)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)reconnectTimerFired {
    [self connect];
}

- (void)cancelReconnect {
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
}

#pragma mark - HAWebSocketClientDelegate

- (void)webSocketClientDidConnect:(HAWebSocketClient *)client {
    NSLog(@"[HAConnection] WebSocket connected, awaiting auth...");
}

- (void)webSocketClientDidAuthenticate:(HAWebSocketClient *)client {
    NSLog(@"[HAConnection] WebSocket authenticated");

    self.connected = YES;
    self.reconnectAttempt = 0;

    // Subscribe to state changes
    [client subscribeToStateChanges];

    // Subscribe to dashboard config changes (for auto-reload)
    [client subscribeToLovelaceUpdates];

    // Fetch available dashboards list
    [self fetchDashboardList];

    // Fetch Lovelace dashboard config for selected dashboard
    NSString *selectedDashboard = [[HAAuthManager sharedManager] selectedDashboardPath];
    [self fetchLovelaceConfig:selectedDashboard];

    // Fetch full state via REST to populate entity store
    [self fetchAllStates];

    // Fetch registries for area-based grouping
    self.registriesLoaded = NO;
    self.areasLoaded = NO;
    self.entitiesRegistryLoaded = NO;
    self.devicesLoaded = NO;
    self.floorsLoaded = NO;
    self.areaRegistryMessageId = [self.wsClient fetchAreaRegistry];
    self.entityRegistryMessageId = [self.wsClient fetchEntityRegistry];
    self.deviceRegistryMessageId = [self.wsClient fetchDeviceRegistry];

    // Fetch floor registry (optional — older HA versions may not support it)
    self.floorRegistryMessageId = [self.wsClient sendCommand:@{@"type": @"config/floor_registry/list"}];

    [self.delegate connectionManagerDidConnect:self];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerDidConnectNotification
                      object:self];
}

- (void)webSocketClient:(HAWebSocketClient *)client didReceiveMessage:(NSDictionary *)message {
    NSString *type = message[@"type"];

    // Handle result messages (responses to commands we sent)
    if ([type isEqualToString:@"result"]) {
        NSInteger msgId = [message[@"id"] integerValue];
        BOOL success = [message[@"success"] boolValue];

        // Check for pending completion handlers first
        void (^completion)(id, NSError *) = self.pendingCompletions[@(msgId)];
        if (completion) {
            [self.pendingCompletions removeObjectForKey:@(msgId)];
            if (success) {
                completion(message[@"result"], nil);
            } else {
                NSDictionary *errDict = message[@"error"];
                NSString *errMsg = [errDict isKindOfClass:[NSDictionary class]] ? errDict[@"message"] : @"Unknown error";
                NSError *err = [NSError errorWithDomain:@"HAConnectionManager" code:-2
                    userInfo:@{NSLocalizedDescriptionKey: errMsg ?: @"Unknown error"}];
                completion(nil, err);
            }
            return;
        }

        if (msgId == self.dashboardListMessageId && success) {
            // get_panels returns a dictionary of panels keyed by name
            NSDictionary *result = message[@"result"];
            if ([result isKindOfClass:[NSDictionary class]]) {
                NSMutableArray *dashboards = [NSMutableArray array];
                for (NSString *key in result) {
                    NSDictionary *panel = result[key];
                    if (![panel isKindOfClass:[NSDictionary class]]) continue;
                    NSString *component = panel[@"component_name"];
                    if (![component isEqualToString:@"lovelace"]) continue;

                    id rawTitle = panel[@"title"];
                    NSString *title = ([rawTitle isKindOfClass:[NSString class]] && [rawTitle length] > 0) ? rawTitle : key;
                    id rawUrlPath = panel[@"url_path"];
                    NSString *urlPath = ([rawUrlPath isKindOfClass:[NSString class]] && [rawUrlPath length] > 0) ? rawUrlPath : key;
                    [dashboards addObject:@{@"title": title, @"url_path": urlPath}];
                }
                // Sort by title for consistent ordering
                [dashboards sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                    return [a[@"title"] caseInsensitiveCompare:b[@"title"]];
                }];
                self.availableDashboards = [dashboards copy];

                if ([self.delegate respondsToSelector:@selector(connectionManager:didReceiveDashboardList:)]) {
                    [self.delegate connectionManager:self didReceiveDashboardList:self.availableDashboards];
                }
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:HAConnectionManagerDidReceiveDashboardListNotification
                                  object:self
                                userInfo:@{@"dashboards": self.availableDashboards}];
            }
            self.dashboardListMessageId = 0;
        } else if (msgId == self.dashboardListMessageId && !success) {
            NSLog(@"[HAConnection] Dashboard list fetch failed: %@", message[@"error"]);
            self.dashboardListMessageId = 0;
        } else if (msgId == self.lovelaceMessageId && success) {
            NSDictionary *result = message[@"result"];
            if ([result isKindOfClass:[NSDictionary class]]) {
                // Check if this is a strategy-based dashboard
                NSDictionary *strategy = result[@"strategy"];
                if ([strategy isKindOfClass:[NSDictionary class]]) {
                    NSString *strategyType = strategy[@"type"];
                    NSLog(@"[HAConnection] Strategy dashboard detected: %@", strategyType);

                    // Store strategy config for re-resolution after states/registries load
                    self.pendingStrategyConfig = strategy;

                    NSDictionary *currentEntities = [self allEntities];
                    if (currentEntities.count == 0) {
                        // Entities not loaded yet — defer resolution until didReceiveAllStates
                        NSLog(@"[HAConnection] Deferring strategy resolution (0 entities loaded)");
                        self.lovelaceMessageId = 0;
                        return;
                    }

                    HALovelaceDashboard *resolved =
                        [HAStrategyResolver resolveDashboardWithStrategy:strategy
                                                               entities:currentEntities
                                                              areaNames:self.areaNames ?: @{}
                                                          entityAreaMap:self.entityAreaMap ?: @{}
                                                         deviceAreaMap:self.deviceAreaMap ?: @{}
                                                                 floors:self.floors
                                                         entityRegistry:self.entityRegistryEntries];
                    if (resolved) {
                        self.lovelaceDashboard = resolved;
                    } else {
                        NSLog(@"[HAConnection] Unknown strategy '%@', falling back to parser", strategyType);
                        self.lovelaceDashboard = [HALovelaceParser parseDashboardFromDictionary:result];
                    }
                } else {
                    self.lovelaceDashboard = [HALovelaceParser parseDashboardFromDictionary:result];
                }

                if ([self.delegate respondsToSelector:@selector(connectionManager:didReceiveLovelaceDashboard:)]) {
                    [self.delegate connectionManager:self didReceiveLovelaceDashboard:self.lovelaceDashboard];
                }
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:HAConnectionManagerDidReceiveLovelaceNotification
                                  object:self
                                userInfo:@{@"dashboard": self.lovelaceDashboard}];
            }
            self.lovelaceMessageId = 0;
        } else if (msgId == self.lovelaceMessageId && !success) {
            NSLog(@"[HAConnection] Lovelace config fetch failed: %@", message[@"error"]);
            self.lovelaceMessageId = 0;
        } else if (msgId == self.areaRegistryMessageId) {
            self.areaRegistryMessageId = 0;
            if (success) {
                [self processAreaRegistry:message[@"result"]];
            }
            self.areasLoaded = YES;
            [self checkRegistriesComplete];
        } else if (msgId == self.deviceRegistryMessageId) {
            self.deviceRegistryMessageId = 0;
            if (success) {
                [self processDeviceRegistry:message[@"result"]];
            }
            self.devicesLoaded = YES;
            [self checkRegistriesComplete];
        } else if (msgId == self.entityRegistryMessageId) {
            self.entityRegistryMessageId = 0;
            if (success) {
                [self processEntityRegistry:message[@"result"]];
            }
            self.entitiesRegistryLoaded = YES;
            [self checkRegistriesComplete];
        } else if (msgId == self.floorRegistryMessageId) {
            self.floorRegistryMessageId = 0;
            if (success) {
                [self processFloorRegistry:message[@"result"]];
            } else {
                NSLog(@"[HAConnection] Floor registry fetch failed (may not be supported): %@", message[@"error"]);
            }
            self.floorsLoaded = YES;
        }
        return;
    }

    if ([type isEqualToString:@"event"]) {
        NSDictionary *event = message[@"event"];
        NSString *eventType = event[@"event_type"];

        if ([eventType isEqualToString:@"state_changed"]) {
            NSDictionary *eventData = event[@"data"];
            NSDictionary *newState = eventData[@"new_state"];
            if (!newState || ![newState isKindOfClass:[NSDictionary class]]) return;

            NSString *entityId = newState[@"entity_id"];
            if (!entityId) return;

            HAEntity *entity;
            @synchronized(self.entityStore) {
                entity = self.entityStore[entityId];
                if (entity) {
                    [entity updateWithDictionary:newState];
                } else {
                    entity = [[HAEntity alloc] initWithDictionary:newState];
                    self.entityStore[entityId] = entity;
                }
            }

            [self.delegate connectionManager:self didUpdateEntity:entity];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:HAConnectionManagerEntityDidUpdateNotification
                              object:self
                            userInfo:@{@"entity": entity}];
        } else if ([eventType isEqualToString:@"lovelace_updated"]) {
            if (![[HAAuthManager sharedManager] autoReloadDashboard]) return;

            NSDictionary *eventData = event[@"data"];
            NSString *updatedUrlPath = nil;
            id urlPathValue = eventData[@"url_path"];
            if ([urlPathValue isKindOfClass:[NSString class]]) {
                updatedUrlPath = urlPathValue;
            }

            NSString *selectedDashboard = [[HAAuthManager sharedManager] selectedDashboardPath];
            BOOL viewingDefault = (selectedDashboard == nil || selectedDashboard.length == 0);
            BOOL updatedIsDefault = (updatedUrlPath == nil);
            BOOL matchesSelected = (updatedUrlPath != nil && [updatedUrlPath isEqualToString:selectedDashboard]);

            if (matchesSelected || (viewingDefault && updatedIsDefault)) {
                NSLog(@"[HAConnection] Lovelace config updated for active dashboard, re-fetching");
                [self fetchLovelaceConfig:selectedDashboard];
            }
        }
    }
}

- (void)webSocketClient:(HAWebSocketClient *)client didDisconnectWithError:(NSError *)error {
    NSLog(@"[HAConnection] WebSocket disconnected: %@", error);

    self.connected = NO;

    [self.delegate connectionManager:self didDisconnectWithError:error];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerDidDisconnectNotification
                      object:self
                    userInfo:error ? @{@"error": error} : nil];

    [self scheduleReconnect];
}

@end
