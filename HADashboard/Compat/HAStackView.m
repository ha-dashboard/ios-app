#import "HAStackView.h"
#import "HAAutoLayout.h"

@interface HAStackView ()
@property (nonatomic, strong) NSMutableArray<UIView *> *mutableArrangedSubviews;
/// The real UIStackView used on iOS 9+.  nil on older systems.
@property (nonatomic, strong) UIView *nativeStack; // typed as UIView to compile on older SDKs
@end

@implementation HAStackView

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _mutableArrangedSubviews = [NSMutableArray array];
        _spacing = 0;
        _axis = 1; // vertical by default
        _distribution = 0; // fill
        _alignment = 0; // fill
        [self setupNativeStackIfAvailable];
    }
    return self;
}

- (instancetype)initWithArrangedSubviews:(NSArray<UIView *> *)views {
    self = [self initWithFrame:CGRectZero];
    if (self) {
        for (UIView *v in views) {
            [self addArrangedSubview:v];
        }
    }
    return self;
}

- (void)setupNativeStackIfAvailable {
    if (!HAAutoLayoutAvailable()) return;

    UIStackView *native = [[UIStackView alloc] init];
    native.translatesAutoresizingMaskIntoConstraints = NO;
    [super addSubview:native];

    // Pin native stack to our edges
    [NSLayoutConstraint activateConstraints:@[
        [native.topAnchor constraintEqualToAnchor:self.topAnchor],
        [native.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [native.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [native.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    self.nativeStack = native;
    [self syncNativeProperties];
}

#pragma mark - Property Setters

- (void)setAxis:(NSInteger)axis {
    _axis = axis;
    [self syncNativeProperties];
    [self setNeedsLayout];
}

- (void)setSpacing:(CGFloat)spacing {
    _spacing = spacing;
    [self syncNativeProperties];
    [self setNeedsLayout];
}

- (void)setDistribution:(NSInteger)distribution {
    _distribution = distribution;
    [self syncNativeProperties];
    [self setNeedsLayout];
}

- (void)setAlignment:(NSInteger)alignment {
    _alignment = alignment;
    [self syncNativeProperties];
    [self setNeedsLayout];
}

- (void)syncNativeProperties {
    if (!self.nativeStack) return;
    UIStackView *native = (UIStackView *)self.nativeStack;
    native.axis = (UILayoutConstraintAxis)self.axis;
    native.spacing = self.spacing;

    // Map distribution values to UIStackViewDistribution enum
    // 0=fill, 1=fillEqually, 2=fillProportionally, 3=equalSpacing, 4=equalCentering
    native.distribution = (UIStackViewDistribution)self.distribution;

    // Map alignment values to UIStackViewAlignment enum
    // 0=fill, 1=leading/top, 2=firstBaseline, 3=center, 4=lastBaseline, 5=trailing/bottom
    native.alignment = (UIStackViewAlignment)self.alignment;
}

#pragma mark - Arranged Subviews

- (NSArray<UIView *> *)arrangedSubviews {
    return [self.mutableArrangedSubviews copy];
}

- (void)addArrangedSubview:(UIView *)view {
    if (!view) return;
    [self.mutableArrangedSubviews addObject:view];
    if (self.nativeStack) {
        [(UIStackView *)self.nativeStack addArrangedSubview:view];
    } else {
        [self addSubview:view];
    }
    [self setNeedsLayout];
}

- (void)removeArrangedSubview:(UIView *)view {
    if (!view) return;
    [self.mutableArrangedSubviews removeObject:view];
    if (self.nativeStack) {
        [(UIStackView *)self.nativeStack removeArrangedSubview:view];
    }
    [self setNeedsLayout];
}

- (void)insertArrangedSubview:(UIView *)view atIndex:(NSUInteger)index {
    if (!view) return;
    if (index > self.mutableArrangedSubviews.count) {
        index = self.mutableArrangedSubviews.count;
    }
    [self.mutableArrangedSubviews insertObject:view atIndex:index];
    if (self.nativeStack) {
        [(UIStackView *)self.nativeStack insertArrangedSubview:view atIndex:index];
    } else {
        [self addSubview:view];
    }
    [self setNeedsLayout];
}

#pragma mark - Fallback Layout (iOS 5-8)

- (void)layoutSubviews {
    [super layoutSubviews];

    // On iOS 9+ the native UIStackView handles layout
    if (self.nativeStack) return;

    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *v in self.mutableArrangedSubviews) {
        if (!v.hidden) [visible addObject:v];
    }
    if (visible.count == 0) return;

    BOOL vertical = (self.axis == 1);
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat totalSpacing = self.spacing * (visible.count - 1);

    if (self.distribution == 1) {
        // fillEqually
        if (vertical) {
            CGFloat itemH = (h - totalSpacing) / visible.count;
            CGFloat y = 0;
            for (UIView *v in visible) {
                v.frame = CGRectMake(0, y, w, itemH);
                [v setNeedsLayout];
                y += itemH + self.spacing;
            }
        } else {
            CGFloat itemW = (w - totalSpacing) / visible.count;
            CGFloat x = 0;
            for (UIView *v in visible) {
                v.frame = CGRectMake(x, 0, itemW, h);
                [v setNeedsLayout];
                x += itemW + self.spacing;
            }
        }
    } else {
        // fill: use sizeThatFits for each view
        if (vertical) {
            CGFloat y = 0;
            for (UIView *v in visible) {
                CGSize fit = [v sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
                CGFloat itemH = fit.height;
                if (self.alignment == 3) {
                    // center horizontally
                    CGFloat itemW = MIN(fit.width, w);
                    v.frame = CGRectMake((w - itemW) / 2.0, y, itemW, itemH);
                } else {
                    v.frame = CGRectMake(0, y, w, itemH);
                }
                [v setNeedsLayout];
                y += itemH + self.spacing;
            }
        } else {
            CGFloat x = 0;
            for (UIView *v in visible) {
                CGSize fit = [v sizeThatFits:CGSizeMake(CGFLOAT_MAX, h)];
                CGFloat itemW = fit.width;
                if (self.alignment == 3) {
                    CGFloat itemH = MIN(fit.height, h);
                    v.frame = CGRectMake(x, (h - itemH) / 2.0, itemW, itemH);
                } else {
                    v.frame = CGRectMake(x, 0, itemW, h);
                }
                [v setNeedsLayout];
                x += itemW + self.spacing;
            }
        }
    }

    // Force immediate child layout so subviews position correctly
    // in the same layout pass (children need their new bounds to
    // calculate internal frame positions)
    for (UIView *v in visible) {
        [v layoutIfNeeded];
    }
}

- (CGSize)intrinsicContentSize {
    if (self.nativeStack) {
        return [self.nativeStack intrinsicContentSize];
    }

    CGFloat totalW = 0, totalH = 0;
    NSInteger visibleCount = 0;
    BOOL vertical = (self.axis == 1);

    for (UIView *v in self.mutableArrangedSubviews) {
        if (v.hidden) continue;
        visibleCount++;
        CGSize fit = [v sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        if (vertical) {
            totalH += fit.height;
            if (fit.width > totalW) totalW = fit.width;
        } else {
            totalW += fit.width;
            if (fit.height > totalH) totalH = fit.height;
        }
    }

    if (visibleCount > 1) {
        CGFloat sp = self.spacing * (visibleCount - 1);
        if (vertical) totalH += sp; else totalW += sp;
    }

    return CGSizeMake(totalW, totalH);
}

- (CGSize)sizeThatFits:(CGSize)size {
    if (self.nativeStack) {
        return [self.nativeStack sizeThatFits:size];
    }
    return [self intrinsicContentSize];
}

@end
