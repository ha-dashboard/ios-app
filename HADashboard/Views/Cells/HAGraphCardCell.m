#import "HAGraphCardCell.h"
#import "HAGraphView.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHistoryManager.h"
#import "HAEntityDisplayHelper.h"
#import "HAIconMapper.h"
#import <objc/runtime.h>

/// Default color palette for multi-entity graphs (matches HA web ordering)
static NSArray<UIColor *> *sColorPalette;

@interface HAGraphCardCell ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UILabel *secondaryLabel; // Right-side values for composite cards
@property (nonatomic, strong) HAGraphView *graphView;
@property (nonatomic, strong) UILabel *statsLabel; // Min/Avg/Max below graph
@property (nonatomic, copy) NSString *currentEntityId;
@property (nonatomic, strong) NSMutableArray<NSURLSessionDataTask *> *fetchTasks;
@property (nonatomic, assign) BOOL needsHistoryLoad; // Deferred until visible
@property (nonatomic, copy) NSArray *colorThresholds; // Sorted array of {value, color}
@property (nonatomic, assign) BOOL showExtrema;
@property (nonatomic, assign) BOOL showAverage;
@property (nonatomic, assign) NSInteger hoursToShow; // 0 = default (24)
@property (nonatomic, strong) NSLayoutConstraint *graphBottomToStats;
@property (nonatomic, strong) NSLayoutConstraint *graphBottomToContent;
// Multi-entity graph support
@property (nonatomic, copy) NSArray<NSDictionary *> *graphEntities; // Array of @{@"entityId", @"color", @"label"}
// State timeline support: YES when all entities are state-based (binary_sensor, switch, etc.)
@property (nonatomic, assign) BOOL isTimelineMode;
@end

@implementation HAGraphCardCell

+ (void)initialize {
    if (self == [HAGraphCardCell class]) {
        sColorPalette = @[
            [UIColor colorWithRed:0.30 green:0.60 blue:1.00 alpha:1.0], // Blue
            [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0], // Red
            [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0], // Green
            [UIColor colorWithRed:1.00 green:0.60 blue:0.00 alpha:1.0], // Orange
            [UIColor colorWithRed:0.60 green:0.30 blue:0.90 alpha:1.0], // Purple
            [UIColor colorWithRed:0.00 green:0.80 blue:0.70 alpha:1.0], // Teal
            [UIColor colorWithRed:0.90 green:0.40 blue:0.70 alpha:1.0], // Pink
            [UIColor colorWithRed:1.00 green:0.85 blue:0.00 alpha:1.0], // Yellow
        ];
    }
}

