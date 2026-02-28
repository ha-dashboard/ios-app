#import "HAEntityDetailSection.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"
#import "HAEntityDisplayHelper.h"
#import "HAColorWheelView.h"
#import "HAConnectionManager.h"
#import "UIView+HAUtilities.h"

#pragma mark - Light Detail Section

@interface HALightDetailSection : NSObject <HAEntityDetailSection, HAColorWheelViewDelegate>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UISlider *brightnessSlider;
@property (nonatomic, strong) UILabel *brightnessLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UISlider *colorTempSlider;
@property (nonatomic, strong) UILabel *colorTempLabel;
@property (nonatomic, strong) UIButton *effectButton;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, weak) UIView *containerRef;
@property (nonatomic, assign) BOOL hasColorTemp;
@property (nonatomic, assign) BOOL hasEffects;
@property (nonatomic, strong) HAColorWheelView *colorWheel;
@property (nonatomic, strong) UILabel *colorLabel;
@property (nonatomic, strong) UIView *tempTrackContainer;
@property (nonatomic, strong) CAGradientLayer *tempGradient;
@property (nonatomic, strong) UIScrollView *sceneScrollView;
@property (nonatomic, strong) NSArray<HAEntity *> *areaScenes;
@property (nonatomic, assign) BOOL hasHSColor;
@end

