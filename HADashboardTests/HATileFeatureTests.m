#import <XCTest/XCTest.h>
#import "HATileFeatureView.h"
#import "HATileFeatureFactory.h"
#import "HASliderFeatureView.h"
#import "HAButtonRowFeatureView.h"
#import "HAModeFeatureView.h"
#import "HATileEntityCell.h"
#import "HAEntity.h"
#import "HAEntity+Climate.h"
#import "HADashboardConfig.h"
#import "HASnapshotTestHelpers.h"

#pragma mark - Test Helpers

/// Create a mock entity with minimal setup.
static HAEntity *makeEntity(NSString *entityId, NSString *state, NSDictionary *attrs) {
    return [HASnapshotTestHelpers entityWithId:entityId state:state attributes:attrs];
}

/// Create a config item with features in customProperties.
static HADashboardConfigItem *makeConfigItem(NSString *entityId, NSArray *features) {
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entityId
                                                                cardType:@"tile"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    if (features) {
        NSMutableDictionary *props = [NSMutableDictionary dictionaryWithDictionary:item.customProperties ?: @{}];
        props[@"features"] = features;
        item.customProperties = [props copy];
    }
    return item;
}

#pragma mark - HATileFeatureFactory Tests

@interface HATileFeatureFactoryTests : XCTestCase
@end

@implementation HATileFeatureFactoryTests

- (void)testSliderTypesReturnSliderView {
    HAEntity *entity = makeEntity(@"light.test", @"on", @{@"brightness": @178});
    NSArray *sliderTypes = @[@"light-brightness", @"cover-position", @"cover-tilt-position",
                             @"fan-speed", @"light-color-temp", @"media-player-volume-slider",
                             @"numeric-input", @"target-humidity"];

    for (NSString *type in sliderTypes) {
        NSDictionary *config = @{@"type": type};
        HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:config entity:entity];
        XCTAssertNotNil(view, @"Factory should return view for %@", type);
        XCTAssertTrue([view isKindOfClass:[HASliderFeatureView class]],
                     @"Factory should return HASliderFeatureView for %@, got %@", type, NSStringFromClass([view class]));
    }
}

- (void)testButtonRowTypesReturnButtonRowView {
    HAEntity *entity = makeEntity(@"cover.test", @"open", @{});
    NSArray *buttonTypes = @[@"cover-open-close", @"lock-commands", @"toggle",
                             @"vacuum-commands", @"counter-actions", @"target-temperature"];

    for (NSString *type in buttonTypes) {
        NSDictionary *config = @{@"type": type};
        HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:config entity:entity];
        XCTAssertNotNil(view, @"Factory should return view for %@", type);
        XCTAssertTrue([view isKindOfClass:[HAButtonRowFeatureView class]],
                     @"Factory should return HAButtonRowFeatureView for %@, got %@", type, NSStringFromClass([view class]));
    }
}

- (void)testModeTypesReturnModeView {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"]
    });
    NSArray *modeTypes = @[@"climate-hvac-modes", @"climate-preset-modes",
                           @"climate-fan-modes", @"alarm-modes"];

    for (NSString *type in modeTypes) {
        NSDictionary *config = @{@"type": type};
        HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:config entity:entity];
        XCTAssertNotNil(view, @"Factory should return view for %@", type);
        XCTAssertTrue([view isKindOfClass:[HAModeFeatureView class]],
                     @"Factory should return HAModeFeatureView for %@, got %@", type, NSStringFromClass([view class]));
    }
}

- (void)testUnknownTypeReturnsNil {
    HAEntity *entity = makeEntity(@"light.test", @"on", @{});
    NSDictionary *config = @{@"type": @"nonexistent-feature"};
    HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:config entity:entity];
    XCTAssertNil(view, @"Factory should return nil for unknown feature type");
}

- (void)testEmptyTypeReturnsNil {
    HAEntity *entity = makeEntity(@"light.test", @"on", @{});
    HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:@{@"type": @""} entity:entity];
    XCTAssertNil(view, @"Factory should return nil for empty type");
}

