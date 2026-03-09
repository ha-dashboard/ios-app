#import "HAAutoLayout.h"
#import "HAAttributeRowView.h"
#import "HATheme.h"

@interface HAAttributeRowView ()
@property (nonatomic, strong) UILabel *keyLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation HAAttributeRowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    self.keyLabel = [[UILabel alloc] init];
    self.keyLabel.font = [UIFont systemFontOfSize:13];
    self.keyLabel.textColor = [HATheme secondaryTextColor];
    self.keyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.keyLabel.numberOfLines = 1;
    [self addSubview:self.keyLabel];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.numberOfLines = 2;
    self.valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.valueLabel];

    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.keyLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.keyLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.keyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.valueLabel.leadingAnchor constant:-8],
    
            [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.valueLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.6],
    
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:28],
        ]];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = MAX(28, self.bounds.size.height);
        CGFloat valW = w * 0.6;
        CGSize keySize = [self.keyLabel sizeThatFits:CGSizeMake(w - valW - 8, CGFLOAT_MAX)];
        self.keyLabel.frame = CGRectMake(0, (h - keySize.height) / 2, w - valW - 8, keySize.height);
        CGSize valSize = [self.valueLabel sizeThatFits:CGSizeMake(valW, CGFLOAT_MAX)];
        self.valueLabel.frame = CGRectMake(w - valW, (h - valSize.height) / 2, valW, valSize.height);
    }
}

- (void)configureWithKey:(NSString *)key value:(NSString *)value {
    self.keyLabel.text = key;
    self.valueLabel.text = value;
}

@end
