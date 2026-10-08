#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HALightEntityCell.h"
#import "HASensorEntityCell.h"
#import "HASwitchEntityCell.h"
#import "HAClimateEntityCell.h"
#import "HADashboardConfig.h"
#import "HATheme.h"

@interface HAEdgeCaseSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HAEdgeCaseSnapshotTests

#pragma mark - Unavailable Entities

- (void)testUnavailableLight {
    HAEntity *entity = [HASnapshotTestHelpers unavailableEntity:@"light.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"light.test"
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testUnavailableSensor {
    HAEntity *entity = [HASnapshotTestHelpers unavailableEntity:@"sensor.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"sensor.test"
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testUnavailableClimate {
    HAEntity *entity = [HASnapshotTestHelpers unavailableEntity:@"climate.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"climate.test"
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testUnavailableSwitch {
    HAEntity *entity = [HASnapshotTestHelpers unavailableEntity:@"switch.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"switch.test"
        cardType:@"switch" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self ha_verifySwitchCell:cell identifier:nil];
}

#pragma mark - Long Name Entities

- (void)testLongNameLight {
    HAEntity *entity = [HASnapshotTestHelpers longNameEntity:@"light.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"light.test"
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLongNameSensor {
    HAEntity *entity = [HASnapshotTestHelpers longNameEntity:@"sensor.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"sensor.test"
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLongNameSwitch {
    HAEntity *entity = [HASnapshotTestHelpers longNameEntity:@"switch.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"switch.test"
        cardType:@"switch" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Minimal Entities

- (void)testMinimalLight {
    HAEntity *entity = [HASnapshotTestHelpers minimalEntity:@"light.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"light.test"
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMinimalSensor {
    HAEntity *entity = [HASnapshotTestHelpers minimalEntity:@"sensor.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"sensor.test"
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMinimalSwitch {
    HAEntity *entity = [HASnapshotTestHelpers minimalEntity:@"switch.test"];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"switch.test"
        cardType:@"switch" columnSpan:6 headingIcon:nil displayName:nil];
    CGFloat width = floor(kSubGridUnit * 6);
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(width, kStandardCellHeight) configItem:item];
    [self ha_verifySwitchCell:cell identifier:nil];
}

#pragma mark - Helpers

/// testMinimalSwitch/testUnavailableSwitch's dark_gradient variant is
/// non-deterministic by a few sub-pixels around the UISwitch knob's rounded
/// edge — confirmed via `magick compare`: all differing pixels are within a
/// 0.5% per-pixel color distance (pure antialiasing; fuzz>=0.5% gives AE=0),
/// concentrated exactly on the knob's circular outline (nothing elsewhere in
/// the cell differs). Raw pixel count without any fuzz can be a few percent
/// for testMinimalSwitch specifically (a circular edge has more antialiased
/// boundary pixels than a straight one), so this scopes a small, explicit
/// tolerance to just these two tests rather than the global default (which
/// stays pixel-exact for every other test).
- (void)ha_verifySwitchCell:(UIView *)cell identifier:(NSString *)identifier {
    [self verifyView:cell identifier:identifier inTheme:HAThemeModeDark gradient:YES
   perPixelTolerance:0.02 overallTolerance:0.04];
    [self verifyView:cell identifier:identifier inTheme:HAThemeModeLight];
}

@end
