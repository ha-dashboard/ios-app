#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HALightEntityCell.h"
#import "HASwitchEntityCell.h"
#import "HAButtonEntityCell.h"
#import "HAFanEntityCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"

@interface HALightingSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HALightingSnapshotTests

#pragma mark - HALightEntityCell

- (void)testLightOnBrightness {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnBrightness];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), [HALightEntityCell preferredHeightForEntity:entity configItem:item]) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightOnRGB {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnRGB];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), [HALightEntityCell preferredHeightForEntity:entity configItem:item]) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightOnDimmed {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnDimmed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), [HALightEntityCell preferredHeightForEntity:entity configItem:item]) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightOff {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), [HALightEntityCell preferredHeightForEntity:entity configItem:item]) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HASwitchEntityCell

- (void)testSwitchOn {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"switch" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSwitchOff {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"switch" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAButtonEntityCell

- (void)testButtonDefault {
    HAEntity *entity = [HASnapshotTestHelpers buttonDefault];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAButtonEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testButtonPressed {
    HAEntity *entity = [HASnapshotTestHelpers buttonPressed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAButtonEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAFanEntityCell

- (void)testFanOnHalf {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOnHalf];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanOnFull {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOnFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanOff {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

@end