- (void)testMissingTypeReturnsNil {
    HAEntity *entity = makeEntity(@"light.test", @"on", @{});
    HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:@{} entity:entity];
    XCTAssertNil(view, @"Factory should return nil for missing type key");
}

- (void)testNonStringTypeReturnsNil {
    HAEntity *entity = makeEntity(@"light.test", @"on", @{});
    HATileFeatureView *view = [HATileFeatureFactory featureViewForConfig:@{@"type": @42} entity:entity];
    XCTAssertNil(view, @"Factory should return nil for non-string type");
}

- (void)testHeightForSliderType {
    CGFloat height = [HATileFeatureFactory heightForFeatureType:@"light-brightness"];
    XCTAssertEqual(height, 44.0, @"Slider features should be 44px");
}

- (void)testHeightForButtonRowType {
    CGFloat height = [HATileFeatureFactory heightForFeatureType:@"cover-open-close"];
    XCTAssertEqual(height, 36.0, @"Button row features should be 36px");
}

- (void)testHeightForModeType {
    CGFloat height = [HATileFeatureFactory heightForFeatureType:@"climate-hvac-modes"];
    XCTAssertEqual(height, 36.0, @"Mode features should be 36px");
}

- (void)testHeightForUnknownTypeIsZero {
    CGFloat height = [HATileFeatureFactory heightForFeatureType:@"nonexistent"];
    XCTAssertEqual(height, 0.0, @"Unknown feature types should return 0 height");
}

@end

#pragma mark - HASliderFeatureView Tests

@interface HASliderFeatureViewTests : XCTestCase
@end

@implementation HASliderFeatureViewTests

