#import <XCTest/XCTest.h>
#import "HABadgeRowCell.h"
#import "HAHeadingBadgesView.h"
#import "HADashboardConfig.h"
#import "HADashboardViewController.h"
#import "HAActionDispatcher.h"
#import "HALovelaceParser.h"
#import "HAEntity.h"
#import "HASnapshotTestHelpers.h"

// Gesture handlers and badge views, exposed for direct invocation.
@interface HABadgeRowCell (BadgeActionTestAccess)
@property (nonatomic, strong) NSMutableArray<UIView *> *badgeViews;
- (void)badgeTapped:(UITapGestureRecognizer *)gesture;
- (void)badgeDoubleTapped:(UITapGestureRecognizer *)gesture;
- (void)badgeHeld:(UILongPressGestureRecognizer *)gesture;
@end

@interface HAHeadingBadgesView (BadgeActionTestAccess)
- (void)badgeTapped:(UITapGestureRecognizer *)gesture;
- (void)badgeDoubleTapped:(UITapGestureRecognizer *)gesture;
- (void)badgeHeld:(UILongPressGestureRecognizer *)gesture;
@end

@interface HADashboardViewController (BadgeActionTestAccess)
- (void)performBadgeAction:(NSString *)actionType forEntity:(HAEntity *)entity badgeConfig:(NSDictionary *)badgeConfig;
@end

/// Stand-in recognizers: the handlers only read `view` and (hold) `state`.
@interface HAStubTap : UITapGestureRecognizer
@property (nonatomic, strong) UIView *stubView;
@end
@implementation HAStubTap
- (UIView *)view { return self.stubView; }
@end

@interface HAStubLongPress : UILongPressGestureRecognizer
@property (nonatomic, strong) UIView *stubView;
@property (nonatomic, assign) UIGestureRecognizerState stubState;
@end
@implementation HAStubLongPress
- (UIView *)view { return self.stubView; }
- (UIGestureRecognizerState)state { return self.stubState; }
@end

/// View badges (HABadgeRowCell) and heading badges (HAHeadingBadgesView):
/// hold and double tap get recognizers only when configured, and each
/// gesture runs the configured action through the dashboard's action path.
@interface HABadgeActionTests : XCTestCase
@property (nonatomic, strong) HADashboardViewController *dashboard;
@end

@implementation HABadgeActionTests

- (void)setUp {
    [super setUp];
    self.dashboard = [[HADashboardViewController alloc] init];
}

- (void)tearDown {
    self.dashboard = nil;
    [super tearDown];
}

- (NSDictionary<NSString *, HAEntity *> *)entities {
    return @{
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"sensor.living_room_humidity": [HASnapshotTestHelpers sensorHumidity],
    };
}

- (NSDictionary *)navigate:(NSString *)path {
    return @{@"action": @"navigate", @"navigation_path": path};
}

- (NSArray<NSString *> *)recognizerClassesOn:(UIView *)view {
    NSMutableArray *classes = [NSMutableArray array];
    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        if ([gr isKindOfClass:[UILongPressGestureRecognizer class]]) [classes addObject:@"hold"];
        else if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            [classes addObject:((UITapGestureRecognizer *)gr).numberOfTapsRequired == 2 ? @"double" : @"tap"];
        }
    }
    return [classes sortedArrayUsingSelector:@selector(compare:)];
}

