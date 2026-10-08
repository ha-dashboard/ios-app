#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "HAThermostatGaugeCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HAConnectionManager.h"
#import "HASnapshotTestHelpers.h"

// -----------------------------------------------------------------------
// PR #18 follow-up (fix/thermostat-primary-polish):
//
// PR #18 fixed HAThermostatGaugeCell so that nudging +/- (applyOptimisticSingleTemp:)
// no longer overwrites the large tempLabel (current room temp) with the setpoint when
// show_current_as_primary is enabled. These tests exercise that fix directly (no
// snapshot rendering) and also cover two related bugs found while auditing the same
// class of issue:
//
//   1. Dragging the arc thumb (handleThumbPan:) never updated targetLabel live in
//      show_current_as_primary mode, so the small setpoint label stayed frozen while
//      the thumb visually moved.
//   2. configureWithEntity:configItem: ignored an in-flight +/- debounce
//      (pendingTargetTemp / buttonDebounceTimer): an entity update arriving from HA
//      mid-debounce would snap the displayed setpoint back to the stale server value.
//
// Network side effects are stubbed: HAConnectionManager's callService:inDomain:withData:
// entityId: is swapped for a capturing block for the duration of each test, so no real
// service calls fire and the 5s debounce timer is never waited on.
// -----------------------------------------------------------------------

typedef void (^HAServiceCallBlock)(id manager, NSString *service, NSString *domain,
                                    NSDictionary *data, NSString *entityId);

@interface HAThermostatGaugeCell (TestAccess)
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UILabel *targetLabel;
@property (nonatomic, strong) UIButton *dualLowButton;
@property (nonatomic, strong) UIButton *dualHighButton;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) UIView *thumbHighView;
@property (nonatomic, assign) CGPoint arcCenter;
@property (nonatomic, assign) CGFloat arcRadius;
@property (nonatomic, assign) BOOL thumbDragging;
@property (nonatomic, assign) double pendingTargetTemp;
@property (nonatomic, assign) double pendingTargetTempLow;
@property (nonatomic, assign) double pendingTargetTempHigh;
@property (nonatomic, strong) NSTimer *buttonDebounceTimer;
- (void)applyOptimisticSingleTemp:(double)newTarget;
- (void)plusTapped;
- (void)minusTapped;
- (void)handleThumbPan:(UIPanGestureRecognizer *)gesture;
- (void)flushPendingButtonChange;
@end

/// A pan gesture recognizer whose reported location and state are fixed by the test
/// rather than driven by real touch events, so handleThumbPan: can be exercised
/// deterministically. UIGestureRecognizer's real state machine won't accept externally
/// injected transitions (KVC `setValue:forKey:@"state"` is silently ignored outside its
/// own touch-tracking lifecycle), so `state` is overridden outright rather than faked via
/// the superclass's storage.
@interface HAFixedLocationPanGestureRecognizer : UIPanGestureRecognizer
@property (nonatomic, assign) CGPoint fixedLocation;
@property (nonatomic, assign) UIGestureRecognizerState fakeState;
@end

@implementation HAFixedLocationPanGestureRecognizer
- (CGPoint)locationInView:(UIView *)view {
    return self.fixedLocation;
}
- (UIGestureRecognizerState)state {
    return self.fakeState;
}
@end

@interface HAThermostatPrimaryPolishTests : XCTestCase
@property (nonatomic, strong) HAThermostatGaugeCell *cell;
@property (nonatomic, strong) HAEntity *entity;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *capturedServiceCalls;
@property (nonatomic, assign) IMP originalCallServiceIMP;
@end

@implementation HAThermostatPrimaryPolishTests