@implementation HALightDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];
    self.containerRef = container;

    // Detect features
    NSArray *supportedModes = [entity supportedColorModes];
    BOOL modesValid = supportedModes != nil;
    self.hasColorTemp = modesValid && [supportedModes containsObject:@"color_temp"];
    self.hasHSColor = modesValid && ([supportedModes containsObject:@"hs"] ||
                                      [supportedModes containsObject:@"xy"] ||
                                      [supportedModes containsObject:@"rgb"] ||
                                      [supportedModes containsObject:@"rgbw"] ||
                                      [supportedModes containsObject:@"rgbww"]);
    // Fall back to color_mode for lights that don't report supported_color_modes
    if (!modesValid) {
        NSString *colorMode = [entity colorMode];
        self.hasColorTemp = [colorMode isEqualToString:@"color_temp"];
        self.hasHSColor = ([colorMode isEqualToString:@"hs"] ||
                           [colorMode isEqualToString:@"rgb"] ||
                           [colorMode isEqualToString:@"xy"]);
    }
    NSArray *effectList = [entity effectList];
    self.hasEffects = effectList.count > 0;

    // Discover scenes in same area
    [self discoverAreaScenes:entity];

    UIView *prevAnchor = nil;

    // Toggle button
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.toggleButton.layer.cornerRadius = 8;
    self.toggleButton.clipsToBounds = YES;
    self.toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.toggleButton];

    // Brightness label
    self.brightnessLabel = [[UILabel alloc] init];
    self.brightnessLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.brightnessLabel.textColor = [HATheme secondaryTextColor];
    self.brightnessLabel.textAlignment = NSTextAlignmentRight;
    self.brightnessLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.brightnessLabel];

    // Brightness slider
    self.brightnessSlider = [[UISlider alloc] init];
    self.brightnessSlider.minimumValue = 0;
    self.brightnessSlider.maximumValue = 100;
    self.brightnessSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.brightnessSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.brightnessSlider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [container addSubview:self.brightnessSlider];

    [NSLayoutConstraint activateConstraints:@[
        [self.toggleButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.toggleButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.toggleButton.heightAnchor constraintEqualToConstant:36],
        [self.toggleButton.widthAnchor constraintEqualToConstant:80],

        [self.brightnessSlider.topAnchor constraintEqualToAnchor:self.toggleButton.bottomAnchor constant:12],
        [self.brightnessSlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.brightnessSlider.trailingAnchor constraintEqualToAnchor:self.brightnessLabel.leadingAnchor constant:-8],

        [self.brightnessLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.brightnessLabel.centerYAnchor constraintEqualToAnchor:self.brightnessSlider.centerYAnchor],
        [self.brightnessLabel.widthAnchor constraintEqualToConstant:44],
    ]];
    prevAnchor = self.brightnessSlider;

    // Color wheel (when HS/RGB/XY color is supported)
    if (self.hasHSColor) {
        self.colorLabel = [[UILabel alloc] init];
        self.colorLabel.text = @"Color";
        self.colorLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        self.colorLabel.textColor = [HATheme secondaryTextColor];
        self.colorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.colorLabel];

        self.colorWheel = [[HAColorWheelView alloc] init];
        self.colorWheel.delegate = self;
        self.colorWheel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.colorWheel];

        [NSLayoutConstraint activateConstraints:@[
            [self.colorLabel.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:16],
            [self.colorLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

            [self.colorWheel.topAnchor constraintEqualToAnchor:self.colorLabel.bottomAnchor constant:8],
            [self.colorWheel.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
            [self.colorWheel.widthAnchor constraintEqualToConstant:200],
            [self.colorWheel.heightAnchor constraintEqualToConstant:200],
        ]];
        prevAnchor = self.colorWheel;
    }

    // Color temperature slider with gradient track
    if (self.hasColorTemp) {
        UILabel *ctLabel = [[UILabel alloc] init];
        ctLabel.text = @"Color Temp";
        ctLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        ctLabel.textColor = [HATheme secondaryTextColor];
        ctLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:ctLabel];

        self.colorTempLabel = [[UILabel alloc] init];
        self.colorTempLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        self.colorTempLabel.textColor = [HATheme secondaryTextColor];
        self.colorTempLabel.textAlignment = NSTextAlignmentRight;
        self.colorTempLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.colorTempLabel];

        // Gradient track container (warm orange -> white -> cool blue)
        self.tempTrackContainer = [[UIView alloc] init];
        self.tempTrackContainer.layer.cornerRadius = 3;
        self.tempTrackContainer.clipsToBounds = YES;
        self.tempTrackContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.tempTrackContainer];

        self.tempGradient = [CAGradientLayer layer];
        self.tempGradient.colors = @[
            (id)[UIColor colorWithRed:1.0 green:0.65 blue:0.25 alpha:1.0].CGColor,  // ~2000K warm
            (id)[UIColor colorWithRed:1.0 green:0.85 blue:0.65 alpha:1.0].CGColor,  // ~3000K warm white
            (id)[UIColor colorWithRed:1.0 green:0.97 blue:0.92 alpha:1.0].CGColor,  // ~4000K neutral
            (id)[UIColor colorWithRed:0.85 green:0.92 blue:1.0 alpha:1.0].CGColor,  // ~5500K daylight
            (id)[UIColor colorWithRed:0.65 green:0.78 blue:1.0 alpha:1.0].CGColor,  // ~6500K cool
        ];
        self.tempGradient.startPoint = CGPointMake(0, 0.5);
        self.tempGradient.endPoint = CGPointMake(1, 0.5);
        [self.tempTrackContainer.layer addSublayer:self.tempGradient];

        self.colorTempSlider = [[UISlider alloc] init];
        NSNumber *minKNum = [entity minColorTempKelvin];
        NSNumber *maxKNum = [entity maxColorTempKelvin];
        NSInteger minK = minKNum ? minKNum.integerValue : 0;
        NSInteger maxK = maxKNum ? maxKNum.integerValue : 0;
        self.colorTempSlider.minimumValue = minK > 0 ? minK : 2000;
        self.colorTempSlider.maximumValue = maxK > minK ? maxK : 6500;
        // Make track transparent so gradient shows through
        UIImage *clearImg = [self onePixelImageWithColor:[UIColor clearColor]];
        [self.colorTempSlider setMinimumTrackImage:clearImg forState:UIControlStateNormal];
        [self.colorTempSlider setMaximumTrackImage:clearImg forState:UIControlStateNormal];
        self.colorTempSlider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.colorTempSlider addTarget:self action:@selector(colorTempChanged:) forControlEvents:UIControlEventValueChanged];
        [self.colorTempSlider addTarget:self action:@selector(colorTempReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [container addSubview:self.colorTempSlider];

        [NSLayoutConstraint activateConstraints:@[
            [ctLabel.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [ctLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

            [self.colorTempSlider.topAnchor constraintEqualToAnchor:ctLabel.bottomAnchor constant:4],
            [self.colorTempSlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.colorTempSlider.trailingAnchor constraintEqualToAnchor:self.colorTempLabel.leadingAnchor constant:-8],

            [self.colorTempLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.colorTempLabel.centerYAnchor constraintEqualToAnchor:self.colorTempSlider.centerYAnchor],
            [self.colorTempLabel.widthAnchor constraintEqualToConstant:52],

            // Gradient track sits behind the slider
            [self.tempTrackContainer.leadingAnchor constraintEqualToAnchor:self.colorTempSlider.leadingAnchor constant:2],
            [self.tempTrackContainer.trailingAnchor constraintEqualToAnchor:self.colorTempSlider.trailingAnchor constant:-2],
            [self.tempTrackContainer.centerYAnchor constraintEqualToAnchor:self.colorTempSlider.centerYAnchor],
            [self.tempTrackContainer.heightAnchor constraintEqualToConstant:6],
        ]];
        prevAnchor = self.colorTempSlider;

        // Update gradient frame after layout
        dispatch_async(dispatch_get_main_queue(), ^{
            self.tempGradient.frame = self.tempTrackContainer.bounds;
        });
    }

    // Effects picker button (when effect_list is non-empty)
    if (self.hasEffects) {
        self.effectButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.effectButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.effectButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.effectButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.effectButton.layer.cornerRadius = 8;
        self.effectButton.clipsToBounds = YES;
        self.effectButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        self.effectButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.effectButton addTarget:self action:@selector(effectTapped) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:self.effectButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.effectButton.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [self.effectButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.effectButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.effectButton.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = self.effectButton;
    }

    // Scene chips (scenes in the same area as this light)
    if (self.areaScenes.count > 0) {
        UILabel *scenesHeader = [[UILabel alloc] init];
        scenesHeader.text = @"Scenes";
        scenesHeader.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        scenesHeader.textColor = [HATheme secondaryTextColor];
        scenesHeader.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:scenesHeader];

        self.sceneScrollView = [[UIScrollView alloc] init];
        self.sceneScrollView.showsHorizontalScrollIndicator = NO;
        self.sceneScrollView.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.sceneScrollView];

        [NSLayoutConstraint activateConstraints:@[
            [scenesHeader.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:16],
            [scenesHeader.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

            [self.sceneScrollView.topAnchor constraintEqualToAnchor:scenesHeader.bottomAnchor constant:8],
            [self.sceneScrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.sceneScrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.sceneScrollView.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = self.sceneScrollView;

        [self layoutSceneChips];
    }

    [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight {
    CGFloat h = 80; // toggle + brightness slider
    if (self.hasHSColor) h += 232; // label + wheel + spacing
    if (self.hasColorTemp) h += 58; // label + gradient slider + spacing
    if (self.hasEffects) h += 48; // button
    if (self.areaScenes.count > 0) h += 64; // label + chips row
    return h;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    BOOL isOn = entity.isOn;

    [self.toggleButton setTitle:isOn ? @"Turn Off" : @"Turn On" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:isOn ? [UIColor whiteColor] : [HATheme primaryTextColor] forState:UIControlStateNormal];
    self.toggleButton.backgroundColor = isOn ? [HATheme onTintColor] : [HATheme buttonBackgroundColor];

    NSInteger pct = [entity brightnessPercent];
    self.brightnessSlider.value = pct;
    self.brightnessSlider.enabled = isOn;
    self.brightnessLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];

    // Color temperature
    if (self.colorTempSlider) {
        NSNumber *kelvinNum = [entity colorTempKelvin];
        NSInteger kelvin = kelvinNum ? kelvinNum.integerValue : 0;
        if (kelvin > 0) self.colorTempSlider.value = kelvin;
        self.colorTempSlider.enabled = isOn;
        self.colorTempLabel.text = kelvin > 0 ? [NSString stringWithFormat:@"%ldK", (long)kelvin] : @"—";
    }

    // Effect
    if (self.effectButton) {
        NSString *effect = [entity effect];
        NSString *title = (effect.length > 0) ? effect : @"None";
        [self.effectButton setTitle:[NSString stringWithFormat:@"Effect: %@  \u25BE", title] forState:UIControlStateNormal];
        self.effectButton.enabled = isOn;
    }

    // Color wheel
    if (self.colorWheel) {
        NSArray *hsColor = [entity hsColor];
        if (hsColor.count >= 2) {
            CGFloat hue = [hsColor[0] doubleValue];
            CGFloat sat = [hsColor[1] doubleValue];
            [self.colorWheel setHue:hue saturation:sat animated:NO];
            self.colorLabel.text = [NSString stringWithFormat:@"H: %.0f\u00B0  S: %.0f%%", hue, sat];
        }
        self.colorWheel.userInteractionEnabled = isOn;
        self.colorWheel.alpha = isOn ? 1.0 : 0.5;
    }

    // Gradient frame update
    if (self.tempGradient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.tempGradient.frame = self.tempTrackContainer.bounds;
        });
    }
}

- (void)toggleTapped {
    HAEntity *entity = self.entity;
    if (!entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSString *service = entity.isOn ? @"turn_off" : @"turn_on";
    self.serviceBlock(service, [entity domain], nil, entity.entityId);
}

- (void)sliderChanged:(UISlider *)sender {
    self.brightnessLabel.text = [NSString stringWithFormat:@"%ld%%", (long)(NSInteger)sender.value];
}

- (void)sliderReleased:(UISlider *)sender {
    HAEntity *entity = self.entity;
    if (!entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSInteger brightness = (NSInteger)round((sender.value / 100.0) * 255.0);
    self.serviceBlock(@"turn_on", [entity domain], @{HAAttrBrightness: @(brightness)}, entity.entityId);
}

- (void)colorTempChanged:(UISlider *)sender {
    self.colorTempLabel.text = [NSString stringWithFormat:@"%ldK", (long)(NSInteger)sender.value];
}

- (void)colorTempReleased:(UISlider *)sender {
    HAEntity *entity = self.entity;
    if (!entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSInteger kelvin = (NSInteger)sender.value;
    self.serviceBlock(@"turn_on", [entity domain], @{HAAttrColorTempKelvin: @(kelvin)}, entity.entityId);
}

- (void)effectTapped {
    HAEntity *entity = self.entity;
    if (!entity || !self.serviceBlock) return;
    NSArray *effects = [entity effectList];
    if (effects.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Effect"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *effect in effects) {
        NSString *entityId = entity.entityId;
        NSString *domain = [entity domain];
        [alert addAction:[UIAlertAction actionWithTitle:effect style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            self.serviceBlock(@"turn_on", domain, @{@"effect": effect}, entityId);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self.containerRef ha_parentViewController];
    if (vc) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.effectButton;
            alert.popoverPresentationController.sourceRect = self.effectButton.bounds;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - HAColorWheelViewDelegate

- (void)colorWheelView:(HAColorWheelView *)view didChangeHue:(CGFloat)hue saturation:(CGFloat)saturation {
    self.colorLabel.text = [NSString stringWithFormat:@"H: %.0f\u00B0  S: %.0f%%", hue, saturation];
}

- (void)colorWheelViewDidFinishChanging:(HAColorWheelView *)view hue:(CGFloat)hue saturation:(CGFloat)saturation {
    HAEntity *entity = self.entity;
    if (!entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"turn_on", [entity domain],
                      @{@"hs_color": @[@(hue), @(saturation)]},
                      entity.entityId);
}

#pragma mark - Scene Discovery

- (void)discoverAreaScenes:(HAEntity *)entity {
    HAConnectionManager *mgr = [HAConnectionManager sharedManager];
    NSString *areaId = [mgr areaIdForEntityId:entity.entityId];
    if (!areaId) {
        self.areaScenes = @[];
        return;
    }

    NSMutableArray<HAEntity *> *scenes = [NSMutableArray array];
    NSDictionary<NSString *, HAEntity *> *allEntities = [mgr allEntities];

    for (NSString *eid in allEntities) {
        HAEntity *e = allEntities[eid];
        if (![[e domain] isEqualToString:@"scene"]) continue;
        NSString *sceneAreaId = [mgr areaIdForEntityId:eid];
        if ([sceneAreaId isEqualToString:areaId]) {
            [scenes addObject:e];
        }
    }

    [scenes sortUsingComparator:^NSComparisonResult(HAEntity *a, HAEntity *b) {
        NSString *nameA = [a friendlyName] ?: a.entityId;
        NSString *nameB = [b friendlyName] ?: b.entityId;
        return [nameA localizedCaseInsensitiveCompare:nameB];
    }];

    self.areaScenes = scenes;
}

#pragma mark - Scene Chips

- (void)layoutSceneChips {
    for (UIView *v in self.sceneScrollView.subviews) [v removeFromSuperview];

    CGFloat x = 0;
    CGFloat chipHeight = 32;
    CGFloat chipSpacing = 8;

    for (NSUInteger i = 0; i < self.areaScenes.count; i++) {
        HAEntity *scene = self.areaScenes[i];
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];

        NSString *name = [scene friendlyName] ?: scene.entityId;
        [chip setTitle:name forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [chip setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
        chip.backgroundColor = [HATheme buttonBackgroundColor];
        chip.layer.cornerRadius = chipHeight / 2.0;
        chip.clipsToBounds = YES;
        chip.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        chip.tag = i;
        [chip addTarget:self action:@selector(sceneChipTapped:) forControlEvents:UIControlEventTouchUpInside];

        [chip sizeToFit];
        CGFloat chipWidth = MAX(chip.frame.size.width, 60);
        chip.frame = CGRectMake(x, 2, chipWidth, chipHeight);

        [self.sceneScrollView addSubview:chip];
        x += chipWidth + chipSpacing;
    }

    self.sceneScrollView.contentSize = CGSizeMake(x, chipHeight + 4);
}

- (void)sceneChipTapped:(UIButton *)sender {
    NSUInteger idx = sender.tag;
    if (idx >= self.areaScenes.count || !self.serviceBlock) return;

    HAEntity *scene = self.areaScenes[idx];
    [HAHaptics lightImpact];
    self.serviceBlock(@"turn_on", @"scene", nil, scene.entityId);

    // Brief visual feedback
    UIColor *original = sender.backgroundColor;
    sender.backgroundColor = [HATheme onTintColor];
    [sender setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        sender.backgroundColor = original;
        [sender setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
    });
}

#pragma mark - Helpers

- (UIImage *)onePixelImageWithColor:(UIColor *)color {
    CGRect rect = CGRectMake(0, 0, 1, 1);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    [color setFill];
    UIRectFill(rect);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end

#pragma mark - Climate Detail Section

@interface HAClimateDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIStepper *tempStepper;
@property (nonatomic, strong) UILabel *targetLabel;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *fanModeLabel;
@property (nonatomic, strong) UISegmentedControl *fanModeControl;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HAClimateDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    // Target temperature stepper + label
    self.targetLabel = [[UILabel alloc] init];
    self.targetLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    self.targetLabel.textColor = [HATheme primaryTextColor];
    self.targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.targetLabel];

    self.tempStepper = [[UIStepper alloc] init];
    self.tempStepper.minimumValue = entity.minTemperature ? entity.minTemperature.doubleValue : 7;
    self.tempStepper.maximumValue = entity.maxTemperature ? entity.maxTemperature.doubleValue : 35;
    self.tempStepper.stepValue = 0.5;
    self.tempStepper.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tempStepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.tempStepper];

    // HVAC mode segment — dynamically built from entity's hvac_modes attribute
    NSArray *rawModes = [entity hvacModes];
    NSMutableArray *displayModes = [NSMutableArray array];
    if (rawModes.count > 0) {
        for (NSString *mode in rawModes) {
            [displayModes addObject:[mode capitalizedString]];
        }
    } else {
        [displayModes addObjectsFromArray:@[@"Off", @"Heat", @"Cool", @"Auto"]];
    }
    self.modeControl = [[UISegmentedControl alloc] initWithItems:displayModes];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.modeControl];

    // Anchor for bottom constraint — either mode control or fan mode control
    UIView *bottomView = self.modeControl;

    // Fan mode — only shown when entity supports fan_modes
    NSArray *fanModes = [entity climateFanModes];
    if (fanModes.count > 0) {
        self.fanModeLabel = [[UILabel alloc] init];
        self.fanModeLabel.text = @"Fan";
        self.fanModeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        self.fanModeLabel.textColor = [HATheme secondaryTextColor];
        self.fanModeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.fanModeLabel];

        NSMutableArray *displayFanModes = [NSMutableArray array];
        for (NSString *fm in fanModes) {
            [displayFanModes addObject:[fm capitalizedString]];
        }
        self.fanModeControl = [[UISegmentedControl alloc] initWithItems:displayFanModes];
        self.fanModeControl.translatesAutoresizingMaskIntoConstraints = NO;
        [self.fanModeControl addTarget:self action:@selector(fanModeChanged:) forControlEvents:UIControlEventValueChanged];
        [container addSubview:self.fanModeControl];

        [NSLayoutConstraint activateConstraints:@[
            [self.fanModeLabel.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:12],
            [self.fanModeLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

            [self.fanModeControl.topAnchor constraintEqualToAnchor:self.fanModeLabel.bottomAnchor constant:4],
            [self.fanModeControl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.fanModeControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        ]];
        bottomView = self.fanModeControl;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.targetLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.targetLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

        [self.tempStepper.centerYAnchor constraintEqualToAnchor:self.targetLabel.centerYAnchor],
        [self.tempStepper.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [self.modeControl.topAnchor constraintEqualToAnchor:self.targetLabel.bottomAnchor constant:12],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [bottomView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight {
    BOOL hasFanModes = self.fanModeControl != nil;
    return hasFanModes ? 130 : 80;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    NSNumber *target = [entity targetTemperature];
    if (target) {
        self.tempStepper.value = target.doubleValue;
        self.targetLabel.text = [NSString stringWithFormat:@"Target: %.1f\u00B0", target.doubleValue];
    } else {
        self.targetLabel.text = @"Target: —";
    }

    NSString *mode = [entity hvacMode] ?: entity.state;
    NSArray *rawModes = [entity hvacModes];
    if (rawModes) {
        NSUInteger idx = [rawModes indexOfObject:mode];
        self.modeControl.selectedSegmentIndex = (idx != NSNotFound) ? (NSInteger)idx : -1;
    } else {
        NSArray *fallback = @[@"off", @"heat", @"cool", @"auto"];
        NSUInteger idx = [fallback indexOfObject:mode];
        self.modeControl.selectedSegmentIndex = (idx != NSNotFound) ? (NSInteger)idx : -1;
    }

    BOOL hasTarget = target != nil && ![mode isEqualToString:@"off"];
    self.tempStepper.enabled = hasTarget;

    // Fan mode
    if (self.fanModeControl) {
        NSString *currentFanMode = [entity climateFanMode];
        NSArray *fanModes = [entity climateFanModes];
        if (fanModes && currentFanMode) {
            NSUInteger idx = [fanModes indexOfObject:currentFanMode];
            self.fanModeControl.selectedSegmentIndex = (idx != NSNotFound) ? (NSInteger)idx : -1;
        } else {
            self.fanModeControl.selectedSegmentIndex = -1;
        }
    }
}

- (void)stepperChanged:(UIStepper *)sender {
    self.targetLabel.text = [NSString stringWithFormat:@"Target: %.1f\u00B0", sender.value];
    if (!self.entity || !self.serviceBlock) return;
    self.serviceBlock(@"set_temperature", @"climate", @{@"temperature": @(sender.value)}, self.entity.entityId);
}

- (void)modeChanged:(UISegmentedControl *)sender {
    if (!self.entity || !self.serviceBlock) return;
    NSArray *rawModes = [self.entity hvacModes];
    if (!rawModes) {
        rawModes = @[@"off", @"heat", @"cool", @"auto"];
    }
    if (sender.selectedSegmentIndex >= 0 && sender.selectedSegmentIndex < (NSInteger)rawModes.count) {
        NSString *mode = rawModes[sender.selectedSegmentIndex];
        [HAHaptics lightImpact];
        self.serviceBlock(@"set_hvac_mode", @"climate", @{@"hvac_mode": mode}, self.entity.entityId);
    }
}

- (void)fanModeChanged:(UISegmentedControl *)sender {
    if (!self.entity || !self.serviceBlock) return;
    NSArray *fanModes = [self.entity climateFanModes];
    if (!fanModes) return;
    if (sender.selectedSegmentIndex >= 0 && sender.selectedSegmentIndex < (NSInteger)fanModes.count) {
        NSString *fanMode = fanModes[sender.selectedSegmentIndex];
        [HAHaptics lightImpact];
        self.serviceBlock(@"set_fan_mode", @"climate", @{@"fan_mode": fanMode}, self.entity.entityId);
    }
}

@end

#pragma mark - Cover Detail Section

@interface HACoverDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UISlider *positionSlider;
@property (nonatomic, strong) UILabel *positionLabel;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UISlider *tiltSlider;
@property (nonatomic, strong) UILabel *tiltLabel;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, assign) BOOL supportsPosition;
@property (nonatomic, assign) BOOL supportsTilt;
@end

@implementation HACoverDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    // Check supported features for SET_POSITION (bit 2 = 4) and TILT (bit 7 = 128)
    NSInteger features = [entity supportedFeatures];
    self.supportsPosition = (features & 4) != 0;
    self.supportsTilt = (features & 128) != 0;

    UIView *prevAnchor = nil;

    if (self.supportsPosition) {
        self.positionLabel = [[UILabel alloc] init];
        self.positionLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        self.positionLabel.textColor = [HATheme secondaryTextColor];
        self.positionLabel.textAlignment = NSTextAlignmentRight;
        self.positionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.positionLabel];

        self.positionSlider = [[UISlider alloc] init];
        self.positionSlider.minimumValue = 0;
        self.positionSlider.maximumValue = 100;
        self.positionSlider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
        [self.positionSlider addTarget:self action:@selector(positionReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [container addSubview:self.positionSlider];

        [NSLayoutConstraint activateConstraints:@[
            [self.positionSlider.topAnchor constraintEqualToAnchor:container.topAnchor],
            [self.positionSlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.positionSlider.trailingAnchor constraintEqualToAnchor:self.positionLabel.leadingAnchor constant:-8],

            [self.positionLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.positionLabel.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor],
            [self.positionLabel.widthAnchor constraintEqualToConstant:44],
        ]];
        prevAnchor = self.positionSlider;
    } else {
        // Open / Stop / Close buttons
        UIStackView *buttonStack = [[UIStackView alloc] init];
        buttonStack.axis = UILayoutConstraintAxisHorizontal;
        buttonStack.spacing = 12;
        buttonStack.distribution = UIStackViewDistributionFillEqually;
        buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:buttonStack];

        self.openButton = [self makeButton:@"Open" action:@selector(openTapped)];
        self.stopButton = [self makeButton:@"Stop" action:@selector(stopTapped)];
        self.closeButton = [self makeButton:@"Close" action:@selector(closeTapped)];

        [buttonStack addArrangedSubview:self.openButton];
        [buttonStack addArrangedSubview:self.stopButton];
        [buttonStack addArrangedSubview:self.closeButton];

        [NSLayoutConstraint activateConstraints:@[
            [buttonStack.topAnchor constraintEqualToAnchor:container.topAnchor],
            [buttonStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [buttonStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [buttonStack.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = buttonStack;
    }

    // Tilt position slider (when TILT feature bit is set)
    if (self.supportsTilt) {
        UILabel *tiltTitle = [[UILabel alloc] init];
        tiltTitle.text = @"Tilt";
        tiltTitle.font = [UIFont systemFontOfSize:13];
        tiltTitle.textColor = [HATheme secondaryTextColor];
        tiltTitle.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:tiltTitle];

        self.tiltLabel = [[UILabel alloc] init];
        self.tiltLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        self.tiltLabel.textColor = [HATheme secondaryTextColor];
        self.tiltLabel.textAlignment = NSTextAlignmentRight;
        self.tiltLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.tiltLabel];

        self.tiltSlider = [[UISlider alloc] init];
        self.tiltSlider.minimumValue = 0;
        self.tiltSlider.maximumValue = 100;
        self.tiltSlider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.tiltSlider addTarget:self action:@selector(tiltChanged:) forControlEvents:UIControlEventValueChanged];
        [self.tiltSlider addTarget:self action:@selector(tiltReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [container addSubview:self.tiltSlider];

        [NSLayoutConstraint activateConstraints:@[
            [tiltTitle.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [tiltTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

            [self.tiltSlider.topAnchor constraintEqualToAnchor:tiltTitle.bottomAnchor constant:4],
            [self.tiltSlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.tiltSlider.trailingAnchor constraintEqualToAnchor:self.tiltLabel.leadingAnchor constant:-8],

            [self.tiltLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.tiltLabel.centerYAnchor constraintEqualToAnchor:self.tiltSlider.centerYAnchor],
            [self.tiltLabel.widthAnchor constraintEqualToConstant:44],
        ]];
        prevAnchor = self.tiltSlider;
    }

    [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;

    [self updateWithEntity:entity];
    return container;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.clipsToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (CGFloat)preferredHeight {
    CGFloat h = 44; // base (position slider or buttons)
    if (self.supportsTilt) h += 50; // tilt label + slider
    return h;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    if (self.supportsPosition) {
        NSInteger pos = [entity coverPosition];
        self.positionSlider.value = pos;
        self.positionLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pos];
    }
    if (self.tiltSlider) {
        NSInteger tilt = [entity coverTiltPosition];
        self.tiltSlider.value = tilt;
        self.tiltLabel.text = [NSString stringWithFormat:@"%ld%%", (long)tilt];
    }
}

- (void)positionChanged:(UISlider *)sender {
    self.positionLabel.text = [NSString stringWithFormat:@"%ld%%", (long)(NSInteger)sender.value];
}

- (void)positionReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"set_cover_position", @"cover", @{@"position": @((NSInteger)sender.value)}, self.entity.entityId);
}

- (void)tiltChanged:(UISlider *)sender {
    self.tiltLabel.text = [NSString stringWithFormat:@"%ld%%", (long)(NSInteger)sender.value];
}

- (void)tiltReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"set_cover_tilt_position", @"cover", @{@"tilt_position": @((NSInteger)sender.value)}, self.entity.entityId);
}

- (void)openTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"open_cover", @"cover", nil, self.entity.entityId);
}

- (void)stopTapped {
    if (!self.entity || !self.serviceBlock) return;
    self.serviceBlock(@"stop_cover", @"cover", nil, self.entity.entityId);
}

- (void)closeTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"close_cover", @"cover", nil, self.entity.entityId);
}

@end

#pragma mark - Toggle Detail Section

@interface HAToggleDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HAToggleDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.toggleSwitch = [[HASwitch alloc] init];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.toggleSwitch];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Toggle";
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = [HATheme primaryTextColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],

        [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [self.toggleSwitch.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.toggleSwitch.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight { return 40; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    self.toggleSwitch.on = entity.isOn;
    self.toggleSwitch.enabled = entity.isAvailable;
}

- (void)switchChanged:(UISwitch *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSString *service = sender.isOn ? @"turn_on" : @"turn_off";
    self.serviceBlock(service, [self.entity domain], nil, self.entity.entityId);
}

@end

#pragma mark - Sensor Detail Section

@interface HASensorDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HASensorDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:36 weight:UIFontWeightBold];
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.valueLabel.textAlignment = NSTextAlignmentCenter;
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.valueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.valueLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [self.valueLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.valueLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.valueLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight { return 60; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    // binary_sensor: use device-class-aware state labels
    if ([[entity domain] isEqualToString:@"binary_sensor"]) {
        NSString *deviceClass = [entity deviceClass];
        self.valueLabel.text = [HAEntityDisplayHelper binarySensorStateForDeviceClass:deviceClass isOn:entity.isOn];
        return;
    }

    NSString *unit = [entity unitOfMeasurement];
    NSString *state = entity.state ?: @"—";
    if (unit.length > 0) {
        self.valueLabel.text = [NSString stringWithFormat:@"%@ %@", state, unit];
    } else {
        self.valueLabel.text = state;
    }
}

@end

#pragma mark - Media Player Detail Section

@interface HAMediaPlayerDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UILabel *mediaInfoLabel;
@property (nonatomic, strong) UILabel *sourceLabel;
@property (nonatomic, strong) UISlider *seekSlider;
@property (nonatomic, strong) UILabel *positionTimeLabel;
@property (nonatomic, strong) UILabel *durationTimeLabel;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic, strong) UIButton *sourceButton;
@property (nonatomic, strong) UIButton *powerButton;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, weak) UIView *containerRef;
@end

@implementation HAMediaPlayerDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];
    self.containerRef = container;

    NSInteger features = [entity supportedFeatures];
    UIView *prevAnchor = nil;

    // Media info: title + source
    self.mediaInfoLabel = [[UILabel alloc] init];
    self.mediaInfoLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.mediaInfoLabel.textColor = [HATheme primaryTextColor];
    self.mediaInfoLabel.textAlignment = NSTextAlignmentCenter;
    self.mediaInfoLabel.numberOfLines = 2;
    self.mediaInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.mediaInfoLabel];

    self.sourceLabel = [[UILabel alloc] init];
    self.sourceLabel.font = [UIFont systemFontOfSize:13];
    self.sourceLabel.textColor = [HATheme secondaryTextColor];
    self.sourceLabel.textAlignment = NSTextAlignmentCenter;
    self.sourceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.sourceLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.mediaInfoLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.mediaInfoLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.mediaInfoLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.sourceLabel.topAnchor constraintEqualToAnchor:self.mediaInfoLabel.bottomAnchor constant:2],
        [self.sourceLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.sourceLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];
    prevAnchor = self.sourceLabel;

    // Seek slider (if SEEK supported, bit 1 = 2)
    if (features & 2) {
        self.positionTimeLabel = [[UILabel alloc] init];
        self.positionTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.positionTimeLabel.textColor = [HATheme secondaryTextColor];
        self.positionTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.positionTimeLabel];

        self.durationTimeLabel = [[UILabel alloc] init];
        self.durationTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.durationTimeLabel.textColor = [HATheme secondaryTextColor];
        self.durationTimeLabel.textAlignment = NSTextAlignmentRight;
        self.durationTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.durationTimeLabel];

        self.seekSlider = [[UISlider alloc] init];
        self.seekSlider.minimumValue = 0;
        self.seekSlider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.seekSlider addTarget:self action:@selector(seekReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [container addSubview:self.seekSlider];

        [NSLayoutConstraint activateConstraints:@[
            [self.seekSlider.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:10],
            [self.seekSlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.seekSlider.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.positionTimeLabel.topAnchor constraintEqualToAnchor:self.seekSlider.bottomAnchor constant:2],
            [self.positionTimeLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.durationTimeLabel.topAnchor constraintEqualToAnchor:self.seekSlider.bottomAnchor constant:2],
            [self.durationTimeLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        ]];
        prevAnchor = self.positionTimeLabel;
    }

    // Transport buttons: prev | play/pause | next
    UIStackView *transportStack = [[UIStackView alloc] init];
    transportStack.axis = UILayoutConstraintAxisHorizontal;
    transportStack.spacing = 24;
    transportStack.alignment = UIStackViewAlignmentCenter;
    transportStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:transportStack];

    if (features & 16) {
        self.prevButton = [self makeTransportButton:@"\u23EE" size:22 action:@selector(prevTapped)];
        [transportStack addArrangedSubview:self.prevButton];
    }

    self.playPauseButton = [self makeTransportButton:@"\u23EF" size:36 action:@selector(playPauseTapped)];
    [transportStack addArrangedSubview:self.playPauseButton];

    if (features & 32) {
        self.nextButton = [self makeTransportButton:@"\u23ED" size:22 action:@selector(nextTapped)];
        [transportStack addArrangedSubview:self.nextButton];
    }

    [NSLayoutConstraint activateConstraints:@[
        [transportStack.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:10],
        [transportStack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
    ]];
    prevAnchor = transportStack;

    // Volume row: mute button + slider
    UIStackView *volumeRow = [[UIStackView alloc] init];
    volumeRow.axis = UILayoutConstraintAxisHorizontal;
    volumeRow.spacing = 8;
    volumeRow.alignment = UIStackViewAlignmentCenter;
    volumeRow.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:volumeRow];

    if (features & 8) { // VOLUME_MUTE
        self.muteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.muteButton.titleLabel.font = [UIFont systemFontOfSize:18];
        [self.muteButton addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.muteButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [volumeRow addArrangedSubview:self.muteButton];
    }

    if (features & 4) { // VOLUME_SET
        self.volumeSlider = [[UISlider alloc] init];
        self.volumeSlider.minimumValue = 0;
        self.volumeSlider.maximumValue = 100;
        [self.volumeSlider addTarget:self action:@selector(volumeReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [volumeRow addArrangedSubview:self.volumeSlider];
    }

    [NSLayoutConstraint activateConstraints:@[
        [volumeRow.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
        [volumeRow.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [volumeRow.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];
    prevAnchor = volumeRow;

    // Bottom row: source selector + power
    UIStackView *bottomRow = [[UIStackView alloc] init];
    bottomRow.axis = UILayoutConstraintAxisHorizontal;
    bottomRow.spacing = 12;
    bottomRow.distribution = UIStackViewDistributionFillEqually;
    bottomRow.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:bottomRow];

    NSArray *soundModes = [entity mediaSoundModes];
    if (soundModes.count > 0 && (features & 65536)) {
        self.sourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.sourceButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        self.sourceButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.sourceButton.layer.cornerRadius = 8;
        self.sourceButton.clipsToBounds = YES;
        [self.sourceButton addTarget:self action:@selector(soundModeTapped) forControlEvents:UIControlEventTouchUpInside];
        [bottomRow addArrangedSubview:self.sourceButton];
    }

    if ((features & 128) || (features & 256)) { // TURN_ON or TURN_OFF
        self.powerButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.powerButton setTitle:@"\u23FB" forState:UIControlStateNormal]; // power symbol
        self.powerButton.titleLabel.font = [UIFont systemFontOfSize:20];
        self.powerButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.powerButton.layer.cornerRadius = 8;
        self.powerButton.clipsToBounds = YES;
        [self.powerButton addTarget:self action:@selector(powerTapped) forControlEvents:UIControlEventTouchUpInside];
        [bottomRow addArrangedSubview:self.powerButton];
    }

    if (bottomRow.arrangedSubviews.count > 0) {
        [NSLayoutConstraint activateConstraints:@[
            [bottomRow.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [bottomRow.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [bottomRow.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [bottomRow.heightAnchor constraintEqualToConstant:36],
            [bottomRow.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        ]];
    } else {
        [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;
    }

    [self updateWithEntity:entity];
    return container;
}

- (UIButton *)makeTransportButton:(NSString *)symbol size:(CGFloat)size action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:symbol forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:size];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (CGFloat)preferredHeight {
    NSInteger features = [self.entity supportedFeatures];
    CGFloat height = 50; // media info + source label
    if (features & 2) height += 50; // seek slider + time labels
    height += 50; // transport buttons
    height += 36; // volume row
    NSArray *soundModes = [self.entity mediaSoundModes];
    BOOL hasBottom = ((features & 128) || (features & 256) ||
                      (soundModes.count > 0 && (features & 65536)));
    if (hasBottom) height += 48; // bottom row
    return height;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    NSString *title = [entity mediaTitle];
    NSString *artist = [entity mediaArtist];
    if (title.length > 0 && artist.length > 0) {
        self.mediaInfoLabel.text = [NSString stringWithFormat:@"%@ \u2014 %@", title, artist];
    } else if (title.length > 0) {
        self.mediaInfoLabel.text = title;
    } else {
        self.mediaInfoLabel.text = entity.state;
    }

    self.sourceLabel.text = [entity mediaAppName];

    BOOL playing = [entity isPlaying];
    [self.playPauseButton setTitle:playing ? @"\u23F8" : @"\u25B6\uFE0F" forState:UIControlStateNormal];

    // Seek slider
    if (self.seekSlider) {
        NSNumber *duration = [entity mediaDuration];
        NSNumber *position = [entity mediaPosition];
        if (duration) self.seekSlider.maximumValue = duration.floatValue;
        if (position) self.seekSlider.value = position.floatValue;
        self.seekSlider.enabled = playing;
        self.positionTimeLabel.text = [self formatTime:position.integerValue];
        self.durationTimeLabel.text = [self formatTime:duration.integerValue];
    }

    // Volume
    NSNumber *vol = [entity volumeLevel];
    NSInteger pct = vol ? (NSInteger)(vol.doubleValue * 100.0) : 0;
    self.volumeSlider.value = pct;

    BOOL muted = [entity isVolumeMuted];
    [self.muteButton setTitle:muted ? @"\U0001F507" : @"\U0001F50A" forState:UIControlStateNormal];

    // Sound mode button
    NSString *soundMode = [entity mediaSoundMode];
    if (soundMode) [self.sourceButton setTitle:soundMode forState:UIControlStateNormal];

    BOOL available = entity.isAvailable && ![entity.state isEqualToString:@"off"];
    self.prevButton.enabled = available;
    self.playPauseButton.enabled = entity.isAvailable;
    self.nextButton.enabled = available;
    self.volumeSlider.enabled = available;
    self.muteButton.enabled = available;
}

- (NSString *)formatTime:(NSInteger)totalSeconds {
    if (totalSeconds <= 0) return @"0:00";
    NSInteger hours = totalSeconds / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;
    NSInteger seconds = totalSeconds % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

- (void)prevTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"media_previous_track", @"media_player", nil, self.entity.entityId);
}

- (void)playPauseTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"media_play_pause", @"media_player", nil, self.entity.entityId);
}

- (void)nextTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"media_next_track", @"media_player", nil, self.entity.entityId);
}

- (void)muteTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    BOOL muted = [self.entity isVolumeMuted];
    self.serviceBlock(@"volume_mute", @"media_player", @{@"is_volume_muted": @(!muted)}, self.entity.entityId);
}

- (void)volumeReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    double level = sender.value / 100.0;
    self.serviceBlock(@"volume_set", @"media_player", @{@"volume_level": @(level)}, self.entity.entityId);
}

- (void)seekReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"media_seek", @"media_player", @{@"seek_position": @((double)sender.value)}, self.entity.entityId);
}

- (void)soundModeTapped {
    if (!self.entity || !self.serviceBlock) return;
    NSArray *modes = [self.entity mediaSoundModes];
    if (modes.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sound Mode"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *mode in modes) {
        [alert addAction:[UIAlertAction actionWithTitle:mode style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            self.serviceBlock(@"select_sound_mode", @"media_player", @{@"sound_mode": mode}, self.entity.entityId);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self.containerRef ha_parentViewController];
    if (vc) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.sourceButton;
            alert.popoverPresentationController.sourceRect = self.sourceButton.bounds;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

- (void)powerTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    BOOL isOff = [self.entity.state isEqualToString:@"off"];
    self.serviceBlock(isOff ? @"turn_on" : @"turn_off", @"media_player", nil, self.entity.entityId);
}

@end

#pragma mark - Fan Detail Section

@interface HAFanDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UISwitch *oscillateSwitch;
@property (nonatomic, strong) UILabel *oscillateLabel;
@property (nonatomic, strong) UIButton *presetModeButton;
@property (nonatomic, strong) UIButton *forwardButton;
@property (nonatomic, strong) UIButton *reverseButton;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, weak) UIView *containerRef;
@property (nonatomic, assign) BOOL hasPresetModes;
@property (nonatomic, assign) BOOL hasDirection;
@end

@implementation HAFanDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];
    self.containerRef = container;

    NSArray *presetModes = [entity fanPresetModes];
    self.hasPresetModes = presetModes.count > 0;
    self.hasDirection = [entity fanDirection] != nil;

    UIView *prevAnchor = nil;

    // Toggle button
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.toggleButton.layer.cornerRadius = 8;
    self.toggleButton.clipsToBounds = YES;
    self.toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.toggleButton];

    // Speed slider + label
    self.speedLabel = [[UILabel alloc] init];
    self.speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.speedLabel.textColor = [HATheme secondaryTextColor];
    self.speedLabel.textAlignment = NSTextAlignmentRight;
    self.speedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.speedLabel];

    self.speedSlider = [[UISlider alloc] init];
    self.speedSlider.minimumValue = 0;
    self.speedSlider.maximumValue = 100;
    self.speedSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.speedSlider addTarget:self action:@selector(speedReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [container addSubview:self.speedSlider];

    // Oscillation switch
    self.oscillateLabel = [[UILabel alloc] init];
    self.oscillateLabel.text = @"Oscillation";
    self.oscillateLabel.font = [UIFont systemFontOfSize:14];
    self.oscillateLabel.textColor = [HATheme primaryTextColor];
    self.oscillateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.oscillateLabel];

    self.oscillateSwitch = [[HASwitch alloc] init];
    self.oscillateSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.oscillateSwitch addTarget:self action:@selector(oscillateChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.oscillateSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [self.toggleButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.toggleButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.toggleButton.heightAnchor constraintEqualToConstant:36],
        [self.toggleButton.widthAnchor constraintEqualToConstant:80],

        [self.speedSlider.topAnchor constraintEqualToAnchor:self.toggleButton.bottomAnchor constant:12],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.speedSlider.trailingAnchor constraintEqualToAnchor:self.speedLabel.leadingAnchor constant:-8],

        [self.speedLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.speedLabel.centerYAnchor constraintEqualToAnchor:self.speedSlider.centerYAnchor],
        [self.speedLabel.widthAnchor constraintEqualToConstant:44],

        [self.oscillateLabel.topAnchor constraintEqualToAnchor:self.speedSlider.bottomAnchor constant:12],
        [self.oscillateLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

        [self.oscillateSwitch.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.oscillateSwitch.centerYAnchor constraintEqualToAnchor:self.oscillateLabel.centerYAnchor],
    ]];
    prevAnchor = self.oscillateLabel;

    // Preset mode dropdown
    if (self.hasPresetModes) {
        self.presetModeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.presetModeButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.presetModeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.presetModeButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.presetModeButton.layer.cornerRadius = 8;
        self.presetModeButton.clipsToBounds = YES;
        self.presetModeButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        self.presetModeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.presetModeButton addTarget:self action:@selector(presetModeTapped) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:self.presetModeButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.presetModeButton.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [self.presetModeButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.presetModeButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.presetModeButton.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = self.presetModeButton;
    }

    // Direction buttons (forward/reverse)
    if (self.hasDirection) {
        UILabel *dirLabel = [[UILabel alloc] init];
        dirLabel.text = @"Direction";
        dirLabel.font = [UIFont systemFontOfSize:13];
        dirLabel.textColor = [HATheme secondaryTextColor];
        dirLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:dirLabel];

        UIStackView *dirStack = [[UIStackView alloc] init];
        dirStack.axis = UILayoutConstraintAxisHorizontal;
        dirStack.spacing = 12;
        dirStack.distribution = UIStackViewDistributionFillEqually;
        dirStack.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:dirStack];

        self.forwardButton = [self makeDirButton:@"Forward" action:@selector(forwardTapped)];
        self.reverseButton = [self makeDirButton:@"Reverse" action:@selector(reverseTapped)];
        [dirStack addArrangedSubview:self.forwardButton];
        [dirStack addArrangedSubview:self.reverseButton];

        [NSLayoutConstraint activateConstraints:@[
            [dirLabel.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [dirLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

            [dirStack.topAnchor constraintEqualToAnchor:dirLabel.bottomAnchor constant:6],
            [dirStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [dirStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [dirStack.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = dirStack;
    }

    [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;

    [self updateWithEntity:entity];
    return container;
}

- (UIButton *)makeDirButton:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.clipsToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (CGFloat)preferredHeight {
    CGFloat h = 110; // toggle + speed + oscillation
    if (self.hasPresetModes) h += 48;
    if (self.hasDirection) h += 60; // label + buttons
    return h;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    BOOL isOn = entity.isOn;

    [self.toggleButton setTitle:isOn ? @"Turn Off" : @"Turn On" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:isOn ? [UIColor whiteColor] : [HATheme primaryTextColor] forState:UIControlStateNormal];
    self.toggleButton.backgroundColor = isOn ? [HATheme onTintColor] : [HATheme buttonBackgroundColor];

    NSInteger pct = [entity fanSpeedPercent];
    self.speedSlider.value = pct;
    self.speedSlider.enabled = isOn;
    self.speedLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];

    BOOL oscillating = [entity fanOscillating];
    self.oscillateSwitch.on = oscillating;
    self.oscillateSwitch.enabled = isOn;

    // Preset mode
    if (self.presetModeButton) {
        NSString *current = [entity fanPresetMode];
        NSString *title = (current.length > 0) ? current : @"None";
        [self.presetModeButton setTitle:[NSString stringWithFormat:@"Preset: %@  \u25BE", title] forState:UIControlStateNormal];
        self.presetModeButton.enabled = isOn;
    }

    // Direction highlight
    if (self.forwardButton && self.reverseButton) {
        NSString *dir = [entity fanDirection];
        BOOL isFwd = [dir isEqualToString:@"forward"];
        BOOL isRev = [dir isEqualToString:@"reverse"];
        self.forwardButton.backgroundColor = isFwd ? [HATheme onTintColor] : [HATheme buttonBackgroundColor];
        [self.forwardButton setTitleColor:isFwd ? [UIColor whiteColor] : nil forState:UIControlStateNormal];
        self.reverseButton.backgroundColor = isRev ? [HATheme onTintColor] : [HATheme buttonBackgroundColor];
        [self.reverseButton setTitleColor:isRev ? [UIColor whiteColor] : nil forState:UIControlStateNormal];
        self.forwardButton.enabled = isOn;
        self.reverseButton.enabled = isOn;
    }
}

- (void)toggleTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSString *service = self.entity.isOn ? @"turn_off" : @"turn_on";
    self.serviceBlock(service, @"fan", nil, self.entity.entityId);
}

- (void)speedChanged:(UISlider *)sender {
    self.speedLabel.text = [NSString stringWithFormat:@"%ld%%", (long)(NSInteger)sender.value];
}

- (void)speedReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"set_percentage", @"fan", @{@"percentage": @((NSInteger)sender.value)}, self.entity.entityId);
}

- (void)oscillateChanged:(UISwitch *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"oscillate", @"fan", @{@"oscillating": @(sender.isOn)}, self.entity.entityId);
}

- (void)presetModeTapped {
    if (!self.entity || !self.serviceBlock) return;
    NSArray *modes = [self.entity fanPresetModes];
    if (modes.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Preset Mode"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *mode in modes) {
        [alert addAction:[UIAlertAction actionWithTitle:mode style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            self.serviceBlock(@"set_preset_mode", @"fan", @{@"preset_mode": mode}, self.entity.entityId);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self.containerRef ha_parentViewController];
    if (vc) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.presetModeButton;
            alert.popoverPresentationController.sourceRect = self.presetModeButton.bounds;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

- (void)forwardTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"set_direction", @"fan", @{@"direction": @"forward"}, self.entity.entityId);
}

- (void)reverseTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"set_direction", @"fan", @{@"direction": @"reverse"}, self.entity.entityId);
}

@end

#pragma mark - Lock Detail Section

@interface HALockDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *lockButton;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) NSTimer *confirmTimer;
@property (nonatomic, assign) BOOL awaitingOpenConfirm;
@property (nonatomic, assign) BOOL supportsOpen;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HALockDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    // Check supported features for OPEN (bit 0 = 1)
    NSInteger features = [entity supportedFeatures];
    self.supportsOpen = (features & 1) != 0;

    self.lockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.lockButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.lockButton.layer.cornerRadius = 8;
    self.lockButton.clipsToBounds = YES;
    self.lockButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.lockButton addTarget:self action:@selector(lockTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.lockButton];

    if (self.supportsOpen) {
        self.openButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.openButton setTitle:@"Open" forState:UIControlStateNormal];
        self.openButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.openButton.layer.cornerRadius = 8;
        self.openButton.clipsToBounds = YES;
        self.openButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.openButton setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
        self.openButton.backgroundColor = [HATheme buttonBackgroundColor];
        [self.openButton addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:self.openButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.lockButton.topAnchor constraintEqualToAnchor:container.topAnchor],
            [self.lockButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.lockButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.lockButton.heightAnchor constraintEqualToConstant:44],

            [self.openButton.topAnchor constraintEqualToAnchor:self.lockButton.bottomAnchor constant:8],
            [self.openButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.openButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.openButton.heightAnchor constraintEqualToConstant:44],
            [self.openButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [self.lockButton.topAnchor constraintEqualToAnchor:container.topAnchor],
            [self.lockButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.lockButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.lockButton.heightAnchor constraintEqualToConstant:44],
            [self.lockButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        ]];
    }

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight {
    return self.supportsOpen ? 96 : 44;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    BOOL locked = [entity isLocked];
    [self.lockButton setTitle:locked ? @"Unlock" : @"Lock" forState:UIControlStateNormal];
    [self.lockButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.lockButton.backgroundColor = locked ? [HATheme onTintColor] : [HATheme buttonBackgroundColor];
    if (!locked) {
        [self.lockButton setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
    }

    // Reset open button appearance if not in confirm state
    if (self.openButton && !self.awaitingOpenConfirm) {
        [self.openButton setTitle:@"Open" forState:UIControlStateNormal];
        [self.openButton setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
        self.openButton.backgroundColor = [HATheme buttonBackgroundColor];
    }
}

- (void)lockTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    BOOL locked = [self.entity isLocked];
    NSString *service = locked ? @"unlock" : @"lock";
    self.serviceBlock(service, @"lock", nil, self.entity.entityId);
}

- (void)openTapped {
    if (!self.entity || !self.serviceBlock) return;

    if (self.awaitingOpenConfirm) {
        // Second tap: execute open
        [self.confirmTimer invalidate];
        self.confirmTimer = nil;
        self.awaitingOpenConfirm = NO;

        [HAHaptics lightImpact];
        self.serviceBlock(@"open", @"lock", nil, self.entity.entityId);
        [self updateWithEntity:self.entity];
    } else {
        // First tap: enter confirmation state
        self.awaitingOpenConfirm = YES;
        [self.openButton setTitle:@"Confirm Open?" forState:UIControlStateNormal];
        self.openButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.2 alpha:1.0];
        [self.openButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        self.confirmTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                             target:self
                                                           selector:@selector(confirmTimeout)
                                                           userInfo:nil
                                                            repeats:NO];
    }
}

- (void)confirmTimeout {
    self.awaitingOpenConfirm = NO;
    self.confirmTimer = nil;
    [self updateWithEntity:self.entity];
}

- (void)dealloc {
    [self.confirmTimer invalidate];
}

@end

#pragma mark - Vacuum Detail Section

@interface HAVacuumDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *returnButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *locateButton;
@property (nonatomic, strong) UIButton *cleanSpotButton;
@property (nonatomic, strong) UIButton *fanSpeedButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, weak) UIView *containerRef;
@property (nonatomic, assign) BOOL hasExtras;
@property (nonatomic, assign) BOOL hasFanSpeed;
@end

