#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HAEntityDetailSection.h"
#import "HAEntityDetailViewController.h"
#import "HAAttributeRowView.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import <CoreText/CoreText.h>

/// Standard width for detail section snapshots (matches bottom sheet content area).
static const CGFloat kDetailSectionWidth = 320.0;

@interface HAEntityDetailSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HAEntityDetailSnapshotTests

#pragma mark - Helpers

/// Create a domain section view for a given entity, sized and laid out for snapshotting.
- (UIView *)sectionViewForEntity:(HAEntity *)entity {
    HADetailServiceBlock noopBlock = ^(NSString *s, NSString *d, NSDictionary *data, NSString *eid) {};
    id<HAEntityDetailSection> section = [HAEntityDetailSectionFactory sectionForEntity:entity serviceBlock:noopBlock];
    if (!section) return nil;

    UIView *view = [section viewForEntity:entity];
    CGFloat height = [section preferredHeight];
    view.frame = CGRectMake(0, 0, kDetailSectionWidth, height);
    view.backgroundColor = [HATheme cellBackgroundColor];
    [view setNeedsLayout];
    [view layoutIfNeeded];
    return view;
}

/// Create a full entity detail view controller view, sized and laid out for snapshotting.
- (UIView *)detailViewForEntity:(HAEntity *)entity {
    HAEntityDetailViewController *vc = [[HAEntityDetailViewController alloc] init];
    vc.entity = entity;

    // Load the view hierarchy
    CGRect frame = CGRectMake(0, 0, 375, 500);
    vc.view.frame = frame;
    [vc viewDidLoad];
    [vc.view setNeedsLayout];
    [vc.view layoutIfNeeded];
    return vc.view;
}

/// Create an attribute row view for snapshotting.
- (UIView *)attributeRowWithKey:(NSString *)key value:(NSString *)value {
    HAAttributeRowView *row = [[HAAttributeRowView alloc] initWithFrame:CGRectMake(0, 0, kDetailSectionWidth, 28)];
    [row configureWithKey:key value:value];
    [row setNeedsLayout];
    [row layoutIfNeeded];
    return row;
}

#pragma mark - Light Section

- (void)testLightSectionOn {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnBrightness];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"lightSectionOn"];
}

- (void)testLightSectionDimmed {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnDimmed];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"lightSectionDimmed"];
}

- (void)testLightSectionOff {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOff];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"lightSectionOff"];
}

#pragma mark - Climate Section

- (void)testClimateSectionHeat {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"climateSectionHeat"];
}

- (void)testClimateSectionCool {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityCool];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"climateSectionCool"];
}

- (void)testClimateSectionOff {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityOff];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"climateSectionOff"];
}

#pragma mark - Cover Section

- (void)testCoverSectionOpen {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityOpenShutter];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"coverSectionOpen"];
}

- (void)testCoverSectionClosed {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityClosedGarage];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"coverSectionClosed"];
}

- (void)testCoverSectionPartial {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityPartial];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"coverSectionPartial"];
}

#pragma mark - Toggle Section (Switch)

- (void)testToggleSectionOn {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"toggleSectionOn"];
}

- (void)testToggleSectionOff {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOff];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"toggleSectionOff"];
}

#pragma mark - Sensor Section

- (void)testSensorSectionTemperature {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"sensorSectionTemp"];
}

- (void)testSensorSectionHumidity {
    HAEntity *entity = [HASnapshotTestHelpers sensorHumidity];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"sensorSectionHumidity"];
}

- (void)testSensorSectionBinary {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorMotionOn];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"sensorSectionBinary"];
}

#pragma mark - Media Player Section

- (void)testMediaPlayerSectionPlaying {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerPlaying];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"mediaPlayerSectionPlaying"];
}

- (void)testMediaPlayerSectionPaused {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerPaused];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"mediaPlayerSectionPaused"];
}

- (void)testMediaPlayerSectionOff {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerOff];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"mediaPlayerSectionOff"];
}