- (void)setUp {
    [super setUp];

    self.capturedServiceCalls = [NSMutableArray array];
    NSMutableArray *captured = self.capturedServiceCalls;
    Method method = class_getInstanceMethod([HAConnectionManager class],
        @selector(callService:inDomain:withData:entityId:));
    self.originalCallServiceIMP = method_setImplementation(method, imp_implementationWithBlock(
        ^(id manager, NSString *service, NSString *domain, NSDictionary *data, NSString *entityId) {
            [captured addObject:@{
                @"service": service ?: @"",
                @"domain": domain ?: @"",
                @"data": data ?: @{},
                @"entityId": entityId ?: @"",
            }];
        }));

    // climateEntityHeat: heat mode, current_temperature=20.8, temperature(target)=21,
    // target_temp_step=0.5, min_temp=7, max_temp=35, temperature_unit="°C".
    self.entity = [HASnapshotTestHelpers climateEntityHeat];
    self.cell = [[HAThermostatGaugeCell alloc] initWithFrame:CGRectMake(0, 0, 350, 320)];
}

- (void)tearDown {
    [self.cell.buttonDebounceTimer invalidate];
    self.cell = nil;

    Method method = class_getInstanceMethod([HAConnectionManager class],
        @selector(callService:inDomain:withData:entityId:));
    method_setImplementation(method, self.originalCallServiceIMP);

    [super tearDown];
}

- (HADashboardConfigItem *)configItemWithShowCurrentAsPrimary:(BOOL)primary {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = self.entity.entityId;
    item.cardType = @"thermostat";
    item.columnSpan = 9;
    item.rowSpan = 1;
    if (primary) {
        item.customProperties = @{@"show_current_as_primary": @YES};
    }
    return item;
}

#pragma mark - show_current_as_primary: nudge buttons (PR #18 regression guard)

- (void)testPrimaryMode_InitialConfigure_LargeLabelShowsCurrentNotSetpoint {
    HADashboardConfigItem *item = [self configItemWithShowCurrentAsPrimary:YES];
    [self.cell configureWithEntity:self.entity configItem:item];
    [self.cell layoutIfNeeded];

    // current_temperature 20.8 -> "%.0f" -> "21°C". Target is also 21, so pin the
    // assertion on the actual current-temp formatting rather than relying on the
    // target coincidentally differing.
    XCTAssertEqualObjects(self.cell.tempLabel.text, @"21°C");
    XCTAssertFalse(self.cell.targetLabel.hidden);
    XCTAssertTrue([self.cell.targetLabel.attributedText.string containsString:@"21.0"]);
}

- (void)testPrimaryMode_PlusTapped_KeepsCurrentTempLargeLabel_UpdatesTargetSecondaryLabel {
    HADashboardConfigItem *item = [self configItemWithShowCurrentAsPrimary:YES];
    [self.cell configureWithEntity:self.entity configItem:item];
    [self.cell layoutIfNeeded];

    NSString *tempLabelBefore = self.cell.tempLabel.text;

    [self.cell plusTapped]; // step 0.5 -> pendingTargetTemp = 21.5

    XCTAssertEqualObjects(self.cell.tempLabel.text, tempLabelBefore,
        @"tempLabel must keep showing current room temp after a nudge in show_current_as_primary mode");
    XCTAssertTrue([self.cell.targetLabel.attributedText.string containsString:@"21.5"],
        @"targetLabel should reflect the new optimistic setpoint");

    [self.cell minusTapped]; // back to 21.0
    [self.cell minusTapped]; // 20.5

    XCTAssertEqualObjects(self.cell.tempLabel.text, tempLabelBefore);
    XCTAssertTrue([self.cell.targetLabel.attributedText.string containsString:@"20.5"]);

    // Confirm the debounced service call eventually carries the net value, not each
    // intermediate tap, and that nothing fired while still debouncing.
    XCTAssertEqual(self.capturedServiceCalls.count, 0u);
    [self.cell flushPendingButtonChange];
    XCTAssertEqual(self.capturedServiceCalls.count, 1u);
    NSDictionary *call = self.capturedServiceCalls.firstObject;
    XCTAssertEqualObjects(call[@"service"], @"set_temperature");
    XCTAssertEqualObjects(call[@"data"][@"temperature"], @20.5);
}