@implementation HAVacuumDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];
    self.containerRef = container;

    NSInteger features = [entity supportedFeatures];
    BOOL hasStop = (features & 8) != 0;       // STOP bit 3
    BOOL hasLocate = (features & 512) != 0;    // LOCATE bit 9
    BOOL hasCleanSpot = (features & 1024) != 0; // CLEAN_SPOT bit 10
    self.hasExtras = hasStop || hasLocate || hasCleanSpot;
    NSArray *fanSpeeds = [entity vacuumFanSpeedList];
    self.hasFanSpeed = fanSpeeds.count > 0;

    // Status + battery row
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textColor = [HATheme secondaryTextColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.statusLabel];

    self.batteryLabel = [[UILabel alloc] init];
    self.batteryLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.batteryLabel.textColor = [HATheme secondaryTextColor];
    self.batteryLabel.textAlignment = NSTextAlignmentRight;
    self.batteryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.batteryLabel];

    // Primary action buttons: start / pause / return
    UIStackView *buttonStack = [[UIStackView alloc] init];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 12;
    buttonStack.distribution = UIStackViewDistributionFillEqually;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:buttonStack];

    self.startButton = [self makeButton:@"Start" action:@selector(startTapped)];
    self.pauseButton = [self makeButton:@"Pause" action:@selector(pauseTapped)];
    self.returnButton = [self makeButton:@"Return" action:@selector(returnTapped)];

    [buttonStack addArrangedSubview:self.startButton];
    [buttonStack addArrangedSubview:self.pauseButton];
    [buttonStack addArrangedSubview:self.returnButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

        [self.batteryLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.batteryLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [buttonStack.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:10],
        [buttonStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [buttonStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [buttonStack.heightAnchor constraintEqualToConstant:36],
    ]];
    UIView *prevAnchor = buttonStack;

    // Extra action buttons: stop / locate / clean spot (conditional)
    if (self.hasExtras) {
        UIStackView *extraStack = [[UIStackView alloc] init];
        extraStack.axis = UILayoutConstraintAxisHorizontal;
        extraStack.spacing = 12;
        extraStack.distribution = UIStackViewDistributionFillEqually;
        extraStack.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:extraStack];

        if (hasStop) {
            self.stopButton = [self makeButton:@"Stop" action:@selector(stopTapped)];
            [extraStack addArrangedSubview:self.stopButton];
        }
        if (hasLocate) {
            self.locateButton = [self makeButton:@"Locate" action:@selector(locateTapped)];
            [extraStack addArrangedSubview:self.locateButton];
        }
        if (hasCleanSpot) {
            self.cleanSpotButton = [self makeButton:@"Clean Spot" action:@selector(cleanSpotTapped)];
            [extraStack addArrangedSubview:self.cleanSpotButton];
        }

        [NSLayoutConstraint activateConstraints:@[
            [extraStack.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:8],
            [extraStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [extraStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [extraStack.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = extraStack;
    }

    // Fan speed dropdown
    if (self.hasFanSpeed) {
        self.fanSpeedButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.fanSpeedButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.fanSpeedButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.fanSpeedButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.fanSpeedButton.layer.cornerRadius = 8;
        self.fanSpeedButton.clipsToBounds = YES;
        self.fanSpeedButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        self.fanSpeedButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.fanSpeedButton addTarget:self action:@selector(fanSpeedTapped) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:self.fanSpeedButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.fanSpeedButton.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:8],
            [self.fanSpeedButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.fanSpeedButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.fanSpeedButton.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = self.fanSpeedButton;
    }

    [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;

    [self updateWithEntity:entity];
    return container;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.clipsToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (CGFloat)preferredHeight {
    CGFloat h = 66; // status row + primary buttons
    if (self.hasExtras) h += 44; // extra button row
    if (self.hasFanSpeed) h += 44; // fan speed dropdown
    return h;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    NSString *status = [entity vacuumStatus] ?: entity.state;
    self.statusLabel.text = status;

    NSNumber *battery = [entity vacuumBatteryLevel];
    if (battery) {
        self.batteryLabel.text = [NSString stringWithFormat:@"\U0001F50B %ld%%", (long)battery.integerValue];
    } else {
        self.batteryLabel.text = nil;
    }

    // Enable/disable based on supported_features
    NSInteger features = [entity supportedFeatures];
    self.startButton.enabled = (features & 1) != 0;  // START
    self.pauseButton.enabled = (features & 4) != 0;   // PAUSE
    self.returnButton.enabled = (features & 16) != 0;  // RETURN_HOME

    // Fan speed button label
    if (self.fanSpeedButton) {
        NSString *current = [entity vacuumFanSpeed];
        NSString *title = (current.length > 0) ? current : @"Default";
        [self.fanSpeedButton setTitle:[NSString stringWithFormat:@"Fan Speed: %@  \u25BE", title] forState:UIControlStateNormal];
    }
}

- (void)startTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"start", @"vacuum", nil, self.entity.entityId);
}

- (void)pauseTapped {
    if (!self.entity || !self.serviceBlock) return;
    self.serviceBlock(@"pause", @"vacuum", nil, self.entity.entityId);
}

- (void)returnTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"return_to_base", @"vacuum", nil, self.entity.entityId);
}

- (void)stopTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"stop", @"vacuum", nil, self.entity.entityId);
}

- (void)locateTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"locate", @"vacuum", nil, self.entity.entityId);
}

