#import "HAAutoLayout.h"
#import "HAStackView.h"
#import "HATileEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HAHTTPClient.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "HATileFeatureView.h"
#import "HATileFeatureFactory.h"
#import "UIFont+HACompat.h"

@interface HATileEntityCell ()
@property (nonatomic, strong) UILabel *tileIconLabel;
@property (nonatomic, strong) UILabel *tileNameLabel;
@property (nonatomic, strong) UILabel *tileStateLabel;
@property (nonatomic, strong) HAStackView *compactStack;
/// Normal (tile) layout constraints
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *normalConstraints;
/// Compact (pill) layout constraints for button cards in horizontal-stack
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *compactConstraints;
@property (nonatomic, assign) BOOL isCompact;
@property (nonatomic, assign) BOOL isVertical;
/// Entity picture image view (shown when show_entity_picture is true)
@property (nonatomic, strong) UIImageView *entityPictureView;
@property (nonatomic, strong) id pictureTask;
/// Feature views below the tile area (brightness slider, cover buttons, etc.)
@property (nonatomic, strong) HAStackView *featuresStack;
@property (nonatomic, strong) NSArray<HATileFeatureView *> *featureViews;
@property (nonatomic, strong) NSLayoutConstraint *featuresTopConstraint;
@end

@implementation HATileEntityCell

+ (CGFloat)compactHeight {
    return 72.0;
}

+ (CGFloat)preferredHeight {
    return 72.0;
}

+ (CGFloat)preferredHeightForConfigItem:(HADashboardConfigItem *)configItem {
    NSArray *features = configItem.customProperties[@"features"];
    if (![features isKindOfClass:[NSArray class]] || features.count == 0) {
        return [self preferredHeight];
    }
    // Don't add features height in compact mode
    if ([configItem.customProperties[@"compact"] boolValue]) {
        return [self compactHeight];
    }
    CGFloat featureHeight = 0;
    for (NSDictionary *f in features) {
        if (![f isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = f[@"type"];
        CGFloat h = [HATileFeatureFactory heightForFeatureType:type];
        if (h > 0) {
            featureHeight += h + 4; // feature height + spacing
        }
    }
    if (featureHeight > 0) {
        return [self preferredHeight] + featureHeight + 4; // base + features + bottom padding
    }
    return [self preferredHeight];
}

- (void)setupSubviews {
    [super setupSubviews];
    // Hide the base cell's name and state — tile has its own centered layout
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Icon label (left-aligned in both normal and compact modes)
    self.tileIconLabel = [[UILabel alloc] init];
    self.tileIconLabel.font = [HAIconMapper mdiFontOfSize:28];
    self.tileIconLabel.textColor = [HATheme primaryTextColor];
    self.tileIconLabel.textAlignment = NSTextAlignmentCenter;
    self.tileIconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.tileIconLabel];

    // Entity name (right of icon in both modes)
    self.tileNameLabel = [[UILabel alloc] init];
    self.tileNameLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium];
    self.tileNameLabel.textColor = [HATheme primaryTextColor];
    self.tileNameLabel.textAlignment = NSTextAlignmentLeft;
    self.tileNameLabel.numberOfLines = 2;
    self.tileNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.tileNameLabel];

    // State label (below name, right of icon in normal mode; hidden in compact mode)
    self.tileStateLabel = [[UILabel alloc] init];
    self.tileStateLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightRegular];
    self.tileStateLabel.textColor = [HATheme secondaryTextColor];
    self.tileStateLabel.textAlignment = NSTextAlignmentLeft;
    self.tileStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.tileStateLabel];

    // Compact layout stack (created unconditionally for addArrangedSubview)
    self.compactStack = [[HAStackView alloc] init];
    self.compactStack.axis = 1;
    self.compactStack.alignment = 3;
    self.compactStack.spacing = 4;
    self.compactStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.compactStack.hidden = YES; // start hidden, activated by applyCompactMode:
    [self.contentView addSubview:self.compactStack];

    // Normal layout: icon on the left, name + state stacked to the right (HA web style).
    // Pin to a fixed 72px top area so features below don't shift the content.
    CGFloat iconWidth = 32.0;
    CGFloat tileAreaCenterY = 72.0 / 2.0; // Center of the 72px tile content area
    self.normalConstraints = @[
        HACon([self.tileIconLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12]),
        HACon([self.tileIconLabel.centerYAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:tileAreaCenterY]),
        HACon([self.tileIconLabel.widthAnchor constraintEqualToConstant:iconWidth]),
        HACon([self.tileNameLabel.leadingAnchor constraintEqualToAnchor:self.tileIconLabel.trailingAnchor constant:10]),
        HACon([self.tileNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.tileNameLabel.bottomAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:tileAreaCenterY - 1]),
        HACon([self.tileStateLabel.leadingAnchor constraintEqualToAnchor:self.tileNameLabel.leadingAnchor]),
        HACon([self.tileStateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.tileStateLabel.topAnchor constraintEqualToAnchor:self.tileNameLabel.bottomAnchor constant:2]),
    ];

    self.compactConstraints = @[
        HACon([self.compactStack.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.compactStack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]),
        HACon([self.compactStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:4]),
        HACon([self.compactStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-4]),
    ];

    // Start with normal layout
    HAActivateConstraints(self.normalConstraints);

    // Features stack (brightness slider, cover buttons, etc.) — below main tile area
    self.featuresStack = [[HAStackView alloc] init];
    self.featuresStack.axis = 1;
    self.featuresStack.spacing = 4;
    self.featuresStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.featuresStack.hidden = YES;
    [self.contentView addSubview:self.featuresStack];

    self.featuresTopConstraint = HAMakeConstraint([self.featuresStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:72]);
    HAActivateConstraints(@[
        HACon(self.featuresTopConstraint),
        HACon([self.featuresStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor]),
        HACon([self.featuresStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]),
    ]);

    // Icon tap gesture: separate from cell selection to support icon_tap_action.
    // When iconTapBlock is set, tapping the icon calls the block instead of
    // passing through to the collection view's didSelectItem.
    self.tileIconLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *iconTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(iconTapped:)];
    iconTap.delegate = self;
    [self.tileIconLabel addGestureRecognizer:iconTap];

    // Body tap toggles via didSelectItemAtIndexPath.
    // Long-press opens detail via the collection view's long-press gesture.
}

