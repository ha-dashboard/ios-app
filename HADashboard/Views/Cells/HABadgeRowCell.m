#import "HABadgeRowCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"

// HA web badge constants (from ha-badge.ts)
static const CGFloat kBadgeHeight = 36.0;   // --ha-badge-size: 36px
static const CGFloat kBadgeIconSize = 18.0;  // --ha-badge-icon-size: 18px
static const CGFloat kBadgeHPad = 12.0;      // padding: 0px 12px
static const CGFloat kBadgeGap = 6.0;        // gap: var(--ha-space-2) ~8px but tighter for mobile
static const CGFloat kBadgeBorderWidth = 1.0; // border-width: 1px

// Arc gauge constants
static const CGFloat kArcDiameter = 54.0;
static const CGFloat kArcLineWidth = 4.0;
static const CGFloat kArcBadgeWidth = 68.0;
static const CGFloat kArcBadgeHeight = 78.0;  // circle + name label below
static const CGFloat kArcSpacing = 8.0;
static const CGFloat kArcPadding = 10.0;
static const CGFloat kArcNameLabelHeight = 16.0;

@interface HABadgeRowCell ()
@property (nonatomic, strong) NSMutableArray<UIView *> *badgeViews;
@property (nonatomic, strong) NSMutableArray<HAEntity *> *badgeEntities;
@property (nonatomic, strong) HADashboardConfigSection *lastSection;
@property (nonatomic, strong) NSDictionary *lastEntities;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@end

@implementation HABadgeRowCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Badge container is transparent — individual badges have their own backgrounds
        self.contentView.backgroundColor = [UIColor clearColor];
        self.backgroundColor = [UIColor clearColor];
        self.badgeViews = [NSMutableArray array];
        self.badgeEntities = [NSMutableArray array];
    }
    return self;
}

#pragma mark - Height Calculation

+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count width:(CGFloat)width {
    return [self preferredHeightForEntityCount:count width:width chipStyle:NO];
}

+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count width:(CGFloat)width chipStyle:(BOOL)chipStyle {
    // All badge/chip styles now use the same HA web badge layout
    CGFloat padding = 4.0;
    CGFloat spacing = 8.0;
    // Typical badge: icon(18) + gap(6) + text(~50) + padding(16) ≈ 90pt
    CGFloat estWidth = chipStyle ? 70.0 : 90.0;
    CGFloat usableWidth = width - padding * 2;
    NSInteger perRow = MAX(1, (NSInteger)floor((usableWidth + spacing) / (estWidth + spacing)));
    NSInteger rows = (count + perRow - 1) / perRow;
    return padding * 2 + rows * kBadgeHeight + MAX(0, rows - 1) * spacing;
}

#pragma mark - Configuration

- (void)configureWithSection:(HADashboardConfigSection *)section entities:(NSDictionary *)entityDict {
    self.lastSection = section;
    self.lastEntities = entityDict;

    // Clear old badges
    for (UIView *v in self.badgeViews) {
        [v removeFromSuperview];
    }
    [self.badgeViews removeAllObjects];
    [self.badgeEntities removeAllObjects];

    if (!section.entityIds || section.entityIds.count == 0) return;

    // Mushroom-chips-card and standard badge cards now use the same pill layout.
    // chipStyle flag is only used for height estimation.

    // Only use arc gauge style if explicitly requested via customProperties
    BOOL arcStyle = [section.customProperties[@"arcStyle"] boolValue];
    if (arcStyle) {
        [self configureArcGaugeStyleWithSection:section entities:entityDict];
        return;
    }

    // Default: flat pill badges (matching previous behavior)
    [self configurePillStyleWithSection:section entities:entityDict];
    self.lastLayoutWidth = self.contentView.bounds.size.width;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat currentWidth = self.contentView.bounds.size.width;
    // Re-layout badges if the cell width changed since last configure
    if (self.lastSection && currentWidth > 0 && fabs(currentWidth - self.lastLayoutWidth) > 1.0) {
        [self configureWithSection:self.lastSection entities:self.lastEntities];
    }
}

#pragma mark - Pill Badge Style (default)