+ (CGFloat)preferredHeight {
    return 180.0;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _fetchTasks = [NSMutableArray array];
        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.contentView.layer.cornerRadius = 12;
    self.contentView.clipsToBounds = YES;

    // Icon label (MDI glyph, top-left)
    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.font = [HAIconMapper mdiFontOfSize:18];
    self.iconLabel.textColor = [HATheme secondaryTextColor];
    self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconLabel.hidden = YES;
    [self.contentView addSubview:self.iconLabel];

    // Name label (top, after icon)
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.nameLabel.textColor = [HATheme secondaryTextColor];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    // Value label (top-left, below name)
    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightBold];
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.valueLabel];

    // Unit label (after value)
    self.unitLabel = [[UILabel alloc] init];
    self.unitLabel.font = [UIFont systemFontOfSize:14];
    self.unitLabel.textColor = [HATheme secondaryTextColor];
    self.unitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.unitLabel];

    // Secondary values label (top-right, for composite cards showing kWh, GBP, etc.)
    self.secondaryLabel = [[UILabel alloc] init];
    self.secondaryLabel.font = [UIFont systemFontOfSize:13];
    self.secondaryLabel.textColor = [HATheme secondaryTextColor];
    self.secondaryLabel.textAlignment = NSTextAlignmentRight;
    self.secondaryLabel.numberOfLines = 0;
    self.secondaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.secondaryLabel.hidden = YES;
    [self.contentView addSubview:self.secondaryLabel];

    // Graph view (middle area)
    self.graphView = [[HAGraphView alloc] init];
    self.graphView.translatesAutoresizingMaskIntoConstraints = NO;
    self.graphView.showAxisLabels = YES;
    [self.contentView addSubview:self.graphView];

    // Stats label (below graph: Min / Avg / Max)
    self.statsLabel = [[UILabel alloc] init];
    self.statsLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.statsLabel.textColor = [HATheme secondaryTextColor];
    self.statsLabel.textAlignment = NSTextAlignmentCenter;
    self.statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statsLabel.hidden = YES;
    [self.contentView addSubview:self.statsLabel];

    CGFloat pad = 12;
    // Icon constraints (fixed width, vertically centered with name)
    NSLayoutConstraint *iconLeading = [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad];
    NSLayoutConstraint *iconCenterY = [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.nameLabel.centerYAnchor];
    NSLayoutConstraint *iconWidth = [self.iconLabel.widthAnchor constraintEqualToConstant:22];

    // Name label: leading anchored to icon when visible, to content edge when not
    // We use two constraints and toggle active state
    NSLayoutConstraint *nameLeadingToIcon = [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:4];
    NSLayoutConstraint *nameLeadingToEdge = [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad];
    // Start with nameLeadingToEdge active (icon hidden by default)
    nameLeadingToEdge.active = YES;
    nameLeadingToIcon.active = NO;
    // Store for later toggling
    objc_setAssociatedObject(self, "nameLeadingToIcon", nameLeadingToIcon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "nameLeadingToEdge", nameLeadingToEdge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Graph bottom: either to stats or to content bottom
    self.graphBottomToStats = [self.graphView.bottomAnchor constraintEqualToAnchor:self.statsLabel.topAnchor constant:-2];
    self.graphBottomToContent = [self.graphView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor];
    self.graphBottomToContent.active = YES;
    self.graphBottomToStats.active = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.secondaryLabel.leadingAnchor constant:-8],

        iconLeading, iconCenterY, iconWidth,

        [self.valueLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
        [self.valueLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],

        [self.unitLabel.leadingAnchor constraintEqualToAnchor:self.valueLabel.trailingAnchor constant:4],
        [self.unitLabel.lastBaselineAnchor constraintEqualToAnchor:self.valueLabel.lastBaselineAnchor],

        [self.secondaryLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad],
        [self.secondaryLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.secondaryLabel.widthAnchor constraintLessThanOrEqualToConstant:140],

        [self.graphView.topAnchor constraintEqualToAnchor:self.valueLabel.bottomAnchor constant:8],
        [self.graphView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.graphView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [self.statsLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.statsLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.statsLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
        [self.statsLabel.heightAnchor constraintEqualToConstant:16],
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (NSURLSessionDataTask *task in self.fetchTasks) {
        [task cancel];
    }
    [self.fetchTasks removeAllObjects];
    self.nameLabel.text = nil;
    self.valueLabel.text = nil;
    self.unitLabel.text = nil;
    self.graphView.dataPoints = nil;
    self.graphView.dataSeries = nil;
    self.graphView.timelineData = nil;
    self.currentEntityId = nil;
    self.graphEntities = nil;
    self.isTimelineMode = NO;
    self.secondaryLabel.text = nil;
    self.secondaryLabel.hidden = YES;
    self.iconLabel.text = nil;
    self.iconLabel.hidden = YES;
    self.statsLabel.text = nil;
    self.statsLabel.hidden = YES;
    self.colorThresholds = nil;
    self.showExtrema = NO;
    self.showAverage = NO;
    self.hoursToShow = 0;

    // Reset icon layout
    NSLayoutConstraint *toIcon = objc_getAssociatedObject(self, "nameLeadingToIcon");
    NSLayoutConstraint *toEdge = objc_getAssociatedObject(self, "nameLeadingToEdge");
    toIcon.active = NO;
    toEdge.active = YES;

    // Reset graph bottom
    self.graphBottomToStats.active = NO;
    self.graphBottomToContent.active = YES;

    // Refresh theme colors (static on iOS 9-12)
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.nameLabel.textColor = [HATheme secondaryTextColor];
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.unitLabel.textColor = [HATheme secondaryTextColor];
    self.iconLabel.textColor = [HATheme secondaryTextColor];
    self.secondaryLabel.textColor = [HATheme secondaryTextColor];
    self.statsLabel.textColor = [HATheme secondaryTextColor];
}

- (void)configureWithEntity:(HAEntity *)entity item:(HADashboardConfigItem *)item {
    if (!entity) return;
    self.currentEntityId = entity.entityId;

    self.nameLabel.text = [HAEntityDisplayHelper displayNameForEntity:entity configItem:item nameOverride:nil];

    // Detect timeline mode for single state-based entity
    self.isTimelineMode = [HAGraphCardCell isStateBasedDomain:entity.entityId];

    if (self.isTimelineMode) {
        // For timeline entities, wrap single entity into graphEntities for unified loading
        self.valueLabel.text = nil;
        self.unitLabel.text = nil;
        self.graphEntities = @[@{
            @"entityId": entity.entityId,
            @"color": sColorPalette[0],
            @"label": entity.friendlyName ?: entity.entityId,
            @"unit": @"",
        }];
    } else {
        // Current value + unit
        NSString *state = entity.state;
        NSString *unit = entity.unitOfMeasurement;
        self.valueLabel.text = state;
        self.unitLabel.text = unit;

        // Set graph color based on entity type
        [self applyDefaultColorForUnit:unit];
    }

    // Defer history fetch until cell is visible (beginLoading)
    self.needsHistoryLoad = YES;
}

- (void)configureWithSection:(HADashboardConfigSection *)section entities:(NSDictionary *)allEntities {
    if (!section || section.entityIds.count == 0) return;

    NSDictionary *props = section.customProperties;
    NSArray *entityConfigs = props[@"entityConfigs"];

    // Parse display config: which entities show graph, which show state only
    NSMutableArray *graphEntityIds = [NSMutableArray array];
    NSMutableArray *stateOnlyEntityIds = [NSMutableArray array];
    NSMutableArray *graphEntityInfos = [NSMutableArray array]; // For multi-series

    for (NSUInteger i = 0; i < section.entityIds.count; i++) {
        NSString *eid = section.entityIds[i];
        NSDictionary *cfg = (i < entityConfigs.count) ? entityConfigs[i] : nil;

        BOOL showGraph = YES; // default: show graph
        BOOL showState = NO;  // default: don't show state as secondary text
        if (cfg) {
            if (cfg[@"show_graph"]) showGraph = [cfg[@"show_graph"] boolValue];
            if (cfg[@"show_state"]) showState = [cfg[@"show_state"] boolValue];
        }

        if (showGraph) {
            [graphEntityIds addObject:eid];

            // Determine color for this entity
            UIColor *color = nil;
            NSString *colorStr = cfg[@"color"];
            if (colorStr) {
                color = [HATheme colorFromString:colorStr];
            }
            if (!color) {
                // Auto-assign from palette
                NSUInteger paletteIdx = graphEntityInfos.count % sColorPalette.count;
                color = sColorPalette[paletteIdx];
            }

            // Determine label for this entity
            HAEntity *entity = allEntities[eid];
            NSString *label = [cfg[@"name"] isKindOfClass:[NSString class]] ? cfg[@"name"] : (section.nameOverrides[eid] ?: entity.friendlyName ?: eid);
            NSString *unit = entity.unitOfMeasurement ?: @"";

            [graphEntityInfos addObject:@{
                @"entityId": eid,
                @"color": color,
                @"label": label,
                @"unit": unit,
            }];
        }
        if (showState && i > 0) {
            [stateOnlyEntityIds addObject:eid];
        }
    }

    // If no entity has show_graph=YES, default to first entity
    if (graphEntityIds.count == 0 && section.entityIds.count > 0) {
        NSString *eid = section.entityIds.firstObject;
        [graphEntityIds addObject:eid];
        HAEntity *entity = allEntities[eid];
        NSString *unit = entity.unitOfMeasurement ?: @"";
        [graphEntityInfos addObject:@{
            @"entityId": eid,
            @"color": sColorPalette[0],
            @"label": entity.friendlyName ?: eid,
            @"unit": unit,
        }];
    }

    // Store multi-entity info for deferred loading
    self.graphEntities = [graphEntityInfos copy];

    // Detect timeline mode: if ALL graph entities are state-based, use timeline bars
    BOOL allStateBased = (graphEntityIds.count > 0);
    for (NSString *eid in graphEntityIds) {
        if (![HAGraphCardCell isStateBasedDomain:eid]) {
            allStateBased = NO;
            break;
        }
    }
    self.isTimelineMode = allStateBased;

    // Primary entity — first graph entity
    NSString *primaryId = graphEntityIds.firstObject;
    HAEntity *primary = allEntities[primaryId];
    self.currentEntityId = primaryId;

    // Icon from card config
    NSString *iconName = props[@"graphIcon"];
    if (iconName.length > 0) {
        NSString *glyph = [HAIconMapper glyphForIconName:iconName];
        if (glyph) {
            self.iconLabel.text = glyph;
            self.iconLabel.hidden = NO;
            // Switch name label leading to icon
            NSLayoutConstraint *toIcon = objc_getAssociatedObject(self, "nameLeadingToIcon");
            NSLayoutConstraint *toEdge = objc_getAssociatedObject(self, "nameLeadingToEdge");
            toEdge.active = NO;
            toIcon.active = YES;
        }
    }

    // Name from section title or primary entity
    self.nameLabel.text = section.title ?: primary.friendlyName ?: primaryId;

    // Primary value — hide for timeline mode (state shown in bars)
    if (primary && !self.isTimelineMode) {
        self.valueLabel.text = primary.state;
        self.unitLabel.text = primary.unitOfMeasurement;
    } else if (self.isTimelineMode) {
        self.valueLabel.text = nil;
        self.unitLabel.text = nil;
    }

    // Color thresholds (only apply for single-entity graphs)
    NSArray *thresholds = props[@"color_thresholds"];
    if ([thresholds isKindOfClass:[NSArray class]] && thresholds.count > 0) {
        // Sort thresholds by value ascending
        self.colorThresholds = [thresholds sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [@([a[@"value"] doubleValue]) compare:@([b[@"value"] doubleValue])];
        }];
        // Apply threshold color for current value (single-entity only)
        if (primary && graphEntityIds.count == 1) {
            UIColor *color = [self colorForValue:[primary.state doubleValue]];
            self.graphView.lineColor = color;
        }
    } else if (graphEntityIds.count == 1) {
        // Default color based on unit (single-entity only)
        [self applyDefaultColorForUnit:primary.unitOfMeasurement ?: @""];
    }

    // Hours to show (history-graph cards may specify 72h, 168h, etc.)
    NSNumber *hours = props[@"hours_to_show"];
    if ([hours isKindOfClass:[NSNumber class]] && [hours integerValue] > 0) {
        self.hoursToShow = [hours integerValue];
    }

    // Show config: extrema, average
    NSDictionary *showConfig = props[@"show"];
    if ([showConfig isKindOfClass:[NSDictionary class]]) {
        self.showExtrema = [showConfig[@"extrema"] boolValue];
        self.showAverage = [showConfig[@"average"] boolValue];
    }
    // Show stats bar if extrema or average is enabled (primary entity only)
    if (self.showExtrema || self.showAverage) {
        self.statsLabel.hidden = NO;
        self.graphBottomToContent.active = NO;
        self.graphBottomToStats.active = YES;
    }

    // Secondary entities — show value + unit on the right, one per line
    // Only for entities NOT graphed (show_state only)
    NSArray *secondaryIds = stateOnlyEntityIds.count > 0 ? stateOnlyEntityIds : nil;
    // If multi-entity graph, don't show secondary values for graphed entities
    if (!secondaryIds && graphEntityIds.count <= 1 && section.entityIds.count > 1) {
        NSMutableArray *fallback = [NSMutableArray array];
        for (NSUInteger i = 1; i < section.entityIds.count; i++) {
            [fallback addObject:section.entityIds[i]];
        }
        secondaryIds = fallback;
    }
    if (secondaryIds.count > 0) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *eid in secondaryIds) {
            HAEntity *ent = allEntities[eid];
            if (!ent) continue;
            NSString *stateStr = [HAEntityDisplayHelper stateWithUnitForEntity:ent decimals:2];
            [lines addObject:stateStr];
        }
        if (lines.count > 0) {
            self.secondaryLabel.text = [lines componentsJoinedByString:@"\n"];
            self.secondaryLabel.hidden = NO;
        }
    }

    // Defer history fetch until cell is visible (beginLoading)
    self.needsHistoryLoad = YES;
}