/// Issue #24: the power button was titled U+23FB, which older iOS fonts don't
/// cover, so it drew as an empty box. It must use a glyph the bundled MDI
/// font actually contains, and draw visible ink.
- (void)testMediaPlayerSectionPowerButtonRendersGlyph {
    HAEntity *tv = [HASnapshotTestHelpers mediaPlayerTVOff];
    HADetailServiceBlock noopBlock = ^(NSString *s, NSString *d, NSDictionary *data, NSString *eid) {};
    id<HAEntityDetailSection> section = [HAEntityDetailSectionFactory sectionForEntity:tv serviceBlock:noopBlock];
    UIView *view = [section viewForEntity:tv];
    view.frame = CGRectMake(0, 0, kDetailSectionWidth, [section preferredHeight]);
    [view layoutIfNeeded];

    UIButton *power = [(NSObject *)section valueForKey:@"powerButton"];
    XCTAssertNotNil(power, @"TURN_ON/TURN_OFF player must get a power button");
    XCTAssertFalse(power.hidden);
    XCTAssertTrue(power.enabled, @"TURN_ON is supported, so power is usable while off");
    XCTAssertEqualObjects(power.accessibilityLabel, @"Turn on");

    NSAttributedString *title = [power attributedTitleForState:UIControlStateNormal];
    XCTAssertEqualObjects(title.string, [HAIconMapper glyphForIconName:@"power-standby"]);
    XCTAssertFalse([title.string containsString:@"\u23FB"]);
    UIFont *font = [title attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertEqualObjects(font.fontName, [HAIconMapper mdiFontName]);

    // The MDI font has a real glyph for it (MDI codepoints are outside the BMP: a surrogate pair).
    unichar chars[2] = {0, 0};
    CGGlyph glyphs[2] = {0, 0};
    XCTAssertEqual(title.string.length, 2u);
    [title.string getCharacters:chars range:NSMakeRange(0, title.string.length)];
    XCTAssertTrue(CTFontGetGlyphsForCharacters((__bridge CTFontRef)font, chars, glyphs, (CFIndex)title.string.length));
    XCTAssertNotEqual(glyphs[0], 0);

    // And it draws ink.
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(40, 40), NO, 1);
    [title drawAtPoint:CGPointMake(4, 4)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage));
    const UInt8 *px = CFDataGetBytePtr(data);
    size_t bytesPerRow = CGImageGetBytesPerRow(image.CGImage);
    NSUInteger ink = 0;
    for (size_t y = 0; y < CGImageGetHeight(image.CGImage); y++) {
        for (size_t x = 0; x < CGImageGetWidth(image.CGImage); x++) {
            if (px[y * bytesPerRow + x * 4 + 3] > 0) ink++;
        }
    }
    CFRelease(data);
    XCTAssertGreaterThan(ink, 40u, @"power glyph should draw visible pixels");
}

#pragma mark - Media detail gating (HA more-info rules)

- (HAEntity *)tvWithState:(NSString *)state extra:(NSDictionary *)extra {
    NSMutableDictionary *attrs = [@{@"friendly_name": @"Sony TV", @"device_class": @"tv",
                                    @"supported_features": @150969,
                                    @"source_list": @[@"HDMI 1", @"HDMI 2", @"TV"]} mutableCopy];
    [attrs addEntriesFromDictionary:extra ?: @{}];
    return [HASnapshotTestHelpers entityWithId:@"media_player.sony_tv" state:state attributes:attrs];
}

/// Builds the media detail section, laid out at the detail width; returns the section.
- (NSObject<HAEntityDetailSection> *)mediaSectionForEntity:(HAEntity *)entity view:(UIView **)outView {
    HADetailServiceBlock noopBlock = ^(NSString *s, NSString *d, NSDictionary *data, NSString *eid) {};
    NSObject<HAEntityDetailSection> *section = (NSObject<HAEntityDetailSection> *)
        [HAEntityDetailSectionFactory sectionForEntity:entity serviceBlock:noopBlock];
    UIView *view = [section viewForEntity:entity];
    view.frame = CGRectMake(0, 0, kDetailSectionWidth, 600);
    [view layoutIfNeeded];
    if (outView) *outView = view;
    return section;
}

- (BOOL)section:(NSObject *)section shows:(NSString *)key inView:(UIView *)root {
    for (UIView *v = [section valueForKey:key]; v && v != root; v = v.superview) {
        if (v.hidden) return NO;
    }
    return YES;
}

- (void)assertSection:(NSObject *)section view:(UIView *)view shows:(NSArray<NSString *> *)shown hides:(NSArray<NSString *> *)hidden {
    for (NSString *key in shown) XCTAssertTrue([self section:section shows:key inView:view], @"%@ should be shown", key);
    for (NSString *key in hidden) XCTAssertFalse([self section:section shows:key inView:view], @"%@ should be hidden", key);
}