- (void)testBrightnessSliderValue {
    HAEntity *entity = makeEntity(@"light.test", @"on", @{@"brightness": @127}); // 127/255 ≈ 50%
    NSDictionary *config = @{@"type": @"light-brightness"};
    HASliderFeatureView *view = (HASliderFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    XCTAssertNotNil(view);

    // Access the slider via subviews
    UISlider *slider = [self findSliderInView:view];
    XCTAssertNotNil(slider, @"Should contain a UISlider");
    XCTAssertEqualWithAccuracy(slider.minimumValue, 0.0, 0.01);
    XCTAssertEqualWithAccuracy(slider.maximumValue, 100.0, 0.01);
    // brightness 127 = 50% (127/255*100 ≈ 49.8)
    XCTAssertEqualWithAccuracy(slider.value, 50.0, 1.0, @"Brightness 127/255 should be ~50%%");
}

- (void)testBrightnessSliderOffEntity {
    HAEntity *entity = makeEntity(@"light.test", @"off", @{@"brightness": @127});
    NSDictionary *config = @{@"type": @"light-brightness"};
    HASliderFeatureView *view = (HASliderFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    UISlider *slider = [self findSliderInView:view];
    XCTAssertEqualWithAccuracy(slider.value, 0.0, 0.01, @"Off entity should show 0 brightness");
}

- (void)testCoverPositionSliderValue {
    HAEntity *entity = makeEntity(@"cover.test", @"open", @{@"current_position": @75, @"device_class": @"blind"});
    NSDictionary *config = @{@"type": @"cover-position"};
    HASliderFeatureView *view = (HASliderFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    UISlider *slider = [self findSliderInView:view];
    XCTAssertNotNil(slider);
    XCTAssertEqualWithAccuracy(slider.value, 75.0, 0.01, @"Cover position should be 75%%");
}

- (void)testFanSpeedSliderValue {
    HAEntity *entity = makeEntity(@"fan.test", @"on", @{@"percentage": @50});
    NSDictionary *config = @{@"type": @"fan-speed"};
    HASliderFeatureView *view = (HASliderFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    UISlider *slider = [self findSliderInView:view];
    XCTAssertNotNil(slider);
    XCTAssertEqualWithAccuracy(slider.value, 50.0, 0.01, @"Fan speed should be 50%%");
}

- (void)testBrightnessServiceCall {
    HAEntity *entity = makeEntity(@"light.test", @"on", @{@"brightness": @127});
    NSDictionary *config = @{@"type": @"light-brightness"};
    HASliderFeatureView *view = (HASliderFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    __block NSString *capturedDomain = nil;
    __block NSDictionary *capturedData = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
        capturedDomain = domain;
        capturedData = data;
    };

    // Simulate slider touch-up by setting value and calling the action
    UISlider *slider = [self findSliderInView:view];
    slider.value = 80;
    [view performSelector:@selector(sliderTouchUp:) withObject:slider];

    XCTAssertEqualObjects(capturedDomain, @"light", @"Should call light domain");
    XCTAssertEqualObjects(capturedService, @"turn_on", @"Should call turn_on");
    XCTAssertEqualObjects(capturedData[@"brightness_pct"], @80, @"Should send brightness_pct=80");
    XCTAssertEqualObjects(capturedData[@"entity_id"], @"light.test");
}

- (void)testCoverPositionServiceCall {
    HAEntity *entity = makeEntity(@"cover.test", @"open", @{@"current_position": @50});
    NSDictionary *config = @{@"type": @"cover-position"};
    HASliderFeatureView *view = (HASliderFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    __block NSString *capturedDomain = nil;
    __block NSDictionary *capturedData = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
        capturedDomain = domain;
        capturedData = data;
    };

    UISlider *slider = [self findSliderInView:view];
    slider.value = 30;
    [view performSelector:@selector(sliderTouchUp:) withObject:slider];

    XCTAssertEqualObjects(capturedDomain, @"cover");
    XCTAssertEqualObjects(capturedService, @"set_cover_position");
    XCTAssertEqualObjects(capturedData[@"position"], @30);
}

- (void)testUnavailableEntityDisablesSlider {
    HAEntity *entity = makeEntity(@"light.test", @"unavailable", @{});
    NSDictionary *config = @{@"type": @"light-brightness"};
    HASliderFeatureView *view = (HASliderFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    UISlider *slider = [self findSliderInView:view];
    XCTAssertFalse(slider.enabled, @"Slider should be disabled for unavailable entity");
}

#pragma mark - Slider Helper

- (UISlider *)findSliderInView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UISlider class]]) return (UISlider *)sub;
        UISlider *found = [self findSliderInView:sub];
        if (found) return found;
    }
    return nil;
}

@end

#pragma mark - HAButtonRowFeatureView Tests

@interface HAButtonRowFeatureViewTests : XCTestCase
@end

@implementation HAButtonRowFeatureViewTests