- (void)configurePillStyleWithSection:(HADashboardConfigSection *)section entities:(NSDictionary *)entityDict {
    CGFloat badgeH = kBadgeHeight;
    CGFloat spacing = 8.0;
    CGFloat padding = 4.0;  // Tight container padding — badges float on background

    // Mushroom chips: icon + state only, no name label (matches HA web mushroom behavior)
    BOOL hideNames = [section.customProperties[@"chipStyle"] boolValue];

    CGFloat maxWidth = self.contentView.bounds.size.width - padding * 2;
    if (maxWidth <= 0) maxWidth = 300;

    NSMutableArray<UIView *> *allBadges = [NSMutableArray array];
    NSMutableArray<NSNumber *> *badgeWidths = [NSMutableArray array];

    for (NSString *entityId in section.entityIds) {
        HAEntity *entity = entityDict[entityId];
        if (!entity) continue;

        [self.badgeEntities addObject:entity];

        NSString *nameOverride = section.nameOverrides[entityId];
        // HA web: label = name (shown above state), content = state value
        // When both show_name and show_state are true, label is the name
        NSString *name = nil;
        if (!hideNames) {
            name = [HAEntityDisplayHelper displayNameForEntity:entity entityId:entityId section:section];
            if (nameOverride.length > 0) name = nameOverride;
        }
        NSString *valueText = [HAEntityDisplayHelper stateWithUnitForEntity:entity decimals:1];
        NSString *icon = [HAEntityDisplayHelper iconGlyphForEntity:entity];

        UIView *badge = [[UIView alloc] init];
        // HA web: card background + 1px border (ha-badge.ts .badge styles)
        badge.backgroundColor = [HATheme cellBackgroundColor];
        badge.layer.cornerRadius = badgeH / 2.0;
        badge.layer.borderWidth = kBadgeBorderWidth;
        badge.layer.borderColor = [self resolvedBorderColor];
        badge.clipsToBounds = YES;

        // Icon on the left
        UILabel *iconLabel = [[UILabel alloc] init];
        iconLabel.text = icon ?: @"";
        iconLabel.font = [HAIconMapper mdiFontOfSize:kBadgeIconSize];
        iconLabel.textColor = [HAEntityDisplayHelper iconColorForEntity:entity];
        iconLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.text = valueText;
        valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        valueLabel.textColor = [HATheme primaryTextColor];
        valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [badge addSubview:iconLabel];
        [badge addSubview:valueLabel];

        CGFloat nameWidth = 0;
        if (name.length > 0) {
            // Info column: label (name) on top, content (state) below
            UILabel *nameLabel = [[UILabel alloc] init];
            nameLabel.text = name;
            nameLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
            nameLabel.textColor = [HATheme secondaryTextColor];
            nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [badge addSubview:nameLabel];

            [NSLayoutConstraint activateConstraints:@[
                [iconLabel.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:kBadgeHPad - 4],
                [iconLabel.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
                [nameLabel.leadingAnchor constraintEqualToAnchor:iconLabel.trailingAnchor constant:kBadgeGap],
                [nameLabel.bottomAnchor constraintEqualToAnchor:badge.centerYAnchor constant:-1],
                [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:badge.trailingAnchor constant:-kBadgeHPad],
                [valueLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
                [valueLabel.topAnchor constraintEqualToAnchor:badge.centerYAnchor constant:1],
                [valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:badge.trailingAnchor constant:-kBadgeHPad],
            ]];
            nameWidth = ceil([name sizeWithAttributes:@{NSFontAttributeName: nameLabel.font}].width);
        } else {
            // No name: icon + value centered on single line (chip style)
            [NSLayoutConstraint activateConstraints:@[
                [iconLabel.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:kBadgeHPad - 4],
                [iconLabel.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
                [valueLabel.leadingAnchor constraintEqualToAnchor:iconLabel.trailingAnchor constant:kBadgeGap],
                [valueLabel.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
                [valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:badge.trailingAnchor constant:-kBadgeHPad],
            ]];
        }

        // Measure badge width (ceil + 4pt buffer prevents truncation from rounding)
        CGFloat valWidth = ceil([valueText sizeWithAttributes:@{NSFontAttributeName: valueLabel.font}].width);
        CGFloat iconW = icon.length > 0 ? kBadgeIconSize : 0;
        CGFloat infoWidth = MAX(nameWidth, valWidth) + 4.0;
        CGFloat badgeWidth = (kBadgeHPad - 4) + iconW + kBadgeGap + infoWidth + kBadgeHPad;
        badgeWidth = MAX(badgeWidth, badgeH); // Minimum: square
        badgeWidth = MIN(badgeWidth, maxWidth);

        [allBadges addObject:badge];
        [badgeWidths addObject:@(badgeWidth)];
    }

    // Layout badges in rows, centered
    CGFloat y = padding;
    NSInteger idx = 0;
    NSInteger total = allBadges.count;

    while (idx < total) {
        CGFloat rowWidth = 0;
        NSInteger rowStart = idx;
        while (idx < total) {
            CGFloat w = [badgeWidths[idx] floatValue];
            CGFloat needed = (idx == rowStart) ? w : rowWidth + spacing + w;
            if (needed > maxWidth && idx > rowStart) break;
            rowWidth = needed;
            idx++;
        }
        NSInteger rowCount = idx - rowStart;

        CGFloat totalBadgeWidth = 0;
        for (NSInteger j = rowStart; j < idx; j++) {
            totalBadgeWidth += [badgeWidths[j] floatValue];
        }
        CGFloat rowContentWidth = totalBadgeWidth + (rowCount - 1) * spacing;
        CGFloat x = padding + (maxWidth - rowContentWidth) / 2.0;

        for (NSInteger j = rowStart; j < idx; j++) {
            CGFloat w = [badgeWidths[j] floatValue];
            UIView *badge = allBadges[j];
            badge.frame = CGRectMake(x, y, w, badgeH);
            badge.tag = j; // index into badgeEntities
            badge.userInteractionEnabled = YES;
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(badgeTapped:)];
            [badge addGestureRecognizer:tap];
            [self.contentView addSubview:badge];
            [self.badgeViews addObject:badge];
            x += w + spacing;
        }

        y += badgeH + spacing;
    }
}

#pragma mark - Arc Gauge Style

- (void)configureArcGaugeStyleWithSection:(HADashboardConfigSection *)section entities:(NSDictionary *)entityDict {
    CGFloat maxWidth = self.contentView.bounds.size.width - kArcPadding * 2;
    if (maxWidth <= 0) maxWidth = 300;

    // First pass: create all badge views
    NSMutableArray<UIView *> *allBadges = [NSMutableArray array];

    for (NSString *entityId in section.entityIds) {
        HAEntity *entity = entityDict[entityId];
        if (!entity) continue;

        [self.badgeEntities addObject:entity];

        // Determine if entity state is numeric
        NSString *stateStr = entity.state;
        BOOL isNumeric = [self isNumericString:stateStr];

        UIView *badge;
        if (isNumeric) {
            badge = [self createArcGaugeBadgeForEntity:entity entityId:entityId section:section];
        } else {
            badge = [self createPillBadgeForEntity:entity entityId:entityId section:section];
        }

        [allBadges addObject:badge];
    }

    // Second pass: layout badges in rows, centered
    CGFloat y = kArcPadding;
    NSInteger idx = 0;
    NSInteger total = allBadges.count;

    while (idx < total) {
        // Determine how many badges fit in this row
        CGFloat rowWidth = 0;
        NSInteger rowStart = idx;
        while (idx < total) {
            CGFloat w = allBadges[idx].bounds.size.width;
            CGFloat needed = (idx == rowStart) ? w : rowWidth + kArcSpacing + w;
            if (needed > maxWidth && idx > rowStart) break;
            rowWidth = needed;
            idx++;
        }
        NSInteger rowCount = idx - rowStart;

        // Calculate row content width for centering
        CGFloat totalBadgeWidth = 0;
        for (NSInteger j = rowStart; j < idx; j++) {
            totalBadgeWidth += allBadges[j].bounds.size.width;
        }
        CGFloat rowContentWidth = totalBadgeWidth + (rowCount - 1) * kArcSpacing;
        CGFloat x = kArcPadding + (maxWidth - rowContentWidth) / 2.0;

        // Find tallest badge in this row for consistent row height
        CGFloat rowHeight = 0;
        for (NSInteger j = rowStart; j < idx; j++) {
            CGFloat h = allBadges[j].bounds.size.height;
            if (h > rowHeight) rowHeight = h;
        }

        for (NSInteger j = rowStart; j < idx; j++) {
            UIView *badge = allBadges[j];
            CGFloat w = badge.bounds.size.width;
            CGFloat h = badge.bounds.size.height;
            // Vertically center shorter badges (pills) within row
            CGFloat yOffset = (rowHeight - h) / 2.0;
            badge.frame = CGRectMake(x, y + yOffset, w, h);
            badge.tag = j; // index into badgeEntities
            badge.userInteractionEnabled = YES;
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(badgeTapped:)];
            [badge addGestureRecognizer:tap];
            [self.contentView addSubview:badge];
            [self.badgeViews addObject:badge];
            x += w + kArcSpacing;
        }

        y += rowHeight + kArcSpacing;
    }
}

/// Create an arc gauge badge for a numeric entity
- (UIView *)createArcGaugeBadgeForEntity:(HAEntity *)entity entityId:(NSString *)entityId section:(HADashboardConfigSection *)section {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kArcBadgeWidth, kArcBadgeHeight)];

    // Get min/max from entity attributes or infer sensible defaults by device_class
    double minVal = 0.0;
    double maxVal = 100.0;
    NSNumber *attrMin = HAAttrNumber(entity.attributes, HAAttrMin);
    NSNumber *attrMax = HAAttrNumber(entity.attributes, HAAttrMax);
    if (attrMin) {
        minVal = [attrMin doubleValue];
    }
    if (attrMax) {
        maxVal = [attrMax doubleValue];
    }
    // If no explicit min/max, use device_class-aware defaults
    if (!attrMin && !attrMax) {
        NSString *dc = [entity deviceClass];
        if ([dc isEqualToString:@"temperature"]) {
            minVal = 0.0; maxVal = 40.0;
        } else if ([dc isEqualToString:@"humidity"] || [dc isEqualToString:@"battery"]) {
            minVal = 0.0; maxVal = 100.0;
        } else if ([dc isEqualToString:@"illuminance"]) {
            minVal = 0.0; maxVal = 1000.0;
        } else if ([dc isEqualToString:@"pressure"]) {
            minVal = 950.0; maxVal = 1050.0;
        } else if ([dc isEqualToString:@"power"]) {
            minVal = 0.0; maxVal = 3000.0;
        }
    }

    double currentValue = [entity.state doubleValue];

    // Clamp fill proportion to 0.0–1.0
    CGFloat fillProportion = 0.0;
    if (maxVal > minVal) {
        fillProportion = (CGFloat)((currentValue - minVal) / (maxVal - minVal));
    }
    fillProportion = MAX(0.0, MIN(1.0, fillProportion));

    // Determine arc color
    UIColor *arcColor = [self arcColorForEntity:entity section:section];

    // Circle center: horizontally centered in container, vertically offset to leave room for name
    CGFloat circleAreaHeight = kArcBadgeHeight - kArcNameLabelHeight;
    CGFloat centerX = kArcBadgeWidth / 2.0;
    CGFloat centerY = circleAreaHeight / 2.0;
    CGFloat radius = (kArcDiameter - kArcLineWidth) / 2.0;

    // Background track ring (full circle)
    UIBezierPath *trackPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(centerX, centerY)
                                                             radius:radius
                                                         startAngle:-M_PI_2
                                                           endAngle:3 * M_PI_2
                                                          clockwise:YES];
    CAShapeLayer *trackLayer = [CAShapeLayer layer];
    trackLayer.path = trackPath.CGPath;
    trackLayer.fillColor = [UIColor clearColor].CGColor;
    trackLayer.strokeColor = [[HATheme backgroundColor] colorWithAlphaComponent:0.5].CGColor;
    trackLayer.lineWidth = kArcLineWidth;
    trackLayer.lineCap = kCALineCapRound;
    [container.layer addSublayer:trackLayer];

    // Filled arc overlay (proportional)
    if (fillProportion > 0.001) {
        CGFloat endAngle = -M_PI_2 + fillProportion * 2 * M_PI;
        UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(centerX, centerY)
                                                               radius:radius
                                                           startAngle:-M_PI_2
                                                             endAngle:endAngle
                                                            clockwise:YES];
        CAShapeLayer *arcLayer = [CAShapeLayer layer];
        arcLayer.path = arcPath.CGPath;
        arcLayer.fillColor = [UIColor clearColor].CGColor;
        arcLayer.strokeColor = arcColor.CGColor;
        arcLayer.lineWidth = kArcLineWidth;
        arcLayer.lineCap = kCALineCapRound;
        [container.layer addSublayer:arcLayer];
    }

    // Value label centered inside the circle — show 1 decimal + unit
    NSString *stateText = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:1];
    NSString *unit = entity.unitOfMeasurement;
    // Abbreviate common units to fit inside the circle
    if ([unit isEqualToString:@"°C"] || [unit isEqualToString:@"°F"]) {
        stateText = [NSString stringWithFormat:@"%@%@", stateText, unit];
    } else if ([unit isEqualToString:@"%"]) {
        stateText = [NSString stringWithFormat:@"%@%%", stateText];
    } else if (unit.length > 0 && unit.length <= 3) {
        stateText = [NSString stringWithFormat:@"%@ %@", stateText, unit];
    }
    NSString *valueText = stateText;
    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.text = valueText;
    valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.0 weight:UIFontWeightBold];
    valueLabel.textColor = [HATheme primaryTextColor];
    valueLabel.textAlignment = NSTextAlignmentCenter;

    // Size the value label to fit the text, then center it
    CGSize valSize = [valueText sizeWithAttributes:@{NSFontAttributeName: valueLabel.font}];
    CGFloat valWidth = MIN(valSize.width + 2, kArcDiameter - kArcLineWidth * 2);
    valueLabel.frame = CGRectMake(centerX - valWidth / 2.0,
                                  centerY - valSize.height / 2.0,
                                  valWidth,
                                  valSize.height);
    valueLabel.adjustsFontSizeToFitWidth = YES;
    valueLabel.minimumScaleFactor = 0.6;
    [container addSubview:valueLabel];

    // Name label below the circle
    NSString *name = [HAEntityDisplayHelper displayNameForEntity:entity entityId:entityId section:section];
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = name;
    nameLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightRegular];
    nameLabel.textColor = [HATheme secondaryTextColor];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    nameLabel.frame = CGRectMake(0, circleAreaHeight, kArcBadgeWidth, kArcNameLabelHeight);
    [container addSubview:nameLabel];

    return container;
}