- (void)testPrimaryMode_ApplyOptimisticSingleTemp_DirectCall_KeepsCurrentTempLabel {
    HADashboardConfigItem *item = [self configItemWithShowCurrentAsPrimary:YES];
    [self.cell configureWithEntity:self.entity configItem:item];
    [self.cell layoutIfNeeded];

    NSString *tempLabelBefore = self.cell.tempLabel.text;
    [self.cell applyOptimisticSingleTemp:23.0];

    XCTAssertEqualObjects(self.cell.tempLabel.text, tempLabelBefore);
    XCTAssertTrue([self.cell.targetLabel.attributedText.string containsString:@"23.0"]);
}

#pragma mark - Default mode (large label legitimately shows the setpoint)

- (void)testDefaultMode_LargeLabelShowsSetpoint_NudgeUpdatesLargeLabel {
    HADashboardConfigItem *item = [self configItemWithShowCurrentAsPrimary:NO];
    [self.cell configureWithEntity:self.entity configItem:item];
    [self.cell layoutIfNeeded];

    XCTAssertEqualObjects(self.cell.tempLabel.text, @"21.0°C");

    [self.cell plusTapped];
    XCTAssertEqualObjects(self.cell.tempLabel.text, @"21.5°C");
    XCTAssertTrue([self.cell.targetLabel.attributedText.string containsString:@"20.8"],
        @"secondary label in default mode shows current temp");
}

#pragma mark - Audit fix: drag must live-update the secondary label in primary mode

- (void)testPrimaryMode_DragThumb_NeverOverwritesTempLabel_LiveUpdatesTargetLabel {
    HADashboardConfigItem *item = [self configItemWithShowCurrentAsPrimary:YES];
    [self.cell configureWithEntity:self.entity configItem:item];
    [self.cell layoutIfNeeded];

    XCTAssertFalse(self.cell.thumbView.hidden);
    XCTAssertGreaterThan(self.cell.arcRadius, 0);
    NSString *tempLabelBefore = self.cell.tempLabel.text;

    // Arc sweep constants from HAThermostatGaugeCell.m (kStartAngle/kEndAngle): 135deg -> 405deg.
    CGFloat startAngle = 135.0 * M_PI / 180.0;
    CGFloat endAngle   = 405.0 * M_PI / 180.0;

    HAFixedLocationPanGestureRecognizer *gesture =
        [[HAFixedLocationPanGestureRecognizer alloc] initWithTarget:nil action:nil];

    // Began near the low end of the range (~30%); this also exercises the Began->Changed
    // fallthrough in handleThumbPan:.
    CGFloat beganAngle = startAngle + 0.3 * (endAngle - startAngle);
    gesture.fixedLocation = CGPointMake(
        self.cell.arcCenter.x + self.cell.arcRadius * cos(beganAngle),
        self.cell.arcCenter.y + self.cell.arcRadius * sin(beganAngle));
    gesture.fakeState = UIGestureRecognizerStateBegan;
    [self.cell handleThumbPan:gesture];

    XCTAssertEqualObjects(self.cell.tempLabel.text, tempLabelBefore,
        @"tempLabel must never show the setpoint while dragging in show_current_as_primary mode");
    XCTAssertFalse(self.cell.targetLabel.hidden);
    XCTAssertFalse([self.cell.targetLabel.attributedText.string containsString:@"21.0"],
        @"targetLabel should already have moved off the pre-drag setpoint");

    // Changed further along the range (~90%) — confirm it keeps tracking live.
    CGFloat changedAngle = startAngle + 0.9 * (endAngle - startAngle);
    gesture.fixedLocation = CGPointMake(
        self.cell.arcCenter.x + self.cell.arcRadius * cos(changedAngle),
        self.cell.arcCenter.y + self.cell.arcRadius * sin(changedAngle));
    gesture.fakeState = UIGestureRecognizerStateChanged;
    [self.cell handleThumbPan:gesture];

    XCTAssertEqualObjects(self.cell.tempLabel.text, tempLabelBefore,
        @"tempLabel must still show current temp mid-drag");
    NSString *targetAfterChanged = self.cell.targetLabel.attributedText.string;

    // Cancel the drag — no service call should have been made.
    gesture.fakeState = UIGestureRecognizerStateCancelled;
    [self.cell handleThumbPan:gesture];
    XCTAssertEqual(self.capturedServiceCalls.count, 0u);
    XCTAssertNotEqualObjects(targetAfterChanged, @"", @"sanity: label was actually populated during the drag");
}

