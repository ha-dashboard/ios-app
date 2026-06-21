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
    self.headerToggle = [[HASwitch alloc] init];
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

static inline NSString *HANormalizeState(id val) {
    if (!val) return @"";
    NSString *str = [[val description] lowercaseString];
    if ([str isEqualToString:@"1"] || [str isEqualToString:@"true"] || [str isEqualToString:@"on"]) {
        return @"on";
    }
    if ([str isEqualToString:@"0"] || [str isEqualToString:@"false"] || [str isEqualToString:@"off"]) {
        return @"off";
    }
    return str;
}

+ (BOOL)meetsCondition:(NSDictionary *)condition
              entities:(NSDictionary *)entities {
    if (![condition isKindOfClass:[NSDictionary class]]) return YES;

    NSString *condType = condition[@"condition"];
    if (!condType && condition[@"entity"]) {
        condType = @"state";
    }

    if ([condType isEqualToString:@"state"]) {
        NSString *entityId = condition[@"entity"];
        if (!entityId) return YES;

        HAEntity *entity = entities[entityId];
        NSString *currentState = entity.state;

        id requiredStateRaw = condition[@"state"];
        id requiredStateNotRaw = condition[@"state_not"];

        if (requiredStateRaw) {
            NSArray *requiredStates = [requiredStateRaw isKindOfClass:[NSArray class]]
                                          ? (NSArray *)requiredStateRaw
                                          : @[ [requiredStateRaw description] ];
            BOOL matched = NO;
            NSString *currNorm = HANormalizeState(currentState);
            for (id req in requiredStates) {
                if ([HANormalizeState(req) isEqualToString:currNorm]) {
                    matched = YES;
                    break;
                }
            }
            if (!matched) return NO;
        }

        if (requiredStateNotRaw) {
            NSArray *requiredStatesNot = [requiredStateNotRaw isKindOfClass:[NSArray class]]
                                              ? (NSArray *)requiredStateNotRaw
                                              : @[ [requiredStateNotRaw description] ];
            NSString *currNorm = HANormalizeState(currentState);
            for (id req in requiredStatesNot) {
                if ([HANormalizeState(req) isEqualToString:currNorm]) {
                    return NO;
                }
            }
        }
        return YES;
    }

    if ([condType isEqualToString:@"numeric_state"]) {
        NSString *entityId = condition[@"entity"];
        if (!entityId) return YES;

        HAEntity *entity = entities[entityId];
        NSString *currentState = entity.state;
        if (!currentState) return NO;

        double currentVal = [currentState doubleValue];
        id aboveRaw = condition[@"above"];
        id belowRaw = condition[@"below"];

        if (aboveRaw) {
            double aboveVal = [aboveRaw doubleValue];
            if (currentVal <= aboveVal) return NO;
        }
        if (belowRaw) {
            double belowVal = [belowRaw doubleValue];
            if (currentVal >= belowVal) return NO;
        }
        return YES;
    }

    if ([condType isEqualToString:@"and"]) {
        NSArray *subConditions = condition[@"conditions"];
        if ([subConditions isKindOfClass:[NSArray class]]) {
            for (NSDictionary *sub in subConditions) {
                if (![self meetsCondition:sub entities:entities]) return NO;
            }
        }
        return YES;
    }

    if ([condType isEqualToString:@"or"]) {
        NSArray *subConditions = condition[@"conditions"];
        if ([subConditions isKindOfClass:[NSArray class]]) {
            if (subConditions.count == 0) return YES;
            for (NSDictionary *sub in subConditions) {
                if ([self meetsCondition:sub entities:entities]) return YES;
            }
            return NO;
        }
        return YES;
    }

    if ([condType isEqualToString:@"not"]) {
        NSArray *subConditions = condition[@"conditions"];
        if ([subConditions isKindOfClass:[NSArray class]]) {
            for (NSDictionary *sub in subConditions) {
                if ([self meetsCondition:sub entities:entities]) return NO;
            }
        }
        return YES;
    }

    if ([condType isEqualToString:@"user"]) {
        return YES; // always pass local dashboard
    }

    if ([condType isEqualToString:@"screen"]) {
        NSString *query = condition[@"media_query"];
        if ([query isKindOfClass:[NSString class]]) {
            CGFloat width = [UIScreen mainScreen].bounds.size.width;
            if ([query containsString:@"min-width"]) {
                NSScanner *scanner = [NSScanner scannerWithString:query];
                [scanner scanUpToString:@"min-width" intoString:nil];
                [scanner scanString:@"min-width" intoString:nil];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:nil];
                NSInteger minWidth = 0;
                if ([scanner scanInteger:&minWidth] && width < minWidth) {
                    return NO;
                }
            }
            if ([query containsString:@"max-width"]) {
                NSScanner *scanner = [NSScanner scannerWithString:query];
                [scanner scanUpToString:@"max-width" intoString:nil];
                [scanner scanString:@"max-width" intoString:nil];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:nil];
                NSInteger maxWidth = 0;
                if ([scanner scanInteger:&maxWidth] && width > maxWidth) {
                    return NO;
                }
            }
        }
        return YES;
    }

    return YES;
}

