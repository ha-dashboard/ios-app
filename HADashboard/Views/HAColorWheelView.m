#import "HAColorWheelView.h"

static void HSVtoRGB(CGFloat h, CGFloat s, CGFloat v, CGFloat *r, CGFloat *g, CGFloat *b) {
    if (s <= 0.0) { *r = *g = *b = v; return; }
    CGFloat hh = h * 6.0;
    if (hh >= 6.0) hh = 0.0;
    NSInteger i = (NSInteger)hh;
    CGFloat ff = hh - i;
    CGFloat p = v * (1.0 - s);
    CGFloat q = v * (1.0 - (s * ff));
    CGFloat t = v * (1.0 - (s * (1.0 - ff)));
    switch (i) {
        case 0: *r = v; *g = t; *b = p; break;
        case 1: *r = q; *g = v; *b = p; break;
        case 2: *r = p; *g = v; *b = t; break;
        case 3: *r = p; *g = q; *b = v; break;
        case 4: *r = t; *g = p; *b = v; break;
        default: *r = v; *g = p; *b = q; break;
    }
}

@interface HAColorWheelView () <UIGestureRecognizerDelegate>
@property (nonatomic, assign) CGFloat hue;
@property (nonatomic, assign) CGFloat saturation;
@property (nonatomic, strong) UIImageView *wheelImageView;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) UILongPressGestureRecognizer *dragGesture;
@property (nonatomic, assign) BOOL scrollViewWired;
@end

@implementation HAColorWheelView {
    CGImageRef _wheelImage;
    CGFloat _lastDiameter;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _hue = 0;
    _saturation = 0;
    _lastDiameter = 0;

    self.wheelImageView = [[UIImageView alloc] init];
    self.wheelImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.wheelImageView.userInteractionEnabled = YES;
    [self addSubview:self.wheelImageView];

    self.thumbView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    self.thumbView.layer.cornerRadius = 14;
    self.thumbView.layer.borderWidth = 3;
    self.thumbView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.thumbView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.thumbView.layer.shadowOpacity = 0.35;
    self.thumbView.layer.shadowOffset = CGSizeMake(0, 1);
    self.thumbView.layer.shadowRadius = 3;
    self.thumbView.backgroundColor = [UIColor redColor];
    self.thumbView.userInteractionEnabled = NO;
    [self addSubview:self.thumbView];

    // Use a long-press gesture with 0 delay — acts like a pan but fires immediately.
    // This lets us claim the touch before the scroll view's pan gesture does.
    self.dragGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    self.dragGesture.minimumPressDuration = 0;
    self.dragGesture.delegate = self;
    [self addGestureRecognizer:self.dragGesture];
}

- (void)dealloc {
    if (_wheelImage) {
        CGImageRelease(_wheelImage);
        _wheelImage = NULL;
    }
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat diameter = MIN(self.bounds.size.width, self.bounds.size.height);
    if (diameter < 1) return;

    CGFloat x = (self.bounds.size.width - diameter) / 2.0;
    CGFloat y = (self.bounds.size.height - diameter) / 2.0;
    self.wheelImageView.frame = CGRectMake(x, y, diameter, diameter);

    if (fabs(diameter - _lastDiameter) > 4.0) {
        _lastDiameter = diameter;
        [self regenerateWheelImage];
    }

    [self updateThumbPositionAnimated:NO];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Wire up scroll view gesture dependency once we're in the view hierarchy
    if (self.window && !self.scrollViewWired) {
        [self wireScrollViewGesture];
        self.scrollViewWired = YES;
    }
}

#pragma mark - Scroll View Gesture Wiring

- (void)wireScrollViewGesture {
    // Find enclosing scroll view and make its pan gesture require our drag gesture to fail.
    // This prevents the scroll view from scrolling while the user drags on the wheel.
    UIView *v = self.superview;
    while (v) {
        if ([v isKindOfClass:[UIScrollView class]]) {
            UIScrollView *sv = (UIScrollView *)v;
            [sv.panGestureRecognizer requireGestureRecognizerToFail:self.dragGesture];
            break;
        }
        v = v.superview;
    }
}

#pragma mark - Wheel Image Generation

