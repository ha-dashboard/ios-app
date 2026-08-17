#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HACoverEntityCell.h"
#import "HALockEntityCell.h"
#import "HAAlarmEntityCell.h"
#import "HAVacuumEntityCell.h"
#import "HAPersonEntityCell.h"
#import "HASceneEntityCell.h"
#import "HADashboardConfig.h"

@interface HAControlSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HAControlSnapshotTests

#pragma mark - Cover (HACoverEntityCell)

- (void)testCoverOpenShutter {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityOpenShutter];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"cover.living_room_shutter"
                                                                cardType:@"cover"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"coverOpenShutter"];
}

- (void)testCoverClosedGarage {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityClosedGarage];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"cover.garage_door"
                                                                cardType:@"cover"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"coverClosedGarage"];
}

- (void)testCoverPartial {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityPartial];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"cover.office_blinds"
                                                                cardType:@"cover"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"coverPartial"];
}

#pragma mark - Lock (HALockEntityCell)

- (void)testLockLocked {
    HAEntity *entity = [HASnapshotTestHelpers lockLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"lock.frontdoor"
                                                                cardType:@"lock"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"lockLocked"];
}

- (void)testLockUnlocked {
    HAEntity *entity = [HASnapshotTestHelpers lockUnlocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"lock.frontdoor"
                                                                cardType:@"lock"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"lockUnlocked"];
}

- (void)testLockJammed {
    HAEntity *entity = [HASnapshotTestHelpers lockJammed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"lock.frontdoor"
                                                                cardType:@"lock"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"lockJammed"];
}

#pragma mark - Alarm (HAAlarmEntityCell)

- (void)testAlarmDisarmed {
    HAEntity *entity = [HASnapshotTestHelpers alarmDisarmed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"alarm_control_panel.home_alarm"
                                                                cardType:@"alarm"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"alarmDisarmed"];
}

- (void)testAlarmArmedHome {
    HAEntity *entity = [HASnapshotTestHelpers alarmArmedHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"alarm_control_panel.home_alarm"
                                                                cardType:@"alarm"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"alarmArmedHome"];
}

- (void)testAlarmArmedAway {
    HAEntity *entity = [HASnapshotTestHelpers alarmArmedAway];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"alarm_control_panel.home_alarm"
                                                                cardType:@"alarm"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"alarmArmedAway"];
}

- (void)testAlarmTriggered {
    HAEntity *entity = [HASnapshotTestHelpers alarmTriggered];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"alarm_control_panel.home_alarm"
                                                                cardType:@"alarm"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"alarmTriggered"];
}

- (void)testAlarmActionButtonsRemainReadableAfterReuse {
    HAEntity *entity = [HASnapshotTestHelpers alarmDisarmed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"alarm_control_panel.home_alarm"
                                                                cardType:@"alarm"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    HAAlarmEntityCell *cell = [[HAAlarmEntityCell alloc] initWithFrame:CGRectMake(0, 0, floor(kSubGridUnit * 6), kStandardCellHeight)];

    // The production failure occurred only after a collection-view reuse.
    [cell prepareForReuse];
    [cell configureWithEntity:entity configItem:item];

    UIButton *awayButton = [cell valueForKey:@"armAwayButton"];
    XCTAssertNotNil([awayButton titleColorForState:UIControlStateNormal]);
    XCTAssertEqualWithAccuracy(CGColorGetAlpha(awayButton.backgroundColor.CGColor), 0.15, 0.001);
}

#pragma mark - Vacuum (HAVacuumEntityCell)

- (void)testVacuumDocked {
    HAEntity *entity = [HASnapshotTestHelpers vacuumDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.roborock"
                                                                cardType:@"vacuum"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"vacuumDocked"];
}

- (void)testVacuumCleaning {
    HAEntity *entity = [HASnapshotTestHelpers vacuumCleaning];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.roborock"
                                                                cardType:@"vacuum"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"vacuumCleaning"];
}

- (void)testVacuumReturning {
    HAEntity *entity = [HASnapshotTestHelpers vacuumReturning];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.roborock"
                                                                cardType:@"vacuum"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"vacuumReturning"];
}

- (void)testVacuumError {
    HAEntity *entity = [HASnapshotTestHelpers vacuumError];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.roborock"
                                                                cardType:@"vacuum"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"vacuumError"];
}

#pragma mark - Person (HAPersonEntityCell)

- (void)testPersonHome {
    HAEntity *entity = [HASnapshotTestHelpers personHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"person.james"
                                                                cardType:@"person"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAPersonEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"personHome"];
}

- (void)testPersonNotHome {
    HAEntity *entity = [HASnapshotTestHelpers personNotHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"person.olivia"
                                                                cardType:@"person"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HAPersonEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"personNotHome"];
}

#pragma mark - Scene (HASceneEntityCell)

- (void)testSceneDefault {
    HAEntity *entity = [HASnapshotTestHelpers sceneDefault];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"scene.movie_night"
                                                                cardType:@"scene"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HASceneEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"sceneDefault"];
}

- (void)testSceneActivated {
    HAEntity *entity = [HASnapshotTestHelpers sceneActivated];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"scene.good_morning"
                                                                cardType:@"scene"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight);
    UIView *cell = [self cellForEntity:entity cellClass:[HASceneEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:@"sceneActivated"];
}

@end