- (void)applyCompactMode:(BOOL)compact {
    if (self.isCompact == compact) return;
    self.isCompact = compact;

    if (compact) {
        [NSLayoutConstraint deactivateConstraints:self.normalConstraints];
        // Move labels into the centered stack
        if (self.tileIconLabel.superview != self.compactStack) {
            [self.compactStack addArrangedSubview:self.tileIconLabel];
            [self.compactStack addArrangedSubview:self.tileNameLabel];
            [self.compactStack addArrangedSubview:self.tileStateLabel];
        }
        self.compactStack.hidden = NO;
        HAActivateConstraints(self.compactConstraints);
        self.tileIconLabel.font = [HAIconMapper mdiFontOfSize:28];
        self.tileNameLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightMedium];
        self.tileNameLabel.textAlignment = NSTextAlignmentCenter;
        self.tileNameLabel.numberOfLines = 1;
        self.contentView.layer.cornerRadius = 12.0;
    } else {
        [NSLayoutConstraint deactivateConstraints:self.compactConstraints];
        self.compactStack.hidden = YES;
        // Move labels back to contentView for normal layout
        [self.contentView addSubview:self.tileIconLabel];
        [self.contentView addSubview:self.tileNameLabel];
        [self.contentView addSubview:self.tileStateLabel];
        HAActivateConstraints(self.normalConstraints);
        self.tileIconLabel.font = [HAIconMapper mdiFontOfSize:28];
        self.tileNameLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium];
        self.tileNameLabel.textAlignment = NSTextAlignmentLeft;
        self.tileNameLabel.numberOfLines = 2;
        self.contentView.layer.cornerRadius = 12.0;
    }
}

