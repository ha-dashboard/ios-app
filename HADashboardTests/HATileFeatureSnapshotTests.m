#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HATileEntityCell.h"
#import "HATileFeatureView.h"
#import "HATileFeatureFactory.h"
#import "HASliderFeatureView.h"
#import "HAButtonRowFeatureView.h"
#import "HAModeFeatureView.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"

static const CGFloat kFeatureViewWidth = 160.0; // half-width tile

@interface HATileFeatureSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HATileFeatureSnapshotTests

#pragma mark - Tile Cell Helpers

/// Create a tile config item with features.
- (HADashboardConfigItem *)tileItemWithEntityId:(NSString *)entityId features:(NSArray *)features {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = entityId;
    item.cardType = @"tile";
    item.columnSpan = 6;
    item.rowSpan = 1;
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    if (features) props[@"features"] = features;
    item.customProperties = [props copy];
    return item;
}

/// Create a standalone feature view for snapshot testing.
- (UIView *)featureViewForEntity:(HAEntity *)entity config:(NSDictionary *)featureConfig width:(CGFloat)width {
    HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:featureConfig entity:entity];
    if (!view) return nil;
    CGFloat height = [[view class] preferredHeight];
    view.frame = CGRectMake(0, 0, width, height);
    view.translatesAutoresizingMaskIntoConstraints = YES;
    [view layoutIfNeeded];
    return view;
}

#pragma mark - Tile + Brightness Slider

- (void)testTileWithBrightnessSlider {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnBrightness];
    NSArray *features = @[@{@"type": @"light-brightness"}];
    HADashboardConfigItem *item = [self tileItemWithEntityId:entity.entityId features:features];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), height);
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"tileBrightnessSlider"];
}

#pragma mark - Tile + Cover Position + Open/Close

- (void)testTileWithCoverFeatures {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityPartial];
    NSArray *features = @[
        @{@"type": @"cover-open-close"},
        @{@"type": @"cover-position"}
    ];
    HADashboardConfigItem *item = [self tileItemWithEntityId:entity.entityId features:features];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), height);
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"tileCoverFeatures"];
}

#pragma mark - Tile + HVAC Mode Buttons

- (void)testTileWithClimateHvacModes {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    NSArray *features = @[@{@"type": @"climate-hvac-modes"}];
    HADashboardConfigItem *item = [self tileItemWithEntityId:entity.entityId features:features];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), height);
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"tileClimateHvacModes"];
}

#pragma mark - Tile + Lock Commands

- (void)testTileWithLockCommands {
    HAEntity *entity = [HASnapshotTestHelpers lockLocked];
    NSArray *features = @[@{@"type": @"lock-commands"}];
    HADashboardConfigItem *item = [self tileItemWithEntityId:entity.entityId features:features];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), height);
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"tileLockCommands"];
}

#pragma mark - Tile + Fan Speed Slider

- (void)testTileWithFanSpeedSlider {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOnHalf];
    NSArray *features = @[@{@"type": @"fan-speed"}];
    HADashboardConfigItem *item = [self tileItemWithEntityId:entity.entityId features:features];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), height);
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"tileFanSpeedSlider"];
}

#pragma mark - Tile + Target Temperature Buttons

- (void)testTileWithTargetTemperature {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityCool];
    NSArray *features = @[@{@"type": @"target-temperature"}];
    HADashboardConfigItem *item = [self tileItemWithEntityId:entity.entityId features:features];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), height);
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"tileTargetTemperature"];
}

#pragma mark - Standalone Feature Views: Slider

- (void)testSliderFeatureBrightness70 {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnBrightness];
    NSDictionary *config = @{@"type": @"light-brightness"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"sliderBrightness70"];
}

- (void)testSliderFeatureBrightness0 {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOff];
    NSDictionary *config = @{@"type": @"light-brightness"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"sliderBrightness0"];
}

- (void)testSliderFeatureCoverPosition50 {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityPartial];
    NSDictionary *config = @{@"type": @"cover-position"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"sliderCoverPosition50"];
}

- (void)testSliderFeatureCoverPosition100 {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityOpenShutter];
    NSDictionary *config = @{@"type": @"cover-position"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"sliderCoverPosition100"];
}

- (void)testSliderFeatureFanSpeed50 {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOnHalf];
    NSDictionary *config = @{@"type": @"fan-speed"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"sliderFanSpeed50"];
}

#pragma mark - Standalone Feature Views: Button Row

- (void)testButtonRowCoverOpenClose {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityPartial];
    NSDictionary *config = @{@"type": @"cover-open-close"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"buttonRowCoverOpenClose"];
}

- (void)testButtonRowCoverClosed {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityClosedGarage];
    NSDictionary *config = @{@"type": @"cover-open-close"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"buttonRowCoverClosed"];
}

- (void)testButtonRowLockLocked {
    HAEntity *entity = [HASnapshotTestHelpers lockLocked];
    NSDictionary *config = @{@"type": @"lock-commands"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"buttonRowLockLocked"];
}

- (void)testButtonRowLockUnlocked {
    HAEntity *entity = [HASnapshotTestHelpers lockUnlocked];
    NSDictionary *config = @{@"type": @"lock-commands"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"buttonRowLockUnlocked"];
}

- (void)testButtonRowTargetTemperature {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    NSDictionary *config = @{@"type": @"target-temperature"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"buttonRowTargetTemp"];
}

#pragma mark - Standalone Feature Views: Mode

- (void)testModeHvacIcons {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    NSDictionary *config = @{@"type": @"climate-hvac-modes"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"modeHvacIcons"];
}

- (void)testModeHvacCooling {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityCool];
    NSDictionary *config = @{@"type": @"climate-hvac-modes"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"modeHvacCooling"];
}

- (void)testModeHvacDropdown {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    NSDictionary *config = @{@"type": @"climate-hvac-modes", @"style": @"dropdown"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"modeHvacDropdown"];
}

- (void)testModeAlarm {
    HAEntity *entity = [HASnapshotTestHelpers alarmDisarmed];
    NSDictionary *config = @{@"type": @"alarm-modes"};
    UIView *view = [self featureViewForEntity:entity config:config width:kFeatureViewWidth];
    [self verifyView:view identifier:@"modeAlarmDisarmed"];
}

@end
