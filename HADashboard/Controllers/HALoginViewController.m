#import "HAAutoLayout.h"
#import "HALoginViewController.h"
#import "HAConnectionFormView.h"
#import "HAConstellationView.h"
#import "HADashboardViewController.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HALog.h"
#import "UIFont+HACompat.h"

@interface HALoginViewController () <HAConnectionFormDelegate>
@property (nonatomic, strong) HAConnectionFormView *connectionForm;
@property (nonatomic, strong) HAConstellationView *constellationView;
@property (nonatomic, strong) UISwitch *demoSwitch;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation HALoginViewController

- (void)viewDidLoad {
    HALogD(@"auth", @"HALoginVC viewDidLoad BEGIN");
    [super viewDidLoad];
    self.title = @"HA Dashboard";
    self.view.backgroundColor = [HATheme backgroundColor];
    self.navigationController.navigationBarHidden = YES;

    HALogD(@"auth", @"HALoginVC setupUI BEGIN");
    [self setupUI];
    HALogD(@"auth", @"HALoginVC setupUI END");
    HALogD(@"auth", @"HALoginVC viewDidLoad END");
}

- (void)viewWillAppear:(BOOL)animated {
    HALogD(@"auth", @"HALoginVC viewWillAppear BEGIN");
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    HALogD(@"auth", @"  loadExistingCredentials BEGIN");
    [self.connectionForm loadExistingCredentials];
    HALogD(@"auth", @"  loadExistingCredentials END");
    HALogD(@"auth", @"  startDiscovery BEGIN");
    [self.connectionForm startDiscovery];
    HALogD(@"auth", @"  startDiscovery END");
    HALogD(@"auth", @"  constellation startAnimating BEGIN");
    [self.constellationView startAnimating];
    HALogD(@"auth", @"  constellation startAnimating END");

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
        name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
        name:UIKeyboardWillHideNotification object:nil];

    HALogD(@"auth", @"HALoginVC viewWillAppear END");
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.connectionForm stopDiscovery];
    [self.constellationView stopAnimating];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [HATheme effectiveDarkMode] ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

#pragma mark - UI Setup

