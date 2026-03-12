#import "HAAutoLayout.h"
#import "HASectionHeaderView.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "UIFont+HACompat.h"

@interface HASectionHeaderView ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingWithIcon;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingNoIcon;
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
    self.iconLabel.textAlignment = NSTextAlignmentCenter;
    self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.iconLabel];

    // Title label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont ha_systemFontOfSize:17 weight:HAFontWeightSemibold];
    self.titleLabel.textColor = [HATheme sectionHeaderColor];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.titleLabel];

    // Layout: icon (fixed 24pt width) | 4pt gap | title
    // Two title leading constraints: with-icon (after icon) and no-icon (flush left).
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.iconLabel.widthAnchor constraintEqualToConstant:24],
    
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }
    if (HAAutoLayoutAvailable()) {
        self.titleLeadingWithIcon = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:4];
    }
    if (HAAutoLayoutAvailable()) {
        self.titleLeadingNoIcon = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16];
    }
    self.titleLeadingNoIcon.active = YES;
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

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;
        if (!self.iconLabel.hidden) {
            self.iconLabel.frame = CGRectMake(16, (h - 24) / 2, 24, 24);
            CGFloat titleX = CGRectGetMaxX(self.iconLabel.frame) + 4;
            self.titleLabel.frame = CGRectMake(titleX, (h - 20) / 2, w - 16 - titleX, 20);
        } else {
            self.titleLabel.frame = CGRectMake(16, (h - 20) / 2, w - 32, 20);
        }
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