/// Determine the arc color for an entity
- (UIColor *)arcColorForEntity:(HAEntity *)entity section:(HADashboardConfigSection *)section {
    // Check for color override in section customProperties (per-entity or global)
    NSString *colorOverride = nil;
    if (section.customProperties[@"color"]) {
        colorOverride = section.customProperties[@"color"];
    }

    if (colorOverride.length > 0) {
        UIColor *parsed = [HATheme colorFromHex:colorOverride];
        if (parsed) return parsed;
    }

    // Default: use entity icon color
    return [HAEntityDisplayHelper iconColorForEntity:entity];
}

/// Create a pill badge (non-numeric fallback) — uses same HA web layout as main pill style
- (UIView *)createPillBadgeForEntity:(HAEntity *)entity entityId:(NSString *)entityId section:(HADashboardConfigSection *)section {
    NSString *nameOverride = section.nameOverrides[entityId];
    NSString *name = [HAEntityDisplayHelper displayNameForEntity:entity entityId:entityId section:section];
    if (nameOverride.length > 0) name = nameOverride;
    NSString *valueText = [HAEntityDisplayHelper stateWithUnitForEntity:entity decimals:1];
    NSString *icon = [HAEntityDisplayHelper iconGlyphForEntity:entity];

    UIView *badge = [[UIView alloc] init];
    badge.backgroundColor = [HATheme cellBackgroundColor];
    badge.layer.cornerRadius = kBadgeHeight / 2.0;
    badge.layer.borderWidth = kBadgeBorderWidth;
    badge.layer.borderColor = [self resolvedBorderColor];
    badge.clipsToBounds = YES;

    UILabel *iconLabel = [[UILabel alloc] init];
    iconLabel.text = icon ?: @"";
    iconLabel.font = [HAIconMapper mdiFontOfSize:kBadgeIconSize];
    iconLabel.textColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    iconLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = name;
    nameLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    nameLabel.textColor = [HATheme secondaryTextColor];
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.text = valueText;
    valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    valueLabel.textColor = [HATheme primaryTextColor];
    valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [badge addSubview:iconLabel];
    [badge addSubview:nameLabel];
    [badge addSubview:valueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconLabel.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:kBadgeHPad - 4],
        [iconLabel.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [nameLabel.leadingAnchor constraintEqualToAnchor:iconLabel.trailingAnchor constant:kBadgeGap],
        [nameLabel.bottomAnchor constraintEqualToAnchor:badge.centerYAnchor constant:-1],
        [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:badge.trailingAnchor constant:-kBadgeHPad],
        [valueLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [valueLabel.topAnchor constraintEqualToAnchor:badge.centerYAnchor constant:1],
        [valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:badge.trailingAnchor constant:-kBadgeHPad],
    ]];

    CGFloat nameWidth = ceil([name sizeWithAttributes:@{NSFontAttributeName: nameLabel.font}].width);
    CGFloat valWidth = ceil([valueText sizeWithAttributes:@{NSFontAttributeName: valueLabel.font}].width);
    CGFloat iconW = icon.length > 0 ? kBadgeIconSize : 0;
    CGFloat infoWidth = MAX(nameWidth, valWidth) + 4.0;
    CGFloat badgeWidth = (kBadgeHPad - 4) + iconW + kBadgeGap + infoWidth + kBadgeHPad;
    badgeWidth = MAX(badgeWidth, kBadgeHeight);
    CGFloat maxWidth = self.contentView.bounds.size.width - kArcPadding * 2;
    if (maxWidth <= 0) maxWidth = 300;
    badgeWidth = MIN(badgeWidth, maxWidth);

    badge.bounds = CGRectMake(0, 0, badgeWidth, kBadgeHeight);

    return badge;
}

