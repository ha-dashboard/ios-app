#import "HAAutoLayout.h"
#import "NSString+HACompat.h"
#import "HAStackView.h"
#import "NSString+HACompat.h"
#import "HAEntitiesCardCell.h"
#import "HASwitch.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HAEntityRowView.h"
#import "HAIconMapper.h"
#import "HATheme.h"
#import "HAConnectionManager.h"
#import "HAHaptics.h"
#import "HAAction.h"
#import "HAActionDispatcher.h"
#import <objc/runtime.h>
#import "UIFont+HACompat.h"

static const void *kButtonActionKey = &kButtonActionKey;
static const void *kButtonEntityIdKey = &kButtonEntityIdKey;

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
@property (nonatomic, weak) HADashboardConfigSection *lastConfiguredSection;
@property (nonatomic, strong) HAStackView *stackView;
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
    self.headingLabel.font = [UIFont ha_systemFontOfSize:17 weight:HAFontWeightSemibold];
    self.headingLabel.textColor = [HATheme sectionHeaderColor];
    self.headingLabel.numberOfLines = 1;
    self.headingLabel.hidden = YES;
    [self addSubview:self.headingLabel]; // on cell itself, not contentView

    // Title label (optional, inside the card)
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont ha_systemFontOfSize:14 weight:HAFontWeightMedium];
    self.titleLabel.textColor = [HATheme secondaryTextColor];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.titleLabel];

    // Header toggle switch (HA web show_header_toggle, also auto-shown for all-toggleable cards)
    self.headerToggle = [[HASwitch alloc] init];
    self.headerToggle.transform = CGAffineTransformMakeScale(0.7, 0.7);
    self.headerToggle.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerToggle.hidden = YES;
    [self.headerToggle addTarget:self action:@selector(headerToggleTapped:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.headerToggle];

    // Position at top-right of card — works with or without title
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.headerToggle.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [self.headerToggle.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        ]];
    }

    // Stack view for entity rows
    self.stackView = [[HAStackView alloc] init];
    self.stackView.axis = 1;
    self.stackView.distribution = 0;
    self.stackView.alignment = 0;
    self.stackView.spacing = 0;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.stackView];

    // Initialize row views array
    self.rowViews = [NSMutableArray array];

    // Layout constraints
    // Title label: 12pt padding from top and sides
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12]
        ]];
    }

    // Stack view: below title (when shown) or at contentView top (no title).
    if (HAAutoLayoutAvailable()) {
        self.stackTopWithTitle = [self.stackView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4];
        self.stackTopNoTitle = [self.stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0];
        self.stackTopWithToggle = [self.stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:36];
        self.stackTopWithTitle.active = NO;
        self.stackTopWithToggle.active = NO;
        self.stackTopNoTitle.active = YES; // default: no title
    }

    // Scene chips scroll view (below entity rows)
    self.sceneChipScrollView = [[UIScrollView alloc] init];
    self.sceneChipScrollView.showsHorizontalScrollIndicator = NO;
    self.sceneChipScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sceneChipScrollView.hidden = YES;
    [self.contentView addSubview:self.sceneChipScrollView];

    if (HAAutoLayoutAvailable()) {
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

    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat y = 0;
        // Title
        if (!self.titleLabel.hidden && self.titleLabel.text.length > 0) {
            CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(w - 24, CGFLOAT_MAX)];
            self.titleLabel.frame = CGRectMake(12, 12, w - 24, titleSize.height);
            y = CGRectGetMaxY(self.titleLabel.frame) + 4;
        }
        // Header toggle
        if (!self.headerToggle.hidden) {
            CGSize toggleSize = [self.headerToggle sizeThatFits:CGSizeZero];
            self.headerToggle.frame = CGRectMake(w - 8 - toggleSize.width, 6, toggleSize.width, toggleSize.height);
            if (y == 0) y = 36;
        }
        // Scene chip scroll view: below stack
        CGFloat chipH = 0;
        if (!self.sceneChipScrollView.hidden) {
            chipH = kSceneChipRowHeight;
        }

        // Stack: fill remaining space minus chips
        CGFloat stackH = self.contentView.bounds.size.height - y - chipH;
        self.stackView.frame = CGRectMake(0, y, w, stackH);
        [self.stackView setNeedsLayout];
        [self.stackView layoutIfNeeded];

        // Scene chips
        if (chipH > 0) {
            self.sceneChipScrollView.frame = CGRectMake(0, y + stackH, w, chipH);
        }
    }
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary *)entityDict
                  configItem:(HADashboardConfigItem *)configItem {
    // Fast-path: if same section and row count matches, just update entity states
    // without rebuilding the entire cell structure (saves ~160ms on A5).
    NSArray<NSString *> *entityIds = section.entityIds ?: @[];
    if (self.lastConfiguredSection == section &&
        self.rowViews.count == (NSUInteger)entityIds.count &&
        self.rowViews.count > 0) {
        for (NSUInteger i = 0; i < self.rowViews.count && i < entityIds.count; i++) {
            HAEntity *entity = entityDict[entityIds[i]];
            HAEntityRowView *rowView = self.rowViews[i];
            NSString *nameOverride = section.nameOverrides[entityIds[i]];
            if (nameOverride) {
                [rowView configureWithEntity:entity nameOverride:nameOverride];
            } else {
                [rowView configureWithEntity:entity];
            }
        }
        // Update header toggle state
        if (self.headerToggle && !self.headerToggle.hidden) {
            BOOL allOn = YES;
            for (NSString *eid in entityIds) {
                HAEntity *e = entityDict[eid];
                if (e && ![e isOn]) { allOn = NO; break; }
            }
            [self.headerToggle setOn:allOn animated:NO];
        }
        return;
    }
    self.lastConfiguredSection = section;

    // Configure heading (above card, from grid heading)
    NSString *headingIcon = configItem.customProperties[@"headingIcon"];
    BOOL hasHeading = (configItem.displayName.length > 0 && headingIcon != nil);

    if (hasHeading) {
        NSString *iconName = headingIcon;
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        NSString *glyph = [HAIconMapper glyphForIconName:iconName];
        if (glyph) {
            NSMutableAttributedString *heading = [[NSMutableAttributedString alloc]
                initWithAttributedString:[HAIconMapper attributedGlyph:glyph fontSize:16 color:[HATheme secondaryTextColor]]];
            [heading appendAttributedString:[[NSAttributedString alloc] initWithString:
                [NSString stringWithFormat:@"  %@", configItem.displayName]
                attributes:@{HAFontAttributeName: [UIFont ha_systemFontOfSize:17 weight:HAFontWeightSemibold],
                             HAForegroundColorAttributeName: [HATheme sectionHeaderColor]}]];
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

    // Header toggle: when explicitly configured, use that value.
    // When absent, default to YES if card has title AND ≥2 toggleable entities
    // (matches HA frontend's computeShowHeaderToggle behavior).

    // Entity-filter card: filter entities by state at render time
    NSArray *stateFilter = section.customProperties[@"state_filter"];
    if ([stateFilter isKindOfClass:[NSArray class]] && stateFilter.count > 0) {
        NSMutableArray<NSString *> *filtered = [NSMutableArray array];
        for (NSString *eid in entityIds) {
            HAEntity *e = entityDict[eid];
            if (!e) continue;
            for (id filter in stateFilter) {
                NSString *filterState = [filter isKindOfClass:[NSString class]] ? filter : nil;
                if (filterState && [e.state isEqualToString:filterState]) {
                    [filtered addObject:eid];
                    break;
                }
            }
        }
        entityIds = [filtered copy];
    }

    NSInteger entityCount = entityIds.count;

    BOOL showToggle;
    id toggleProp = section.customProperties[@"showHeaderToggle"];
    if (toggleProp) {
        showToggle = [toggleProp boolValue];
    } else {
        // Compute default: title present + ≥2 toggleable entities
        showToggle = NO;
        if (hasTitle) {
            NSInteger toggleCount = 0;
            for (NSString *eid in entityIds) {
                HAEntity *e = entityDict[eid];
                if (!e) continue;
                NSString *d = [e domain];
                if ([d isEqualToString:HAEntityDomainLight] ||
                    [d isEqualToString:HAEntityDomainSwitch] ||
                    [d isEqualToString:HAEntityDomainInputBoolean] ||
                    [d isEqualToString:HAEntityDomainFan]) {
                    toggleCount++;
                    if (toggleCount >= 2) { showToggle = YES; break; }
                }
            }
        }
    }
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

    // Remove any previously added special row views (dividers, section headers)
    for (UIView *sub in [self.stackView.arrangedSubviews copy]) {
        if (sub.tag == 999) { // tag 999 = special row
            [self.stackView removeArrangedSubview:sub];
            [sub removeFromSuperview];
        }
    }

    // Check for orderedRows (includes divider/section special rows)
    NSArray *orderedRows = section.customProperties[@"orderedRows"];

    // Configure each row view with its entity
    __weak typeof(self) weakSelf = self;
    NSInteger entityRowIdx = 0;
    if (orderedRows.count > 0) {
        // Ordered mode: iterate orderedRows, insert special views between entity rows
        for (NSDictionary *rowInfo in orderedRows) {
            NSString *rowType = rowInfo[@"row_type"];
            if ([rowType isEqualToString:@"divider"]) {
                UIView *divider = [[UIView alloc] init];
                divider.backgroundColor = [HATheme controlBorderColor];
                divider.tag = 999;
                divider.translatesAutoresizingMaskIntoConstraints = NO;
                if (HAAutoLayoutAvailable()) {
                    [divider.heightAnchor constraintEqualToConstant:1].active = YES;
                }
                // Insert at correct position in stack
                NSInteger insertIdx = MIN(entityRowIdx, (NSInteger)self.stackView.arrangedSubviews.count);
                [self.stackView insertArrangedSubview:divider atIndex:insertIdx];
                entityRowIdx++;
                continue;
            }
            if ([rowType isEqualToString:@"section"]) {
                UILabel *sectionLabel = [[UILabel alloc] init];
                sectionLabel.text = rowInfo[@"label"] ?: @"";
                sectionLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightSemibold];
                sectionLabel.textColor = [HATheme sectionHeaderColor];
                sectionLabel.tag = 999;
                sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
                UIEdgeInsets insets = UIEdgeInsetsMake(8, 10, 4, 10);
                UIView *wrapper = [[UIView alloc] init];
                wrapper.tag = 999;
                [wrapper addSubview:sectionLabel];
                sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
                if (HAAutoLayoutAvailable()) {
                    [NSLayoutConstraint activateConstraints:@[
                        [sectionLabel.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:insets.left],
                        [sectionLabel.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-insets.right],
                        [sectionLabel.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:insets.top],
                        [sectionLabel.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-insets.bottom],
                    ]];
                }
                NSInteger insertIdx = MIN(entityRowIdx, (NSInteger)self.stackView.arrangedSubviews.count);
                [self.stackView insertArrangedSubview:wrapper atIndex:insertIdx];
                entityRowIdx++;
                continue;
            }
            if ([rowType isEqualToString:@"weblink"]) {
                UIButton *linkRow = [UIButton buttonWithType:UIButtonTypeSystem];
                NSString *iconName = rowInfo[@"icon"];
                NSString *name = rowInfo[@"name"] ?: rowInfo[@"url"] ?: @"Link";
                if (iconName) {
                    if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
                    NSString *glyph = [HAIconMapper glyphForIconName:iconName];
                    if (glyph) {
                        name = [NSString stringWithFormat:@"%@  %@", glyph, name];
                    }
                }
                [linkRow setTitle:name forState:UIControlStateNormal];
                linkRow.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
                linkRow.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
                linkRow.titleLabel.font = [UIFont systemFontOfSize:14];
                [linkRow setTitleColor:[HATheme accentColor] forState:UIControlStateNormal];
                linkRow.tag = 999;
                linkRow.translatesAutoresizingMaskIntoConstraints = NO;
                if (HAAutoLayoutAvailable()) {
                    [linkRow.heightAnchor constraintEqualToConstant:36].active = YES;
                }
                // Store URL for tap — use objc_setAssociatedObject or just open on tap
                NSString *url = rowInfo[@"url"];
                [linkRow addTarget:self action:@selector(weblinkTapped:) forControlEvents:UIControlEventTouchUpInside];
                if (url) linkRow.accessibilityValue = url; // store URL for retrieval
                NSInteger insertIdx = MIN(entityRowIdx, (NSInteger)self.stackView.arrangedSubviews.count);
                [self.stackView insertArrangedSubview:linkRow atIndex:insertIdx];
                entityRowIdx++;
                continue;
            }
            if ([rowType isEqualToString:@"button"]) {
                UIButton *btnRow = [UIButton buttonWithType:UIButtonTypeSystem];
                NSString *name = rowInfo[@"action_name"] ?: rowInfo[@"name"] ?: @"Run";
                NSString *iconName = rowInfo[@"icon"];
                if (iconName) {
                    if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
                    NSString *glyph = [HAIconMapper glyphForIconName:iconName];
                    if (glyph) name = [NSString stringWithFormat:@"%@  %@", glyph, name];
                }
                [btnRow setTitle:name forState:UIControlStateNormal];
                btnRow.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
                btnRow.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
                btnRow.titleLabel.font = [UIFont systemFontOfSize:14];
                btnRow.tag = 999;
                btnRow.translatesAutoresizingMaskIntoConstraints = NO;
                if (HAAutoLayoutAvailable()) {
                    [btnRow.heightAnchor constraintEqualToConstant:36].active = YES;
                }
                // Wire tap action from config
                NSDictionary *tapAction = rowInfo[@"tap_action"];
                if ([tapAction isKindOfClass:[NSDictionary class]]) {
                    objc_setAssociatedObject(btnRow, kButtonActionKey, tapAction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [btnRow addTarget:self action:@selector(buttonRowTapped:) forControlEvents:UIControlEventTouchUpInside];
                }
                NSInteger insertIdx = MIN(entityRowIdx, (NSInteger)self.stackView.arrangedSubviews.count);
                [self.stackView insertArrangedSubview:btnRow atIndex:insertIdx];
                entityRowIdx++;
                continue;
            }
            if ([rowType isEqualToString:@"buttons"]) {
                HAStackView *btnStack = [[HAStackView alloc] init];
                btnStack.axis = 0;
                btnStack.spacing = 8;
                btnStack.distribution = 1;
                btnStack.tag = 999;
                btnStack.translatesAutoresizingMaskIntoConstraints = NO;
                if (HAAutoLayoutAvailable()) {
                    [btnStack.heightAnchor constraintEqualToConstant:36].active = YES;
                }
                NSArray *entities = rowInfo[@"entities"];
                if ([entities isKindOfClass:[NSArray class]]) {
                    for (id btnEntry in entities) {
                        NSString *entityId = nil;
                        NSString *btnName = nil;
                        if ([btnEntry isKindOfClass:[NSString class]]) {
                            entityId = btnEntry;
                            HAEntity *e = entityDict[entityId];
                            btnName = [e friendlyName] ?: entityId;
                        } else if ([btnEntry isKindOfClass:[NSDictionary class]]) {
                            entityId = btnEntry[@"entity"];
                            btnName = btnEntry[@"name"];
                            if (!btnName) {
                                HAEntity *e = entityDict[entityId];
                                btnName = [e friendlyName] ?: entityId ?: @"Button";
                            }
                        }
                        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
                        [btn setTitle:btnName forState:UIControlStateNormal];
                        btn.titleLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightMedium];
                        btn.backgroundColor = [HATheme buttonBackgroundColor];
                        btn.layer.cornerRadius = 6;
                        if (entityId) {
                            objc_setAssociatedObject(btn, kButtonEntityIdKey, entityId, OBJC_ASSOCIATION_COPY_NONATOMIC);
                            [btn addTarget:self action:@selector(buttonsRowEntityTapped:) forControlEvents:UIControlEventTouchUpInside];
                        }
                        [btnStack addArrangedSubview:btn];
                    }
                }
                UIView *wrapper = [[UIView alloc] init];
                wrapper.tag = 999;
                [wrapper addSubview:btnStack];
                btnStack.translatesAutoresizingMaskIntoConstraints = NO;
                if (HAAutoLayoutAvailable()) {
                    [NSLayoutConstraint activateConstraints:@[
                        [btnStack.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:10],
                        [btnStack.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-10],
                        [btnStack.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:4],
                        [btnStack.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-4],
                    ]];
                }
                NSInteger insertIdx = MIN(entityRowIdx, (NSInteger)self.stackView.arrangedSubviews.count);
                [self.stackView insertArrangedSubview:wrapper atIndex:insertIdx];
                entityRowIdx++;
                continue;
            }
            if ([rowType isEqualToString:@"conditional"]) {
                // Evaluate conditions — if all match, render the inner row as an entity
                NSArray *conditions = rowInfo[@"conditions"];
                NSDictionary *innerRow = rowInfo[@"row"];
                if ([conditions isKindOfClass:[NSArray class]] && [innerRow isKindOfClass:[NSDictionary class]]) {
                    BOOL allMet = YES;
                    for (NSDictionary *cond in conditions) {
                        if (![cond isKindOfClass:[NSDictionary class]]) continue;
                        NSString *condEntityId = cond[@"entity"];
                        NSString *condState = cond[@"state"];
                        if (condEntityId && condState) {
                            HAEntity *condEntity = entityDict[condEntityId];
                            if (!condEntity || ![condEntity.state isEqualToString:condState]) {
                                allMet = NO;
                                break;
                            }
                        }
                    }
                    if (allMet) {
                        // The inner row is a regular entity — add to orderedRows as entity
                        NSString *innerEntity = innerRow[@"entity"];
                        if (innerEntity) {
                            // This entity row will be rendered in the standard entity loop below
                            entityRowIdx++;
                            continue;
                        }
                    }
                    // Condition not met or no inner entity — skip (insert nothing)
                }
                entityRowIdx++;
                continue;
            }
            // Regular entity row — handled below in the entity loop
            entityRowIdx++;
        }
    }

    // Reset entity row index for actual configuration
    for (NSInteger i = 0; i < rowCount; i++) {
        NSString *entityId = entityIds[i];
        HAEntity *entity = entityDict[entityId];
        HAEntityRowView *rowView = self.rowViews[i];

        // Per-entity row config (actions, secondary_info, attribute, state_color)
        NSDictionary *entityRowConfigs = section.customProperties[@"entityRowConfigs"];
        NSDictionary *rowCfg = entityRowConfigs[entityId];

        // Set properties BEFORE configure (configure reads them)
        // state_color: per-entity override > card-level > default NO
        if (rowCfg[@"state_color"]) {
            rowView.stateColor = [rowCfg[@"state_color"] boolValue];
        } else {
            rowView.stateColor = [section.customProperties[@"state_color"] boolValue];
        }
        rowView.secondaryInfo = rowCfg[@"secondary_info"];
        rowView.secondaryInfoFormat = rowCfg[@"format"];
        rowView.attributeOverride = rowCfg[@"attribute"];

        NSString *nameOverride = section.nameOverrides[entityId];
        if (nameOverride) {
            [rowView configureWithEntity:entity nameOverride:nameOverride];
        } else {
            [rowView configureWithEntity:entity];
        }

        // Per-entity action config
        rowView.actionConfig = rowCfg;

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
            chip.titleLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium];
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

- (void)weblinkTapped:(UIButton *)sender {
    NSString *urlStr = sender.accessibilityValue;
    if (!urlStr) return;
    NSURL *url = [NSURL URLWithString:urlStr];
    if (url) {
        // iOS 9 compatible — openURL:options:completionHandler: is iOS 10+
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [[UIApplication sharedApplication] openURL:url];
#pragma clang diagnostic pop
    }
}

- (void)buttonRowTapped:(UIButton *)sender {
    [HAHaptics lightImpact];
    NSDictionary *actionDict = objc_getAssociatedObject(sender, kButtonActionKey);
    if (!actionDict) return;
    HAAction *action = [HAAction actionFromDictionary:actionDict];
    if (!action) return;
    UIViewController *vc = nil;
    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            vc = (UIViewController *)responder;
            break;
        }
    }
    [[HAActionDispatcher sharedDispatcher] executeAction:action forEntity:nil fromViewController:vc];
}

- (void)buttonsRowEntityTapped:(UIButton *)sender {
    [HAHaptics lightImpact];
    NSString *entityId = objc_getAssociatedObject(sender, kButtonEntityIdKey);
    if (!entityId) return;
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    HAEntity *entity = [conn entityForId:entityId];
    if (!entity) return;
    NSString *service = entity.toggleService;
    if (service) {
        [conn callService:service inDomain:[entity domain] withData:nil entityId:entityId];
    } else {
        [conn callService:@"toggle" inDomain:@"homeassistant" withData:nil entityId:entityId];
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
    self.lastConfiguredSection = nil;

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
