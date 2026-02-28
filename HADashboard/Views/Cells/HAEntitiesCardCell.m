#import "HAEntitiesCardCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HAEntityRowView.h"
#import "HAIconMapper.h"
#import "HATheme.h"
#import "HAConnectionManager.h"
#import "HAHaptics.h"

static const CGFloat kHeadingHeight = 28.0;
static const CGFloat kHeadingGap    = 2.0;

static const CGFloat kSceneChipHeight = 32.0;
static const CGFloat kSceneChipSpacing = 8.0;
static const CGFloat kSceneChipRowHeight = 44.0; // chip height + padding

@interface HAEntitiesCardCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *headingLabel;
@property (nonatomic, strong) UISwitch *headerToggle;
@property (nonatomic, strong) NSMutableArray<HAEntityRowView *> *rowViews;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) NSLayoutConstraint *stackTopWithTitle;
@property (nonatomic, strong) NSLayoutConstraint *stackTopNoTitle;
@property (nonatomic, strong) NSLayoutConstraint *stackTopWithToggle;
@property (nonatomic, assign) BOOL showsHeading;
@property (nonatomic, copy) NSArray<NSString *> *toggleEntityIds;
@property (nonatomic, strong) UIScrollView *sceneChipScrollView;
@property (nonatomic, strong) NSLayoutConstraint *chipScrollHeight;
@end

@implementation HAEntitiesCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSubviews];
        // Tap gesture to detect which entity row was tapped.
        // Added to the cell (not contentView) so it fires alongside collection view selection.
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cellTapped:)];
        tap.cancelsTouchesInView = NO;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)cellTapped:(UITapGestureRecognizer *)gesture {
    if (!self.entityTapBlock) return;
    CGPoint point = [gesture locationInView:self.stackView];
    for (HAEntityRowView *row in self.rowViews) {
        if (CGRectContainsPoint(row.frame, point) && row.entity) {
            self.entityTapBlock(row.entity);
            return;
        }
    }
}

