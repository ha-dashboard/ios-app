#import "HAAutoLayout.h"
#import "HAEntityRowView.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"
#import "HAConnectionManager.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIView+HAUtilities.h"
#import "UIViewController+HAAlert.h"
#import "UIFont+HACompat.h"

@interface HAEntityRowView ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UILabel *secondaryInfoLabel;
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
    if (HAAutoLayoutAvailable()) {
        [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:0];
    }
    if (HAAutoLayoutAvailable()) {
        [self.stateLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:0];
    }
    // State label should hug its content (not expand beyond needed)
    if (HAAutoLayoutAvailable()) {
        [self.stateLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:0];
    }

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
    self.pressButton.titleLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium];
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
    self.sliderValueLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightMedium];
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
    if (HAAutoLayoutAvailable()) {
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
    }

    // Separator line
    self.separatorLine = [[UIView alloc] init];
    self.separatorLine.backgroundColor = [HATheme cellBorderColor];
    self.separatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.separatorLine];

    // Layout constraints
    // Icon: 24pt wide, 12pt from left, vertically centered
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.iconLabel.widthAnchor constraintEqualToConstant:24]
        ]];
    }

    // Secondary info label (below name, smaller font)
    self.secondaryInfoLabel = [[UILabel alloc] init];
    self.secondaryInfoLabel.font = [UIFont systemFontOfSize:11];
    self.secondaryInfoLabel.textColor = [HATheme secondaryTextColor];
    self.secondaryInfoLabel.numberOfLines = 1;
    self.secondaryInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.secondaryInfoLabel.hidden = YES;
    [self addSubview:self.secondaryInfoLabel];

    // Name label: starts after icon + 8pt, vertically centered.
    // When secondary_info is visible, name shifts up and secondary sits below.
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:8],
            [self.nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.secondaryInfoLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
            [self.secondaryInfoLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:1],
            [self.secondaryInfoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateLabel.leadingAnchor constant:-8],
        ]];
    }
    // Default trailing: name -> stateLabel
    if (HAAutoLayoutAvailable()) {
        self.nameLabelToStateLabelConstraint = [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateLabel.leadingAnchor constant:-8];
        self.nameLabelToStateLabelConstraint.active = YES;
        // Slider-mode trailing: name -> inlineSlider
        self.nameLabelToSliderConstraint = [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.inlineSlider.leadingAnchor constant:-4];
        self.nameLabelToSliderConstraint.active = NO;
    }

    // State label: 16pt from right, vertically centered, max 65% of row width
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.stateLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.stateLabel.widthAnchor constraintGreaterThanOrEqualToConstant:40],
            [self.stateLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.65]
        ]];
    }

    // Toggle switch: 16pt from right, vertically centered
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }

    // Press button: 16pt from right, vertically centered, compact height
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.pressButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.pressButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.pressButton.heightAnchor constraintEqualToConstant:28]
        ]];
    }

    // Cover buttons container: 16pt from right, vertically centered
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.coverButtonsContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.coverButtonsContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }

    // Slider value label: rightmost, 60pt wide, 12pt from right edge
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.sliderValueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [self.sliderValueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.sliderValueLabel.widthAnchor constraintEqualToConstant:60]
        ]];
    }

    // Inline slider: between name and value label, ~120pt wide, vertically centered
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.inlineSlider.trailingAnchor constraintEqualToAnchor:self.sliderValueLabel.leadingAnchor constant:-4],
            [self.inlineSlider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.inlineSlider.widthAnchor constraintGreaterThanOrEqualToConstant:80],
            [self.inlineSlider.widthAnchor constraintLessThanOrEqualToConstant:160]
        ]];
    }

    // Separator line: 0.5pt height, full width, at bottom
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.separatorLine.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [self.separatorLine.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.separatorLine.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.separatorLine.heightAnchor constraintEqualToConstant:0.5]
        ]];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;
        CGFloat midY = h / 2.0;

        // Icon: 24pt wide, 12pt from left, vertically centered
        self.iconLabel.frame = CGRectMake(12, midY - 9, 24, 18);
        CGFloat nameX = 12 + 24 + 8; // after icon

        // Determine right-side control width
        CGFloat rightEdge = w - 16;
        if (!self.toggleSwitch.hidden) {
            CGSize sz = [self.toggleSwitch sizeThatFits:CGSizeZero];
            self.toggleSwitch.frame = CGRectMake(rightEdge - sz.width, midY - sz.height / 2, sz.width, sz.height);
            rightEdge = CGRectGetMinX(self.toggleSwitch.frame) - 8;
        } else if (!self.pressButton.hidden) {
            CGSize sz = [self.pressButton sizeThatFits:CGSizeZero];
            self.pressButton.frame = CGRectMake(rightEdge - sz.width, midY - 14, sz.width, 28);
            rightEdge = CGRectGetMinX(self.pressButton.frame) - 8;
        } else if (!self.coverButtonsContainer.hidden) {
            CGFloat cw = 28 * 3 + 4 * 2; // 3 buttons + 2 gaps
            self.coverButtonsContainer.frame = CGRectMake(rightEdge - cw, midY - 14, cw, 28);
            self.coverOpenButton.frame = CGRectMake(0, 0, 28, 28);
            self.coverStopButton.frame = CGRectMake(32, 0, 28, 28);
            self.coverCloseButton.frame = CGRectMake(64, 0, 28, 28);
            rightEdge = CGRectGetMinX(self.coverButtonsContainer.frame) - 8;
        } else if (!self.inlineSlider.hidden) {
            // TODO: complex slider layout fallback
            CGFloat sliderValW = 60;
            self.sliderValueLabel.frame = CGRectMake(rightEdge - sliderValW, midY - 9, sliderValW, 18);
            CGFloat sliderW = MIN(160, MAX(80, rightEdge - sliderValW - 4 - nameX - 80));
            self.inlineSlider.frame = CGRectMake(CGRectGetMinX(self.sliderValueLabel.frame) - 4 - sliderW, midY - 15, sliderW, 30);
            rightEdge = CGRectGetMinX(self.inlineSlider.frame) - 4;
        } else if (!self.stateLabel.hidden) {
            CGSize sz = [self.stateLabel sizeThatFits:CGSizeMake(w * 0.65, CGFLOAT_MAX)];
            sz.width = MAX(40, MIN(sz.width, w * 0.65));
            self.stateLabel.frame = CGRectMake(rightEdge - sz.width, midY - sz.height / 2, sz.width, sz.height);
            rightEdge = CGRectGetMinX(self.stateLabel.frame) - 8;
        }

        // Name
        CGFloat nameW = rightEdge - nameX;
        CGSize nameSize = [self.nameLabel sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
        self.nameLabel.frame = CGRectMake(nameX, midY - nameSize.height / 2, nameW, nameSize.height);

        // Secondary info
        if (!self.secondaryInfoLabel.hidden) {
            CGSize secSize = [self.secondaryInfoLabel sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
            self.secondaryInfoLabel.frame = CGRectMake(nameX, CGRectGetMaxY(self.nameLabel.frame) + 1, nameW, secSize.height);
        }

        // Separator
        self.separatorLine.frame = CGRectMake(16, h - 0.5, w - 32, 0.5);
    }
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
    // state_color: tint icon by entity active state. Default NO for entities card rows.
    if (self.stateColor) {
        self.iconLabel.textColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    } else {
        self.iconLabel.textColor = [HATheme secondaryTextColor];
    }

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

        NSString *stateText;
        if (self.attributeOverride.length > 0) {
            id attrVal = entity.attributes[self.attributeOverride];
            stateText = (attrVal && attrVal != [NSNull null]) ? [NSString stringWithFormat:@"%@", attrVal] : @"—";
        } else {
            stateText = [HAEntityDisplayHelper stateWithUnitForEntity:entity decimals:2];
        }
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

    // Secondary info (below name label)
    [self configureSecondaryInfo:entity];
}

