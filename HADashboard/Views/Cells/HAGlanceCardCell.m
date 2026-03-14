#import "HAAutoLayout.h"
#import "HAGlanceCardCell.h"
#import "HAGlanceItemView.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "UIFont+HACompat.h"

static const CGFloat kTitleHeight = 28.0;
static const CGFloat kTitleFontSize = 14.0;
static const CGFloat kCardPadding = 8.0;
static const CGFloat kRowSpacing = 4.0;
static const CGFloat kMinColumnWidth = 70.0; // auto column calculation threshold

@interface HAGlanceCardCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSMutableArray<HAGlanceItemView *> *itemViews;
@property (nonatomic, strong) UIView *gridContainer;
@end

@implementation HAGlanceCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
        self.contentView.layer.cornerRadius = 12.0;
        self.contentView.clipsToBounds = YES;
        self.itemViews = [NSMutableArray array];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont ha_systemFontOfSize:kTitleFontSize weight:HAFontWeightSemibold];
        self.titleLabel.textColor = [HATheme primaryTextColor];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.hidden = YES;
        [self.contentView addSubview:self.titleLabel];

        HAActivateConstraints(@[
            HACon([self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kCardPadding]),
            HACon([self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12]),
            HACon([self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12]),
        ]);

        self.gridContainer = [[UIView alloc] init];
        self.gridContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.gridContainer];

        HAActivateConstraints(@[
            HACon([self.gridContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor]),
            HACon([self.gridContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]),
            HACon([self.gridContainer.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor]),
        ]);
    }
    return self;
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary<NSString *, HAEntity *> *)allEntities
                  configItem:(HADashboardConfigItem *)configItem {
    NSDictionary *props = configItem.customProperties;

    // Title
    NSString *title = props[@"glance_title"];
    if ([title isKindOfClass:[NSString class]] && title.length > 0) {
        self.titleLabel.text = title;
        self.titleLabel.hidden = NO;
    } else {
        self.titleLabel.hidden = YES;
    }

    // Card-level visibility flags (defaults per HA docs)
    BOOL showName  = props[@"show_name"]  ? [props[@"show_name"] boolValue]  : YES;
    BOOL showState = props[@"show_state"] ? [props[@"show_state"] boolValue] : YES;
    BOOL showIcon  = props[@"show_icon"]  ? [props[@"show_icon"] boolValue]  : YES;
    BOOL stateColor = props[@"state_color"] ? [props[@"state_color"] boolValue] : YES;

    // Entity configs (per-entity overrides from card YAML)
    NSArray *entityConfigs = props[@"entityConfigs"];

    // Columns
    NSArray *entityIds = section.entityIds;
    NSInteger entityCount = (NSInteger)entityIds.count;
    NSInteger columns = [self columnsForProps:props entityCount:entityCount width:self.contentView.bounds.size.width];
    NSInteger rows = entityCount > 0 ? (entityCount + columns - 1) / columns : 0;

    // Clear old item views
    for (HAGlanceItemView *iv in self.itemViews) {
        [iv removeFromSuperview];
    }
    [self.itemViews removeAllObjects];

    // Grid container top constraint depends on title
    BOOL hasTitle = !self.titleLabel.hidden;
    // Remove old top constraint and re-add
    for (NSLayoutConstraint *c in self.contentView.constraints) {
        if (c.firstItem == self.gridContainer && c.firstAttribute == NSLayoutAttributeTop) {
            c.active = NO;
        }
    }
    if (hasTitle) {
        HASetConstraintActive([self.titleLabel.bottomAnchor constraintEqualToAnchor:self.gridContainer.topAnchor constant:-4], YES);
    } else {
        HASetConstraintActive([self.gridContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kCardPadding], YES);
    }

    // Create and layout item views
    CGFloat containerWidth = self.contentView.bounds.size.width;
    if (containerWidth <= 0) containerWidth = 300; // fallback
    CGFloat columnWidth = containerWidth / (CGFloat)columns;
    CGFloat itemHeight = [HAGlanceItemView preferredHeightShowingName:showName showState:showState showIcon:showIcon];

    for (NSInteger i = 0; i < entityCount; i++) {
        NSString *entityId = entityIds[i];
        HAEntity *entity = allEntities[entityId];

        // Per-entity config
        NSDictionary *entityConfig = nil;
        if (i < (NSInteger)entityConfigs.count && [entityConfigs[i] isKindOfClass:[NSDictionary class]]) {
            entityConfig = entityConfigs[i];
        }

        HAGlanceItemView *itemView = [[HAGlanceItemView alloc] initWithFrame:CGRectZero];
        [itemView configureWithEntity:entity
                         entityConfig:entityConfig ?: @{}
                             showName:showName
                            showState:showState
                             showIcon:showIcon
                           stateColor:stateColor];

        NSInteger col = i % columns;
        NSInteger row = i / columns;
        itemView.frame = CGRectMake(col * columnWidth, row * (itemHeight + kRowSpacing),
                                    columnWidth, itemHeight);
        itemView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        // Tap gesture
        itemView.tag = i;
        itemView.userInteractionEnabled = YES;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(itemTapped:)];
        [itemView addGestureRecognizer:tap];

        [self.gridContainer addSubview:itemView];
        [self.itemViews addObject:itemView];
    }
}

