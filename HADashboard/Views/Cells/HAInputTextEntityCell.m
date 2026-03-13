#import "HAAutoLayout.h"
#import "HAInputTextEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HAEntityDisplayHelper.h"

@interface HAInputTextEntityCell () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, assign) BOOL isEditing;
@end

@implementation HAInputTextEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    self.textField = [[UITextField alloc] init];
    self.textField.borderStyle = UITextBorderStyleRoundedRect;
    self.textField.font = [UIFont systemFontOfSize:15];
    self.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textField.returnKeyType = UIReturnKeyDone;
    self.textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.textField.delegate = self;
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.textField];

    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.textField attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.textField attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.textField attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.textField attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:36]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        self.textField.frame = CGRectMake(padding, h - padding - 36, w - padding * 2, 36);
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    // Only update text if not currently being edited
    if (!self.isEditing) {
        self.textField.text = [entity inputTextValue];
    }

    self.textField.enabled = entity.isAvailable;
    self.textField.placeholder = [HAEntityDisplayHelper displayNameForEntity:entity configItem:configItem nameOverride:nil];

    // Password mode
    BOOL isPassword = [[entity inputTextMode] isEqualToString:@"password"];
    self.textField.secureTextEntry = isPassword;
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.isEditing = YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (!self.entity) return YES;

    NSString *newText = [textField.text stringByReplacingCharactersInRange:range withString:string];
    NSInteger maxLen = [self.entity inputTextMaxLength];
    if (maxLen > 0 && (NSInteger)newText.length > maxLen) {
        return NO;
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.isEditing = NO;
    if (!self.entity) return;

    NSString *newValue = textField.text ?: @"";
    NSString *currentValue = [self.entity inputTextValue] ?: @"";

    // Only send if value actually changed
    if ([newValue isEqualToString:currentValue]) return;

    // Validate min length
    NSInteger minLen = [self.entity inputTextMinLength];
    if ((NSInteger)newValue.length < minLen) {
        // Revert to current value
        textField.text = currentValue;
        return;
    }

    // Validate pattern if present
    NSString *pattern = [self.entity inputTextPattern];
    if (pattern.length > 0) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        if (regex) {
            NSUInteger matches = [regex numberOfMatchesInString:newValue options:0 range:NSMakeRange(0, newValue.length)];
            if (matches == 0) {
                textField.text = currentValue;
                return;
            }
        }
    }

    NSDictionary *data = @{@"value": newValue};
    [self callService:@"set_value" inDomain:@"input_text" withData:data];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.textField resignFirstResponder];
    self.textField.text = nil;
    self.textField.secureTextEntry = NO;
    self.isEditing = NO;
}

@end