#pragma mark - Audit fix: configureWithEntity re-entry must not clobber a pending nudge

- (void)testConfigureReentryWhileDebouncePending_DoesNotSnapOptimisticTargetBack {
    HADashboardConfigItem *item = [self configItemWithShowCurrentAsPrimary:YES];
    [self.cell configureWithEntity:self.entity configItem:item];
    [self.cell layoutIfNeeded];

    [self.cell plusTapped]; // pendingTargetTemp = 21.5, 5s debounce timer now pending
    XCTAssertNotNil(self.cell.buttonDebounceTimer);
    XCTAssertTrue([self.cell.targetLabel.attributedText.string containsString:@"21.5"]);

    // Simulate a WebSocket state push landing mid-debounce. HA hasn't processed the
    // pending set_temperature call yet, so the entity it reports still carries the
    // OLD target (21.0) — exactly the race the 5s debounce window is meant to survive.
    [self.cell configureWithEntity:self.entity configItem:item];
    [self.cell layoutIfNeeded];

    XCTAssertTrue([self.cell.targetLabel.attributedText.string containsString:@"21.5"],
        @"an entity update that arrives while a nudge is debouncing must not snap the "
        @"displayed setpoint back to HA's stale pre-tap value");

    [self.cell flushPendingButtonChange];
    XCTAssertEqual(self.capturedServiceCalls.count, 1u);
    XCTAssertEqualObjects(self.capturedServiceCalls.firstObject[@"data"][@"temperature"], @21.5);
}

- (void)testConfigureReentryWhileDebouncePending_DualSetpoint_DoesNotSnapBack {
    HAEntity *dualEntity = [HASnapshotTestHelpers entityWithId:@"climate.dual_test"
        state:@"heat_cool"
        attributes:@{
            @"friendly_name": @"Dual Test",
            @"current_temperature": @20.0,
            @"target_temp_low": @18.0,
            @"target_temp_high": @24.0,
            @"hvac_modes": @[@"off", @"heat_cool"],
            @"min_temp": @7,
            @"max_temp": @35,
            @"target_temp_step": @0.5,
            @"temperature_unit": @"°C",
        }];
    HADashboardConfigItem *item = [self configItemWithShowCurrentAsPrimary:NO];
    item.entityId = dualEntity.entityId;
    [self.cell configureWithEntity:dualEntity configItem:item];
    [self.cell layoutIfNeeded];

    [self.cell plusTapped]; // low side (default selection) +0.5 -> pendingTargetTempLow = 18.5
    [self.cell plusTapped]; // +0.5 again -> 19.0 (avoids the 18.5 rounding to "18" ambiguity below)
    XCTAssertNotNil(self.cell.buttonDebounceTimer);
    XCTAssertEqualWithAccuracy(self.cell.pendingTargetTempLow, 19.0, 0.001);

    NSString *expectedPendingLowTitle = [NSString stringWithFormat:@"%.0f°C", self.cell.pendingTargetTempLow];
    NSString *staleLowTitle = [NSString stringWithFormat:@"%.0f°C", 18.0];
    XCTAssertEqualObjects([self.cell.dualLowButton titleForState:UIControlStateNormal], expectedPendingLowTitle);

    // Re-entry mid-debounce with HA still reporting the stale low=18.
    [self.cell configureWithEntity:dualEntity configItem:item];
    [self.cell layoutIfNeeded];

    NSString *lowTitleAfterReentry = [self.cell.dualLowButton titleForState:UIControlStateNormal];
    XCTAssertEqualObjects(lowTitleAfterReentry, expectedPendingLowTitle,
        @"dual-setpoint low button must not snap back to the stale pre-tap value while debouncing");
    XCTAssertNotEqualObjects(lowTitleAfterReentry, staleLowTitle);
}

@end