- (void)setupSubviews {
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.contentView.layer.cornerRadius = 14.0;
    self.contentView.layer.masksToBounds = YES;

    // Heading label (above contentView, for grid headings like "Lights")
    self.headingLabel = [[UILabel alloc] init];
    self.headingLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.headingLabel.textColor = [HATheme sectionHeaderColor];
    self.headingLabel.numberOfLines = 1;
    self.headingLabel.hidden = YES;
    [self addSubview:self.headingLabel]; // on cell itself, not contentView

    // Title label (optional, inside the card)
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.titleLabel.textColor = [HATheme secondaryTextColor];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.titleLabel];

    // Header toggle switch (HA web show_header_toggle, also auto-shown for all-toggleable cards)
    self.headerToggle = [[UISwitch alloc] init];
    self.headerToggle.transform = CGAffineTransformMakeScale(0.7, 0.7);
    self.headerToggle.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerToggle.hidden = YES;
    [self.headerToggle addTarget:self action:@selector(headerToggleTapped:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.headerToggle];

    // Position at top-right of card — works with or without title
    [NSLayoutConstraint activateConstraints:@[
        [self.headerToggle.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
        [self.headerToggle.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
    ]];

    // Stack view for entity rows
    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.distribution = UIStackViewDistributionFill;
    self.stackView.alignment = UIStackViewAlignmentFill;
    self.stackView.spacing = 0;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.stackView];

    // Initialize row views array
    self.rowViews = [NSMutableArray array];

    // Layout constraints
    // Title label: 12pt padding from top and sides
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12]
    ]];

    // Stack view: below title (when shown) or at contentView top (no title).
    self.stackTopWithTitle = [self.stackView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4];
    self.stackTopNoTitle = [self.stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0];
    self.stackTopWithToggle = [self.stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:36];
    self.stackTopWithTitle.active = NO;
    self.stackTopWithToggle.active = NO;
    self.stackTopNoTitle.active = YES; // default: no title

    // Scene chips scroll view (below entity rows)
    self.sceneChipScrollView = [[UIScrollView alloc] init];
    self.sceneChipScrollView.showsHorizontalScrollIndicator = NO;
    self.sceneChipScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sceneChipScrollView.hidden = YES;
    [self.contentView addSubview:self.sceneChipScrollView];

    self.chipScrollHeight = [self.sceneChipScrollView.heightAnchor constraintEqualToConstant:0];

    // Layout chain: stack → chipScroll → contentView bottom
    // Bottom constraint uses high priority (not required) to avoid conflicts
    // with the cell frame height set by HAColumnarLayout.
    NSLayoutConstraint *bottom = [self.sceneChipScrollView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:0];
    bottom.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [self.sceneChipScrollView.topAnchor constraintEqualToAnchor:self.stackView.bottomAnchor],
        [self.sceneChipScrollView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.sceneChipScrollView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        self.chipScrollHeight,
        bottom,
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.showsHeading) {
        CGFloat headingH = kHeadingHeight + kHeadingGap;
        self.headingLabel.frame = CGRectMake(4, 0, self.bounds.size.width - 8, kHeadingHeight);
        self.contentView.frame = CGRectMake(0, headingH,
            self.bounds.size.width, self.bounds.size.height - headingH);
    } else {
        self.contentView.frame = self.bounds;
    }

    // Sync backgroundView (blur) with contentView frame so it doesn't cover headings.
    if (self.backgroundView) {
        self.backgroundView.frame = self.contentView.frame;
    }
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary *)entityDict
                  configItem:(HADashboardConfigItem *)configItem {
    // Configure heading (above card, from grid heading)
    NSString *headingIcon = configItem.customProperties[@"headingIcon"];
    BOOL hasHeading = (configItem.displayName.length > 0 && headingIcon != nil);

    if (hasHeading) {
        NSString *iconName = headingIcon;
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        NSString *glyph = [HAIconMapper glyphForIconName:iconName];
        if (glyph) {
            NSMutableAttributedString *heading = [[NSMutableAttributedString alloc] initWithString:glyph
                attributes:@{NSFontAttributeName: [HAIconMapper mdiFontOfSize:16],
                             NSForegroundColorAttributeName: [HATheme secondaryTextColor]}];
            [heading appendAttributedString:[[NSAttributedString alloc] initWithString:
                [NSString stringWithFormat:@"  %@", configItem.displayName]
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold],
                             NSForegroundColorAttributeName: [HATheme sectionHeaderColor]}]];
            self.headingLabel.attributedText = heading;
        } else {
            self.headingLabel.text = configItem.displayName;
        }
        self.headingLabel.hidden = NO;
        self.showsHeading = YES;
    } else {
        self.headingLabel.hidden = YES;
        self.showsHeading = NO;
    }
    [self setNeedsLayout];

    // Configure title — toggle stack top constraint to avoid dead space
    BOOL hasTitle = (section.title && section.title.length > 0);
    if (hasTitle) {
        self.titleLabel.text = section.title;
        self.titleLabel.hidden = NO;
    } else {
        self.titleLabel.hidden = YES;
    }
    // Constraint activation deferred until after toggle visibility is determined (below)

    // Header toggle: only shown when config explicitly sets show_header_toggle: true
    NSArray<NSString *> *entityIds = section.entityIds ?: @[];
    NSInteger entityCount = entityIds.count;

    BOOL showToggle = [section.customProperties[@"showHeaderToggle"] boolValue];
    NSInteger onCount = 0;
    NSMutableArray<NSString *> *toggleIds = [NSMutableArray array];

    if (showToggle) {
        for (NSString *eid in entityIds) {
            HAEntity *e = entityDict[eid];
            if (!e) continue;
            NSString *d = [e domain];
            if ([d isEqualToString:HAEntityDomainLight] ||
                [d isEqualToString:HAEntityDomainSwitch] ||
                [d isEqualToString:HAEntityDomainInputBoolean] ||
                [d isEqualToString:HAEntityDomainFan]) {
                [toggleIds addObject:eid];
                if (e.isOn) onCount++;
            }
        }
        showToggle = (toggleIds.count > 0);
    }
    self.headerToggle.hidden = !showToggle;
    self.toggleEntityIds = toggleIds;
    if (showToggle) {
        self.headerToggle.on = (onCount > 0);
    }

    // Activate correct stack top constraint
    self.stackTopWithTitle.active = NO;
    self.stackTopWithToggle.active = NO;
    self.stackTopNoTitle.active = NO;
    if (hasTitle) {
        self.stackTopWithTitle.active = YES;
    } else if (showToggle) {
        self.stackTopWithToggle.active = YES; // 36pt room for header toggle
    } else {
        self.stackTopNoTitle.active = YES;
    }

    // Scene chip IDs from config (pre-computed by strategy resolver or default builder)
    NSArray *chipEntityIds = section.customProperties[@"sceneEntityIds"];
    if (![chipEntityIds isKindOfClass:[NSArray class]]) chipEntityIds = nil;
    NSDictionary *chipNames = section.customProperties[@"sceneChipNames"];
    if (![chipNames isKindOfClass:[NSDictionary class]]) chipNames = nil;

    NSInteger rowCount = entityCount;

    // Pool-based row view management: reuse hidden views instead of creating/destroying.
    // Each HAEntityRowView allocates 10+ subviews with 30+ constraints — expensive on iPad 2.
    NSInteger poolSize = (NSInteger)self.rowViews.count;
    // Create only the deficit
    for (NSInteger i = poolSize; i < rowCount; i++) {
        HAEntityRowView *rowView = [[HAEntityRowView alloc] initWithFrame:CGRectZero];
        [self.rowViews addObject:rowView];
        [self.stackView addArrangedSubview:rowView];
    }
    // Show needed rows, hide excess (keep in pool for reuse)
    for (NSInteger i = 0; i < (NSInteger)self.rowViews.count; i++) {
        self.rowViews[i].hidden = (i >= rowCount);
    }

    // Configure each row view with its entity
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < rowCount; i++) {
        NSString *entityId = entityIds[i];
        HAEntity *entity = entityDict[entityId];
        HAEntityRowView *rowView = self.rowViews[i];

        NSString *nameOverride = section.nameOverrides[entityId];
        if (nameOverride) {
            [rowView configureWithEntity:entity nameOverride:nameOverride];
        } else {
            [rowView configureWithEntity:entity];
        }

        rowView.entityTapBlock = ^(HAEntity *tappedEntity) {
            if (weakSelf.entityTapBlock) {
                weakSelf.entityTapBlock(tappedEntity);
            }
        };

        rowView.showsSeparator = (i < rowCount - 1);
    }

    // Scene chips
    for (UIView *v in self.sceneChipScrollView.subviews) [v removeFromSuperview];

    if (chipEntityIds.count > 0) {
        self.sceneChipScrollView.hidden = NO;
        self.chipScrollHeight.constant = kSceneChipRowHeight;

        CGFloat x = 12.0;
        for (NSString *sceneId in chipEntityIds) {
            HAEntity *scene = entityDict[sceneId];
            if (!scene) scene = [[HAConnectionManager sharedManager] entityForId:sceneId];
            if (!scene) continue;

            UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
            // Use pre-computed display name (area prefix already stripped), fall back to friendlyName
            NSString *name = chipNames[sceneId] ?: [scene friendlyName];
            [chip setTitle:name forState:UIControlStateNormal];
            chip.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            [chip setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
            chip.backgroundColor = [HATheme buttonBackgroundColor];
            chip.layer.cornerRadius = kSceneChipHeight / 2.0;
            chip.clipsToBounds = YES;
            chip.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
            chip.tag = [sceneId hash];

            [chip sizeToFit];
            CGFloat chipWidth = MAX(chip.frame.size.width, 60);
            chip.frame = CGRectMake(x, (kSceneChipRowHeight - kSceneChipHeight) / 2.0, chipWidth, kSceneChipHeight);
            [chip addTarget:self action:@selector(sceneChipTapped:) forControlEvents:UIControlEventTouchUpInside];
            // Store entity ID in accessibility identifier for retrieval on tap
            chip.accessibilityIdentifier = sceneId;
            [self.sceneChipScrollView addSubview:chip];

            x += chipWidth + kSceneChipSpacing;
        }
        self.sceneChipScrollView.contentSize = CGSizeMake(x - kSceneChipSpacing + 12.0, kSceneChipRowHeight);
    } else {
        self.sceneChipScrollView.hidden = YES;
        self.chipScrollHeight.constant = 0;
    }
}