#pragma mark - Color Helpers

- (void)applyDefaultColorForUnit:(NSString *)unit {
    if ([unit containsString:@"W"] || [unit containsString:@"kWh"]) {
        self.graphView.lineColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.2 alpha:1.0]; // Orange-red
    } else if ([unit containsString:@"°"] || [unit containsString:@"C"] || [unit containsString:@"F"]) {
        self.graphView.lineColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.7 alpha:1.0]; // Teal
    } else {
        self.graphView.lineColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0]; // Blue
    }
}

- (UIColor *)colorForValue:(double)value {
    if (!self.colorThresholds || self.colorThresholds.count == 0) {
        return self.graphView.lineColor;
    }
    // Find the highest threshold whose value <= the current value
    UIColor *result = nil;
    for (NSDictionary *threshold in self.colorThresholds) {
        double tv = [threshold[@"value"] doubleValue];
        if (value >= tv) {
            result = [HATheme colorFromString:threshold[@"color"]];
        } else {
            break;
        }
    }
    return result ?: self.graphView.lineColor;
}

#pragma mark - State-based Entity Detection

/// Returns YES if the entity domain is state-based (binary states, not numeric sensor data)
+ (BOOL)isStateBasedDomain:(NSString *)entityId {
    if (!entityId) return NO;
    NSRange dot = [entityId rangeOfString:@"."];
    if (dot.location == NSNotFound) return NO;
    NSString *domain = [entityId substringToIndex:dot.location];

    static NSSet *stateBasedDomains = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stateBasedDomains = [NSSet setWithArray:@[
            @"binary_sensor",
            @"switch",
            @"input_boolean",
            @"light",
            @"fan",
            @"automation",
            @"script",
            @"person",
            @"device_tracker",
            @"lock",
            @"cover",
            @"alarm_control_panel",
            @"vacuum",
            @"media_player",
            @"siren",
            @"update",
            @"scene",
        ]];
    });

    return [stateBasedDomains containsObject:domain];
}

