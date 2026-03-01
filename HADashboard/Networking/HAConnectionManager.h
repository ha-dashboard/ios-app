#import <Foundation/Foundation.h>

@class HAEntity;
@class HAConnectionManager;
@class HALovelaceDashboard;
@class HAFloor;

extern NSString *const HAConnectionManagerDidConnectNotification;
extern NSString *const HAConnectionManagerDidDisconnectNotification;
extern NSString *const HAConnectionManagerEntityDidUpdateNotification;        // userInfo: @{@"entity": HAEntity}
extern NSString *const HAConnectionManagerDidReceiveAllStatesNotification;    // userInfo: @{@"entities": NSDictionary}
extern NSString *const HAConnectionManagerDidReceiveLovelaceNotification;     // userInfo: @{@"dashboard": HALovelaceDashboard}
extern NSString *const HAConnectionManagerDidReceiveDashboardListNotification; // userInfo: @{@"dashboards": NSArray}
extern NSString *const HAConnectionManagerDidReceiveRegistriesNotification;    // userInfo: nil (registries ready)

@protocol HAConnectionManagerDelegate <NSObject>
@optional
- (void)connectionManagerDidConnect:(HAConnectionManager *)manager;
- (void)connectionManager:(HAConnectionManager *)manager didDisconnectWithError:(NSError *)error;
- (void)connectionManager:(HAConnectionManager *)manager didUpdateEntity:(HAEntity *)entity;
- (void)connectionManager:(HAConnectionManager *)manager didReceiveAllStates:(NSDictionary<NSString *, HAEntity *> *)entities;
- (void)connectionManager:(HAConnectionManager *)manager didReceiveLovelaceDashboard:(HALovelaceDashboard *)dashboard;
- (void)connectionManager:(HAConnectionManager *)manager didReceiveDashboardList:(NSArray<NSDictionary *> *)dashboards;
- (void)connectionManagerDidFailToLoadLovelaceDashboard:(HAConnectionManager *)manager;
@end


@interface HAConnectionManager : NSObject

@property (nonatomic, weak) id<HAConnectionManagerDelegate> delegate;
@property (nonatomic, readonly, getter=isConnected) BOOL connected;

+ (instancetype)sharedManager;

/// Configure and connect using stored auth credentials
- (void)connect;
- (void)disconnect;

/// Fetch all entity states via REST, then subscribe via WebSocket
- (void)fetchAllStates;

/// Fetch Lovelace dashboard config. Pass nil for default dashboard.
- (void)fetchLovelaceConfig:(NSString *)urlPath;

/// Last fetched Lovelace dashboard
@property (nonatomic, strong, readonly) HALovelaceDashboard *lovelaceDashboard;

/// Fetch the list of available dashboards
- (void)fetchDashboardList;

/// Last fetched dashboard list. Each entry has "url_path" and "title" keys.
/// The default dashboard is prepended with url_path=nil, title="Default".
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *availableDashboards;

/// Call a service (uses WebSocket if connected, falls back to REST)
- (void)callService:(NSString *)service
           inDomain:(NSString *)domain
           withData:(NSDictionary *)data
    entityId:(NSString *)entityId;

/// Send a WebSocket command and receive the result via completion handler.
/// The completion block is called on the main queue with (result, error).
- (void)sendCommand:(NSDictionary *)command
         completion:(void (^)(id result, NSError *error))completion;

/// Get a cached entity by ID
- (HAEntity *)entityForId:(NSString *)entityId;

/// Get all cached entities
- (NSDictionary<NSString *, HAEntity *> *)allEntities;

/// Area name for an entity (nil if entity has no area assignment)
- (NSString *)areaNameForEntityId:(NSString *)entityId;

/// Area ID for an entity (nil if entity has no area assignment)
- (NSString *)areaIdForEntityId:(NSString *)entityId;

/// Raw entity registry entries (NSArray of NSDictionary), available after registries load
@property (nonatomic, strong, readonly) NSArray *entityRegistryEntries;

/// Area names dictionary: area_id -> area name
@property (nonatomic, strong, readonly) NSDictionary<NSString *, NSString *> *areaNamesByAreaId;

/// Device area map: device_id -> area_id
@property (nonatomic, strong, readonly) NSDictionary<NSString *, NSString *> *deviceAreaMapping;

/// Floor registry entries (available after registries load, nil if HA doesn't support floors)
@property (nonatomic, copy, readonly) NSArray<HAFloor *> *floors;

/// Look up the floor for a given area_id (nil if area has no floor assignment)
- (HAFloor *)floorForAreaId:(NSString *)areaId;

/// Whether area/entity/device registries have been loaded
@property (nonatomic, readonly) BOOL registriesLoaded;

@end