- (void)cleanSpotTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"clean_spot", @"vacuum", nil, self.entity.entityId);
}

- (void)fanSpeedTapped {
    if (!self.entity || !self.serviceBlock) return;
    NSArray *speeds = [self.entity vacuumFanSpeedList];
    if (speeds.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Fan Speed"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *speed in speeds) {
        [alert addAction:[UIAlertAction actionWithTitle:speed style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            self.serviceBlock(@"set_fan_speed", @"vacuum", @{@"fan_speed": speed}, self.entity.entityId);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self.containerRef ha_parentViewController];
    if (vc) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.fanSpeedButton;
            alert.popoverPresentationController.sourceRect = self.fanSpeedButton.bounds;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

@end

#pragma mark - Timer Detail Section

@interface HATimerDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UILabel *countdownLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) NSTimer *countdownTimer;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HATimerDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    // Countdown display
    self.countdownLabel = [[UILabel alloc] init];
    self.countdownLabel.font = [UIFont monospacedDigitSystemFontOfSize:32 weight:UIFontWeightBold];
    self.countdownLabel.textColor = [HATheme primaryTextColor];
    self.countdownLabel.textAlignment = NSTextAlignmentCenter;
    self.countdownLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.countdownLabel];

    // Action buttons
    UIStackView *buttonStack = [[UIStackView alloc] init];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 12;
    buttonStack.distribution = UIStackViewDistributionFillEqually;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:buttonStack];

    self.startButton = [self makeButton:@"Start" action:@selector(startTapped)];
    self.pauseButton = [self makeButton:@"Pause" action:@selector(pauseTapped)];
    self.cancelButton = [self makeButton:@"Cancel" action:@selector(cancelTapped)];

    [buttonStack addArrangedSubview:self.startButton];
    [buttonStack addArrangedSubview:self.pauseButton];
    [buttonStack addArrangedSubview:self.cancelButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.countdownLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [self.countdownLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.countdownLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [buttonStack.topAnchor constraintEqualToAnchor:self.countdownLabel.bottomAnchor constant:10],
        [buttonStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [buttonStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [buttonStack.heightAnchor constraintEqualToConstant:36],
        [buttonStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.clipsToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (CGFloat)preferredHeight { return 84; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    [self stopCountdownTimer];

    NSString *state = entity.state;
    BOOL isActive = [state isEqualToString:@"active"];
    BOOL isPaused = [state isEqualToString:@"paused"];
    BOOL isIdle = [state isEqualToString:@"idle"];

    // Button visibility based on state
    self.startButton.enabled = isIdle || isPaused;
    self.pauseButton.enabled = isActive;
    self.cancelButton.enabled = isActive || isPaused;

    if (isActive) {
        // Start live countdown from finishes_at
        [self startCountdownTimer];
    } else if (isPaused) {
        NSString *remaining = [entity timerRemaining];
        self.countdownLabel.text = remaining ?: @"--:--:--";
    } else {
        NSString *duration = [entity timerDuration];
        self.countdownLabel.text = duration ?: @"--:--:--";
    }
}

- (void)startCountdownTimer {
    [self updateCountdownDisplay];
    self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                           target:self
                                                         selector:@selector(updateCountdownDisplay)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)stopCountdownTimer {
    [self.countdownTimer invalidate];
    self.countdownTimer = nil;
}

- (void)updateCountdownDisplay {
    NSString *finishesAt = [self.entity timerFinishesAt];
    if (!finishesAt) {
        self.countdownLabel.text = @"--:--:--";
        return;
    }

    // Parse ISO 8601 datetime
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    NSDate *finishDate = [formatter dateFromString:finishesAt];

    if (!finishDate) {
        // Try alternate format without timezone colon
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
        finishDate = [formatter dateFromString:finishesAt];
    }

    if (!finishDate) {
        self.countdownLabel.text = @"--:--:--";
        return;
    }

    NSTimeInterval remaining = [finishDate timeIntervalSinceNow];
    if (remaining <= 0) {
        self.countdownLabel.text = @"0:00:00";
        [self stopCountdownTimer];
        return;
    }

    NSInteger hours = (NSInteger)(remaining / 3600);
    NSInteger minutes = ((NSInteger)remaining % 3600) / 60;
    NSInteger seconds = (NSInteger)remaining % 60;
    self.countdownLabel.text = [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
}

- (void)startTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"start", @"timer", nil, self.entity.entityId);
}

- (void)pauseTapped {
    if (!self.entity || !self.serviceBlock) return;
    self.serviceBlock(@"pause", @"timer", nil, self.entity.entityId);
}

- (void)cancelTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"cancel", @"timer", nil, self.entity.entityId);
}

- (void)dealloc {
    [self stopCountdownTimer];
}

@end

#pragma mark - Scene Detail Section

@interface HASceneDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *activateButton;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HASceneDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.activateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.activateButton setTitle:@"Activate" forState:UIControlStateNormal];
    self.activateButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.activateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.activateButton.backgroundColor = [HATheme onTintColor];
    self.activateButton.layer.cornerRadius = 8;
    self.activateButton.clipsToBounds = YES;
    self.activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activateButton addTarget:self action:@selector(activateTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.activateButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.activateButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.activateButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.activateButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.activateButton.heightAnchor constraintEqualToConstant:44],
        [self.activateButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    return container;
}

- (CGFloat)preferredHeight { return 44; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
}

- (void)activateTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"turn_on", @"scene", nil, self.entity.entityId);
}