#pragma mark - Deferred Loading

- (void)beginLoading {
    if (self.needsHistoryLoad && self.currentEntityId) {
        self.needsHistoryLoad = NO;
        if (self.graphEntities.count > 1 || self.isTimelineMode) {
            [self loadHistoryForMultipleEntities];
        } else {
            [self loadHistoryForEntityId:self.currentEntityId];
        }
    }
}

- (void)cancelLoading {
    for (NSURLSessionDataTask *task in self.fetchTasks) {
        [task cancel];
    }
    [self.fetchTasks removeAllObjects];
}

#pragma mark - History Fetch (Single Entity)

- (void)loadHistoryForEntityId:(NSString *)entityId {
    NSInteger hours = self.hoursToShow > 0 ? self.hoursToShow : 24;

    __weak typeof(self) weakSelf = self;
    NSString *capturedEntityId = [entityId copy];
    [[HAHistoryManager sharedManager] fetchHistoryForEntityId:entityId
                                                   hoursBack:hours
                                                  completion:^(NSArray *points, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.currentEntityId isEqualToString:capturedEntityId]) return;
        if (points.count > 0) {
            strongSelf.graphView.dataPoints = points;
            [strongSelf updateStatsFromPoints:points];
        }
    }];
}

#pragma mark - History Fetch (Multiple Entities)