- (void)testMediaMoreInfoControlsPerState {
    HAEntity *off = [self tvWithState:@"off" extra:nil];
    // HA's more-info keeps source select while off; power is turn_on.
    XCTAssertEqualObjects([off mediaMoreInfoControls], (@[HAMediaControlTurnOn, HAMediaControlSelectSource]));
    XCTAssertEqualObjects([[self tvWithState:@"unavailable" extra:nil] mediaMoreInfoControls], @[]);
    HAEntity *withModes = [HASnapshotTestHelpers entityWithId:@"media_player.avr" state:@"standby" attributes:@{
        @"supported_features": @(HAMediaPlayerFeatureTurnOn | HAMediaPlayerFeatureSelectSoundMode),
        @"sound_mode_list": @[@"Movie", @"Music"]}];
    XCTAssertEqualObjects([withModes mediaMoreInfoControls], (@[HAMediaControlTurnOn, HAMediaControlSelectSoundMode]));
    // Active: the card's controls (source already included), no duplicates.
    HAEntity *on = [self tvWithState:@"on" extra:nil];
    XCTAssertEqualObjects([on mediaMoreInfoControls], [on mediaControls]);
}

- (void)testMediaDetailOffShowsPowerAndSourceOnly {
    UIView *view = nil;
    NSObject *section = [self mediaSectionForEntity:[self tvWithState:@"off" extra:nil] view:&view];
    [self assertSection:section view:view shows:@[@"powerButton", @"sourceSelectButton"]
                  hides:@[@"transportRow", @"volumeRow", @"seekRow", @"soundModeButton"]];
    XCTAssertEqualObjects(((UIButton *)[section valueForKey:@"powerButton"]).accessibilityLabel, @"Turn on");
}

- (void)testMediaDetailUnavailableShowsNothingActionable {
    UIView *view = nil;
    NSObject *section = [self mediaSectionForEntity:[self tvWithState:@"unavailable" extra:nil] view:&view];
    [self assertSection:section view:view shows:@[@"mediaInfoLabel"]
                  hides:@[@"transportRow", @"volumeRow", @"seekRow", @"bottomRow", @"powerButton"]];
}

- (void)testMediaDetailUpdatesInPlaceWhenTurnedOnAndOff {
    UIView *view = nil;
    NSObject<HAEntityDetailSection> *section = [self mediaSectionForEntity:[self tvWithState:@"off" extra:nil] view:&view];
    CGFloat offHeight = [section preferredHeight];

    [section updateWithEntity:[self tvWithState:@"playing" extra:@{@"media_title": @"News", @"source": @"TV"}]];
    [view layoutIfNeeded];
    [self assertSection:section view:view
                  shows:@[@"prevButton", @"playPauseButton", @"nextButton", @"muteButton", @"volumeDownButton",
                          @"volumeUpButton", @"sourceSelectButton", @"powerButton"]
                  hides:@[@"volumeSlider", @"shuffleButton", @"repeatButton", @"seekRow"]];
    XCTAssertEqualObjects(((UIButton *)[section valueForKey:@"powerButton"]).accessibilityLabel, @"Turn off");
    XCTAssertEqualObjects(((UIButton *)[section valueForKey:@"playPauseButton"]).accessibilityLabel, @"Pause");
    XCTAssertGreaterThan([section preferredHeight], offHeight, @"controls added in place must grow the section");

    [section updateWithEntity:[self tvWithState:@"off" extra:nil]];
    [view layoutIfNeeded];
    [self assertSection:section view:view shows:@[@"powerButton"] hides:@[@"transportRow", @"volumeRow"]];
    XCTAssertEqualWithAccuracy([section preferredHeight], offHeight, 0.5);
}

- (void)testMediaDetailFullSpeakerShowsExtendedControls {
    UIView *view = nil;
    NSObject *section = [self mediaSectionForEntity:[HASnapshotTestHelpers mediaPlayerSpeakerFullPlaying] view:&view];
    [self assertSection:section view:view
                  shows:@[@"repeatButton", @"prevButton", @"playPauseButton", @"nextButton", @"shuffleButton",
                          @"muteButton", @"volumeSlider", @"seekRow", @"sourceSelectButton", @"powerButton"]
                  hides:@[@"volumeDownButton", @"volumeUpButton", @"soundModeButton"]];
}

- (void)testMediaPlayerSectionSpeakerFull {
    UIView *view = [self sectionViewForEntity:[HASnapshotTestHelpers mediaPlayerSpeakerFullPlaying]];
    [self verifyView:view identifier:@"mediaPlayerSectionSpeakerFull"];
}

- (void)testMediaPlayerSectionTVOff {
    UIView *view = [self sectionViewForEntity:[HASnapshotTestHelpers mediaPlayerTVOff]];
    [self verifyView:view identifier:@"mediaPlayerSectionTVOff"];
}

#pragma mark - Fan Section