- (void)testCoverOpenCloseHasThreeButtons {
    HAEntity *entity = makeEntity(@"cover.test", @"open", @{@"device_class": @"garage"});
    NSDictionary *config = @{@"type": @"cover-open-close"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    NSArray *buttons = [self findButtonsInView:view];
    XCTAssertEqual(buttons.count, 3, @"cover-open-close should have 3 buttons (Open/Stop/Close)");
}

- (void)testLockCommandsHasTwoButtons {
    HAEntity *entity = makeEntity(@"lock.test", @"locked", @{});
    NSDictionary *config = @{@"type": @"lock-commands"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    NSArray *buttons = [self findButtonsInView:view];
    XCTAssertEqual(buttons.count, 2, @"lock-commands should have 2 buttons (Lock/Unlock)");
}

- (void)testToggleHasSwitch {
    HAEntity *entity = makeEntity(@"switch.test", @"on", @{});
    NSDictionary *config = @{@"type": @"toggle"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    UISwitch *sw = [self findSwitchInView:view];
    XCTAssertNotNil(sw, @"toggle feature should contain a UISwitch");
    XCTAssertTrue(sw.on, @"Switch should be ON for entity state 'on'");
}

- (void)testToggleSwitchOffState {
    HAEntity *entity = makeEntity(@"switch.test", @"off", @{});
    NSDictionary *config = @{@"type": @"toggle"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    UISwitch *sw = [self findSwitchInView:view];
    XCTAssertNotNil(sw);
    XCTAssertFalse(sw.on, @"Switch should be OFF for entity state 'off'");
}

- (void)testCoverOpenCloseServiceCallOpen {
    HAEntity *entity = makeEntity(@"cover.test", @"closed", @{});
    NSDictionary *config = @{@"type": @"cover-open-close"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    __block NSString *capturedDomain = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
        capturedDomain = domain;
    };

    // Find the Open button (tag 0)
    NSArray *buttons = [self findButtonsInView:view];
    UIButton *openBtn = nil;
    for (UIButton *btn in buttons) {
        if (btn.tag == 0) { openBtn = btn; break; }
    }
    XCTAssertNotNil(openBtn, @"Should find Open button with tag 0");
    [openBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

    XCTAssertEqualObjects(capturedDomain, @"cover");
    XCTAssertEqualObjects(capturedService, @"open_cover");
}

- (void)testCoverOpenCloseServiceCallClose {
    HAEntity *entity = makeEntity(@"cover.test", @"open", @{});
    NSDictionary *config = @{@"type": @"cover-open-close"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
    };

    NSArray *buttons = [self findButtonsInView:view];
    UIButton *closeBtn = nil;
    for (UIButton *btn in buttons) {
        if (btn.tag == 2) { closeBtn = btn; break; }
    }
    XCTAssertNotNil(closeBtn, @"Should find Close button with tag 2");
    [closeBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

    XCTAssertEqualObjects(capturedService, @"close_cover");
}

- (void)testLockServiceCallLock {
    HAEntity *entity = makeEntity(@"lock.test", @"unlocked", @{});
    NSDictionary *config = @{@"type": @"lock-commands"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    __block NSString *capturedDomain = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
        capturedDomain = domain;
    };

    NSArray *buttons = [self findButtonsInView:view];
    UIButton *lockBtn = nil;
    for (UIButton *btn in buttons) {
        if (btn.tag == 10) { lockBtn = btn; break; }
    }
    XCTAssertNotNil(lockBtn);
    [lockBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

    XCTAssertEqualObjects(capturedDomain, @"lock");
    XCTAssertEqualObjects(capturedService, @"lock");
}

- (void)testTargetTemperatureHasThreeViews {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"temperature": @21, @"target_temp_step": @0.5
    });
    NSDictionary *config = @{@"type": @"target-temperature"};
    HAButtonRowFeatureView *view = (HAButtonRowFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    // Should have minus button, value label, plus button
    NSArray *buttons = [self findButtonsInView:view];
    XCTAssertEqual(buttons.count, 2, @"target-temperature should have 2 buttons (minus and plus)");

    UILabel *valueLabel = [self findLabelWithTextContaining:@"21" inView:view];
    XCTAssertNotNil(valueLabel, @"Should display current temperature value");
}

#pragma mark - Button/Switch Helpers

- (NSArray<UIButton *> *)findButtonsInView:(UIView *)view {
    NSMutableArray *buttons = [NSMutableArray array];
    [self _findButtons:view result:buttons];
    return [buttons copy];
}

- (void)_findButtons:(UIView *)view result:(NSMutableArray *)result {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            [result addObject:(UIButton *)sub];
        }
        [self _findButtons:sub result:result];
    }
}

- (UISwitch *)findSwitchInView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UISwitch class]]) return (UISwitch *)sub;
        UISwitch *found = [self findSwitchInView:sub];
        if (found) return found;
    }
    return nil;
}

- (UILabel *)findLabelWithTextContaining:(NSString *)text inView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)sub;
            if ([label.text containsString:text]) return label;
        }
        UILabel *found = [self findLabelWithTextContaining:text inView:sub];
        if (found) return found;
    }
    return nil;
}

@end

