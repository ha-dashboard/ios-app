#import "HAAutoLayout.h"
#import "HASliderFeatureView.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAEntityDisplayHelper.h"
#import "UIFont+HACompat.h"

@interface HASliderFeatureView ()
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, assign) BOOL isTracking;  // Suppress external updates while user is dragging
@property (nonatomic, copy) NSString *valueSuffix; // Stored for drag display (fix #7)
@end

@implementation HASliderFeatureView

+ (CGFloat)preferredHeight {
    return 44.0;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.slider = [[UISlider alloc] init];
    self.slider.translatesAutoresizingMaskIntoConstraints = NO;
    self.slider.minimumValue = 0;
    self.slider.maximumValue = 100;
    self.slider.continuous = YES;
    [self.slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    [self.slider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpOutside];
    [self addSubview:self.slider];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.valueLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    self.valueLabel.textColor = [HATheme secondaryTextColor];
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    if (HAAutoLayoutAvailable()) {
        [self.valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:0];
        [self.valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:0];
    }
    [self addSubview:self.valueLabel];

    // Fix #5: use DefaultHigh instead of Required for height constraint
    if (HAAutoLayoutAvailable()) {
        NSLayoutConstraint *heightConstraint = [self.heightAnchor constraintEqualToConstant:[HASliderFeatureView preferredHeight]];
        heightConstraint.priority = UILayoutPriorityDefaultHigh;

        HAActivateConstraints(@[
            HACon([self.slider.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12]),
            HACon([self.slider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]),
            HACon([self.slider.trailingAnchor constraintEqualToAnchor:self.valueLabel.leadingAnchor constant:-8]),
            HACon([self.valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12]),
            HACon([self.valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]),
            HACon([self.valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:36]),
            HACon(heightConstraint),
        ]);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat h = [HASliderFeatureView preferredHeight];
        CGFloat w = self.bounds.size.width;
        CGSize valSize = [self.valueLabel sizeThatFits:CGSizeMake(w, h)];
        CGFloat valW = MAX(36, valSize.width);
        self.valueLabel.frame = CGRectMake(w - 12 - valW, (h - valSize.height) / 2, valW, valSize.height);
        self.slider.frame = CGRectMake(12, (h - 31) / 2, w - 24 - 8 - valW, 31);
    }
}

- (void)configureWithEntity:(HAEntity *)entity featureConfig:(NSDictionary *)config {
    [super configureWithEntity:entity featureConfig:config];

    NSString *type = config[@"type"];
    CGFloat value = 0;
    CGFloat min = 0;
    CGFloat max = 100;
    NSString *suffix = @"%";

    if ([type isEqualToString:@"light-brightness"]) {
        value = [entity brightnessPercent];
        if (![entity isOn]) value = 0;
    } else if ([type isEqualToString:@"cover-position"]) {
        value = [entity coverPosition];
    } else if ([type isEqualToString:@"cover-tilt-position"]) {
        NSNumber *tilt = entity.attributes[@"current_tilt_position"];
        value = tilt ? [tilt floatValue] : 0;
    } else if ([type isEqualToString:@"fan-speed"]) {
        value = [entity fanSpeedPercent];
        if (![entity isOn]) value = 0;
    } else if ([type isEqualToString:@"light-color-temp"]) {
        // Fix #1: Use Kelvin instead of mireds
        NSNumber *minKelvin = entity.attributes[@"min_color_temp_kelvin"];
        NSNumber *maxKelvin = entity.attributes[@"max_color_temp_kelvin"];
        NSNumber *curKelvin = entity.attributes[@"color_temp_kelvin"];
        min = minKelvin ? [minKelvin floatValue] : 2000;
        max = maxKelvin ? [maxKelvin floatValue] : 6500;
        value = curKelvin ? [curKelvin floatValue] : min;
        suffix = @"K";
    } else if ([type isEqualToString:@"media-player-volume-slider"]) {
        NSNumber *vol = entity.attributes[@"volume_level"];
        value = vol ? [vol floatValue] * 100.0 : 0;
    } else if ([type isEqualToString:@"numeric-input"]) {
        value = [entity.state floatValue];
        NSNumber *attrMin = entity.attributes[@"min"];
        NSNumber *attrMax = entity.attributes[@"max"];
        if (attrMin) min = [attrMin floatValue];
        if (attrMax) max = [attrMax floatValue];
        NSString *unit = entity.unitOfMeasurement;
        suffix = unit.length > 0 ? unit : @"";
    } else if ([type isEqualToString:@"target-humidity"]) {
        NSNumber *humidity = entity.attributes[@"humidity"];
        value = humidity ? [humidity floatValue] : 0;
        NSNumber *attrMin = entity.attributes[@"min_humidity"];
        NSNumber *attrMax = entity.attributes[@"max_humidity"];
        if (attrMin) min = [attrMin floatValue];
        if (attrMax) max = [attrMax floatValue];
    }

    self.valueSuffix = suffix; // Fix #7: store suffix for drag display
    self.slider.minimumValue = min;
    self.slider.maximumValue = max;
    if (!self.isTracking) {
        self.slider.value = value;
    }

    // Format value label
    if ([suffix length] > 0) {
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f%@", value, suffix];
    } else {
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f", value];
    }

    // Tint: use entity accent color when active
    UIColor *tintColor = [entity isOn] || [entity.state isEqualToString:@"open"]
        ? [HAEntityDisplayHelper iconColorForEntity:entity]
        : [HATheme secondaryTextColor];
    self.slider.minimumTrackTintColor = tintColor;

    // Disable when entity unavailable
    BOOL available = entity.isAvailable;
    self.slider.enabled = available;
    self.alpha = available ? 1.0 : 0.4;
}

#pragma mark - Slider Events

- (void)sliderTouchDown:(UISlider *)slider {
    self.isTracking = YES;
}

- (void)sliderValueChanged:(UISlider *)slider {
    // Fix #7: Use stored suffix during drag instead of hardcoded "%"
    NSString *suffix = self.valueSuffix ?: @"%";
    if ([suffix length] > 0) {
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f%@", slider.value, suffix];
    } else {
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f", slider.value];
    }
}

- (void)sliderTouchUp:(UISlider *)slider {
    self.isTracking = NO;
    [HAHaptics lightImpact];

    NSString *type = self.featureType;
    NSString *entityId = self.entity.entityId;
    if (!entityId) return;

    NSString *service = nil;
    NSString *domain = nil;
    NSDictionary *data = nil;

    if ([type isEqualToString:@"light-brightness"]) {
        domain = @"light";
        service = @"turn_on";
        data = @{@"entity_id": entityId, @"brightness_pct": @((NSInteger)slider.value)};
    } else if ([type isEqualToString:@"cover-position"]) {
        domain = @"cover";
        service = @"set_cover_position";
        data = @{@"entity_id": entityId, @"position": @((NSInteger)slider.value)};
    } else if ([type isEqualToString:@"cover-tilt-position"]) {
        domain = @"cover";
        service = @"set_cover_tilt_position";
        data = @{@"entity_id": entityId, @"tilt_position": @((NSInteger)slider.value)};
    } else if ([type isEqualToString:@"fan-speed"]) {
        domain = @"fan";
        service = @"set_percentage";
        data = @{@"entity_id": entityId, @"percentage": @((NSInteger)slider.value)};
    } else if ([type isEqualToString:@"light-color-temp"]) {
        // Fix #1: Send color_temp_kelvin instead of color_temp (mireds)
        domain = @"light";
        service = @"turn_on";
        data = @{@"entity_id": entityId, @"color_temp_kelvin": @((NSInteger)slider.value)};
    } else if ([type isEqualToString:@"media-player-volume-slider"]) {
        domain = @"media_player";
        service = @"volume_set";
        data = @{@"entity_id": entityId, @"volume_level": @(slider.value / 100.0)};
    } else if ([type isEqualToString:@"numeric-input"]) {
        domain = [self.entity domain];
        service = @"set_value";
        data = @{@"entity_id": entityId, @"value": @(slider.value)};
    } else if ([type isEqualToString:@"target-humidity"]) {
        domain = @"humidifier";
        service = @"set_humidity";
        data = @{@"entity_id": entityId, @"humidity": @((NSInteger)slider.value)};
    }

    if (self.serviceCallBlock && service && domain && data) {
        self.serviceCallBlock(service, domain, data);
    }
}

@end