@end

#pragma mark - Alarm Control Panel Detail Section

@interface HAAlarmDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIStackView *modesStack;
@property (nonatomic, strong) UIButton *disarmButton;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HAAlarmDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    NSInteger features = [entity supportedFeatures];
    BOOL codeRequired = [entity alarmCodeArmRequired];

    // Arm mode buttons — vertical stack matching HA's layout
    self.modesStack = [[UIStackView alloc] init];
    self.modesStack.axis = UILayoutConstraintAxisVertical;
    self.modesStack.spacing = 8;
    self.modesStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.modesStack];

    if (features & 1)  [self addModeButton:@"Arm Home"     service:@"alarm_arm_home"];
    if (features & 2)  [self addModeButton:@"Arm Away"     service:@"alarm_arm_away"];
    if (features & 4)  [self addModeButton:@"Arm Night"    service:@"alarm_arm_night"];
    if (features & 32) [self addModeButton:@"Arm Vacation" service:@"alarm_arm_vacation"];
    if (features & 16) [self addModeButton:@"Arm Custom"   service:@"alarm_arm_custom_bypass"];

    // Disarm button
    self.disarmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.disarmButton setTitle:@"Disarm" forState:UIControlStateNormal];
    self.disarmButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.disarmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.disarmButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0];
    self.disarmButton.layer.cornerRadius = 8;
    self.disarmButton.clipsToBounds = YES;
    self.disarmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.disarmButton addTarget:self action:@selector(disarmTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.modesStack addArrangedSubview:self.disarmButton];
    [self.disarmButton.heightAnchor constraintEqualToConstant:44].active = YES;

    // Code input field (if code required)
    if (codeRequired) {
        self.codeField = [[UITextField alloc] init];
        self.codeField.placeholder = @"Enter code";
        self.codeField.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
        self.codeField.textAlignment = NSTextAlignmentCenter;
        self.codeField.borderStyle = UITextBorderStyleRoundedRect;
        self.codeField.keyboardType = UIKeyboardTypeNumberPad;
        self.codeField.secureTextEntry = YES;
        self.codeField.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.codeField];

        [NSLayoutConstraint activateConstraints:@[
            [self.codeField.topAnchor constraintEqualToAnchor:container.topAnchor],
            [self.codeField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:40],
            [self.codeField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-40],
            [self.codeField.heightAnchor constraintEqualToConstant:44],
            [self.modesStack.topAnchor constraintEqualToAnchor:self.codeField.bottomAnchor constant:12],
        ]];
    } else {
        [self.modesStack.topAnchor constraintEqualToAnchor:container.topAnchor].active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.modesStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.modesStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.modesStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (void)addModeButton:(NSString *)title service:(NSString *)service {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.clipsToBounds = YES;
    btn.accessibilityIdentifier = service;
    [btn addTarget:self action:@selector(armModeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.modesStack addArrangedSubview:btn];
    [btn.heightAnchor constraintEqualToConstant:44].active = YES;
}

- (CGFloat)preferredHeight {
    NSInteger features = [self.entity supportedFeatures];
    BOOL codeRequired = [self.entity alarmCodeArmRequired];
    NSInteger count = 1; // disarm
    if (features & 1) count++;
    if (features & 2) count++;
    if (features & 4) count++;
    if (features & 16) count++;
    if (features & 32) count++;
    CGFloat height = count * 44 + (count - 1) * 8;
    if (codeRequired) height += 56;
    return height;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    BOOL isDisarmed = [entity.state isEqualToString:@"disarmed"];
    for (UIView *view in self.modesStack.arrangedSubviews) {
        if (view == self.disarmButton) {
            self.disarmButton.enabled = !isDisarmed;
            self.disarmButton.alpha = isDisarmed ? 0.4 : 1.0;
        } else if ([view isKindOfClass:[UIButton class]]) {
            ((UIButton *)view).enabled = isDisarmed;
            view.alpha = isDisarmed ? 1.0 : 0.4;
        }
    }
}

- (void)armModeTapped:(UIButton *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (self.codeField.text.length > 0) data[@"code"] = self.codeField.text;
    self.serviceBlock(sender.accessibilityIdentifier, @"alarm_control_panel", data.count > 0 ? data : nil, self.entity.entityId);
    self.codeField.text = @"";
}

- (void)disarmTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (self.codeField.text.length > 0) data[@"code"] = self.codeField.text;
    self.serviceBlock(@"alarm_disarm", @"alarm_control_panel", data.count > 0 ? data : nil, self.entity.entityId);
    self.codeField.text = @"";
}

@end

#pragma mark - Button Detail Section

@interface HAButtonDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *pressButton;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HAButtonDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.pressButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pressButton setTitle:@"Press" forState:UIControlStateNormal];
    self.pressButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.pressButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pressButton.backgroundColor = [HATheme onTintColor];
    self.pressButton.layer.cornerRadius = 8;
    self.pressButton.clipsToBounds = YES;
    self.pressButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pressButton addTarget:self action:@selector(pressTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.pressButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.pressButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.pressButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.pressButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.pressButton.heightAnchor constraintEqualToConstant:44],
        [self.pressButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    return container;
}