- (void)setupUI {
    CGFloat padding = 24.0;
    CGFloat maxWidth = 460.0;
    CGFloat cardPadding = 28.0;
    CGFloat cardRadius = 16.0;

    // ── Constellation background ───────────────────────────────────────
    self.constellationView = [[HAConstellationView alloc] initWithFrame:self.view.bounds];
    self.constellationView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.constellationView];

    // ── Scroll view ────────────────────────────────────────────────────
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    UIScrollView *scrollView = self.scrollView;
    [self.view addSubview:scrollView];
    HAActivateConstraints(@[
        HACon([scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor]),
        HACon([scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]),
        HACon([scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor]),
        HACon([scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]),
    ]);

    // ── Outer wrapper (scroll content, at least screen-height for centering) ──
    UIView *wrapper = [[UIView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    wrapper.tag = 100;
    [scrollView addSubview:wrapper];
    // contentLayoutGuide/frameLayoutGuide are iOS 11+. On iOS 9-10, pin the
    // wrapper directly to the scroll view (which acts as the content guide)
    // and use an equal-width constraint to the scroll view itself.
    if (@available(iOS 11.0, *)) {
        HAActivateConstraints(@[
            HACon([wrapper.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor]),
            HACon([wrapper.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor]),
            HACon([wrapper.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor]),
            HACon([wrapper.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor]),
            HACon([wrapper.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor]),
        ]);
        HASetConstraintActive([wrapper.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.frameLayoutGuide.heightAnchor], YES);
    } else {
        HAActivateConstraints(@[
            HACon([wrapper.topAnchor constraintEqualToAnchor:scrollView.topAnchor]),
            HACon([wrapper.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor]),
            HACon([wrapper.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor]),
            HACon([wrapper.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor]),
            HACon([wrapper.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor]),
        ]);
        HASetConstraintActive([wrapper.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.heightAnchor], YES);
    }

    // ── Column (centered content holder) ───────────────────────────────
    UIView *column = [[UIView alloc] init];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    column.tag = 101;
    [wrapper addSubview:column];

    // Center column horizontally with max width
    HAActivateConstraints(@[
        HACon([column.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor]),
        HACon([column.widthAnchor constraintLessThanOrEqualToConstant:maxWidth]),
        HACon([column.leadingAnchor constraintGreaterThanOrEqualToAnchor:wrapper.leadingAnchor constant:padding]),
        HACon([column.trailingAnchor constraintLessThanOrEqualToAnchor:wrapper.trailingAnchor constant:-padding]),
    ]);

    NSLayoutConstraint *preferWidth = HAMakeConstraint([column.widthAnchor constraintEqualToConstant:maxWidth]);
    if (preferWidth) {
        preferWidth.priority = UILayoutPriorityDefaultHigh;
        HASetConstraintActive(preferWidth, YES);
    }

    // Center column vertically (low priority so it yields when content > screen)
    NSLayoutConstraint *centerY = HAMakeConstraint([column.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor]);
    if (centerY) {
        centerY.priority = UILayoutPriorityDefaultLow;
        HASetConstraintActive(centerY, YES);
    }

    // Hard constraints: don't let it escape the wrapper
    HAActivateConstraints(@[
        HACon([column.topAnchor constraintGreaterThanOrEqualToAnchor:wrapper.topAnchor constant:40]),
        HACon([column.bottomAnchor constraintLessThanOrEqualToAnchor:wrapper.bottomAnchor constant:-20]),
    ]);

    // ── App icon ───────────────────────────────────────────────────────
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tag = 102;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    NSDictionary *icons = [[NSBundle mainBundle] infoDictionary][@"CFBundleIcons"];
    NSString *iconName = [icons[@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"] lastObject];
    if (iconName) {
        iconView.image = [UIImage imageNamed:iconName];
    }
    iconView.layer.cornerRadius = 20;
    iconView.layer.masksToBounds = YES;
    [column addSubview:iconView];

    // ── Card ───────────────────────────────────────────────────────────
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [HATheme cellBackgroundColor];
    self.cardView.layer.cornerRadius = cardRadius;
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOpacity = [HATheme effectiveDarkMode] ? 0.4f : 0.12f;
    self.cardView.layer.shadowRadius = 20;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 4);
    [column addSubview:self.cardView];

    // Card title
    UILabel *cardTitle = [[UILabel alloc] init];
    cardTitle.tag = 103;
    cardTitle.text = @"Connect to your server";
    cardTitle.font = [UIFont ha_systemFontOfSize:20 weight:HAFontWeightSemibold];
    cardTitle.textColor = [HATheme primaryTextColor];
    cardTitle.textAlignment = NSTextAlignmentCenter;
    cardTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:cardTitle];

    // Connection form
    self.connectionForm = [[HAConnectionFormView alloc] initWithFrame:CGRectZero];
    self.connectionForm.delegate = self;
    self.connectionForm.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:self.connectionForm];

    // Card internal layout
    HAActivateConstraints(@[
        HACon([cardTitle.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:cardPadding]),
        HACon([cardTitle.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:cardPadding]),
        HACon([cardTitle.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-cardPadding]),
        HACon([self.connectionForm.topAnchor constraintEqualToAnchor:cardTitle.bottomAnchor constant:24]),
        HACon([self.connectionForm.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:cardPadding]),
        HACon([self.connectionForm.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-cardPadding]),
        HACon([self.connectionForm.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-cardPadding]),
    ]);

    // ── Demo mode (below card) ─────────────────────────────────────────
    UIView *demoRow = [[UIView alloc] init];
    demoRow.translatesAutoresizingMaskIntoConstraints = NO;
    demoRow.tag = 104;
    [column addSubview:demoRow];

    UILabel *demoLabel = [[UILabel alloc] init];
    demoLabel.text = @"Try Demo Mode";
    demoLabel.font = [UIFont systemFontOfSize:14];
    demoLabel.textColor = [HATheme secondaryTextColor];
    demoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [demoRow addSubview:demoLabel];

    self.demoSwitch = [[HASwitch alloc] init];
    self.demoSwitch.on = [[HAAuthManager sharedManager] isDemoMode];
    [self.demoSwitch addTarget:self action:@selector(demoSwitchToggled:) forControlEvents:UIControlEventValueChanged];
    self.demoSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [demoRow addSubview:self.demoSwitch];

    HAActivateConstraints(@[
        HACon([demoLabel.topAnchor constraintEqualToAnchor:demoRow.topAnchor]),
        HACon([demoLabel.leadingAnchor constraintEqualToAnchor:demoRow.leadingAnchor]),
        HACon([demoLabel.bottomAnchor constraintEqualToAnchor:demoRow.bottomAnchor]),
        HACon([self.demoSwitch.trailingAnchor constraintEqualToAnchor:demoRow.trailingAnchor]),
        HACon([self.demoSwitch.centerYAnchor constraintEqualToAnchor:demoLabel.centerYAnchor]),
    ]);

    // ── Column vertical layout: icon → card → demo ─────────────────────
    HAActivateConstraints(@[
        HACon([iconView.topAnchor constraintEqualToAnchor:column.topAnchor]),
        HACon([iconView.centerXAnchor constraintEqualToAnchor:column.centerXAnchor]),
        HACon([iconView.widthAnchor constraintEqualToConstant:88]),
        HACon([iconView.heightAnchor constraintEqualToConstant:88]),
        HACon([self.cardView.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:24]),
        HACon([self.cardView.leadingAnchor constraintEqualToAnchor:column.leadingAnchor]),
        HACon([self.cardView.trailingAnchor constraintEqualToAnchor:column.trailingAnchor]),
        HACon([demoRow.topAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:24]),
        HACon([demoRow.leadingAnchor constraintEqualToAnchor:column.leadingAnchor constant:4]),
        HACon([demoRow.trailingAnchor constraintEqualToAnchor:column.trailingAnchor constant:-4]),
        HACon([demoRow.bottomAnchor constraintEqualToAnchor:column.bottomAnchor]),
    ]);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGRect bounds = self.view.bounds;
        CGFloat padding = 24.0;
        CGFloat maxWidth = 460.0;
        CGFloat cardPadding = 28.0;

        // Scroll view fills the view
        self.scrollView.frame = bounds;

        // Wrapper fills scroll content (at least screen height)
        UIView *wrapper = [self.scrollView viewWithTag:100];
        UIView *column = [wrapper viewWithTag:101];
        UIView *iconView = [column viewWithTag:102];

        CGFloat columnWidth = MIN(maxWidth, bounds.size.width - padding * 2);

        // Icon: 88x88 centered at top
        iconView.frame = CGRectMake((columnWidth - 88) / 2, 0, 88, 88);

        // Card title
        UILabel *cardTitle = (UILabel *)[self.cardView viewWithTag:103];
        CGSize titleSize = [cardTitle sizeThatFits:CGSizeMake(columnWidth - cardPadding * 2, CGFLOAT_MAX)];
        cardTitle.frame = CGRectMake(cardPadding, cardPadding, columnWidth - cardPadding * 2, titleSize.height);

        // Connection form
        CGFloat formTop = CGRectGetMaxY(cardTitle.frame) + 24;
        CGFloat formWidth = columnWidth - cardPadding * 2;
        CGSize formSize = [self.connectionForm sizeThatFits:CGSizeMake(formWidth, CGFLOAT_MAX)];
        self.connectionForm.frame = CGRectMake(cardPadding, formTop, formWidth, formSize.height);

        // Card
        CGFloat cardHeight = CGRectGetMaxY(self.connectionForm.frame) + cardPadding;
        CGFloat cardTop = CGRectGetMaxY(iconView.frame) + 24;
        self.cardView.frame = CGRectMake(0, cardTop, columnWidth, cardHeight);

        // Demo row
        UIView *demoRow = [column viewWithTag:104];
        CGFloat demoTop = CGRectGetMaxY(self.cardView.frame) + 24;
        CGSize switchSize = [self.demoSwitch sizeThatFits:CGSizeMake(columnWidth, 44)];
        demoRow.frame = CGRectMake(4, demoTop, columnWidth - 8, switchSize.height);

        // Layout demo row children (label + switch)
        for (UIView *sub in demoRow.subviews) {
            if ([sub isKindOfClass:[UISwitch class]]) {
                sub.frame = CGRectMake(demoRow.bounds.size.width - sub.frame.size.width, 0,
                                       sub.frame.size.width, sub.frame.size.height);
            } else if ([sub isKindOfClass:[UILabel class]]) {
                CGSize lblSize = [sub sizeThatFits:demoRow.bounds.size];
                sub.frame = CGRectMake(0, (switchSize.height - lblSize.height) / 2,
                                       lblSize.width, lblSize.height);
            }
        }

        // Column
        CGFloat columnHeight = CGRectGetMaxY(demoRow.frame);
        CGFloat columnX = (bounds.size.width - columnWidth) / 2;
        // Center column vertically in wrapper, min 40pt from top
        CGFloat columnY = MAX(40, (bounds.size.height - columnHeight) / 2);
        column.frame = CGRectMake(columnX, columnY, columnWidth, columnHeight);

        // Wrapper
        CGFloat wrapperHeight = MAX(bounds.size.height, CGRectGetMaxY(column.frame) + 20);
        wrapper.frame = CGRectMake(0, 0, bounds.size.width, wrapperHeight);
        self.scrollView.contentSize = CGSizeMake(bounds.size.width, wrapperHeight);
    }
}