- (void)testFanSectionOnHalf {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOnHalf];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"fanSectionOnHalf"];
}

- (void)testFanSectionOnFull {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOnFull];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"fanSectionOnFull"];
}

- (void)testFanSectionOff {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOff];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"fanSectionOff"];
}

#pragma mark - Lock Section

- (void)testLockSectionLocked {
    HAEntity *entity = [HASnapshotTestHelpers lockLocked];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"lockSectionLocked"];
}

- (void)testLockSectionUnlocked {
    HAEntity *entity = [HASnapshotTestHelpers lockUnlocked];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"lockSectionUnlocked"];
}

#pragma mark - Vacuum Section

- (void)testVacuumSectionDocked {
    HAEntity *entity = [HASnapshotTestHelpers vacuumDocked];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"vacuumSectionDocked"];
}

- (void)testVacuumSectionCleaning {
    HAEntity *entity = [HASnapshotTestHelpers vacuumCleaning];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"vacuumSectionCleaning"];
}

- (void)testVacuumSectionReturning {
    HAEntity *entity = [HASnapshotTestHelpers vacuumReturning];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"vacuumSectionReturning"];
}

#pragma mark - Timer Section

- (void)testTimerSectionPaused {
    HAEntity *entity = [HASnapshotTestHelpers timerPaused];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"timerSectionPaused"];
}

- (void)testTimerSectionIdle {
    HAEntity *entity = [HASnapshotTestHelpers timerIdle];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"timerSectionIdle"];
}

#pragma mark - Scene Section

- (void)testSceneSectionDefault {
    HAEntity *entity = [HASnapshotTestHelpers sceneDefault];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"sceneSectionDefault"];
}

- (void)testSceneSectionActivated {
    HAEntity *entity = [HASnapshotTestHelpers sceneActivated];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"sceneSectionActivated"];
}

#pragma mark - Default Section (Unknown Domain)

- (void)testDefaultSectionUnknownDomain {
    HAEntity *entity = [HASnapshotTestHelpers entityWithId:@"unknown.test"
                                                     state:@"some_state"
                                                attributes:@{@"friendly_name": @"Unknown Entity"}];
    UIView *view = [self sectionViewForEntity:entity];
    [self verifyView:view identifier:@"defaultSection"];
}

#pragma mark - Attribute Row

- (void)testAttributeRowShortValue {
    UIView *row = [self attributeRowWithKey:@"Device class" value:@"temperature"];
    row.backgroundColor = [HATheme cellBackgroundColor];
    [self verifyView:row identifier:@"attributeRowShort"];
}

- (void)testAttributeRowLongValue {
    UIView *row = [self attributeRowWithKey:@"Supported features" value:@"This is a very long attribute value that might need to be truncated"];
    row.backgroundColor = [HATheme cellBackgroundColor];
    [self verifyView:row identifier:@"attributeRowLong"];
}

#pragma mark - Full Detail View

- (void)testDetailViewLight {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnBrightness];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewLight"];
}

- (void)testDetailViewClimate {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewClimate"];
}

- (void)testDetailViewSensor {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewSensor"];
}

- (void)testDetailViewSwitch {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewSwitch"];
}

- (void)testDetailViewMediaPlayer {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerPlaying];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewMediaPlayer"];
}

- (void)testDetailViewFan {
    HAEntity *entity = [HASnapshotTestHelpers fanEntityOnHalf];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewFan"];
}

- (void)testDetailViewLock {
    HAEntity *entity = [HASnapshotTestHelpers lockLocked];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewLock"];
}

- (void)testDetailViewVacuum {
    HAEntity *entity = [HASnapshotTestHelpers vacuumCleaning];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewVacuum"];
}

- (void)testDetailViewTimer {
    HAEntity *entity = [HASnapshotTestHelpers timerPaused];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewTimer"];
}

- (void)testDetailViewScene {
    HAEntity *entity = [HASnapshotTestHelpers sceneDefault];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewScene"];
}

- (void)testDetailViewCover {
    HAEntity *entity = [HASnapshotTestHelpers coverEntityPartial];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewCover"];
}

- (void)testDetailViewDefault {
    HAEntity *entity = [HASnapshotTestHelpers entityWithId:@"automation.morning_routine"
                                                     state:@"on"
                                                attributes:@{
        @"friendly_name": @"Morning Routine",
        @"last_triggered": @"2026-01-15T07:00:00Z",
        @"current": @0,
        @"icon": @"mdi:robot"
    }];
    UIView *view = [self detailViewForEntity:entity];
    [self verifyView:view identifier:@"detailViewDefault"];
}

@end