- (CGFloat)preferredHeight { return 44; }
- (void)updateWithEntity:(HAEntity *)entity { self.entity = entity; }

- (void)pressTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"press", [self.entity domain], nil, self.entity.entityId);
}

@end

#pragma mark - Counter Detail Section

@interface HACounterDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *decrementButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UIButton *incrementButton;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HACounterDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    UIStackView *buttonStack = [[UIStackView alloc] init];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 12;
    buttonStack.distribution = UIStackViewDistributionFillEqually;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:buttonStack];

    self.decrementButton = [self makeButton:@"−" action:@selector(decrementTapped)];
    self.resetButton = [self makeButton:@"Reset" action:@selector(resetTapped)];
    self.incrementButton = [self makeButton:@"+" action:@selector(incrementTapped)];

    [buttonStack addArrangedSubview:self.decrementButton];
    [buttonStack addArrangedSubview:self.resetButton];
    [buttonStack addArrangedSubview:self.incrementButton];

    [NSLayoutConstraint activateConstraints:@[
        [buttonStack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [buttonStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [buttonStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [buttonStack.heightAnchor constraintEqualToConstant:44],
        [buttonStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.clipsToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (CGFloat)preferredHeight { return 44; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    NSNumber *minimum = [entity counterMinimum];
    NSNumber *maximum = [entity counterMaximum];
    NSInteger value = [entity.state integerValue];
    self.decrementButton.enabled = !minimum || value > minimum.integerValue;
    self.incrementButton.enabled = !maximum || value < maximum.integerValue;
}

- (void)decrementTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"decrement", @"counter", nil, self.entity.entityId);
}

- (void)resetTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"reset", @"counter", nil, self.entity.entityId);
}

- (void)incrementTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"increment", @"counter", nil, self.entity.entityId);
}

@end

#pragma mark - Input Number Detail Section

@interface HAInputNumberDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HAInputNumberDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.valueLabel];

    self.slider = [[UISlider alloc] init];
    double minVal = [entity inputNumberMin];
    double maxVal = [entity inputNumberMax];
    self.slider.minimumValue = minVal;
    self.slider.maximumValue = maxVal > minVal ? maxVal : 100;
    self.slider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [container addSubview:self.slider];

    [NSLayoutConstraint activateConstraints:@[
        [self.slider.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.slider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.slider.trailingAnchor constraintEqualToAnchor:self.valueLabel.leadingAnchor constant:-8],
        [self.slider.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [self.valueLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.slider.centerYAnchor],
        [self.valueLabel.widthAnchor constraintEqualToConstant:60],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight { return 40; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    double value = [entity.state doubleValue];
    self.slider.value = value;
    double step = [entity inputNumberStep];
    if (step >= 1.0) {
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f", value];
    } else {
        self.valueLabel.text = [NSString stringWithFormat:@"%.1f", value];
    }
}

- (void)sliderChanged:(UISlider *)sender {
    double step = [self.entity inputNumberStep];
    if (step >= 1.0) {
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f", (double)sender.value];
    } else {
        self.valueLabel.text = [NSString stringWithFormat:@"%.1f", (double)sender.value];
    }
}

- (void)sliderReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    double step = [self.entity inputNumberStep];
    double value = sender.value;
    if (step > 0) {
        value = round(value / step) * step;
        sender.value = value;
    }
    self.serviceBlock(@"set_value", [self.entity domain], @{@"value": @(value)}, self.entity.entityId);
}

@end

#pragma mark - Input Select Detail Section

@interface HAInputSelectDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *selectorButton;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, weak) UIView *containerRef;
@end

@implementation HAInputSelectDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];
    self.containerRef = container;

    self.selectorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.selectorButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.selectorButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.selectorButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.selectorButton.layer.cornerRadius = 8;
    self.selectorButton.clipsToBounds = YES;
    self.selectorButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    self.selectorButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.selectorButton addTarget:self action:@selector(selectorTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.selectorButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.selectorButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.selectorButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.selectorButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.selectorButton.heightAnchor constraintEqualToConstant:44],
        [self.selectorButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight { return 44; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    NSString *current = entity.state ?: @"—";
    [self.selectorButton setTitle:[NSString stringWithFormat:@"%@  \u25BE", current] forState:UIControlStateNormal];
}

- (void)selectorTapped {
    if (!self.entity || !self.serviceBlock) return;

    NSArray *options = [self.entity inputSelectOptions];
    if (options.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *option in options) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:option
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            self.serviceBlock(@"select_option", [self.entity domain], @{@"option": option}, self.entity.entityId);
        }];
        [alert addAction:action];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self.containerRef ha_parentViewController];
    if (vc) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.selectorButton;
            alert.popoverPresentationController.sourceRect = self.selectorButton.bounds;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

@end

#pragma mark - Valve Detail Section

@interface HAValveDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UISlider *positionSlider;
@property (nonatomic, strong) UILabel *positionLabel;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, assign) BOOL supportsPosition;
@end

@implementation HAValveDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    NSInteger features = [entity supportedFeatures];
    self.supportsPosition = (features & 4) != 0; // SET_POSITION

    if (self.supportsPosition) {
        self.positionLabel = [[UILabel alloc] init];
        self.positionLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        self.positionLabel.textColor = [HATheme secondaryTextColor];
        self.positionLabel.textAlignment = NSTextAlignmentRight;
        self.positionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.positionLabel];

        self.positionSlider = [[UISlider alloc] init];
        self.positionSlider.minimumValue = 0;
        self.positionSlider.maximumValue = 100;
        self.positionSlider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
        [self.positionSlider addTarget:self action:@selector(positionReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [container addSubview:self.positionSlider];

        [NSLayoutConstraint activateConstraints:@[
            [self.positionSlider.topAnchor constraintEqualToAnchor:container.topAnchor],
            [self.positionSlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.positionSlider.trailingAnchor constraintEqualToAnchor:self.positionLabel.leadingAnchor constant:-8],
            [self.positionSlider.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

            [self.positionLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.positionLabel.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor],
            [self.positionLabel.widthAnchor constraintEqualToConstant:44],
        ]];
    } else {
        UIStackView *buttonStack = [[UIStackView alloc] init];
        buttonStack.axis = UILayoutConstraintAxisHorizontal;
        buttonStack.spacing = 12;
        buttonStack.distribution = UIStackViewDistributionFillEqually;
        buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:buttonStack];

        self.openButton = [self makeButton:@"Open" action:@selector(openTapped)];
        self.stopButton = [self makeButton:@"Stop" action:@selector(stopTapped)];
        self.closeButton = [self makeButton:@"Close" action:@selector(closeTapped)];

        [buttonStack addArrangedSubview:self.openButton];
        [buttonStack addArrangedSubview:self.stopButton];
        [buttonStack addArrangedSubview:self.closeButton];

        [NSLayoutConstraint activateConstraints:@[
            [buttonStack.topAnchor constraintEqualToAnchor:container.topAnchor],
            [buttonStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [buttonStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [buttonStack.heightAnchor constraintEqualToConstant:36],
            [buttonStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        ]];
    }

    [self updateWithEntity:entity];
    return container;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.clipsToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (CGFloat)preferredHeight { return 44; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    if (self.supportsPosition) {
        NSInteger pos = HAAttrInteger(entity.attributes, HAAttrCurrentPosition, 0);
        self.positionSlider.value = pos;
        self.positionLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pos];
    }
}

- (void)positionChanged:(UISlider *)sender {
    self.positionLabel.text = [NSString stringWithFormat:@"%ld%%", (long)(NSInteger)sender.value];
}

- (void)positionReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"set_valve_position", @"valve", @{@"position": @((NSInteger)sender.value)}, self.entity.entityId);
}

- (void)openTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"open_valve", @"valve", nil, self.entity.entityId);
}

- (void)stopTapped {
    if (!self.entity || !self.serviceBlock) return;
    self.serviceBlock(@"stop_valve", @"valve", nil, self.entity.entityId);
}

- (void)closeTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"close_valve", @"valve", nil, self.entity.entityId);
}

@end

#pragma mark - Siren Detail Section

@interface HASirenDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HASirenDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.toggleButton.layer.cornerRadius = 8;
    self.toggleButton.clipsToBounds = YES;
    self.toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.toggleButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.toggleButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.toggleButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.toggleButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.toggleButton.heightAnchor constraintEqualToConstant:44],
        [self.toggleButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight { return 44; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    BOOL isOn = entity.isOn;
    [self.toggleButton setTitle:isOn ? @"Turn Off" : @"Turn On" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:isOn ? [UIColor whiteColor] : [HATheme primaryTextColor] forState:UIControlStateNormal];
    self.toggleButton.backgroundColor = isOn ? [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0] : [HATheme buttonBackgroundColor];
}

- (void)toggleTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSString *service = self.entity.isOn ? @"turn_off" : @"turn_on";
    self.serviceBlock(service, @"siren", nil, self.entity.entityId);
}