- (BOOL)meetsCondition:(NSDictionary *)condition
              entities:(NSDictionary *)entities {
    return [[self class] meetsCondition:condition entities:entities];
}

+ (NSInteger)visibleRowCountForRows:(NSArray *)rows
                            entities:(NSDictionary *)entities {
    NSInteger count = 0;
    for (NSDictionary *row in rows) {
        NSString *rowType = row[@"row_type"];
        if ([rowType isEqualToString:@"conditional"]) {
            NSArray *conditions = row[@"conditions"];
            NSDictionary *innerRow = row[@"row"];
            if ([conditions isKindOfClass:[NSArray class]] &&
                [innerRow isKindOfClass:[NSDictionary class]]) {
                BOOL allMet = YES;
                for (NSDictionary *cond in conditions) {
                    if (![self meetsCondition:cond entities:entities]) {
                        allMet = NO;
                        break;
                    }
                }
                if (allMet) {
                    count += [self visibleRowCountForRows:@[ innerRow ]
                                                 entities:entities];
                }
            }
        } else {
            count++;
        }
    }
    return count;
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary *)entityDict
                  configItem:(HADashboardConfigItem *)configItem {
    self.lastConfiguredSection = section;

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

    NSArray<NSString *> *entityIds = section.entityIds ?: @[];

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

    // Header toggle: when explicitly configured, use that value.
    // When absent, default to YES if card has title AND >=2 toggleable entities
    BOOL showToggle;
    id toggleProp = section.customProperties[@"showHeaderToggle"];
    if (toggleProp) {
        showToggle = [toggleProp boolValue];
    } else {
        // Compute default: title present + >=2 toggleable entities
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

    // Clear stack view of all arranged subviews to rebuild dynamically in correct order
    for (UIView *sub in [self.stackView.arrangedSubviews copy]) {
        [self.stackView removeArrangedSubview:sub];
        if (sub.tag == 999) { // tag 999 = special row
            [sub removeFromSuperview];
        } else {
            sub.hidden = YES;
        }
    }

    // Parse orderedRows
    NSArray *orderedRows = section.customProperties[@"orderedRows"];
    if (orderedRows.count == 0) {
        NSMutableArray *temp = [NSMutableArray arrayWithCapacity:entityIds.count];
        for (NSString *eid in entityIds) {
            [temp addObject:@{@"entity" : eid}];
        }
        orderedRows = [temp copy];
    }

    // Pool-based row view management setup
    __block NSInteger rowViewUseIdx = 0;
    __weak typeof(self) weakSelf = self;

    HAEntityRowView * (^getOrCreateRowView)(void) = ^HAEntityRowView * {
        if (rowViewUseIdx < (NSInteger)weakSelf.rowViews.count) {
            HAEntityRowView *rv = weakSelf.rowViews[rowViewUseIdx++];
            rv.hidden = NO;
            return rv;
        } else {
            HAEntityRowView *rv = [[HAEntityRowView alloc] initWithFrame:CGRectZero];
            [weakSelf.rowViews addObject:rv];
            [weakSelf.stackView addSubview:rv]; // load into hierarchy
            rowViewUseIdx++;
            return rv;
        }
    };

    // Recursive block to render rows in order
    __block void (^renderRowBlock)(NSDictionary *rowInfo);
    void (^renderRowBlockTmp)(NSDictionary *rowInfo) = ^(NSDictionary *rowInfo) {
        NSString *rowType = rowInfo[@"row_type"];
        if ([rowType isEqualToString:@"divider"]) {
            UIView *divider = [[UIView alloc] init];
            divider.backgroundColor = [HATheme controlBorderColor];
            divider.tag = 999;
            divider.translatesAutoresizingMaskIntoConstraints = NO;
            [divider.heightAnchor constraintEqualToConstant:1].active = YES;
            [weakSelf.stackView addArrangedSubview:divider];
            return;
        }
        if ([rowType isEqualToString:@"section"]) {
            UILabel *sectionLabel = [[UILabel alloc] init];
            sectionLabel.text = rowInfo[@"label"] ?: @"";
            sectionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            sectionLabel.textColor = [HATheme sectionHeaderColor];
            sectionLabel.tag = 999;
            sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
            UIEdgeInsets insets = UIEdgeInsetsMake(8, 10, 4, 10);
            UIView *wrapper = [[UIView alloc] init];
            wrapper.tag = 999;
            [wrapper addSubview:sectionLabel];
            sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [sectionLabel.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:insets.left],
                [sectionLabel.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-insets.right],
                [sectionLabel.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:insets.top],
                [sectionLabel.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-insets.bottom],
            ]];
            [weakSelf.stackView addArrangedSubview:wrapper];
            return;
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
            [linkRow.heightAnchor constraintEqualToConstant:36].active = YES;
            NSString *url = rowInfo[@"url"];
            [linkRow addTarget:weakSelf action:@selector(weblinkTapped:) forControlEvents:UIControlEventTouchUpInside];
            if (url) linkRow.accessibilityValue = url;
            [weakSelf.stackView addArrangedSubview:linkRow];
            return;
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
            [btnRow.heightAnchor constraintEqualToConstant:36].active = YES;
            NSDictionary *tapAction = rowInfo[@"tap_action"];
            if ([tapAction isKindOfClass:[NSDictionary class]]) {
                objc_setAssociatedObject(btnRow, kButtonActionKey, tapAction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [btnRow addTarget:weakSelf action:@selector(buttonRowTapped:) forControlEvents:UIControlEventTouchUpInside];
            }
            [weakSelf.stackView addArrangedSubview:btnRow];
            return;
        }
        if ([rowType isEqualToString:@"buttons"]) {
            UIStackView *btnStack = [[UIStackView alloc] init];
            btnStack.axis = UILayoutConstraintAxisHorizontal;
            btnStack.spacing = 8;
            btnStack.distribution = UIStackViewDistributionFillEqually;
            btnStack.tag = 999;
            btnStack.translatesAutoresizingMaskIntoConstraints = NO;
            [btnStack.heightAnchor constraintEqualToConstant:36].active = YES;
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
                    btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
                    btn.backgroundColor = [HATheme buttonBackgroundColor];
                    btn.layer.cornerRadius = 6;
                    if (entityId) {
                        objc_setAssociatedObject(btn, kButtonEntityIdKey, entityId, OBJC_ASSOCIATION_COPY_NONATOMIC);
                        [btn addTarget:weakSelf action:@selector(buttonsRowEntityTapped:) forControlEvents:UIControlEventTouchUpInside];
                    }
                    [btnStack addArrangedSubview:btn];
                }
            }
            UIView *wrapper = [[UIView alloc] init];
            wrapper.tag = 999;
            [wrapper addSubview:btnStack];
            btnStack.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [btnStack.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:10],
                [btnStack.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-10],
                [btnStack.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:4],
                [btnStack.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-4],
            ]];
            [weakSelf.stackView addArrangedSubview:wrapper];
            return;
        }
        if ([rowType isEqualToString:@"conditional"]) {
            NSArray *conditions = rowInfo[@"conditions"];
            NSDictionary *innerRow = rowInfo[@"row"];
            if ([conditions isKindOfClass:[NSArray class]] && [innerRow isKindOfClass:[NSDictionary class]]) {
                BOOL allMet = YES;
                for (NSDictionary *cond in conditions) {
                    if (![weakSelf meetsCondition:cond entities:entityDict]) {
                        allMet = NO;
                        break;
                    }
                }
                if (allMet) {
                    renderRowBlock(innerRow);
                }
            }
            return;
        }

        // Regular entity row
        NSString *entityId = rowInfo[@"entity"];
        if (entityId) {
            HAEntity *entity = entityDict[entityId];
            HAEntityRowView *rowView = getOrCreateRowView();

            NSDictionary *entityRowConfigs = section.customProperties[@"entityRowConfigs"];
            NSDictionary *rowCfg = entityRowConfigs[entityId];

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

            rowView.actionConfig = rowCfg;
            rowView.entityTapBlock = ^(HAEntity *tappedEntity) {
                if (weakSelf.entityTapBlock) {
                    weakSelf.entityTapBlock(tappedEntity);
                }
            };
            [weakSelf.stackView addArrangedSubview:rowView];
        }
    };
    renderRowBlock = renderRowBlockTmp;

    // Render all rows
    for (NSDictionary *rowInfo in orderedRows) {
        renderRowBlock(rowInfo);
    }

    // Set separator visibility on arranged subviews of type HAEntityRowView
    NSMutableArray<HAEntityRowView *> *visibleEntityRows = [NSMutableArray array];
    for (UIView *subview in self.stackView.arrangedSubviews) {
        if ([subview isKindOfClass:[HAEntityRowView class]]) {
            [visibleEntityRows addObject:(HAEntityRowView *)subview];
        }
    }
    for (NSInteger i = 0; i < (NSInteger)visibleEntityRows.count; i++) {
        visibleEntityRows[i].showsSeparator = (i < (NSInteger)visibleEntityRows.count - 1);
    }

    // Hide any unused row views in the pool
    for (NSInteger i = rowViewUseIdx; i < (NSInteger)self.rowViews.count; i++) {
        self.rowViews[i].hidden = YES;
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
    NSArray *entityIds = section.entityIds ?: @[];
    NSArray *orderedRows = section.customProperties[@"orderedRows"];
    if (orderedRows.count == 0) {
        NSMutableArray *temp = [NSMutableArray arrayWithCapacity:entityIds.count];
        for (NSString *eid in entityIds) {
            [temp addObject:@{@"entity" : eid}];
        }
        orderedRows = [temp copy];
    }

    NSInteger rowCount = [self visibleRowCountForRows:orderedRows
                                             entities:entityDict];
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