/// Expect a navigate action for `path` to reach HAActionDispatcher while `block` runs.
- (void)expectNavigateTo:(NSString *)path during:(void (^)(void))block {
    [self expectationForNotification:HAActionNavigateNotification object:nil handler:^BOOL(NSNotification *note) {
        return [note.userInfo[@"path"] isEqualToString:path];
    }];
    block();
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (HAStubTap *)tapOn:(UIView *)view {
    HAStubTap *tap = [[HAStubTap alloc] init];
    tap.stubView = view;
    return tap;
}

- (HAStubLongPress *)holdOn:(UIView *)view state:(UIGestureRecognizerState)state {
    HAStubLongPress *hold = [[HAStubLongPress alloc] init];
    hold.stubView = view;
    hold.stubState = state;
    return hold;
}

#pragma mark - View badges

- (void)testViewBadge_holdAndDoubleTap_dispatchConfiguredActions {
    NSArray *configs = [HALovelaceParser normalizedViewBadgeConfigs:@[
        @{@"entity": @"sensor.living_room_temperature",
          @"hold_action": [self navigate:@"/hold"], @"double_tap_action": [self navigate:@"/double"]},
        @{@"entity": @"sensor.living_room_humidity"},
    ]];
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.cardType = @"badges";
    section.entityIds = @[@"sensor.living_room_temperature", @"sensor.living_room_humidity"];
    section.customProperties = @{@"badgeConfigs": configs, @"viewBadges": @YES};

    HABadgeRowCell *cell = [[HABadgeRowCell alloc] initWithFrame:CGRectMake(0, 0, 320, 60)];
    [cell configureWithSection:section entities:[self entities]];
    NSMutableArray<NSString *> *fired = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    cell.badgeActionBlock = ^(HAEntity *entity, NSDictionary *badgeConfig, NSString *actionType) {
        [fired addObject:[NSString stringWithFormat:@"%@:%@", entity.entityId, actionType]];
        [weakSelf.dashboard performBadgeAction:actionType forEntity:entity badgeConfig:badgeConfig];
    };
    XCTAssertEqual(cell.badgeViews.count, 2u);
    UIView *configured = cell.badgeViews[0];
    UIView *plain = cell.badgeViews[1];
    XCTAssertEqualObjects([self recognizerClassesOn:configured], (@[@"double", @"hold", @"tap"]));
    XCTAssertEqualObjects([self recognizerClassesOn:plain], (@[@"tap"]),
                          @"Unconfigured hold/double tap add no recognizers (HA: none unless configured)");

    [self expectNavigateTo:@"/hold" during:^{
        [cell badgeHeld:[self holdOn:configured state:UIGestureRecognizerStateBegan]];
    }];
    [cell badgeHeld:[self holdOn:configured state:UIGestureRecognizerStateEnded]]; // only Began fires
    [self expectNavigateTo:@"/double" during:^{
        [cell badgeDoubleTapped:[self tapOn:configured]];
    }];
    XCTAssertEqualObjects(fired, (@[@"sensor.living_room_temperature:hold_action",
                                    @"sensor.living_room_temperature:double_tap_action"]));

    // Tap without tap_action keeps the more-info default
    [self expectationForNotification:@"HAActionMoreInfoNotification" object:nil handler:^BOOL(NSNotification *note) {
        return [((HAEntity *)note.userInfo[@"entity"]).entityId isEqualToString:@"sensor.living_room_humidity"];
    }];
    [cell badgeTapped:[self tapOn:plain]];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

#pragma mark - Heading badges

- (void)testHeadingBadge_tapHoldDoubleTap_dispatchConfiguredActions_defaultsNone {
    NSArray *configs = [HALovelaceParser normalizedHeadingBadgeConfigs:@{@"type": @"heading", @"badges": @[
        @{@"entity": @"sensor.living_room_temperature", @"tap_action": [self navigate:@"/tap"],
          @"hold_action": [self navigate:@"/hold"], @"double_tap_action": [self navigate:@"/double"]},
        @{@"entity": @"sensor.living_room_humidity"},
    ]}];
    HAHeadingBadgesView *view = [[HAHeadingBadgesView alloc] initWithFrame:CGRectMake(0, 0, 300, 36)];
    [view configureWithBadgeConfigs:configs entities:[self entities]];
    [view layoutIfNeeded];
    NSMutableArray<NSString *> *fired = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    view.badgeActionBlock = ^(HAEntity *entity, NSDictionary *badgeConfig, NSString *actionType) {
        [fired addObject:actionType];
        [weakSelf.dashboard performBadgeAction:actionType forEntity:entity badgeConfig:badgeConfig];
    };
    XCTAssertEqual(view.badgeViews.count, 2u);
    UIView *configured = view.badgeViews[0];
    UIView *plain = view.badgeViews[1];
    XCTAssertEqualObjects([self recognizerClassesOn:configured], (@[@"double", @"hold", @"tap"]));
    XCTAssertEqual(plain.gestureRecognizers.count, 0u, @"HA heading badges default every action to none");
    XCTAssertFalse(plain.accessibilityTraits & UIAccessibilityTraitButton);

    [self expectNavigateTo:@"/tap" during:^{ [view badgeTapped:[self tapOn:configured]]; }];
    [self expectNavigateTo:@"/hold" during:^{
        [view badgeHeld:[self holdOn:configured state:UIGestureRecognizerStateBegan]];
    }];
    [self expectNavigateTo:@"/double" during:^{ [view badgeDoubleTapped:[self tapOn:configured]]; }];
    [view badgeTapped:[self tapOn:plain]];
    [view badgeHeld:[self holdOn:plain state:UIGestureRecognizerStateBegan]];
    XCTAssertEqualObjects(fired, (@[@"tap_action", @"hold_action", @"double_tap_action"]),
                          @"A badge whose actions are none reports nothing");
}

/// Right-aligned layout: the last badge ends at the trailing edge, 8pt apart.
- (void)testHeadingBadges_rightAlignedWithSpacing {
    NSArray *configs = [HALovelaceParser normalizedHeadingBadgeConfigs:@{@"badges": @[
        @"sensor.living_room_temperature", @"sensor.living_room_humidity"]}];
    HAHeadingBadgesView *view = [[HAHeadingBadgesView alloc] initWithFrame:CGRectMake(0, 0, 300, 36)];
    [view configureWithBadgeConfigs:configs entities:[self entities]];
    [view layoutIfNeeded];
    CGRect first = view.badgeViews[0].frame, second = view.badgeViews[1].frame;
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(second), 300.0, 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetMinX(second) - CGRectGetMaxX(first), 8.0, 0.01);
    XCTAssertEqualWithAccuracy(view.contentWidth, CGRectGetMaxX(second) - CGRectGetMinX(first), 0.01);
}

@end
