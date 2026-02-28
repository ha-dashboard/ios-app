#import "HAEntityRowView.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"
#import "HAConnectionManager.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIView+HAUtilities.h"

@interface HAEntityRowView ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIButton *pressButton;
@property (nonatomic, strong) UIView *separatorLine;
@property (nonatomic, weak) HAEntity *entity;
@property (nonatomic, strong) UITapGestureRecognizer *selectTapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *rowTapGesture;

// Inline slider for input_number / number entities
@property (nonatomic, strong) UISlider *inlineSlider;
@property (nonatomic, strong) UILabel *sliderValueLabel;
@property (nonatomic, assign) BOOL sliderDragging;
@property (nonatomic, assign) double sliderMin;
@property (nonatomic, assign) double sliderMax;
@property (nonatomic, assign) double sliderStep;
// Constraints toggled between slider mode and normal mode
@property (nonatomic, strong) NSLayoutConstraint *nameLabelToStateLabelConstraint;
@property (nonatomic, strong) NSLayoutConstraint *nameLabelToSliderConstraint;

// Cover entity inline buttons (up / stop / down)
@property (nonatomic, strong) UIView *coverButtonsContainer;
@property (nonatomic, strong) UIButton *coverOpenButton;
@property (nonatomic, strong) UIButton *coverStopButton;
@property (nonatomic, strong) UIButton *coverCloseButton;
@end

@implementation HAEntityRowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSubviews];
        self.showsSeparator = YES;
    }
    return self;
}