- (void)applyVerticalMode:(BOOL)vertical {
    if (self.isVertical == vertical) return;
    self.isVertical = vertical;

    if (vertical) {
        [NSLayoutConstraint deactivateConstraints:self.normalConstraints];
        if (self.tileIconLabel.superview != self.compactStack) {
            [self.compactStack addArrangedSubview:self.tileIconLabel];
            [self.compactStack addArrangedSubview:self.tileNameLabel];
            [self.compactStack addArrangedSubview:self.tileStateLabel];
        }
        self.compactStack.hidden = NO;
        HAActivateConstraints(self.compactConstraints);
        // Vertical keeps normal font sizes (unlike compact which shrinks)
        self.tileIconLabel.font = [HAIconMapper mdiFontOfSize:28];
        self.tileNameLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium];
        self.tileNameLabel.textAlignment = NSTextAlignmentCenter;
        self.tileNameLabel.numberOfLines = 2;
        self.contentView.layer.cornerRadius = 14.0;
    } else {
        [NSLayoutConstraint deactivateConstraints:self.compactConstraints];
        self.compactStack.hidden = YES;
        [self.contentView addSubview:self.tileIconLabel];
        [self.contentView addSubview:self.tileNameLabel];
        [self.contentView addSubview:self.tileStateLabel];
        HAActivateConstraints(self.normalConstraints);
        self.tileIconLabel.font = [HAIconMapper mdiFontOfSize:28];
        self.tileNameLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium];
        self.tileNameLabel.textAlignment = NSTextAlignmentLeft;
        self.tileNameLabel.numberOfLines = 2;
        self.contentView.layer.cornerRadius = 14.0;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat padding = 10.0;

        if (!self.compactStack.hidden) {
            // Compact mode: centered stack
            CGSize stackSize = [self.compactStack sizeThatFits:self.contentView.bounds.size];
            self.compactStack.frame = CGRectMake((w - stackSize.width) / 2.0,
                                                  (self.contentView.bounds.size.height - stackSize.height) / 2.0,
                                                  stackSize.width, stackSize.height);
        } else {
            // Normal mode: icon left, name+state right
            CGFloat iconWidth = 32.0;
            CGFloat tileAreaCenterY = 72.0 / 2.0;
            self.tileIconLabel.frame = CGRectMake(12, tileAreaCenterY - 14, iconWidth, 28);
            CGFloat nameX = 12 + iconWidth + 10;
            CGFloat nameW = w - nameX - padding;
            CGSize nameSize = [self.tileNameLabel sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
            self.tileNameLabel.frame = CGRectMake(nameX, tileAreaCenterY - 1 - nameSize.height, nameW, nameSize.height);
            CGSize stateSize = [self.tileStateLabel sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
            self.tileStateLabel.frame = CGRectMake(nameX, tileAreaCenterY + 1, nameW, stateSize.height);
        }

        // Features stack below tile area
        if (!self.featuresStack.hidden) {
            self.featuresStack.frame = CGRectMake(0, 72, w, self.contentView.bounds.size.height - 72);
        }
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // Determine if this is a compact button card (inside horizontal-stack)
    BOOL compact = [configItem.customProperties[@"compact"] boolValue];
    BOOL vertical = [configItem.customProperties[@"vertical"] boolValue];

    // Compact takes priority over vertical (both use the same stack)
    if (compact) {
        self.isVertical = NO;
        [self applyCompactMode:compact];
    } else if (vertical) {
        self.isCompact = NO;
        [self applyVerticalMode:YES];
    } else {
        [self applyCompactMode:NO];
        [self applyVerticalMode:NO];
    }

    // Apply icon_height from card config (e.g. "36px") — parse numeric value
    NSString *iconHeightStr = configItem.customProperties[@"icon_height"];
    if (iconHeightStr.length > 0) {
        CGFloat iconPx = [[iconHeightStr stringByReplacingOccurrencesOfString:@"px" withString:@""] floatValue];
        if (iconPx > 0) {
            self.tileIconLabel.font = [HAIconMapper mdiFontOfSize:iconPx];
        }
    }

    NSString *name = [HAEntityDisplayHelper displayNameForEntity:entity configItem:configItem nameOverride:nil];
    self.tileNameLabel.text = name;

    // Attribute override: show a specific attribute value instead of state
    NSString *attributeOverride = configItem.customProperties[@"attribute"];
    NSString *displayState;
    if (attributeOverride.length > 0) {
        id attrVal = entity.attributes[attributeOverride];
        displayState = (attrVal && attrVal != [NSNull null]) ? [NSString stringWithFormat:@"%@", attrVal] : @"—";
    } else {
        // State: formatted state with human-readable text + unit
        NSString *formattedState = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:2];
        displayState = [HAEntityDisplayHelper humanReadableState:formattedState];
        NSString *unit = entity.unitOfMeasurement;
        // Append unit unless binary_sensor or duration (already includes units)
        if (unit.length > 0 &&
            ![[entity domain] isEqualToString:@"binary_sensor"] &&
            ![unit isEqualToString:@"h"] && ![unit isEqualToString:@"min"] &&
            ![unit isEqualToString:@"s"] && ![unit isEqualToString:@"d"]) {
            displayState = [NSString stringWithFormat:@"%@ %@", displayState, unit];
        }
    }

    // Domain-specific secondary detail (e.g. "71%", "Open · 70%", "Heat · 22°C")
    // Skip domain overrides when attribute override is active
    NSString *domain = [entity domain];
    if (attributeOverride.length > 0) {
        // attribute override — skip domain-specific formatting
    } else if ([domain isEqualToString:@"light"]) {
        if ([entity isOn]) {
            NSInteger pct = [entity brightnessPercent];
            if (pct > 0) {
                displayState = [NSString stringWithFormat:@"%ld%%", (long)pct];
            }
        }
    } else if ([domain isEqualToString:@"humidifier"]) {
        NSNumber *targetHumidity = [entity humidifierTargetHumidity];
        if (targetHumidity) {
            displayState = [NSString stringWithFormat:@"%@ · %@%%", displayState, targetHumidity];
        }
    } else if ([domain isEqualToString:@"cover"]) {
        NSInteger pos = [entity coverPosition];
        // coverPosition returns 0 as default; check if attribute actually exists
        if (HAAttrNumber(entity.attributes, HAAttrCurrentPosition)) {
            displayState = [NSString stringWithFormat:@"%@ · %ld%%", displayState, (long)pos];
        }
    } else if ([domain isEqualToString:@"climate"]) {
        // Format HVAC mode with "/" separator: "heat_cool" → "Heat/Cool"
        NSString *hvacMode = entity.state;
        NSString *formattedMode = [[hvacMode stringByReplacingOccurrencesOfString:@"_" withString:@"/"] capitalizedString];
        displayState = formattedMode;
        NSNumber *targetTemp = [entity targetTemperature];
        if (targetTemp) {
            NSString *tempUnit = [entity weatherTemperatureUnit];
            if (!tempUnit || tempUnit.length == 0) {
                tempUnit = @"°C";
            }
            displayState = [NSString stringWithFormat:@"%@ · %@%@", displayState, targetTemp, tempUnit];
        }
    } else if ([domain isEqualToString:@"fan"]) {
        if ([entity isOn]) {
            NSInteger pct = [entity fanSpeedPercent];
            if (pct > 0) {
                displayState = [NSString stringWithFormat:@"%ld%%", (long)pct];
            }
        }
    } else if ([domain isEqualToString:@"media_player"]) {
        NSString *title = [entity mediaTitle];
        NSString *artist = [entity mediaArtist];
        if (title.length > 0 && artist.length > 0) {
            displayState = [NSString stringWithFormat:@"%@ · %@", artist, title];
        } else if (title.length > 0) {
            displayState = title;
        }
    }

    // state_content override: display last_changed, last_updated, or attribute values
    id stateContent = configItem.customProperties[@"state_content"];
    if (stateContent) {
        NSArray *contentItems = [stateContent isKindOfClass:[NSArray class]]
            ? (NSArray *)stateContent
            : @[stateContent];
        NSMutableArray *parts = [NSMutableArray arrayWithCapacity:contentItems.count];
        for (id item in contentItems) {
            NSString *key = [item isKindOfClass:[NSString class]] ? (NSString *)item : nil;
            if (!key) continue;
            NSString *value = nil;
            if ([key isEqualToString:@"last_changed"] || [key isEqualToString:@"last-changed"]) {
                value = [HAEntityDisplayHelper relativeTimeFromISO8601:entity.lastChanged];
            } else if ([key isEqualToString:@"last_updated"] || [key isEqualToString:@"last-updated"]) {
                value = [HAEntityDisplayHelper relativeTimeFromISO8601:entity.lastUpdated];
            } else if ([key isEqualToString:@"state"]) {
                value = displayState;
            } else {
                // Attribute name lookup
                id attrVal = entity.attributes[key];
                if (attrVal && attrVal != [NSNull null]) {
                    value = [NSString stringWithFormat:@"%@", attrVal];
                }
            }
            if (value.length > 0) [parts addObject:value];
        }
        if (parts.count > 0) {
            displayState = [parts componentsJoinedByString:@" · "];
        }
    }

    // Respect show_state / show_name / show_icon from card config.
    // HA button card defaults: show_name=YES, show_icon=YES, show_state=NO.
    // HA tile card defaults: show_name=YES, show_icon=YES, show_state=YES.
    NSDictionary *props = configItem.customProperties;
    BOOL isButtonCard = [configItem.cardType isEqualToString:@"button"];
    BOOL defaultShowState = !isButtonCard; // button cards hide state by default
    BOOL hideState = [props[@"hide_state"] boolValue]; // tile-specific hide_state field
    BOOL showState = hideState ? NO : (props[@"show_state"] ? [props[@"show_state"] boolValue] : defaultShowState);
    BOOL showName  = props[@"show_name"]  ? [props[@"show_name"] boolValue]  : YES;
    BOOL showIcon  = props[@"show_icon"]  ? [props[@"show_icon"] boolValue]  : YES;
    self.tileStateLabel.text = showState ? displayState : nil;
    self.tileStateLabel.hidden = !showState;
    self.tileNameLabel.hidden = !showName;
    self.tileIconLabel.hidden = !showIcon;

    // Icon: from card config override, else centralized entity icon resolution
    NSString *iconName = configItem.customProperties[@"icon"];
    NSString *glyph = nil;
    if (iconName) {
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        glyph = [HAIconMapper glyphForIconName:iconName];
    }
    if (!glyph) glyph = [HAEntityDisplayHelper iconGlyphForEntity:entity];
    self.tileIconLabel.text = glyph ?: @"?";

    // Entity picture: show circular image instead of icon when configured
    [[HAHTTPClient sharedClient] cancelTask:self.pictureTask];
    BOOL showEntityPicture = [configItem.customProperties[@"show_entity_picture"] boolValue];
    NSString *entityPicture = entity.attributes[@"entity_picture"];
    if (showEntityPicture && entityPicture.length > 0) {
        self.tileIconLabel.hidden = YES;
        if (!self.entityPictureView) {
            self.entityPictureView = [[UIImageView alloc] init];
            self.entityPictureView.translatesAutoresizingMaskIntoConstraints = NO;
            self.entityPictureView.contentMode = UIViewContentModeScaleAspectFill;
            self.entityPictureView.clipsToBounds = YES;
            self.entityPictureView.layer.cornerRadius = 16;
            [self.contentView addSubview:self.entityPictureView];
            HAActivateConstraints(@[
                HACon([self.entityPictureView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12]),
                HACon([self.entityPictureView.centerYAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:36]),
                HACon([self.entityPictureView.widthAnchor constraintEqualToConstant:32]),
                HACon([self.entityPictureView.heightAnchor constraintEqualToConstant:32]),
            ]);
        }
        self.entityPictureView.hidden = NO;
        self.entityPictureView.image = nil;
        // Build full URL from HA server base + entity_picture path
        NSString *serverURL = [[HAAuthManager sharedManager] serverURL];
        if (serverURL && [entityPicture hasPrefix:@"/"]) {
            NSURL *url = [NSURL URLWithString:[serverURL stringByAppendingString:entityPicture]];
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            NSString *token = [[HAAuthManager sharedManager] accessToken];
            if (token) [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
            __weak typeof(self) weakSelf = self;
            self.pictureTask = [[HAHTTPClient sharedClient] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                if (!data) return;
                UIImage *img = [UIImage imageWithData:data];
                if (!img) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf) strongSelf.entityPictureView.image = img;
                });
            }];
        }
    } else {
        self.entityPictureView.hidden = YES;
    }

    // Color: domain+state-aware icon color from centralized helper
    UIColor *iconColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    self.tileIconLabel.textColor = iconColor;
    // State label matches icon color when entity is active, secondary otherwise
    BOOL isActive = [entity isOn] ||
                    [entity.state isEqualToString:@"open"] ||
                    [entity.state isEqualToString:@"opening"] ||
                    [entity.state isEqualToString:@"locked"] ||
                    [entity.state isEqualToString:@"playing"] ||
                    [entity.state hasPrefix:@"armed"];
    self.tileStateLabel.textColor = isActive ? iconColor : [HATheme secondaryTextColor];

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];

    // --- Tile Features ---
    // Clear previous feature views
    for (UIView *v in self.featuresStack.arrangedSubviews) {
        [self.featuresStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    self.featureViews = nil;

    // Create feature views from config (skip in compact mode)
    NSArray *featuresConfig = configItem.customProperties[@"features"];
    if (!compact && [featuresConfig isKindOfClass:[NSArray class]] && featuresConfig.count > 0) {
        NSMutableArray *views = [NSMutableArray arrayWithCapacity:featuresConfig.count];
        for (NSDictionary *featureConfig in featuresConfig) {
            if (![featureConfig isKindOfClass:[NSDictionary class]]) continue;
            HATileFeatureView *featureView = [HATileFeatureFactory featureViewForConfig:featureConfig entity:entity];
            if (featureView) {
                featureView.serviceCallBlock = ^(NSString *service, NSString *domain, NSDictionary *data) {
                    [[HAConnectionManager sharedManager] callService:service
                                                            inDomain:domain
                                                            withData:data
                                                            entityId:entity.entityId];
                };
                [self.featuresStack addArrangedSubview:featureView];
                [views addObject:featureView];
            }
        }
        if (views.count > 0) {
            self.featureViews = [views copy];
            self.featuresStack.hidden = NO;
        } else {
            self.featuresStack.hidden = YES;
        }
    } else {
        self.featuresStack.hidden = YES;
    }
}

- (void)tileLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    if (!self.entity || !self.entity.isAvailable) return;

    [HAHaptics mediumImpact];

    NSString *domain = [self.entity domain];
    NSString *service = nil;

    if ([domain isEqualToString:@"cover"]) {
        // Toggle cover: open if closed, close if open, stop if moving
        NSString *state = self.entity.state;
        if ([state isEqualToString:@"open"] || [state isEqualToString:@"opening"]) {
            service = @"close_cover";
        } else {
            service = @"open_cover";
        }
    } else if ([domain isEqualToString:@"scene"] || [domain isEqualToString:@"script"]) {
        service = @"turn_on";
    } else {
        service = @"toggle";
    }

    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:domain
                                            withData:nil
                                            entityId:self.entity.entityId];

    // Brief visual feedback
    [UIView animateWithDuration:0.15 animations:^{
        self.contentView.alpha = 0.6;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            self.contentView.alpha = 1.0;
        }];
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.tileIconLabel.text = nil;
    self.tileNameLabel.text = nil;
    self.tileStateLabel.text = nil;
    self.tileIconLabel.hidden = NO;
    self.tileNameLabel.hidden = NO;
    self.tileStateLabel.hidden = NO;
    // Force reset to normal mode — set flags to YES first so the guards
    // in apply*Mode: don't short-circuit when already NO.
    self.isVertical = YES;
    [self applyVerticalMode:NO];
    self.isCompact = YES;
    [self applyCompactMode:NO];

    // Clear entity picture
    [[HAHTTPClient sharedClient] cancelTask:self.pictureTask];
    self.pictureTask = nil;
    self.entityPictureView.hidden = YES;
    self.entityPictureView.image = nil;

    // Clear feature views
    for (UIView *v in self.featuresStack.arrangedSubviews) {
        [self.featuresStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    self.featureViews = nil;
    self.featuresStack.hidden = YES;

    self.iconTapBlock = nil;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.tileIconLabel.textColor = [HATheme primaryTextColor];
    self.tileStateLabel.textColor = [HATheme secondaryTextColor];
    self.tileNameLabel.textColor = [HATheme primaryTextColor];
}

#pragma mark - Icon Tap

- (void)iconTapped:(UITapGestureRecognizer *)gesture {
    if (self.iconTapBlock) {
        [HAHaptics lightImpact];
        self.iconTapBlock();
    }
}

/// When iconTapBlock is nil, the gesture should fail so the touch passes
/// through to the collection view's didSelectItemAtIndexPath (e.g. script buttons).
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.view == self.tileIconLabel && !self.iconTapBlock) {
        return NO; // Let the tap pass through to the collection view
    }
    return YES;
}

@end
