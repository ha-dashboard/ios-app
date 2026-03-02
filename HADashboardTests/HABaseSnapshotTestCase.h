#import "FBSnapshotTestCase.h"

@class HAEntity;
@class HADashboardConfigItem;
@class HADashboardConfigSection;
@class HATheme;

/// Standard column width for a 3-column iPad layout (1024pt landscape, minus padding).
static const CGFloat kColumnWidth = 320.0;

/// Sub-grid unit: each column divided by 12 for sub-grid positioning.
static const CGFloat kSubGridUnit = 320.0 / 12.0; // ~26.7pt per sub-grid column

/// Standard cell heights for snapshot tests.
static const CGFloat kStandardCellHeight = 80.0;
static const CGFloat kThermostatHeight = 280.0;
static const CGFloat kVacuumHeight = 120.0;
static const CGFloat kEntitiesRowHeight = 36.0;
static const CGFloat kHeadingExtra = 30.0;   // kHeadingHeight(28) + kHeadingGap(2)
static const CGFloat kHeadingCellHeight = 40.0;
static const CGFloat kGaugeCardHeight = 200.0;
static const CGFloat kGraphCardHeight = 180.0;
static const CGFloat kWeatherHeight = 200.0;
static const CGFloat kClockWeatherHeight = 280.0;
static const CGFloat kBadgeRowHeight = 60.0;
static const CGFloat kTileHeight = 80.0;

/// Shared base class for all snapshot tests.
/// Provides reference/failure image directory resolution, size constants,
/// cell creation helpers, and theme verification helpers.
@interface HABaseSnapshotTestCase : FBSnapshotTestCase

/// Create and configure a single-entity cell for snapshot testing.
/// Allocates the cell, calls configureWithEntity:configItem:, and lays it out.
- (UIView *)cellForEntity:(HAEntity *)entity
                 cellClass:(Class)cellClass
                      size:(CGSize)size
                configItem:(HADashboardConfigItem *)configItem;

/// Create and configure a composite card cell (HAEntitiesCardCell, HABadgeRowCell).
/// Allocates the cell, calls the appropriate section-based configure method, and lays it out.
- (UIView *)compositeCell:(Class)cellClass
                     size:(CGSize)size
                  section:(HADashboardConfigSection *)section
                 entities:(NSDictionary<NSString *, HAEntity *> *)entities
               configItem:(HADashboardConfigItem *)configItem;

/// Verify a view snapshot in a specific theme mode.
/// Temporarily sets the theme, re-lays out the view, verifies the snapshot
/// with a theme-suffixed identifier, then restores the original theme.
- (void)verifyView:(UIView *)view identifier:(NSString *)identifier inTheme:(NSInteger)mode;

/// Verify a view snapshot in Dark+Gradient and Light themes.
- (void)verifyView:(UIView *)view identifier:(NSString *)identifier;

@end
