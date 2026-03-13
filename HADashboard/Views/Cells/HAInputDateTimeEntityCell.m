#import "HAAutoLayout.h"
#import "HAInputDateTimeEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import <objc/runtime.h>
#import "UIView+HAUtilities.h"
#import "UIFont+HACompat.h"

@interface HAInputDateTimeEntityCell ()
@property (nonatomic, strong) UIButton *valueButton;
@property (nonatomic, assign) BOOL hasDate;
@property (nonatomic, assign) BOOL hasTime;
@end

@implementation HAInputDateTimeEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    self.valueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.valueButton.titleLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:18 weight:HAFontWeightMedium];
    self.valueButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.valueButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.valueButton addTarget:self action:@selector(valueTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.valueButton];

    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.valueButton attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.valueButton attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.valueButton attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGSize btnSize = [self.valueButton sizeThatFits:CGSizeMake(w - padding * 2, CGFLOAT_MAX)];
        self.valueButton.frame = CGRectMake(padding, h - padding - btnSize.height, w - padding * 2, btnSize.height);
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.hasDate = [entity inputDatetimeHasDate];
    self.hasTime = [entity inputDatetimeHasTime];

    NSString *display = [entity inputDatetimeDisplayString];
    [self.valueButton setTitle:display ?: @"—" forState:UIControlStateNormal];
    self.valueButton.enabled = entity.isAvailable;
}

#pragma mark - Actions

- (void)valueTapped {
    if (!self.entity) return;

    // Present a UIDatePicker in an alert-style popover
    UIViewController *pickerVC = [[UIViewController alloc] init];
    pickerVC.modalPresentationStyle = UIModalPresentationPopover;

    UIDatePicker *picker = [[UIDatePicker alloc] init];
    if (self.hasDate && self.hasTime) {
        picker.datePickerMode = UIDatePickerModeDateAndTime;
    } else if (self.hasDate) {
        picker.datePickerMode = UIDatePickerModeDate;
    } else {
        picker.datePickerMode = UIDatePickerModeTime;
    }

    NSDate *current = [self.entity inputDatetimeValue];
    if (current) {
        picker.date = current;
    }

    picker.translatesAutoresizingMaskIntoConstraints = NO;
    [pickerVC.view addSubview:picker];
    HAActivateConstraints(@[
        HACon([picker.leadingAnchor constraintEqualToAnchor:pickerVC.view.leadingAnchor]),
        HACon([picker.trailingAnchor constraintEqualToAnchor:pickerVC.view.trailingAnchor]),
        HACon([picker.topAnchor constraintEqualToAnchor:pickerVC.view.topAnchor]),
        HACon([picker.bottomAnchor constraintEqualToAnchor:pickerVC.view.bottomAnchor]),
    ]);

    pickerVC.preferredContentSize = CGSizeMake(320, 216);

    // Done button in nav bar
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pickerVC];
    nav.modalPresentationStyle = UIModalPresentationPopover;
    pickerVC.title = [self.entity friendlyName];
    pickerVC.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(pickerDone:)];

    // Store picker reference via objc_setAssociatedObject so we can read it in pickerDone
    objc_setAssociatedObject(self, @selector(valueTapped), picker, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, @selector(pickerDone:), nav, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // iPad popover
    nav.popoverPresentationController.sourceView = self.valueButton;
    nav.popoverPresentationController.sourceRect = self.valueButton.bounds;
    nav.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;

    UIViewController *vc = [self ha_parentViewController];
    if (vc) {
        [vc presentViewController:nav animated:YES completion:nil];
    }
}

- (void)pickerDone:(UIBarButtonItem *)sender {
    UIDatePicker *picker = objc_getAssociatedObject(self, @selector(valueTapped));
    UINavigationController *nav = objc_getAssociatedObject(self, @selector(pickerDone:));

    if (picker && self.entity) {
        [self sendDatetimeValue:picker.date];
    }

    [nav dismissViewControllerAnimated:YES completion:nil];

    objc_setAssociatedObject(self, @selector(valueTapped), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, @selector(pickerDone:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)sendDatetimeValue:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comp = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                              NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                    fromDate:date];

    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (self.hasDate) {
        data[@"date"] = [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
            (long)comp.year, (long)comp.month, (long)comp.day];
    }
    if (self.hasTime) {
        data[@"time"] = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",
            (long)comp.hour, (long)comp.minute, (long)comp.second];
    }

    [self callService:@"set_datetime" inDomain:@"input_datetime" withData:data];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Dismiss any presented date picker modal to prevent orphaned modals
    UINavigationController *nav = objc_getAssociatedObject(self, @selector(pickerDone:));
    if (nav.presentingViewController) {
        [nav dismissViewControllerAnimated:NO completion:nil];
    }
    [self.valueButton setTitle:nil forState:UIControlStateNormal];
    objc_setAssociatedObject(self, @selector(valueTapped), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, @selector(pickerDone:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