- (void)setupSubviews {
    // Domain icon (MDI font glyph)
    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.font = [HAIconMapper mdiFontOfSize:18];
    self.iconLabel.textAlignment = NSTextAlignmentCenter;
    self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.iconLabel];

    // Name label
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont systemFontOfSize:15];
    self.nameLabel.textColor = [HATheme primaryTextColor];
    self.nameLabel.numberOfLines = 1;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.nameLabel];

    // State label (for non-toggle entities)
    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.font = [UIFont systemFontOfSize:15];
    self.stateLabel.textColor = [HATheme secondaryTextColor];
    self.stateLabel.textAlignment = NSTextAlignmentRight;
    self.stateLabel.numberOfLines = 2;
    self.stateLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.stateLabel];

    // Name label should resist compression so it always shows
    [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.stateLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    // State label should hug its content (not expand beyond needed)
    [self.stateLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

    // Toggle switch (for toggle-capable entities) — scaled down to 80% for compact rows
    self.toggleSwitch = [[HASwitch alloc] init];
    self.toggleSwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    self.toggleSwitch.onTintColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0]; // HA teal
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(toggleValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.toggleSwitch];

    // Compact "Press" button for button / input_button entities
    self.pressButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pressButton setTitle:@"Press" forState:UIControlStateNormal];
    self.pressButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.pressButton.layer.cornerRadius = 14;
    self.pressButton.layer.borderWidth = 1.0;
    self.pressButton.layer.borderColor = [UIColor systemBlueColor].CGColor;
    self.pressButton.contentEdgeInsets = UIEdgeInsetsMake(4, 14, 4, 14);
    self.pressButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.pressButton.hidden = YES;
    [self.pressButton addTarget:self action:@selector(pressButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.pressButton];

    // Inline slider for input_number / number entities (compact, fits 36pt row)
    self.sliderValueLabel = [[UILabel alloc] init];
    self.sliderValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    self.sliderValueLabel.textColor = [HATheme secondaryTextColor];
    self.sliderValueLabel.textAlignment = NSTextAlignmentRight;
    self.sliderValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sliderValueLabel.hidden = YES;
    [self addSubview:self.sliderValueLabel];

    self.inlineSlider = [[UISlider alloc] init];
    self.inlineSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.inlineSlider.hidden = YES;
    [self.inlineSlider addTarget:self action:@selector(inlineSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.inlineSlider addTarget:self action:@selector(inlineSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.inlineSlider addTarget:self action:@selector(inlineSliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self addSubview:self.inlineSlider];

    // Cover entity inline buttons container (up / stop / down)
    self.coverButtonsContainer = [[UIView alloc] init];
    self.coverButtonsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.coverButtonsContainer.hidden = YES;
    [self addSubview:self.coverButtonsContainer];

    self.coverOpenButton  = [self makeCoverButtonWithFallbackTitle:@"\u25B2" sfSymbolName:@"chevron.up" action:@selector(coverOpenTapped)];
    self.coverStopButton  = [self makeCoverButtonWithFallbackTitle:@"\u25A0" sfSymbolName:@"stop.fill" action:@selector(coverStopTapped)];
    self.coverCloseButton = [self makeCoverButtonWithFallbackTitle:@"\u25BC" sfSymbolName:@"chevron.down" action:@selector(coverCloseTapped)];

    // Arrange buttons horizontally inside the container: [open 28][4][stop 28][4][close 28]
    [NSLayoutConstraint activateConstraints:@[
        [self.coverOpenButton.leadingAnchor constraintEqualToAnchor:self.coverButtonsContainer.leadingAnchor],
        [self.coverOpenButton.centerYAnchor constraintEqualToAnchor:self.coverButtonsContainer.centerYAnchor],
        [self.coverOpenButton.widthAnchor constraintEqualToConstant:28],
        [self.coverOpenButton.heightAnchor constraintEqualToConstant:28],

        [self.coverStopButton.leadingAnchor constraintEqualToAnchor:self.coverOpenButton.trailingAnchor constant:4],
        [self.coverStopButton.centerYAnchor constraintEqualToAnchor:self.coverButtonsContainer.centerYAnchor],
        [self.coverStopButton.widthAnchor constraintEqualToConstant:28],
        [self.coverStopButton.heightAnchor constraintEqualToConstant:28],

        [self.coverCloseButton.leadingAnchor constraintEqualToAnchor:self.coverStopButton.trailingAnchor constant:4],
        [self.coverCloseButton.centerYAnchor constraintEqualToAnchor:self.coverButtonsContainer.centerYAnchor],
        [self.coverCloseButton.widthAnchor constraintEqualToConstant:28],
        [self.coverCloseButton.heightAnchor constraintEqualToConstant:28],
        [self.coverCloseButton.trailingAnchor constraintEqualToAnchor:self.coverButtonsContainer.trailingAnchor],

        // Container height matches buttons
        [self.coverButtonsContainer.heightAnchor constraintEqualToConstant:28]
    ]];

    // Separator line
    self.separatorLine = [[UIView alloc] init];
    self.separatorLine.backgroundColor = [HATheme cellBorderColor];
    self.separatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.separatorLine];

    // Layout constraints
    // Icon: 24pt wide, 12pt from left, vertically centered
    [NSLayoutConstraint activateConstraints:@[
        [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.iconLabel.widthAnchor constraintEqualToConstant:24]
    ]];

    // Name label: starts after icon + 8pt, vertically centered
    // The trailing constraint depends on mode (state label vs slider), created below
    [NSLayoutConstraint activateConstraints:@[
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:8],
        [self.nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    // Default trailing: name -> stateLabel
    self.nameLabelToStateLabelConstraint = [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateLabel.leadingAnchor constant:-8];
    self.nameLabelToStateLabelConstraint.active = YES;
    // Slider-mode trailing: name -> inlineSlider
    self.nameLabelToSliderConstraint = [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.inlineSlider.leadingAnchor constant:-4];
    self.nameLabelToSliderConstraint.active = NO;

    // State label: 16pt from right, vertically centered, max 65% of row width
    [NSLayoutConstraint activateConstraints:@[
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.stateLabel.widthAnchor constraintGreaterThanOrEqualToConstant:40],
        [self.stateLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.65]
    ]];

    // Toggle switch: 16pt from right, vertically centered
    [NSLayoutConstraint activateConstraints:@[
        [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];

    // Press button: 16pt from right, vertically centered, compact height
    [NSLayoutConstraint activateConstraints:@[
        [self.pressButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.pressButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.pressButton.heightAnchor constraintEqualToConstant:28]
    ]];

    // Cover buttons container: 16pt from right, vertically centered
    [NSLayoutConstraint activateConstraints:@[
        [self.coverButtonsContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.coverButtonsContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];

    // Slider value label: rightmost, 60pt wide, 12pt from right edge
    [NSLayoutConstraint activateConstraints:@[
        [self.sliderValueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [self.sliderValueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.sliderValueLabel.widthAnchor constraintEqualToConstant:60]
    ]];

    // Inline slider: between name and value label, ~120pt wide, vertically centered
    [NSLayoutConstraint activateConstraints:@[
        [self.inlineSlider.trailingAnchor constraintEqualToAnchor:self.sliderValueLabel.leadingAnchor constant:-4],
        [self.inlineSlider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.inlineSlider.widthAnchor constraintGreaterThanOrEqualToConstant:80],
        [self.inlineSlider.widthAnchor constraintLessThanOrEqualToConstant:160]
    ]];

    // Separator line: 0.5pt height, full width, at bottom
    [NSLayoutConstraint activateConstraints:@[
        [self.separatorLine.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.separatorLine.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.separatorLine.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.separatorLine.heightAnchor constraintEqualToConstant:0.5]
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity {
    self.entity = entity;

    if (!entity) {
        self.nameLabel.text = @"";
        self.stateLabel.text = @"—";
        self.iconLabel.text = nil;
        self.toggleSwitch.hidden = YES;
        self.pressButton.hidden = YES;
        self.coverButtonsContainer.hidden = YES;
        self.stateLabel.hidden = NO;
        [self hideInlineSlider];
        return;
    }

    self.nameLabel.text = [HAEntityDisplayHelper displayNameForEntity:entity configItem:nil nameOverride:nil];
    self.nameLabel.textColor = [HATheme primaryTextColor];
    self.stateLabel.textColor = [HATheme secondaryTextColor];
    self.iconLabel.text = [HAEntityDisplayHelper iconGlyphForEntity:entity];
    self.iconLabel.textColor = [HAEntityDisplayHelper iconColorForEntity:entity];

    NSString *domain = [entity domain];
    BOOL isToggleable = [HAEntityDisplayHelper isEntityToggleable:entity];
    BOOL isInputNumber = [domain isEqualToString:HAEntityDomainInputNumber] || [domain isEqualToString:HAEntityDomainNumber];
    BOOL isButton = [domain isEqualToString:HAEntityDomainButton] || [domain isEqualToString:HAEntityDomainInputButton];
    BOOL isCover = [domain isEqualToString:HAEntityDomainCover];

    if (isInputNumber) {
        // Slider mode for input_number / number entities
        self.toggleSwitch.hidden = YES;
        self.stateLabel.hidden = YES;
        self.pressButton.hidden = YES;
        self.coverButtonsContainer.hidden = YES;
        self.selectTapGesture.enabled = NO;
        [self showInlineSlider];
        [self configureInlineSliderWithEntity:entity];
    } else if (isButton) {
        // "Press" action button for button / input_button entities
        self.toggleSwitch.hidden = YES;
        self.stateLabel.hidden = YES;
        self.pressButton.hidden = NO;
        self.coverButtonsContainer.hidden = YES;
        self.pressButton.enabled = entity.isAvailable;
        self.selectTapGesture.enabled = NO;
        [self hideInlineSlider];
    } else if (isCover) {
        // Inline cover buttons (up / stop / down)
        self.toggleSwitch.hidden = YES;
        self.stateLabel.hidden = YES;
        self.pressButton.hidden = YES;
        self.selectTapGesture.enabled = NO;
        [self hideInlineSlider];

        // Show cover buttons container and configure per supported_features
        self.coverButtonsContainer.hidden = NO;
        NSInteger features = [entity supportedFeatures];
        BOOL showAll = (features == 0);
        self.coverOpenButton.hidden  = !showAll && !(features & 1);  // Bit 0: OPEN
        self.coverCloseButton.hidden = !showAll && !(features & 2);  // Bit 1: CLOSE
        self.coverStopButton.hidden  = !showAll && !(features & 8);  // Bit 3: STOP

        BOOL available = entity.isAvailable;
        self.coverOpenButton.enabled  = available;
        self.coverStopButton.enabled  = available;
        self.coverCloseButton.enabled = available;
    } else if (isToggleable) {
        self.toggleSwitch.hidden = NO;
        self.stateLabel.hidden = YES;
        self.pressButton.hidden = YES;
        self.coverButtonsContainer.hidden = YES;
        self.toggleSwitch.on = [entity isOn];
        [self hideInlineSlider];
    } else {
        self.toggleSwitch.hidden = YES;
        self.stateLabel.hidden = NO;
        self.pressButton.hidden = YES;
        self.coverButtonsContainer.hidden = YES;
        [self hideInlineSlider];

        NSString *stateText = [HAEntityDisplayHelper stateWithUnitForEntity:entity decimals:2];
        // Add dropdown indicator for select entities and enable tap
        if ([domain isEqualToString:HAEntityDomainInputSelect] || [domain isEqualToString:HAEntityDomainSelect]) {
            stateText = [NSString stringWithFormat:@"%@  \u25BE", [stateText uppercaseString]];
            self.stateLabel.userInteractionEnabled = YES;
            if (!self.selectTapGesture) {
                self.selectTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(selectStateTapped)];
                [self.stateLabel addGestureRecognizer:self.selectTapGesture];
            }
            self.selectTapGesture.enabled = YES;
        } else {
            self.selectTapGesture.enabled = NO;
            self.stateLabel.userInteractionEnabled = NO;
        }
        self.stateLabel.text = stateText;
    }
}

- (void)configureWithEntity:(HAEntity *)entity nameOverride:(NSString *)nameOverride {
    [self configureWithEntity:entity];
    if (nameOverride.length > 0) {
        self.nameLabel.text = nameOverride;
    }
}

- (void)toggleValueChanged:(UISwitch *)sender {
    if (!self.entity) return;

    [HAHaptics lightImpact];

    NSString *service = sender.isOn ? [self.entity turnOnService] : [self.entity turnOffService];
    NSString *domain = [self.entity domain];

    [[HAConnectionManager sharedManager] callService:service
                                             inDomain:domain
                                             withData:nil
                                             entityId:self.entity.entityId];
}

- (void)pressButtonTapped {
    if (!self.entity) return;

    [HAHaptics lightImpact];

    [[HAConnectionManager sharedManager] callService:@"press"
                                             inDomain:[self.entity domain]
                                             withData:nil
                                             entityId:self.entity.entityId];
}

#pragma mark - Cover Buttons

- (UIButton *)makeCoverButtonWithFallbackTitle:(NSString *)fallbackTitle sfSymbolName:(NSString *)sfSymbolName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.tintColor = [HATheme primaryTextColor];

    // Use SF Symbols on iOS 13+, fall back to Unicode text on older versions
    if (@available(iOS 13.0, *)) {
        UIImage *symbol = [UIImage systemImageNamed:sfSymbolName];
        if (symbol) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium];
            symbol = [symbol imageWithConfiguration:config];
            [btn setImage:symbol forState:UIControlStateNormal];
        } else {
            [btn setTitle:fallbackTitle forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        }
    } else {
        [btn setTitle:fallbackTitle forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    }

    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.coverButtonsContainer addSubview:btn];
    return btn;
}

- (void)coverOpenTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    [[HAConnectionManager sharedManager] callService:@"open_cover"
                                            inDomain:HAEntityDomainCover
                                            withData:nil
                                            entityId:self.entity.entityId];
}

- (void)coverStopTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    [[HAConnectionManager sharedManager] callService:@"stop_cover"
                                            inDomain:HAEntityDomainCover
                                            withData:nil
                                            entityId:self.entity.entityId];
}

- (void)coverCloseTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    [[HAConnectionManager sharedManager] callService:@"close_cover"
                                            inDomain:HAEntityDomainCover
                                            withData:nil
                                            entityId:self.entity.entityId];
}

- (void)selectStateTapped {
    if (!self.entity) return;

    NSString *domain = [self.entity domain];
    if (![domain isEqualToString:HAEntityDomainInputSelect] && ![domain isEqualToString:HAEntityDomainSelect]) return;

    NSArray<NSString *> *options = [self.entity inputSelectOptions];
    if (options.count == 0) return;

    [HAHaptics selectionChanged];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self.entity friendlyName]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *current = [self.entity inputSelectCurrentOption];

    for (NSString *option in options) {
        BOOL isSelected = [option isEqualToString:current];
        NSString *title = isSelected ? [NSString stringWithFormat:@"\u2713 %@", option] : option;

        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *a) {
            [self selectOption:option];
        }];
        [alert addAction:action];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover anchor
    alert.popoverPresentationController.sourceView = self.stateLabel;
    alert.popoverPresentationController.sourceRect = self.stateLabel.bounds;

    UIViewController *vc = [self ha_parentViewController];
    if (vc) {
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

- (void)selectOption:(NSString *)option {
    if (!self.entity) return;

    [HAHaptics selectionChanged];

    NSString *stateText = [NSString stringWithFormat:@"%@  \u25BE", [option uppercaseString]];
    self.stateLabel.text = stateText;

    NSDictionary *data = @{@"option": option};
    [[HAConnectionManager sharedManager] callService:@"select_option"
                                            inDomain:[self.entity domain]
                                            withData:data
                                            entityId:self.entity.entityId];
}

- (void)setShowsSeparator:(BOOL)showsSeparator {
    _showsSeparator = showsSeparator;
    self.separatorLine.hidden = !showsSeparator;
}

#pragma mark - Inline Slider (input_number / number)

- (void)showInlineSlider {
    self.inlineSlider.hidden = NO;
    self.sliderValueLabel.hidden = NO;
    self.nameLabelToStateLabelConstraint.active = NO;
    self.nameLabelToSliderConstraint.active = YES;
}

- (void)hideInlineSlider {
    self.inlineSlider.hidden = YES;
    self.sliderValueLabel.hidden = YES;
    self.sliderDragging = NO;
    self.nameLabelToSliderConstraint.active = NO;
    self.nameLabelToStateLabelConstraint.active = YES;
}

- (void)configureInlineSliderWithEntity:(HAEntity *)entity {
    self.sliderMin  = [entity inputNumberMin];
    self.sliderMax  = [entity inputNumberMax];
    self.sliderStep = [entity inputNumberStep];

    self.inlineSlider.minimumValue = (float)self.sliderMin;
    self.inlineSlider.maximumValue = (float)self.sliderMax;
    self.inlineSlider.enabled = entity.isAvailable;

    double currentValue = [entity inputNumberValue];
    if (!self.sliderDragging) {
        self.inlineSlider.value = (float)currentValue;
    }

    [self updateSliderValueLabel:currentValue];
}

- (void)updateSliderValueLabel:(double)value {
    NSString *formatted = [self formatSliderValue:value];
    NSString *unit = [self.entity unitOfMeasurement];
    if (unit.length > 0) {
        self.sliderValueLabel.text = [NSString stringWithFormat:@"%@ %@", formatted, unit];
    } else {
        self.sliderValueLabel.text = formatted;
    }
}

- (NSString *)formatSliderValue:(double)value {
    if (self.sliderStep >= 1.0 && fmod(self.sliderStep, 1.0) == 0.0) {
        return [NSString stringWithFormat:@"%.0f", value];
    }
    NSString *stepStr = [NSString stringWithFormat:@"%g", self.sliderStep];
    NSRange dotRange = [stepStr rangeOfString:@"."];
    if (dotRange.location != NSNotFound) {
        NSUInteger decimals = stepStr.length - dotRange.location - 1;
        NSString *fmt = [NSString stringWithFormat:@"%%.%luf", (unsigned long)decimals];
        return [NSString stringWithFormat:fmt, value];
    }
    return [NSString stringWithFormat:@"%g", value];
}

- (double)snapSliderToStep:(double)value {
    if (self.sliderStep <= 0) return value;
    double snapped = round((value - self.sliderMin) / self.sliderStep) * self.sliderStep + self.sliderMin;
    return MIN(MAX(snapped, self.sliderMin), self.sliderMax);
}

- (void)inlineSliderTouchDown:(UISlider *)sender {
    self.sliderDragging = YES;
}

- (void)inlineSliderChanged:(UISlider *)sender {
    double snapped = [self snapSliderToStep:sender.value];
    [self updateSliderValueLabel:snapped];
}

- (void)inlineSliderTouchUp:(UISlider *)sender {
    self.sliderDragging = NO;
    if (!self.entity) return;

    [HAHaptics lightImpact];

    double snapped = [self snapSliderToStep:sender.value];
    sender.value = (float)snapped;
    [self updateSliderValueLabel:snapped];

    NSDictionary *data = @{@"value": @(snapped)};
    [[HAConnectionManager sharedManager] callService:@"set_value"
                                            inDomain:[self.entity domain]
                                            withData:data
                                            entityId:self.entity.entityId];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 48.0);
}

// Clip touch events to this row's bounds. UISwitch touch targets extend beyond
// their visual size (~51×31pt even when scaled to 0.8x). With 0pt spacing
// between rows in the stack view, this causes taps on one row's control to
// trigger the adjacent row's switch.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(self.bounds, point);
}

#pragma mark - Row Tap (Entity Detail)

- (void)setEntityTapBlock:(void (^)(HAEntity *))entityTapBlock {
    _entityTapBlock = [entityTapBlock copy];
    if (entityTapBlock && !self.rowTapGesture) {
        self.rowTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rowTapped:)];
        [self addGestureRecognizer:self.rowTapGesture];
    }
    self.rowTapGesture.enabled = (entityTapBlock != nil);
}

- (void)rowTapped:(UITapGestureRecognizer *)gesture {
    if (!self.entityTapBlock || !self.entity) return;

    CGPoint point = [gesture locationInView:self];

    // Don't trigger if the touch landed on an interactive control
    if (!self.toggleSwitch.hidden && CGRectContainsPoint(self.toggleSwitch.frame, point)) return;
    if (!self.pressButton.hidden && CGRectContainsPoint(self.pressButton.frame, point)) return;
    if (!self.inlineSlider.hidden && CGRectContainsPoint(self.inlineSlider.frame, point)) return;
    if (!self.coverButtonsContainer.hidden && CGRectContainsPoint(self.coverButtonsContainer.frame, point)) return;
    if (self.selectTapGesture.enabled && CGRectContainsPoint(self.stateLabel.frame, point)) return;

    self.entityTapBlock(self.entity);
}

@end