- (void)sceneChipTapped:(UIButton *)sender {
    [HAHaptics lightImpact];
    NSString *sceneId = sender.accessibilityIdentifier;
    if (!sceneId) return;
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    HAEntity *scene = [conn entityForId:sceneId];
    if (!scene) return;
    [conn callService:@"turn_on" inDomain:[scene domain] withData:nil entityId:sceneId];
}

+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count hasTitle:(BOOL)hasTitle hasHeaderToggle:(BOOL)hasHeaderToggle {
    return [self preferredHeightForEntityCount:count hasTitle:hasTitle hasHeaderToggle:hasHeaderToggle hasSceneChips:NO];
}

+ (CGFloat)preferredHeightForSection:(HADashboardConfigSection *)section
                            entities:(NSDictionary *)entityDict {
    NSInteger rowCount = (NSInteger)(section.entityIds.count);
    NSArray *sceneIds = section.customProperties[@"sceneEntityIds"];
    BOOL hasChips = [sceneIds isKindOfClass:[NSArray class]] && [(NSArray *)sceneIds count] > 0;
    BOOL hasTitle = section.title.length > 0;
    BOOL hasToggle = [section.customProperties[@"showHeaderToggle"] boolValue];
    return [self preferredHeightForEntityCount:rowCount hasTitle:hasTitle hasHeaderToggle:hasToggle hasSceneChips:hasChips];
}