#pragma mark - HAConnectionFormDelegate

- (void)connectionFormDidConnect:(HAConnectionFormView *)form {
    [self navigateToDashboard];
}

#pragma mark - Demo Mode

- (void)demoSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setDemoMode:sender.isOn];
    if (sender.isOn) {
        [[HAConnectionManager sharedManager] disconnect];
        [self navigateToDashboard];
    }
}

#pragma mark - Navigation

- (void)navigateToDashboard {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        HADashboardViewController *dashVC = [[HADashboardViewController alloc] init];
        UINavigationController *nav = self.navigationController;
        nav.navigationBarHidden = NO;
        [nav setViewControllers:@[dashVC] animated:YES];
    });
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

#pragma mark - Keyboard Avoidance

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    CGRect kbFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect kbLocal = [self.view convertRect:kbFrame fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(kbLocal);
    if (overlap < 0) overlap = 0;

    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [info[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;

    [UIView animateWithDuration:duration delay:0 options:curve animations:^{
        UIEdgeInsets insets = self.scrollView.contentInset;
        insets.bottom = overlap;
        self.scrollView.contentInset = insets;
        self.scrollView.scrollIndicatorInsets = insets;
    } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [info[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;

    [UIView animateWithDuration:duration delay:0 options:curve animations:^{
        UIEdgeInsets insets = self.scrollView.contentInset;
        insets.bottom = 0;
        self.scrollView.contentInset = insets;
        self.scrollView.scrollIndicatorInsets = insets;
    } completion:nil];
}

@end