@end

#pragma mark - Humidifier Detail Section

@interface HAHumidifierDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UISlider *humiditySlider;
@property (nonatomic, strong) UILabel *humidityLabel;
@property (nonatomic, strong) UIButton *modeButton;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, weak) UIView *containerRef;
@property (nonatomic, assign) BOOL hasModes;
@end

@implementation HAHumidifierDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];
    self.containerRef = container;

    NSArray *modes = [entity humidifierAvailableModes];
    self.hasModes = modes.count > 0;

    UIView *prevAnchor = nil;

    // Power toggle button
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.toggleButton.layer.cornerRadius = 8;
    self.toggleButton.clipsToBounds = YES;
    self.toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.toggleButton];

    // Humidity value label
    self.humidityLabel = [[UILabel alloc] init];
    self.humidityLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.humidityLabel.textColor = [HATheme secondaryTextColor];
    self.humidityLabel.textAlignment = NSTextAlignmentRight;
    self.humidityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.humidityLabel];

    // Target humidity slider
    self.humiditySlider = [[UISlider alloc] init];
    NSNumber *minH = [entity humidifierMinHumidity];
    NSNumber *maxH = [entity humidifierMaxHumidity];
    self.humiditySlider.minimumValue = minH ? minH.floatValue : 0;
    self.humiditySlider.maximumValue = (maxH && maxH.floatValue > self.humiditySlider.minimumValue) ? maxH.floatValue : 100;
    self.humiditySlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.humiditySlider addTarget:self action:@selector(humidityChanged:) forControlEvents:UIControlEventValueChanged];
    [self.humiditySlider addTarget:self action:@selector(humidityReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [container addSubview:self.humiditySlider];

    [NSLayoutConstraint activateConstraints:@[
        [self.toggleButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.toggleButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.toggleButton.heightAnchor constraintEqualToConstant:36],
        [self.toggleButton.widthAnchor constraintEqualToConstant:80],

        [self.humiditySlider.topAnchor constraintEqualToAnchor:self.toggleButton.bottomAnchor constant:12],
        [self.humiditySlider.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.humiditySlider.trailingAnchor constraintEqualToAnchor:self.humidityLabel.leadingAnchor constant:-8],

        [self.humidityLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.humidityLabel.centerYAnchor constraintEqualToAnchor:self.humiditySlider.centerYAnchor],
        [self.humidityLabel.widthAnchor constraintEqualToConstant:44],
    ]];
    prevAnchor = self.humiditySlider;

    // Mode dropdown button (when available_modes is non-empty)
    if (self.hasModes) {
        self.modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.modeButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.modeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.modeButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.modeButton.layer.cornerRadius = 8;
        self.modeButton.clipsToBounds = YES;
        self.modeButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        self.modeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.modeButton addTarget:self action:@selector(modeTapped) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:self.modeButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.modeButton.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [self.modeButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.modeButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.modeButton.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = self.modeButton;
    }

    [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight {
    CGFloat h = 120; // toggle + humidity slider
    if (self.hasModes) h += 48; // mode button
    return h;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    BOOL isOn = entity.isOn;

    [self.toggleButton setTitle:isOn ? @"Turn Off" : @"Turn On" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:isOn ? [UIColor whiteColor] : [HATheme primaryTextColor] forState:UIControlStateNormal];
    self.toggleButton.backgroundColor = isOn ? [HATheme onTintColor] : [HATheme buttonBackgroundColor];

    NSNumber *target = [entity humidifierTargetHumidity];
    NSInteger pct = target ? target.integerValue : 0;
    self.humiditySlider.value = pct;
    self.humiditySlider.enabled = isOn;
    self.humidityLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];

    if (self.modeButton) {
        NSString *current = [entity humidifierMode];
        NSString *title = (current.length > 0) ? current : @"None";
        [self.modeButton setTitle:[NSString stringWithFormat:@"Mode: %@  \u25BE", title] forState:UIControlStateNormal];
        self.modeButton.enabled = isOn;
    }
}

- (void)toggleTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    NSString *service = self.entity.isOn ? @"turn_off" : @"turn_on";
    self.serviceBlock(service, @"humidifier", nil, self.entity.entityId);
}

- (void)humidityChanged:(UISlider *)sender {
    self.humidityLabel.text = [NSString stringWithFormat:@"%ld%%", (long)(NSInteger)sender.value];
}

- (void)humidityReleased:(UISlider *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"set_humidity", @"humidifier", @{@"humidity": @((NSInteger)sender.value)}, self.entity.entityId);
}

- (void)modeTapped {
    if (!self.entity || !self.serviceBlock) return;
    NSArray *modes = [self.entity humidifierAvailableModes];
    if (modes.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mode"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *mode in modes) {
        [alert addAction:[UIAlertAction actionWithTitle:mode style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            self.serviceBlock(@"set_mode", @"humidifier", @{@"mode": mode}, self.entity.entityId);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self.containerRef ha_parentViewController];
    if (vc) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.modeButton;
            alert.popoverPresentationController.sourceRect = self.modeButton.bounds;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

@end

#pragma mark - Weather Detail Section

@interface HAWeatherDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HAWeatherDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    // Condition (primary display)
    NSString *condition = [entity weatherCondition] ?: entity.state;
    NSString *symbol = [HAEntity symbolForWeatherCondition:condition];
    UILabel *conditionLabel = [[UILabel alloc] init];
    conditionLabel.text = [NSString stringWithFormat:@"%@ %@", symbol, [condition capitalizedString]];
    conditionLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    conditionLabel.textColor = [HATheme primaryTextColor];
    [stack addArrangedSubview:conditionLabel];

    // Temperature
    NSNumber *temp = [entity weatherTemperature];
    if (temp) {
        NSString *unit = [entity weatherTemperatureUnit] ?: @"\u00B0";
        [stack addArrangedSubview:[self rowWithIcon:@"\U0001F321" label:@"Temperature" value:[NSString stringWithFormat:@"%.1f %@", temp.doubleValue, unit]]];
    }

    // Humidity
    NSNumber *humidity = [entity weatherHumidity];
    if (humidity) {
        [stack addArrangedSubview:[self rowWithIcon:@"\U0001F4A7" label:@"Humidity" value:[NSString stringWithFormat:@"%ld%%", (long)humidity.integerValue]]];
    }

    // Air pressure
    NSNumber *pressure = [entity weatherPressure];
    if (pressure) {
        NSString *pUnit = [entity weatherPressureUnit];
        NSString *pValue = pUnit ? [NSString stringWithFormat:@"%.0f %@", pressure.doubleValue, pUnit] : [NSString stringWithFormat:@"%.0f", pressure.doubleValue];
        [stack addArrangedSubview:[self rowWithIcon:@"\u2B07" label:@"Pressure" value:pValue]];
    }

    // Wind speed
    NSNumber *wind = [entity weatherWindSpeed];
    if (wind) {
        NSString *wUnit = [entity weatherWindSpeedUnit];
        NSString *wValue = wUnit ? [NSString stringWithFormat:@"%.1f %@", wind.doubleValue, wUnit] : [NSString stringWithFormat:@"%.1f", wind.doubleValue];
        [stack addArrangedSubview:[self rowWithIcon:@"\U0001F4A8" label:@"Wind" value:wValue]];
    }

    // Attribution
    NSString *attribution = [entity weatherAttribution];
    if (attribution.length > 0) {
        UILabel *attrLabel = [[UILabel alloc] init];
        attrLabel.text = attribution;
        attrLabel.font = [UIFont systemFontOfSize:10];
        attrLabel.textColor = [HATheme secondaryTextColor];
        attrLabel.numberOfLines = 2;
        [stack addArrangedSubview:attrLabel];
    }

    return container;
}

- (UIView *)rowWithIcon:(NSString *)icon label:(NSString *)label value:(NSString *)value {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentCenter;

    UILabel *iconLabel = [[UILabel alloc] init];
    iconLabel.text = icon;
    iconLabel.font = [UIFont systemFontOfSize:14];
    [iconLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:iconLabel];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = label;
    nameLabel.font = [UIFont systemFontOfSize:14];
    nameLabel.textColor = [HATheme secondaryTextColor];
    [row addArrangedSubview:nameLabel];

    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:spacer];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.text = value;
    valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    valueLabel.textColor = [HATheme primaryTextColor];
    valueLabel.textAlignment = NSTextAlignmentRight;
    [valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:valueLabel];

    return row;
}

- (CGFloat)preferredHeight { return 200; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    // Weather is rebuilt on each update via viewForEntity — no live controls to update
}

@end

#pragma mark - Update Detail Section

@interface HAUpdateDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UILabel *installedLabel;
@property (nonatomic, strong) UILabel *latestLabel;
@property (nonatomic, strong) UIButton *installButton;
@property (nonatomic, strong) UIButton *skipButton;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, assign) BOOL supportsInstall;
@property (nonatomic, assign) BOOL hasSummary;
@end

@implementation HAUpdateDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    NSInteger features = [entity supportedFeatures];
    self.supportsInstall = (features & 1) != 0; // INSTALL bit 0

    NSString *summary = [entity updateReleaseSummary];
    self.hasSummary = summary.length > 0;

    UIView *prevAnchor = nil;

    // Installed version
    self.installedLabel = [[UILabel alloc] init];
    self.installedLabel.font = [UIFont systemFontOfSize:14];
    self.installedLabel.textColor = [HATheme secondaryTextColor];
    self.installedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.installedLabel];

    // Latest version
    self.latestLabel = [[UILabel alloc] init];
    self.latestLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.latestLabel.textColor = [HATheme primaryTextColor];
    self.latestLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.latestLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.installedLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.installedLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.installedLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [self.latestLabel.topAnchor constraintEqualToAnchor:self.installedLabel.bottomAnchor constant:4],
        [self.latestLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.latestLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];
    prevAnchor = self.latestLabel;

    // Action buttons row
    if (self.supportsInstall) {
        UIStackView *buttonRow = [[UIStackView alloc] init];
        buttonRow.axis = UILayoutConstraintAxisHorizontal;
        buttonRow.spacing = 12;
        buttonRow.distribution = UIStackViewDistributionFillEqually;
        buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:buttonRow];

        self.installButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.installButton setTitle:@"Install" forState:UIControlStateNormal];
        self.installButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [self.installButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.installButton.backgroundColor = [HATheme onTintColor];
        self.installButton.layer.cornerRadius = 8;
        self.installButton.clipsToBounds = YES;
        [self.installButton addTarget:self action:@selector(installTapped) forControlEvents:UIControlEventTouchUpInside];
        [buttonRow addArrangedSubview:self.installButton];

        self.skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.skipButton setTitle:@"Skip" forState:UIControlStateNormal];
        self.skipButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.skipButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.skipButton.layer.cornerRadius = 8;
        self.skipButton.clipsToBounds = YES;
        [self.skipButton addTarget:self action:@selector(skipTapped) forControlEvents:UIControlEventTouchUpInside];
        [buttonRow addArrangedSubview:self.skipButton];

        [NSLayoutConstraint activateConstraints:@[
            [buttonRow.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:10],
            [buttonRow.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [buttonRow.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [buttonRow.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = buttonRow;
    }

    // Release summary
    if (self.hasSummary) {
        self.summaryLabel = [[UILabel alloc] init];
        self.summaryLabel.font = [UIFont systemFontOfSize:12];
        self.summaryLabel.textColor = [HATheme secondaryTextColor];
        self.summaryLabel.numberOfLines = 0;
        self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:self.summaryLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.summaryLabel.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:10],
            [self.summaryLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.summaryLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        ]];
        prevAnchor = self.summaryLabel;
    }

    [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight {
    CGFloat h = 40; // version labels
    if (self.supportsInstall) h += 46; // button row
    if (self.hasSummary) h += 60; // summary text (approximate)
    return h;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    NSString *installed = [entity updateInstalledVersion] ?: @"—";
    NSString *latest = [entity updateLatestVersion] ?: @"—";
    self.installedLabel.text = [NSString stringWithFormat:@"Installed: %@", installed];
    self.latestLabel.text = [NSString stringWithFormat:@"Latest: %@", latest];

    BOOL updateAvailable = [entity updateAvailable];
    self.installButton.enabled = updateAvailable;
    self.installButton.alpha = updateAvailable ? 1.0 : 0.4;
    self.skipButton.enabled = updateAvailable;

    NSString *summary = [entity updateReleaseSummary];
    if (summary.length > 0) {
        self.summaryLabel.text = summary;
    }
}

- (void)installTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"install", @"update", nil, self.entity.entityId);
}

- (void)skipTapped {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];
    self.serviceBlock(@"skip", @"update", nil, self.entity.entityId);
}

@end

#pragma mark - Water Heater Detail Section

@interface HAWaterHeaterDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIStepper *tempStepper;
@property (nonatomic, strong) UILabel *targetLabel;
@property (nonatomic, strong) UIButton *modeButton;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, weak) UIView *containerRef;
@property (nonatomic, assign) BOOL hasModes;
@end