- (void)loadHistoryForMultipleEntities {
    NSInteger hours = self.hoursToShow > 0 ? self.hoursToShow : 24;
    NSArray *graphEntities = [self.graphEntities copy];
    NSString *capturedPrimaryId = [self.currentEntityId copy];
    BOOL capturedTimelineMode = self.isTimelineMode;

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:graphEntities.count];
    for (NSUInteger i = 0; i < graphEntities.count; i++) {
        [results addObject:[NSNull null]];
    }

    dispatch_group_t group = dispatch_group_create();
    HAHistoryManager *mgr = [HAHistoryManager sharedManager];

    for (NSUInteger i = 0; i < graphEntities.count; i++) {
        NSDictionary *info = graphEntities[i];
        NSString *entityId = info[@"entityId"];
        NSUInteger capturedIndex = i;

        dispatch_group_enter(group);
        if (capturedTimelineMode) {
            [mgr fetchTimelineForEntityId:entityId hoursBack:hours completion:^(NSArray *segments, NSError *error) {
                if (segments.count > 0) {
                    @synchronized(results) {
                        results[capturedIndex] = segments;
                    }
                }
                dispatch_group_leave(group);
            }];
        } else {
            [mgr fetchHistoryForEntityId:entityId hoursBack:hours completion:^(NSArray *points, NSError *error) {
                if (points.count > 0) {
                    @synchronized(results) {
                        results[capturedIndex] = points;
                    }
                }
                dispatch_group_leave(group);
            }];
        }
    }

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.currentEntityId isEqualToString:capturedPrimaryId]) return;

        if (capturedTimelineMode) {
            NSMutableArray *timelineEntries = [NSMutableArray array];
            for (NSUInteger i = 0; i < graphEntities.count; i++) {
                NSArray *segments = results[i];
                if (![segments isKindOfClass:[NSArray class]] || segments.count == 0) continue;

                NSDictionary *info = graphEntities[i];
                [timelineEntries addObject:@{
                    @"segments": segments,
                    @"label": info[@"label"] ?: @"",
                    @"entityId": info[@"entityId"] ?: @"",
                }];
            }

            if (timelineEntries.count > 0) {
                strongSelf.graphView.timelineData = timelineEntries;
            }
        } else {
            NSMutableArray *dataSeries = [NSMutableArray array];
            for (NSUInteger i = 0; i < graphEntities.count; i++) {
                NSArray *points = results[i];
                if (![points isKindOfClass:[NSArray class]] || points.count == 0) continue;

                NSDictionary *info = graphEntities[i];
                [dataSeries addObject:@{
                    @"points": points,
                    @"color": info[@"color"],
                    @"label": info[@"label"],
                    @"unit": info[@"unit"] ?: @"",
                }];
            }

            if (dataSeries.count > 0) {
                strongSelf.graphView.dataSeries = dataSeries;
            }

            NSArray *primaryPoints = results[0];
            if ([primaryPoints isKindOfClass:[NSArray class]]) {
                [strongSelf updateStatsFromPoints:primaryPoints];
            }
        }
    });
}