- (void)configureSecondaryInfo:(HAEntity *)entity {
    if (!self.secondaryInfo || self.secondaryInfo.length == 0 || !entity) {
        self.secondaryInfoLabel.hidden = YES;
        // Reset name label to vertically centered when no secondary info
        for (NSLayoutConstraint *c in self.constraints) {
            if (c.firstItem == self.nameLabel && c.firstAttribute == NSLayoutAttributeCenterY) {
                c.constant = 0;
            }
        }
        return;
    }

    NSString *text = nil;
    NSString *type = self.secondaryInfo;
    NSString *format = self.secondaryInfoFormat ?: @"relative";

    if ([type isEqualToString:@"entity-id"]) {
        text = entity.entityId;
    } else if ([type isEqualToString:@"last-changed"]) {
        text = [HAEntityDisplayHelper formattedValue:entity.lastChanged withFormat:format];
    } else if ([type isEqualToString:@"last-updated"]) {
        text = [HAEntityDisplayHelper formattedValue:entity.lastUpdated withFormat:format];
    } else if ([type isEqualToString:@"last-triggered"]) {
        NSString *triggered = HAAttrString(entity.attributes, @"last_triggered");
        if (triggered) text = [HAEntityDisplayHelper formattedValue:triggered withFormat:format];
    } else if ([type isEqualToString:@"position"]) {
        NSNumber *pos = HAAttrNumber(entity.attributes, HAAttrCurrentPosition);
        if (pos) text = [NSString stringWithFormat:@"%@%%", pos];
    } else if ([type isEqualToString:@"tilt-position"]) {
        NSNumber *tilt = HAAttrNumber(entity.attributes, HAAttrCurrentTiltPosition);
        if (tilt) text = [NSString stringWithFormat:@"%@%%", tilt];
    } else if ([type isEqualToString:@"brightness"]) {
        NSInteger pct = [entity brightnessPercent];
        if (pct > 0) text = [NSString stringWithFormat:@"%ld%%", (long)pct];
    }

    if (text.length > 0) {
        self.secondaryInfoLabel.text = text;
        self.secondaryInfoLabel.hidden = NO;
        // Shift name label up to make room for secondary info
        for (NSLayoutConstraint *c in self.constraints) {
            if (c.firstItem == self.nameLabel && c.firstAttribute == NSLayoutAttributeCenterY) {
                c.constant = -7;
            }
        }
    } else {
        self.secondaryInfoLabel.hidden = YES;
        for (NSLayoutConstraint *c in self.constraints) {
            if (c.firstItem == self.nameLabel && c.firstAttribute == NSLayoutAttributeCenterY) {
                c.constant = 0;
            }
        }
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
            btn.titleLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightMedium];
        }
    } else {
        [btn setTitle:fallbackTitle forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightMedium];
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

    NSString *current = [self.entity inputSelectCurrentOption];
    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:options.count];
    for (NSString *option in options) {
        BOOL isSelected = [option isEqualToString:current];
        [titles addObject:isSelected ? [NSString stringWithFormat:@"\u2713 %@", option] : option];
    }

    UIViewController *vc = [self ha_parentViewController];
    if (vc) {
        [vc ha_showActionSheetWithTitle:[self.entity friendlyName]
                            cancelTitle:@"Cancel"
                           actionTitles:titles
                             sourceView:self.stateLabel
                                handler:^(NSInteger index) {
            [self selectOption:options[(NSUInteger)index]];
        }];
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
    self.inlineSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.inlineSlider.hidden = NO;
    self.sliderValueLabel.hidden = NO;
    if (HAAutoLayoutAvailable()) {
        self.nameLabelToStateLabelConstraint.active = NO;
    }
    if (HAAutoLayoutAvailable()) {
        self.nameLabelToSliderConstraint.active = YES;
    }
}

- (void)hideInlineSlider {
    self.inlineSlider.hidden = YES;
    self.sliderValueLabel.hidden = YES;
    self.sliderDragging = NO;
    if (HAAutoLayoutAvailable()) {
        self.nameLabelToSliderConstraint.active = NO;
    }
    if (HAAutoLayoutAvailable()) {
        self.nameLabelToStateLabelConstraint.active = YES;
    }
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

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 48.0);
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
