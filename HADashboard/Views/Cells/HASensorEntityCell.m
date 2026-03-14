#import "HASensorEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAEntityDisplayHelper.h"

@interface HASensorEntityCell ()
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@end

@implementation HASensorEntityCell

- (void)setupSubviews {
    [super setupSubviews];

    // Override: use a large value display
    self.stateLabel.hidden = YES;

    self.valueLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightMedium]
                                     color:[HATheme primaryTextColor] lines:1];
    self.valueLabel.textAlignment = NSTextAlignmentLeft;
    self.valueLabel.adjustsFontSizeToFitWidth = YES;
    self.valueLabel.minimumScaleFactor = 0.5;

    self.unitLabel = [self labelWithFont:[UIFont systemFontOfSize:14] color:[HATheme secondaryTextColor] lines:1];

    CGFloat padding = 10.0;
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.valueLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.valueLabel attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];

    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.unitLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.valueLabel attribute:NSLayoutAttributeTrailing multiplier:1 constant:4]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.unitLabel attribute:NSLayoutAttributeBaseline
        relatedBy:NSLayoutRelationEqual toItem:self.valueLabel attribute:NSLayoutAttributeBaseline multiplier:1 constant:0]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.unitLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.valueLabel.text = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:2];
    self.unitLabel.text = [entity unitOfMeasurement] ?: @"";

    // Color code binary sensors
    if ([[entity domain] isEqualToString:@"binary_sensor"]) {
        [self applyOnStateTint:entity.isOn];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.valueLabel.text = nil;
    self.unitLabel.text = nil;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.unitLabel.textColor = [HATheme secondaryTextColor];
}

@end
