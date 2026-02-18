#import <Foundation/Foundation.h>

@class HAEntity;
@class HALovelaceDashboard;

/// Provides demo entities, dashboard config, and fake history data for Demo Mode.
/// Used when app runs without a live Home Assistant connection to demonstrate
/// app capabilities (e.g., for App Store reviewers).
@interface HADemoDataProvider : NSObject

/// Singleton instance
+ (instancetype)sharedProvider;

#pragma mark - Entity Data

/// All demo entities, keyed by entity_id
@property (nonatomic, readonly) NSDictionary<NSString *, HAEntity *> *allEntities;

/// Get a specific entity by ID
- (HAEntity *)entityForId:(NSString *)entityId;

#pragma mark - Dashboard Data

/// The default demo dashboard (Home)
@property (nonatomic, readonly) HALovelaceDashboard *demoDashboard;

/// List of available demo dashboards
@property (nonatomic, readonly) NSArray<NSDictionary *> *availableDashboards;

/// Get a specific demo dashboard by URL path (e.g., @"demo-home", @"demo-monitoring")
- (HALovelaceDashboard *)dashboardForPath:(NSString *)urlPath;

#pragma mark - Fake History

/// Generate fake numeric history data points for graph cards.
/// Returns array of @{@"value": NSNumber, @"timestamp": NSNumber (epoch)}.
- (NSArray *)historyPointsForEntityId:(NSString *)entityId hoursBack:(NSInteger)hours;

/// Generate fake timeline segments for state-based entities.
/// Returns array of @{@"state": NSString, @"start": NSNumber (epoch), @"end": NSNumber (epoch)}.
- (NSArray *)timelineSegmentsForEntityId:(NSString *)entityId hoursBack:(NSInteger)hours;

#pragma mark - State Simulation

/// Start periodically updating entities to simulate a live system.
/// Sensors will fluctuate, binary sensors will occasionally toggle.
- (void)startSimulation;

/// Stop the simulation timer.
- (void)stopSimulation;

/// Whether simulation is currently running.
@property (nonatomic, readonly, getter=isSimulating) BOOL simulating;

#pragma mark - Data Reload

/// Reload demo data (resets all entities to initial state).
- (void)reloadDemoData;

@end
