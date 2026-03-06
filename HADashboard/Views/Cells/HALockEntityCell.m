#import "HALockEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "UIView+HAUtilities.h"

@interface HALockEntityCell ()
@property (nonatomic, strong) UIButton *lockButton;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UILabel *lockStateLabel;
@end

@implementation HALockEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Lock state indicator
    self.lockStateLabel = [self labelWithFont:[UIFont systemFontOfSize:24] color:[HATheme primaryTextColor] lines:1];
    self.lockStateLabel.textAlignment = NSTextAlignmentCenter;

    // Lock/unlock button
    self.lockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.lockButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.lockButton.layer.cornerRadius = 6.0;
    self.lockButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.lockButton addTarget:self action:@selector(lockButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.lockButton];

    // State icon: right of name
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.lockStateLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.lockStateLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

    // Open button (unlatch/release — only shown when entity supports it)
    self.openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.openButton setTitle:@"Open" forState:UIControlStateNormal];
    self.openButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.openButton.layer.cornerRadius = 6.0;
    self.openButton.backgroundColor = [HATheme accentColor];
    [self.openButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.openButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.openButton.hidden = YES;
    [self.openButton addTarget:self action:@selector(openButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.openButton];

    // Lock button: bottom-right
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.lockButton attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.lockButton attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.lockButton attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:70]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.lockButton attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:32]];

    // Open button: left of lock button
    [NSLayoutConstraint activateConstraints:@[
        [self.openButton.trailingAnchor constraintEqualToAnchor:self.lockButton.leadingAnchor constant:-6],
        [self.openButton.centerYAnchor constraintEqualToAnchor:self.lockButton.centerYAnchor],
        [self.openButton.widthAnchor constraintGreaterThanOrEqualToConstant:60],
        [self.openButton.heightAnchor constraintEqualToConstant:32],
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.lockButton.enabled = entity.isAvailable;

    // Show "Open" button when entity supports open (unlatch) — LockEntityFeature.OPEN = 1
    BOOL supportsOpen = ([entity supportedFeatures] & 1) != 0;
    self.openButton.hidden = !supportsOpen || !entity.isAvailable;
    self.openButton.enabled = entity.isAvailable;

    if ([entity isLocked]) {
        self.lockStateLabel.text = @"\U0001F512"; // locked padlock
        [self.lockButton setTitle:@"Unlock" forState:UIControlStateNormal];
        self.lockButton.backgroundColor = [HATheme destructiveColor];
        [self.lockButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.contentView.backgroundColor = [HATheme onTintColor];
    } else if ([entity isJammed]) {
        self.lockStateLabel.text = @"\u26A0"; // warning
        [self.lockButton setTitle:@"Lock" forState:UIControlStateNormal];
        self.lockButton.backgroundColor = [HATheme warningColor];
        [self.lockButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.contentView.backgroundColor = [HATheme onTintColor];
    } else {
        // unlocked or unlocking/locking
        self.lockStateLabel.text = @"\U0001F513"; // unlocked padlock
        [self.lockButton setTitle:@"Lock" forState:UIControlStateNormal];
        self.lockButton.backgroundColor = [HATheme successColor];
        [self.lockButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

#pragma mark - Actions

- (void)lockButtonTapped {
    if (!self.entity) return;

    BOOL isLocked = [self.entity isLocked];
    NSString *actionTitle = isLocked ? @"Unlock" : @"Lock";
    NSString *message = [NSString stringWithFormat:@"%@ %@?", actionTitle, [self.entity friendlyName]];

    // Check if entity requires a code
    NSString *codeFormat = HAAttrString(self.entity.attributes, HAAttrCodeFormat);
    BOOL needsCode = (codeFormat != nil);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:actionTitle
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    if (needsCode) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Enter code";
            textField.secureTextEntry = YES;
            // Use numeric keyboard for numeric code patterns
            if ([codeFormat isEqualToString:@"number"] ||
                [codeFormat rangeOfString:@"\\d"].location != NSNotFound) {
                textField.keyboardType = UIKeyboardTypeNumberPad;
            } else {
                textField.keyboardType = UIKeyboardTypeDefault;
            }
        }];
    }

    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:isLocked ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        NSString *code = needsCode ? alert.textFields.firstObject.text : nil;
        [self performLockAction:isLocked code:code];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = [self ha_parentViewController];
    if (vc) {
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

- (void)openButtonTapped {
    if (!self.entity) return;
    [HAHaptics heavyImpact];
    [self callService:@"open" inDomain:HAEntityDomainLock];
}

- (void)performLockAction:(BOOL)currentlyLocked code:(NSString *)code {
    [HAHaptics heavyImpact];

    NSString *service = currentlyLocked ? @"unlock" : @"lock";
    NSDictionary *data = (code.length > 0) ? @{@"code": code} : nil;
    [self callService:service inDomain:HAEntityDomainLock withData:data];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.lockStateLabel.text = nil;
    self.openButton.hidden = YES;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

@end