- (void)regenerateWheelImage {
    if (_wheelImage) {
        CGImageRelease(_wheelImage);
        _wheelImage = NULL;
    }

    NSInteger dim = 256;
    NSInteger bytesPerRow = dim * 4;
    unsigned char *data = calloc(dim * dim, 4);
    if (!data) return;

    CGFloat cx = dim / 2.0;
    CGFloat cy = dim / 2.0;
    CGFloat radius = cx;

    for (NSInteger py = 0; py < dim; py++) {
        for (NSInteger px = 0; px < dim; px++) {
            CGFloat dx = px - cx;
            CGFloat dy = py - cy;
            CGFloat dist = sqrt(dx * dx + dy * dy);

            if (dist > radius) continue;

            CGFloat angle = atan2(dy, dx);
            CGFloat h = fmod(angle * 180.0 / M_PI + 360.0, 360.0) / 360.0;
            CGFloat s = dist / radius;

            CGFloat r, g, b;
            HSVtoRGB(h, s, 1.0, &r, &g, &b);

            NSInteger offset = (py * dim + px) * 4;
            data[offset + 0] = (unsigned char)(r * 255);
            data[offset + 1] = (unsigned char)(g * 255);
            data[offset + 2] = (unsigned char)(b * 255);
            data[offset + 3] = 255;
        }
    }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(data, dim, dim, 8, bytesPerRow, space,
                                              kCGImageAlphaPremultipliedLast);
    if (ctx) {
        _wheelImage = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(space);
    free(data);

    if (_wheelImage) {
        self.wheelImageView.image = [UIImage imageWithCGImage:_wheelImage];
    }
}

#pragma mark - Gesture Handling

- (void)handleDrag:(UILongPressGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            [self updateHSFromPoint:point];
            [self.delegate colorWheelView:self didChangeHue:self.hue saturation:self.saturation];
            break;

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [self.delegate colorWheelViewDidFinishChanging:self hue:self.hue saturation:self.saturation];
            break;

        default:
            break;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.dragGesture) return YES;

    // Only begin if touch is inside (or near) the wheel circle
    CGPoint point = [gestureRecognizer locationInView:self];
    CGFloat cx = self.bounds.size.width / 2.0;
    CGFloat cy = self.bounds.size.height / 2.0;
    CGFloat radius = MIN(cx, cy);
    CGFloat dx = point.x - cx;
    CGFloat dy = point.y - cy;
    CGFloat dist = sqrt(dx * dx + dy * dy);

    return dist <= radius + 20;
}

#pragma mark - Coordinate Math

- (void)updateHSFromPoint:(CGPoint)point {
    CGFloat cx = self.bounds.size.width / 2.0;
    CGFloat cy = self.bounds.size.height / 2.0;
    CGFloat radius = MIN(cx, cy);

    CGFloat dx = point.x - cx;
    CGFloat dy = point.y - cy;
    CGFloat dist = sqrt(dx * dx + dy * dy);

    // Clamp to circle
    if (dist > radius) {
        dx = dx / dist * radius;
        dy = dy / dist * radius;
        dist = radius;
    }

    self.hue = fmod(atan2(dy, dx) * 180.0 / M_PI + 360.0, 360.0);
    self.saturation = (dist / radius) * 100.0;

    [self updateThumbPositionAnimated:NO];
    [self updateThumbColor];
}

- (void)updateThumbPositionAnimated:(BOOL)animated {
    CGFloat cx = self.bounds.size.width / 2.0;
    CGFloat cy = self.bounds.size.height / 2.0;
    CGFloat radius = MIN(cx, cy);
    if (radius < 1) return;

    CGFloat angleRad = self.hue * M_PI / 180.0;
    CGFloat dist = (self.saturation / 100.0) * radius;
    CGPoint center = CGPointMake(cx + cos(angleRad) * dist, cy + sin(angleRad) * dist);

    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            self.thumbView.center = center;
        }];
    } else {
        self.thumbView.center = center;
    }
}

- (void)updateThumbColor {
    CGFloat r, g, b;
    HSVtoRGB(self.hue / 360.0, self.saturation / 100.0, 1.0, &r, &g, &b);
    self.thumbView.backgroundColor = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

#pragma mark - Public API

- (void)setHue:(CGFloat)hue saturation:(CGFloat)saturation animated:(BOOL)animated {
    _hue = hue;
    _saturation = saturation;
    [self updateThumbPositionAnimated:animated];
    [self updateThumbColor];
}

@end
