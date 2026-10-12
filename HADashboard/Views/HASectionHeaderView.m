#import "HASectionHeaderView.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"

@interface HASectionHeaderView ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingWithIcon;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingNoIcon;
@property (nonatomic, strong) NSLayoutConstraint *iconLeading;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailing;
@end

@implementation HASectionHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    // Icon label (MDI font glyph)
    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.font = [HAIconMapper mdiFontOfSize:16];
    self.iconLabel.textColor = [HATheme secondaryTextColor];
    self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.iconLabel];

    // Title label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [HATheme sectionHeaderColor];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.titleLabel];

    // Layout: icon (fixed 24pt width, glyph leading-aligned) | 4pt gap | title —
    // the same geometry as a standalone heading row (HAHeadingCell), so the
    // section's first heading and any later heading line up.
    // Two title leading constraints: with-icon (after icon) and no-icon (flush left).
    _contentInset = 8.0;
    self.iconLeading = [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:_contentInset];
    self.titleTrailing = [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-_contentInset];
    [NSLayoutConstraint activateConstraints:@[
        self.iconLeading,
        [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.iconLabel.widthAnchor constraintEqualToConstant:24],

        self.titleTrailing,
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    self.titleLeadingWithIcon = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:4];
    self.titleLeadingNoIcon = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:_contentInset];
    self.titleLeadingNoIcon.active = YES;
}

- (void)setContentInset:(CGFloat)contentInset {
    _contentInset = contentInset;
    self.iconLeading.constant = contentInset;
    self.titleLeadingNoIcon.constant = contentInset;
    self.titleTrailing.constant = -contentInset;
}

- (void)configureWithSection:(HADashboardConfigSection *)section {
    self.titleLabel.text = section.title;

    // Try icon from section config, then from card type as domain hint
    NSString *glyph = [HAIconMapper glyphForIconName:section.icon];
    if (!glyph && section.cardType) {
        if ([section.cardType isEqualToString:@"thermostat"]) {
            glyph = [HAIconMapper glyphForDomain:@"climate"];
        } else if ([section.cardType isEqualToString:@"weather-forecast"]) {
            glyph = [HAIconMapper glyphForDomain:@"weather"];
        } else if ([section.cardType isEqualToString:@"media-control"]) {
            glyph = [HAIconMapper glyphForDomain:@"media_player"];
        }
    }

    if (glyph) {
        self.iconLabel.text = glyph;
        self.iconLabel.hidden = NO;
        self.titleLeadingNoIcon.active = NO;
        self.titleLeadingWithIcon.active = YES;
    } else {
        self.iconLabel.text = nil;
        self.iconLabel.hidden = YES;
        self.titleLeadingWithIcon.active = NO;
        self.titleLeadingNoIcon.active = YES;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.iconLabel.text = nil;
    self.iconLabel.hidden = YES;
    self.titleLabel.textColor = [HATheme sectionHeaderColor];
    self.iconLabel.textColor = [HATheme secondaryTextColor];
}

@end
