#import "HAInputNumberEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HAHaptics.h"
#import "HATheme.h"

@interface HAInputNumberEntityCell () <UITextFieldDelegate>
@property (nonatomic, strong) UISlider *valueSlider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UITextField *boxTextField;
@property (nonatomic, strong) UIButton *boxSubmitButton;
@property (nonatomic, assign) BOOL isBoxMode;
@property (nonatomic, assign) double entityMin;
@property (nonatomic, assign) double entityMax;
@property (nonatomic, assign) double entityStep;
@end

@implementation HAInputNumberEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Value label (right side, shows current number)
    self.valueLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightMedium] color:[HATheme primaryTextColor] lines:1];
    self.valueLabel.textAlignment = NSTextAlignmentRight;

    // Slider (shown in slider mode)
    self.valueSlider = [[UISlider alloc] init];
    self.valueSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.valueSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.valueSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.valueSlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.valueSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.contentView addSubview:self.valueSlider];

    // Box text field (shown in box mode)
    self.boxTextField = [[UITextField alloc] init];
    self.boxTextField.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
    self.boxTextField.textColor = [HATheme primaryTextColor];
    self.boxTextField.textAlignment = NSTextAlignmentCenter;
    self.boxTextField.keyboardType = UIKeyboardTypeDecimalPad;
    self.boxTextField.backgroundColor = [HATheme controlBackgroundColor];
    self.boxTextField.layer.cornerRadius = 8.0;
    self.boxTextField.layer.borderWidth = 1.0;
    self.boxTextField.layer.borderColor = [HATheme controlBorderColor].CGColor;
    self.boxTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.boxTextField.delegate = self;
    self.boxTextField.hidden = YES;
    [self.contentView addSubview:self.boxTextField];

    // Submit button for box mode
    self.boxSubmitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.boxSubmitButton setTitle:@"Set" forState:UIControlStateNormal];
    self.boxSubmitButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.boxSubmitButton.backgroundColor = [HATheme accentColor];
    [self.boxSubmitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.boxSubmitButton.layer.cornerRadius = 6.0;
    self.boxSubmitButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.boxSubmitButton.hidden = YES;
    [self.boxSubmitButton addTarget:self action:@selector(boxSubmitTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.boxSubmitButton];

    // Value label: top-right
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.valueLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.valueLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

    // Slider: bottom
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.valueSlider attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.valueSlider attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.valueSlider attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];

    // Box text field: bottom-left
    [NSLayoutConstraint activateConstraints:@[
        [self.boxTextField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.boxTextField.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
        [self.boxTextField.widthAnchor constraintEqualToConstant:120],
        [self.boxTextField.heightAnchor constraintEqualToConstant:32],
    ]];

    // Submit button: right of text field
    [NSLayoutConstraint activateConstraints:@[
        [self.boxSubmitButton.leadingAnchor constraintEqualToAnchor:self.boxTextField.trailingAnchor constant:8],
        [self.boxSubmitButton.centerYAnchor constraintEqualToAnchor:self.boxTextField.centerYAnchor],
        [self.boxSubmitButton.widthAnchor constraintEqualToConstant:50],
        [self.boxSubmitButton.heightAnchor constraintEqualToConstant:32],
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.valueSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.entityMin  = [entity inputNumberMin];
    self.entityMax  = [entity inputNumberMax];
    self.entityStep = [entity inputNumberStep];

    NSString *mode = entity.attributes[@"mode"];
    self.isBoxMode = [mode isKindOfClass:[NSString class]] && [mode isEqualToString:@"box"];

    double currentValue = [entity inputNumberValue];

    // Toggle slider vs box mode
    self.valueSlider.hidden = self.isBoxMode;
    self.boxTextField.hidden = !self.isBoxMode;
    self.boxSubmitButton.hidden = !self.isBoxMode;

    if (self.isBoxMode) {
        self.boxTextField.text = [self formatValue:currentValue];
        self.boxTextField.enabled = entity.isAvailable;
        self.boxSubmitButton.enabled = entity.isAvailable;
    } else {
        self.valueSlider.minimumValue = (float)self.entityMin;
        self.valueSlider.maximumValue = (float)self.entityMax;
        self.valueSlider.enabled = entity.isAvailable;
        if (!self.sliderDragging) {
            self.valueSlider.value = (float)currentValue;
        }
    }

    self.valueLabel.text = [self formatValue:currentValue];
    NSString *unit = [entity unitOfMeasurement];
    if (unit) {
        self.valueLabel.text = [NSString stringWithFormat:@"%@ %@", [self formatValue:currentValue], unit];
    }
}

- (NSString *)formatValue:(double)value {
    if (self.entityStep >= 1.0 && fmod(self.entityStep, 1.0) == 0.0) {
        return [NSString stringWithFormat:@"%.0f", value];
    }
    NSString *stepStr = [NSString stringWithFormat:@"%g", self.entityStep];
    NSRange dotRange = [stepStr rangeOfString:@"."];
    if (dotRange.location != NSNotFound) {
        NSUInteger decimals = stepStr.length - dotRange.location - 1;
        NSString *fmt = [NSString stringWithFormat:@"%%.%luf", (unsigned long)decimals];
        return [NSString stringWithFormat:fmt, value];
    }
    return [NSString stringWithFormat:@"%g", value];
}

- (double)snapToStep:(double)value {
    if (self.entityStep <= 0) return value;
    double snapped = round((value - self.entityMin) / self.entityStep) * self.entityStep + self.entityMin;
    return MIN(MAX(snapped, self.entityMin), self.entityMax);
}

#pragma mark - Slider Actions

- (void)sliderChanged:(UISlider *)sender {
    double snapped = [self snapToStep:sender.value];
    self.valueLabel.text = [self formatValue:snapped];
    NSString *unit = [self.entity unitOfMeasurement];
    if (unit) {
        self.valueLabel.text = [NSString stringWithFormat:@"%@ %@", [self formatValue:snapped], unit];
    }
}

- (void)sliderTouchUp:(UISlider *)sender {
    [super sliderTouchUp:sender];
    [HAHaptics lightImpact];
    double snapped = [self snapToStep:sender.value];
    sender.value = (float)snapped;
    NSDictionary *data = @{@"value": @(snapped)};
    [self callService:@"set_value" inDomain:[self.entity domain] withData:data];
}

#pragma mark - Box Actions

- (void)boxSubmitTapped {
    [self.boxTextField resignFirstResponder];
    [self submitBoxValue];
}

- (void)submitBoxValue {
    double value = [self.boxTextField.text doubleValue];
    double clamped = MIN(MAX(value, self.entityMin), self.entityMax);
    double snapped = [self snapToStep:clamped];

    [HAHaptics lightImpact];
    self.boxTextField.text = [self formatValue:snapped];
    NSDictionary *data = @{@"value": @(snapped)};
    [self callService:@"set_value" inDomain:[self.entity domain] withData:data];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self submitBoxValue];
    return YES;
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    self.valueLabel.text = nil;
    self.valueSlider.value = 0;
    self.valueSlider.hidden = NO;
    self.boxTextField.hidden = YES;
    self.boxTextField.text = nil;
    self.boxSubmitButton.hidden = YES;
    self.sliderDragging = NO;
    self.isBoxMode = NO;
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.boxTextField.textColor = [HATheme primaryTextColor];
    self.boxTextField.layer.borderColor = [HATheme controlBorderColor].CGColor;
    self.boxTextField.backgroundColor = [HATheme controlBackgroundColor];
    self.boxSubmitButton.backgroundColor = [HATheme accentColor];
}

@end