#pragma mark - HAModeFeatureView Tests

@interface HAModeFeatureViewTests : XCTestCase
@end

@implementation HAModeFeatureViewTests

- (void)testHvacModesRendersButtons {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"]
    });
    NSDictionary *config = @{@"type": @"climate-hvac-modes",
                             @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
                             @"style": @"icons"};
    HAModeFeatureView *view = (HAModeFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    XCTAssertNotNil(view);

    NSArray *buttons = [self findButtonsInView:view];
    XCTAssertEqual(buttons.count, 4, @"Should render 4 HVAC mode buttons");
}

- (void)testHvacModesConfigFiltersModes {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto", @"dry", @"fan_only"]
    });
    // Config only requests 3 modes
    NSDictionary *config = @{@"type": @"climate-hvac-modes",
                             @"hvac_modes": @[@"off", @"heat", @"cool"]};
    HAModeFeatureView *view = (HAModeFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    NSArray *buttons = [self findButtonsInView:view];
    XCTAssertEqual(buttons.count, 3, @"Should only render modes from config, not all entity modes");
}

- (void)testHvacModeServiceCall {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"hvac_modes": @[@"off", @"heat", @"cool"]
    });
    NSDictionary *config = @{@"type": @"climate-hvac-modes",
                             @"hvac_modes": @[@"off", @"heat", @"cool"]};
    HAModeFeatureView *view = (HAModeFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    __block NSString *capturedDomain = nil;
    __block NSDictionary *capturedData = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
        capturedDomain = domain;
        capturedData = data;
    };

    // Tap the "cool" button (tag 2 = index 2)
    NSArray *buttons = [self findButtonsInView:view];
    UIButton *coolBtn = nil;
    for (UIButton *btn in buttons) {
        if (btn.tag == 2) { coolBtn = btn; break; }
    }
    XCTAssertNotNil(coolBtn);
    [coolBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

    XCTAssertEqualObjects(capturedDomain, @"climate");
    XCTAssertEqualObjects(capturedService, @"set_hvac_mode");
    XCTAssertEqualObjects(capturedData[@"hvac_mode"], @"cool");
}

- (void)testPresetModeServiceCall {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"preset_modes": @[@"eco", @"comfort", @"boost"],
        @"preset_mode": @"eco"
    });
    NSDictionary *config = @{@"type": @"climate-preset-modes",
                             @"preset_modes": @[@"eco", @"comfort", @"boost"]};
    HAModeFeatureView *view = (HAModeFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    __block NSDictionary *capturedData = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
        capturedData = data;
    };

    NSArray *buttons = [self findButtonsInView:view];
    // Tap "comfort" (index 1)
    UIButton *comfortBtn = nil;
    for (UIButton *btn in buttons) {
        if (btn.tag == 1) { comfortBtn = btn; break; }
    }
    XCTAssertNotNil(comfortBtn);
    [comfortBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

    XCTAssertEqualObjects(capturedService, @"set_preset_mode");
    XCTAssertEqualObjects(capturedData[@"preset_mode"], @"comfort");
}

- (void)testFanModeServiceCall {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"fan_modes": @[@"auto", @"low", @"high"],
        @"fan_mode": @"auto"
    });
    NSDictionary *config = @{@"type": @"climate-fan-modes"};
    HAModeFeatureView *view = (HAModeFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    __block NSString *capturedService = nil;
    __block NSDictionary *capturedData = nil;
    view.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
        capturedService = service;
        capturedData = data;
    };

    NSArray *buttons = [self findButtonsInView:view];
    XCTAssertEqual(buttons.count, 3, @"Should have 3 fan mode buttons");

    // Tap "high" (index 2)
    UIButton *highBtn = nil;
    for (UIButton *btn in buttons) {
        if (btn.tag == 2) { highBtn = btn; break; }
    }
    XCTAssertNotNil(highBtn);
    [highBtn sendActionsForControlEvents:UIControlEventTouchUpInside];

    XCTAssertEqualObjects(capturedService, @"set_fan_mode");
    XCTAssertEqualObjects(capturedData[@"fan_mode"], @"high");
}