- (void)itemTapped:(UITapGestureRecognizer *)gesture {
    NSInteger idx = gesture.view.tag;
    if (idx >= 0 && idx < (NSInteger)self.itemViews.count) {
        HAGlanceItemView *itemView = self.itemViews[idx];
        if (itemView.entity && self.entityTapBlock) {
            self.entityTapBlock(itemView.entity, itemView.actionConfig);
        }
    }
}

- (NSInteger)columnsForProps:(NSDictionary *)props entityCount:(NSInteger)count width:(CGFloat)width {
    // Explicit columns config
    NSNumber *configColumns = props[@"columns"];
    if ([configColumns isKindOfClass:[NSNumber class]]) {
        NSInteger cols = [configColumns integerValue];
        if (cols > 0) return cols;
    }
    // Auto: min(entityCount, 5) — matches HA frontend's hardcoded max of 5
    if (count <= 0) return 1;
    return MIN(count, 5);
}

+ (CGFloat)preferredHeightForSection:(HADashboardConfigSection *)section
                               width:(CGFloat)width
                          configItem:(HADashboardConfigItem *)configItem {
    NSDictionary *props = configItem.customProperties;

    BOOL showName  = props[@"show_name"]  ? [props[@"show_name"] boolValue]  : YES;
    BOOL showState = props[@"show_state"] ? [props[@"show_state"] boolValue] : YES;
    BOOL showIcon  = props[@"show_icon"]  ? [props[@"show_icon"] boolValue]  : YES;

    NSInteger entityCount = (NSInteger)section.entityIds.count;
    if (entityCount == 0) return kCardPadding * 2;

    // Columns
    NSInteger columns;
    NSNumber *configColumns = props[@"columns"];
    if ([configColumns isKindOfClass:[NSNumber class]] && [configColumns integerValue] > 0) {
        columns = [configColumns integerValue];
    } else {
        columns = MIN(entityCount, 5);
    }

    NSInteger rows = (entityCount + columns - 1) / columns;
    CGFloat itemHeight = [HAGlanceItemView preferredHeightShowingName:showName showState:showState showIcon:showIcon];

    BOOL hasTitle = [props[@"glance_title"] isKindOfClass:[NSString class]] && [props[@"glance_title"] length] > 0;
    CGFloat titleExtra = hasTitle ? kTitleHeight : 0;

    return titleExtra + kCardPadding + rows * itemHeight + MAX(0, rows - 1) * kRowSpacing + kCardPadding;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;

        // Title label: top
        if (!self.titleLabel.hidden) {
            CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(w - 24, CGFLOAT_MAX)];
            self.titleLabel.frame = CGRectMake(12, kCardPadding, w - 24, titleSize.height);
        }

        // Grid container: below title or at top
        CGFloat gridY = self.titleLabel.hidden ? kCardPadding : CGRectGetMaxY(self.titleLabel.frame) + 4;
        self.gridContainer.frame = CGRectMake(0, gridY, w, self.contentView.bounds.size.height - gridY);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (HAGlanceItemView *iv in self.itemViews) {
        [iv removeFromSuperview];
    }
    [self.itemViews removeAllObjects];
    self.titleLabel.text = nil;
    self.titleLabel.hidden = YES;
    self.entityTapBlock = nil;
}

@end
