#import "HAInputSelectEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "UIView+HAUtilities.h"

@interface HAInputSelectEntityCell ()
@property (nonatomic, strong) UIButton *optionButton;
@end

@implementation HAInputSelectEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    self.optionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.optionButton.titleLabel.font = [UIFont systemFontOfSize:15];
    self.optionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.optionButton.backgroundColor = [HATheme controlBackgroundColor];
    self.optionButton.layer.cornerRadius = 6.0;
    self.optionButton.layer.borderColor = [[HATheme controlBorderColor] CGColor];
    self.optionButton.layer.borderWidth = 0.5;
    self.optionButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    self.optionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.optionButton addTarget:self action:@selector(optionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.optionButton];

    // Button: below name, full width
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.optionButton attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.optionButton attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.optionButton attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.optionButton attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:36]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSString *current = [entity inputSelectCurrentOption];
    [self.optionButton setTitle:current ?: @"—" forState:UIControlStateNormal];
    self.optionButton.enabled = entity.isAvailable;
}

#pragma mark - Actions

- (void)optionButtonTapped {
    if (!self.entity) return;

    NSArray<NSString *> *options = [self.entity inputSelectOptions];
    if (options.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self.entity friendlyName]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *current = [self.entity inputSelectCurrentOption];

    for (NSString *option in options) {
        BOOL isSelected = [option isEqualToString:current];
        NSString *title = isSelected ? [NSString stringWithFormat:@"\u2713 %@", option] : option;

        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *a) {
            [self selectOption:option];
        }];
        [alert addAction:action];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover anchor
    alert.popoverPresentationController.sourceView = self.optionButton;
    alert.popoverPresentationController.sourceRect = self.optionButton.bounds;

    UIViewController *vc = [self ha_parentViewController];
    if (vc) {
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

- (void)selectOption:(NSString *)option {
    [HAHaptics selectionChanged];

    [self.optionButton setTitle:option forState:UIControlStateNormal];

    NSDictionary *data = @{@"option": option};
    [self callService:@"select_option" inDomain:[self.entity domain] withData:data];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.optionButton setTitle:nil forState:UIControlStateNormal];
    self.optionButton.backgroundColor = [HATheme controlBackgroundColor];
    self.optionButton.layer.borderColor = [HATheme controlBorderColor].CGColor;
}

@end