- (void)testDropdownStyleRendersOneButton {
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"]
    });
    NSDictionary *config = @{@"type": @"climate-hvac-modes",
                             @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
                             @"style": @"dropdown"};
    HAModeFeatureView *view = (HAModeFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];

    // Dropdown should have one button (not 4 mode buttons)
    NSArray *buttons = [self findButtonsInView:view];
    XCTAssertEqual(buttons.count, 1, @"Dropdown style should render 1 button, not individual mode buttons");
}

- (void)testEmptyModesHidesView {
    // Entity with no hvac_modes attribute and no config modes
    HAEntity *entity = makeEntity(@"climate.test", @"heat", @{});
    NSDictionary *config = @{@"type": @"climate-hvac-modes"};
    HAModeFeatureView *view = (HAModeFeatureView *)[HATileFeatureFactory featureViewForConfig:config entity:entity];
    // View should be hidden when no modes are available
    XCTAssertTrue(view.hidden, @"View should be hidden when no modes available");
}

#pragma mark - Button Helper

- (NSArray<UIButton *> *)findButtonsInView:(UIView *)view {
    NSMutableArray *buttons = [NSMutableArray array];
    [self _findButtons:view result:buttons];
    return [buttons copy];
}

- (void)_findButtons:(UIView *)view result:(NSMutableArray *)result {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            [result addObject:(UIButton *)sub];
        }
        [self _findButtons:sub result:result];
    }
}

@end

#pragma mark - Dynamic Height Tests

@interface HATileFeatureDynamicHeightTests : XCTestCase
@end

@implementation HATileFeatureDynamicHeightTests

- (void)testNoFeaturesReturnsBaseHeight {
    HADashboardConfigItem *item = makeConfigItem(@"light.test", nil);
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    XCTAssertEqual(height, 72.0, @"No features should return base 72px height");
}

- (void)testSingleSliderFeatureAddsHeight {
    HADashboardConfigItem *item = makeConfigItem(@"light.test", @[@{@"type": @"light-brightness"}]);
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    // 72 base + 44 slider + 4 spacing + 4 bottom padding = 124
    XCTAssertGreaterThan(height, 72.0, @"Single slider feature should increase height");
    XCTAssertEqualWithAccuracy(height, 72.0 + 44.0 + 4.0 + 4.0, 1.0);
}

- (void)testTwoFeaturesStackHeight {
    HADashboardConfigItem *item = makeConfigItem(@"cover.test",
        @[@{@"type": @"cover-open-close"}, @{@"type": @"cover-position"}]);
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    // 72 base + 36 buttons + 4 spacing + 44 slider + 4 spacing + 4 bottom = 164
    CGFloat expected = 72.0 + 36.0 + 4.0 + 44.0 + 4.0 + 4.0;
    XCTAssertEqualWithAccuracy(height, expected, 1.0, @"Two features should stack heights");
}

- (void)testCompactModeIgnoresFeatures {
    HADashboardConfigItem *item = makeConfigItem(@"light.test", @[@{@"type": @"light-brightness"}]);
    NSMutableDictionary *props = [item.customProperties mutableCopy];
    props[@"compact"] = @YES;
    item.customProperties = [props copy];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    XCTAssertEqual(height, 72.0, @"Compact mode should ignore features and return compact height");
}

- (void)testUnknownFeatureTypeSkipped {
    HADashboardConfigItem *item = makeConfigItem(@"light.test",
        @[@{@"type": @"light-brightness"}, @{@"type": @"nonexistent-widget"}]);
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    // Only the brightness slider should contribute (unknown skipped)
    CGFloat expectedWithOne = 72.0 + 44.0 + 4.0 + 4.0;
    XCTAssertEqualWithAccuracy(height, expectedWithOne, 1.0,
        @"Unknown feature types should not contribute to height");
}

@end