@implementation HAWaterHeaterDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];
    self.containerRef = container;

    NSArray *opList = [entity waterHeaterOperationList];
    self.hasModes = opList.count > 0;

    UIView *prevAnchor = nil;

    // Target temperature stepper + label
    self.targetLabel = [[UILabel alloc] init];
    self.targetLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    self.targetLabel.textColor = [HATheme primaryTextColor];
    self.targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.targetLabel];

    self.tempStepper = [[UIStepper alloc] init];
    NSNumber *minTNum = [entity waterHeaterMinTemp];
    NSNumber *maxTNum = [entity waterHeaterMaxTemp];
    double minT = minTNum ? minTNum.doubleValue : 0;
    double maxT = maxTNum ? maxTNum.doubleValue : 0;
    self.tempStepper.minimumValue = minT > 0 ? minT : 30;
    self.tempStepper.maximumValue = maxT > minT ? maxT : 60;
    self.tempStepper.stepValue = 1.0;
    self.tempStepper.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tempStepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.tempStepper];

    [NSLayoutConstraint activateConstraints:@[
        [self.targetLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.targetLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

        [self.tempStepper.centerYAnchor constraintEqualToAnchor:self.targetLabel.centerYAnchor],
        [self.tempStepper.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];
    prevAnchor = self.targetLabel;

    // Operation mode dropdown
    if (self.hasModes) {
        self.modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.modeButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.modeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.modeButton.backgroundColor = [HATheme buttonBackgroundColor];
        self.modeButton.layer.cornerRadius = 8;
        self.modeButton.clipsToBounds = YES;
        self.modeButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        self.modeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.modeButton addTarget:self action:@selector(modeTapped) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:self.modeButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.modeButton.topAnchor constraintEqualToAnchor:prevAnchor.bottomAnchor constant:12],
            [self.modeButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.modeButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.modeButton.heightAnchor constraintEqualToConstant:36],
        ]];
        prevAnchor = self.modeButton;
    }

    [prevAnchor.bottomAnchor constraintEqualToAnchor:container.bottomAnchor].active = YES;

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight {
    CGFloat h = 50; // stepper row
    if (self.hasModes) h += 48; // mode button
    return h;
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    NSNumber *temp = [entity waterHeaterTemperature];
    if (temp) {
        self.tempStepper.value = temp.doubleValue;
        self.targetLabel.text = [NSString stringWithFormat:@"Target: %.0f\u00B0", temp.doubleValue];
    } else {
        self.targetLabel.text = @"Target: \u2014";
    }

    if (self.modeButton) {
        NSString *current = [entity waterHeaterOperationMode];
        NSString *title = (current.length > 0) ? [current capitalizedString] : @"\u2014";
        [self.modeButton setTitle:[NSString stringWithFormat:@"Mode: %@  \u25BE", title] forState:UIControlStateNormal];
    }
}

- (void)stepperChanged:(UIStepper *)sender {
    self.targetLabel.text = [NSString stringWithFormat:@"Target: %.0f\u00B0", sender.value];
    if (!self.entity || !self.serviceBlock) return;
    self.serviceBlock(@"set_temperature", @"water_heater", @{@"temperature": @(sender.value)}, self.entity.entityId);
}

- (void)modeTapped {
    if (!self.entity || !self.serviceBlock) return;
    NSArray *modes = [self.entity waterHeaterOperationList];
    if (modes.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Operation Mode"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *mode in modes) {
        [alert addAction:[UIAlertAction actionWithTitle:[mode capitalizedString] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            self.serviceBlock(@"set_operation_mode", @"water_heater", @{@"operation_mode": mode}, self.entity.entityId);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self.containerRef ha_parentViewController];
    if (vc) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.modeButton;
            alert.popoverPresentationController.sourceRect = self.modeButton.bounds;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

@end

#pragma mark - Text Detail Section

@interface HATextDetailSection : NSObject <HAEntityDetailSection, UITextFieldDelegate>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HATextDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.textField = [[UITextField alloc] init];
    self.textField.font = [UIFont systemFontOfSize:16];
    self.textField.textColor = [HATheme primaryTextColor];
    self.textField.borderStyle = UITextBorderStyleRoundedRect;
    self.textField.returnKeyType = UIReturnKeyDone;
    self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textField.delegate = self;
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.textField];

    [NSLayoutConstraint activateConstraints:@[
        [self.textField.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.textField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.textField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.textField.heightAnchor constraintEqualToConstant:40],
        [self.textField.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight { return 50; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    // Only update text if user is not actively editing
    if (!self.textField.isFirstResponder) {
        self.textField.text = entity.state;
    }

    NSString *mode = [entity inputTextMode];
    self.textField.secureTextEntry = [mode isEqualToString:@"password"];

    self.textField.enabled = entity.isAvailable;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (!self.entity || !self.serviceBlock) return YES;

    NSString *value = textField.text ?: @"";

    // Validate length constraints
    NSInteger minLen = [self.entity inputTextMinLength];
    NSInteger maxLen = [self.entity inputTextMaxLength];
    if (minLen > 0 && (NSInteger)value.length < minLen) return NO;
    if (maxLen > 0 && (NSInteger)value.length > maxLen) return NO;

    [HAHaptics lightImpact];
    NSString *domain = [self.entity domain];
    if ([domain isEqualToString:@"input_text"]) {
        self.serviceBlock(@"set_value", @"input_text", @{@"value": value}, self.entity.entityId);
    } else {
        self.serviceBlock(@"set_value", @"text", @{@"value": value}, self.entity.entityId);
    }
    [textField resignFirstResponder];
    return YES;
}

@end

#pragma mark - Date Detail Section

@interface HADateDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, copy) HADetailServiceBlock serviceBlock;
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HADateDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.datePicker = [[UIDatePicker alloc] init];
    self.datePicker.translatesAutoresizingMaskIntoConstraints = NO;

    // Determine picker mode based on domain and attributes
    NSString *domain = [entity domain];
    if ([domain isEqualToString:@"date"]) {
        self.datePicker.datePickerMode = UIDatePickerModeDate;
    } else {
        // input_datetime: check has_date / has_time
        BOOL hasDate = [entity inputDatetimeHasDate];
        BOOL hasTime = [entity inputDatetimeHasTime];
        if (hasDate && hasTime) {
            self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
        } else if (hasTime) {
            self.datePicker.datePickerMode = UIDatePickerModeTime;
        } else {
            self.datePicker.datePickerMode = UIDatePickerModeDate;
        }
    }

    // Use compact style on iOS 13.4+, fall back to wheels on older
    if (@available(iOS 13.4, *)) {
        self.datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    }

    [self.datePicker addTarget:self action:@selector(dateChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.datePicker];

    [NSLayoutConstraint activateConstraints:@[
        [self.datePicker.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.datePicker.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.datePicker.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight {
    if (@available(iOS 13.4, *)) {
        return 50;
    }
    return 200; // wheels style on older iOS
}

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;

    NSString *domain = [entity domain];
    if ([domain isEqualToString:@"input_datetime"]) {
        NSDate *date = [entity inputDatetimeValue];
        if (date) self.datePicker.date = date;
    } else {
        // date domain: parse YYYY-MM-DD from state
        NSDate *date = [self parseDateFromState:entity.state];
        if (date) self.datePicker.date = date;
    }
}

- (NSDate *)parseDateFromState:(NSString *)state {
    if (!state || state.length == 0) return nil;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    // Try YYYY-MM-DD
    fmt.dateFormat = @"yyyy-MM-dd";
    NSDate *date = [fmt dateFromString:state];
    if (date) return date;

    // Try ISO 8601 full datetime
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    date = [fmt dateFromString:state];
    if (date) return date;

    // Try HH:mm:ss (time only)
    fmt.dateFormat = @"HH:mm:ss";
    date = [fmt dateFromString:state];
    return date;
}

- (void)dateChanged:(UIDatePicker *)sender {
    if (!self.entity || !self.serviceBlock) return;
    [HAHaptics lightImpact];

    NSString *domain = [self.entity domain];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    if ([domain isEqualToString:@"date"]) {
        fmt.dateFormat = @"yyyy-MM-dd";
        NSString *value = [fmt stringFromDate:sender.date];
        self.serviceBlock(@"set_value", @"date", @{@"date": value}, self.entity.entityId);
    } else {
        // input_datetime
        BOOL hasDate = [self.entity inputDatetimeHasDate];
        BOOL hasTime = [self.entity inputDatetimeHasTime];

        if (hasDate && hasTime) {
            fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
            NSString *value = [fmt stringFromDate:sender.date];
            self.serviceBlock(@"set_datetime", @"input_datetime", @{@"datetime": value}, self.entity.entityId);
        } else if (hasTime) {
            fmt.dateFormat = @"HH:mm:ss";
            NSString *value = [fmt stringFromDate:sender.date];
            self.serviceBlock(@"set_datetime", @"input_datetime", @{@"time": value}, self.entity.entityId);
        } else {
            fmt.dateFormat = @"yyyy-MM-dd";
            NSString *value = [fmt stringFromDate:sender.date];
            self.serviceBlock(@"set_datetime", @"input_datetime", @{@"date": value}, self.entity.entityId);
        }
    }
}

@end

#pragma mark - Default Detail Section

@interface HADefaultDetailSection : NSObject <HAEntityDetailSection>
@property (nonatomic, strong) UILabel *stateValueLabel;
@property (nonatomic, weak) HAEntity *entity;
@end

@implementation HADefaultDetailSection

- (UIView *)viewForEntity:(HAEntity *)entity {
    self.entity = entity;
    UIView *container = [[UIView alloc] init];

    self.stateValueLabel = [[UILabel alloc] init];
    self.stateValueLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    self.stateValueLabel.textColor = [HATheme primaryTextColor];
    self.stateValueLabel.textAlignment = NSTextAlignmentCenter;
    self.stateValueLabel.numberOfLines = 2;
    self.stateValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.stateValueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.stateValueLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [self.stateValueLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.stateValueLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.stateValueLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
    ]];

    [self updateWithEntity:entity];
    return container;
}

- (CGFloat)preferredHeight { return 48; }

- (void)updateWithEntity:(HAEntity *)entity {
    self.entity = entity;
    NSString *unit = [entity unitOfMeasurement];
    NSString *state = entity.state ?: @"—";
    if (unit.length > 0) {
        self.stateValueLabel.text = [NSString stringWithFormat:@"%@ %@", state, unit];
    } else {
        self.stateValueLabel.text = state;
    }
}

@end

#pragma mark - Factory

@implementation HAEntityDetailSectionFactory

+ (id<HAEntityDetailSection>)sectionForEntity:(HAEntity *)entity
                                 serviceBlock:(HADetailServiceBlock)serviceBlock {
    NSString *domain = [entity domain];

    if ([domain isEqualToString:@"light"]) {
        HALightDetailSection *section = [[HALightDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"climate"]) {
        HAClimateDetailSection *section = [[HAClimateDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"cover"]) {
        HACoverDetailSection *section = [[HACoverDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"switch"] || [domain isEqualToString:@"input_boolean"]) {
        HAToggleDetailSection *section = [[HAToggleDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"sensor"] || [domain isEqualToString:@"binary_sensor"]) {
        HASensorDetailSection *section = [[HASensorDetailSection alloc] init];
        return section;
    }
    if ([domain isEqualToString:@"media_player"]) {
        HAMediaPlayerDetailSection *section = [[HAMediaPlayerDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"fan"]) {
        HAFanDetailSection *section = [[HAFanDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"lock"]) {
        HALockDetailSection *section = [[HALockDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"vacuum"]) {
        HAVacuumDetailSection *section = [[HAVacuumDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"timer"]) {
        HATimerDetailSection *section = [[HATimerDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"scene"] || [domain isEqualToString:@"script"]) {
        HASceneDetailSection *section = [[HASceneDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"button"] || [domain isEqualToString:@"input_button"]) {
        HAButtonDetailSection *section = [[HAButtonDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"counter"]) {
        HACounterDetailSection *section = [[HACounterDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"input_number"] || [domain isEqualToString:@"number"]) {
        HAInputNumberDetailSection *section = [[HAInputNumberDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"input_select"] || [domain isEqualToString:@"select"]) {
        HAInputSelectDetailSection *section = [[HAInputSelectDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"valve"]) {
        HAValveDetailSection *section = [[HAValveDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"siren"]) {
        HASirenDetailSection *section = [[HASirenDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"alarm_control_panel"]) {
        HAAlarmDetailSection *section = [[HAAlarmDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"humidifier"]) {
        HAHumidifierDetailSection *section = [[HAHumidifierDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"weather"]) {
        HAWeatherDetailSection *section = [[HAWeatherDetailSection alloc] init];
        return section;
    }
    if ([domain isEqualToString:@"update"]) {
        HAUpdateDetailSection *section = [[HAUpdateDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"water_heater"]) {
        HAWaterHeaterDetailSection *section = [[HAWaterHeaterDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"text"] || [domain isEqualToString:@"input_text"]) {
        HATextDetailSection *section = [[HATextDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"date"] || [domain isEqualToString:@"input_datetime"]) {
        HADateDetailSection *section = [[HADateDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }
    if ([domain isEqualToString:@"automation"]) {
        HAToggleDetailSection *section = [[HAToggleDetailSection alloc] init];
        section.serviceBlock = serviceBlock;
        return section;
    }

    // Default fallback for unknown domains
    HADefaultDetailSection *section = [[HADefaultDetailSection alloc] init];
    return section;
}

@end