+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count hasTitle:(BOOL)hasTitle hasHeaderToggle:(BOOL)hasHeaderToggle hasSceneChips:(BOOL)hasSceneChips {
    CGFloat height = 0;

    if (hasTitle) {
        // Title: 12pt top + 14pt font + 4pt gap to stack = 30pt
        height += 30.0;
    } else if (hasHeaderToggle) {
        // Toggle-only header: 36pt (room for scaled UISwitch)
        height += 36.0;
    }
    // No title or toggle: stack starts at contentView top (0pt)

    // Each entity row: 48pt (matching HA web entity row spacing with padding)
    height += (count * 48.0);

    // Scene chip row
    if (hasSceneChips) {
        height += kSceneChipRowHeight;
    }

    return height;
}

- (void)headerToggleTapped:(UISwitch *)sender {
    [HAHaptics lightImpact];

    NSString *service = sender.isOn ? @"turn_on" : @"turn_off";
    HAConnectionManager *conn = [HAConnectionManager sharedManager];

    for (NSString *entityId in self.toggleEntityIds) {
        HAEntity *entity = [conn entityForId:entityId];
        if (!entity) continue;
        [conn callService:service inDomain:[entity domain] withData:nil entityId:entityId];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.titleLabel.textColor = [HATheme secondaryTextColor];
    self.titleLabel.hidden = YES;
    self.stackTopWithTitle.active = NO;
    self.stackTopWithToggle.active = NO;
    self.stackTopNoTitle.active = YES;
    self.headingLabel.attributedText = nil;
    self.headingLabel.text = nil;
    self.headingLabel.hidden = YES;
    self.headingLabel.textColor = [HATheme sectionHeaderColor];
    self.showsHeading = NO;
    self.headerToggle.hidden = YES;
    self.headerToggle.on = NO;
    self.toggleEntityIds = nil;

    // Clear scene chips
    for (UIView *v in self.sceneChipScrollView.subviews) [v removeFromSuperview];
    self.sceneChipScrollView.hidden = YES;
    self.chipScrollHeight.constant = 0;

    // Clear row views
    for (HAEntityRowView *rowView in self.rowViews) {
        [rowView configureWithEntity:nil];
    }
}

@end
