#import "HABaseEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"

static const CGFloat kHeadingHeight = 28.0;
static const CGFloat kHeadingGap = 2.0;

@interface HABaseEntityCell ()
@property (nonatomic, assign) BOOL showsHeading;
@end

@implementation HABaseEntityCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerRadius = 14.0;
        self.contentView.layer.masksToBounds = YES;
        self.contentView.layer.borderWidth = 0.0;
        [self applyGradientBackground];

        // Heading label: added to the CELL (self), not contentView.
        // When visible, layoutSubviews pushes contentView down below it.
        self.headingLabel = [[UILabel alloc] init];
        self.headingLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        self.headingLabel.textColor = [HATheme sectionHeaderColor];
        self.headingLabel.numberOfLines = 1;
        self.headingLabel.hidden = YES;
        [self addSubview:self.headingLabel];

        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont systemFontOfSize:13];
    self.nameLabel.textColor = [HATheme secondaryTextColor];
    self.nameLabel.numberOfLines = 1;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.font = [UIFont boldSystemFontOfSize:16];
    self.stateLabel.textColor = [HATheme primaryTextColor];
    self.stateLabel.numberOfLines = 1;
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.stateLabel];

    CGFloat padding = 10.0;
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4]];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.showsHeading) {
        CGFloat headingH = kHeadingHeight + kHeadingGap;
        // Heading sits at top of cell bounds, no card background
        self.headingLabel.frame = CGRectMake(4, 0, self.bounds.size.width - 8, kHeadingHeight);
        // Push contentView below the heading
        self.contentView.frame = CGRectMake(0, headingH,
            self.bounds.size.width, self.bounds.size.height - headingH);
    } else {
        self.contentView.frame = self.bounds;
    }

    // Sync backgroundView (blur) with contentView frame so it doesn't cover headings.
    // UICollectionViewCell auto-sizes backgroundView to cell bounds; override here.
    if (self.backgroundView) {
        self.backgroundView.frame = self.contentView.frame;
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    self.entity = entity;

    // Configure heading (from grid heading — e.g. "House Climate", "Ribbit")
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

    if (!entity) {
        self.nameLabel.text = configItem.entityId;
        self.stateLabel.text = @"—";
        self.contentView.alpha = 0.5;
        return;
    }

    self.contentView.alpha = entity.isAvailable ? 1.0 : 0.5;
    // When heading is present, displayName holds the heading text (shown as banner).
    // The entity name should come from the card-level nameOverride or friendly_name.
    NSString *cardNameOverride = configItem.customProperties[@"nameOverride"];
    if (cardNameOverride.length > 0) {
        self.nameLabel.text = cardNameOverride;
    } else if (hasHeading) {
        self.nameLabel.text = [entity friendlyName];
    } else {
        self.nameLabel.text = configItem.displayName ?: [entity friendlyName];
    }
    self.stateLabel.text = [self displayState];
}

- (NSString *)displayState {
    if (!self.entity) return @"—";
    return self.entity.state;
}

+ (CGFloat)headingHeight {
    return kHeadingHeight + kHeadingGap;
}

/// Configures the cell background color and opacity.
/// Blur backgroundView is applied externally by HADashboardViewController willDisplayCell.
- (void)applyGradientBackground {
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.contentView.opaque = NO;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.entity = nil;
    self.nameLabel.text = nil;
    self.stateLabel.text = nil;
    self.headingLabel.attributedText = nil;
    self.headingLabel.text = nil;
    self.headingLabel.hidden = YES;
    self.showsHeading = NO;
    self.contentView.alpha = 1.0;
    [self applyGradientBackground];
    // Refresh theme-dependent colors (labels set once in setupSubviews)
    self.nameLabel.textColor = [HATheme secondaryTextColor];
    self.stateLabel.textColor = [HATheme primaryTextColor];
    self.headingLabel.textColor = [HATheme sectionHeaderColor];
}

@end