#pragma mark - Stats

- (void)updateStatsFromPoints:(NSArray *)points {
    if ((!self.showExtrema && !self.showAverage) || points.count == 0) return;

    double minVal = HUGE_VAL, maxVal = -HUGE_VAL, sum = 0;
    for (NSDictionary *pt in points) {
        double v = [pt[@"value"] doubleValue];
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
        sum += v;
    }
    double avg = sum / points.count;

    NSMutableArray *parts = [NSMutableArray array];
    if (self.showExtrema) {
        [parts addObject:[NSString stringWithFormat:@"Min: %.1f", minVal]];
    }
    if (self.showAverage) {
        [parts addObject:[NSString stringWithFormat:@"Avg: %.1f", avg]];
    }
    if (self.showExtrema) {
        [parts addObject:[NSString stringWithFormat:@"Max: %.1f", maxVal]];
    }

    self.statsLabel.text = [parts componentsJoinedByString:@"  \u2022  "];
    self.statsLabel.hidden = NO;

    // Apply threshold color to icon based on current value (last point)
    if (self.colorThresholds.count > 0 && points.count > 0) {
        double lastValue = [[points.lastObject valueForKey:@"value"] doubleValue];
        UIColor *thresholdColor = [self colorForValue:lastValue];
        self.iconLabel.textColor = thresholdColor;
    }
}

@end