#pragma mark - Helpers

/// Check if a string represents a numeric value
- (BOOL)isNumericString:(NSString *)str {
    if (!str || str.length == 0) return NO;

    // Quick reject for known non-numeric states
    if ([str isEqualToString:@"unavailable"] ||
        [str isEqualToString:@"unknown"] ||
        [str isEqualToString:@"on"] ||
        [str isEqualToString:@"off"]) {
        return NO;
    }

    NSScanner *scanner = [NSScanner scannerWithString:str];
    double value;
    return [scanner scanDouble:&value] && [scanner isAtEnd];
}

#pragma mark - Badge Tap

- (void)badgeTapped:(UITapGestureRecognizer *)gesture {
    NSInteger idx = gesture.view.tag;
    if (idx >= 0 && idx < (NSInteger)self.badgeEntities.count && self.entityTapBlock) {
        self.entityTapBlock(self.badgeEntities[idx]);
    }
}

#pragma mark - Border Color

/// Resolve cellBorderColor to a static CGColorRef using the cell's own trait collection.
/// CALayer.borderColor is a CGColorRef — it does NOT auto-update with dynamic UIColors.
/// Without explicit resolution, the dynamic color can resolve against the wrong trait
/// when badges are created off-hierarchy during entity update reconfiguration.
- (CGColorRef)resolvedBorderColor {
    UIColor *color = [HATheme cellBorderColor];
    if (@available(iOS 13.0, *)) {
        return [color resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    }
    return color.CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([previousTraitCollection hasDifferentColorAppearanceComparedToTraitCollection:self.traitCollection]) {
            CGColorRef border = [self resolvedBorderColor];
            for (UIView *badge in self.badgeViews) {
                badge.layer.borderColor = border;
            }
        }
    }
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    for (UIView *v in self.badgeViews) {
        [v removeFromSuperview];
    }
    [self.badgeViews removeAllObjects];
    [self.badgeEntities removeAllObjects];
    self.lastSection = nil;
    self.lastEntities = nil;
    self.lastLayoutWidth = 0;
}

@end
