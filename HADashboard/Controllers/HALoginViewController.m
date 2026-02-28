#import "HALoginViewController.h"
#import "HAConnectionFormView.h"
#import "HAConstellationView.h"
#import "HADashboardViewController.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAStartupLog.h"

@interface HALoginViewController () <HAConnectionFormDelegate>
@property (nonatomic, strong) HAConnectionFormView *connectionForm;
@property (nonatomic, strong) HAConstellationView *constellationView;
@property (nonatomic, strong) UISwitch *demoSwitch;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation HALoginViewController

- (void)viewDidLoad {
    [HAStartupLog log:@"HALoginVC viewDidLoad BEGIN"];
    [super viewDidLoad];
    self.title = @"HA Dashboard";
    self.view.backgroundColor = [HATheme backgroundColor];
    self.navigationController.navigationBarHidden = YES;

    [HAStartupLog log:@"HALoginVC setupUI BEGIN"];
    [self setupUI];
    [HAStartupLog log:@"HALoginVC setupUI END"];
    [HAStartupLog log:@"HALoginVC viewDidLoad END"];
}

- (void)viewWillAppear:(BOOL)animated {
    [HAStartupLog log:@"HALoginVC viewWillAppear BEGIN"];
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    [HAStartupLog log:@"  loadExistingCredentials BEGIN"];
    [self.connectionForm loadExistingCredentials];
    [HAStartupLog log:@"  loadExistingCredentials END"];
    [HAStartupLog log:@"  startDiscovery BEGIN"];
    [self.connectionForm startDiscovery];
    [HAStartupLog log:@"  startDiscovery END"];
    [HAStartupLog log:@"  constellation startAnimating BEGIN"];
    [self.constellationView startAnimating];
    [HAStartupLog log:@"  constellation startAnimating END"];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
        name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
        name:UIKeyboardWillHideNotification object:nil];

    [HAStartupLog log:@"HALoginVC viewWillAppear END"];
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
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    // ── Outer wrapper (scroll content, at least screen-height for centering) ──
    UIView *wrapper = [[UIView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:wrapper];
    // contentLayoutGuide/frameLayoutGuide are iOS 11+. On iOS 9-10, pin the
    // wrapper directly to the scroll view (which acts as the content guide)
    // and use an equal-width constraint to the scroll view itself.
    if (@available(iOS 11.0, *)) {
        [NSLayoutConstraint activateConstraints:@[
            [wrapper.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
            [wrapper.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
            [wrapper.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
            [wrapper.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
            [wrapper.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
        ]];
        [wrapper.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.frameLayoutGuide.heightAnchor].active = YES;
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [wrapper.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
            [wrapper.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
            [wrapper.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
            [wrapper.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
            [wrapper.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
        ]];
        [wrapper.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.heightAnchor].active = YES;
    }

    // ── Column (centered content holder) ───────────────────────────────
    UIView *column = [[UIView alloc] init];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:column];

    // Center column horizontally with max width
    [NSLayoutConstraint activateConstraints:@[
        [column.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [column.widthAnchor constraintLessThanOrEqualToConstant:maxWidth],
        [column.leadingAnchor constraintGreaterThanOrEqualToAnchor:wrapper.leadingAnchor constant:padding],
        [column.trailingAnchor constraintLessThanOrEqualToAnchor:wrapper.trailingAnchor constant:-padding],
    ]];
    NSLayoutConstraint *preferWidth = [column.widthAnchor constraintEqualToConstant:maxWidth];
    preferWidth.priority = UILayoutPriorityDefaultHigh;
    preferWidth.active = YES;

    // Center column vertically (low priority so it yields when content > screen)
    NSLayoutConstraint *centerY = [column.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor];
    centerY.priority = UILayoutPriorityDefaultLow;
    centerY.active = YES;
    // Hard constraints: don't let it escape the wrapper
    [NSLayoutConstraint activateConstraints:@[
        [column.topAnchor constraintGreaterThanOrEqualToAnchor:wrapper.topAnchor constant:40],
        [column.bottomAnchor constraintLessThanOrEqualToAnchor:wrapper.bottomAnchor constant:-20],
    ]];

    // ── App icon ───────────────────────────────────────────────────────
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
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
    cardTitle.text = @"Connect to your server";
    cardTitle.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
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
    [NSLayoutConstraint activateConstraints:@[
        [cardTitle.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:cardPadding],
        [cardTitle.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:cardPadding],
        [cardTitle.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-cardPadding],
        [self.connectionForm.topAnchor constraintEqualToAnchor:cardTitle.bottomAnchor constant:24],
        [self.connectionForm.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:cardPadding],
        [self.connectionForm.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-cardPadding],
        [self.connectionForm.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-cardPadding],
    ]];

    // ── Demo mode (below card) ─────────────────────────────────────────
    UIView *demoRow = [[UIView alloc] init];
    demoRow.translatesAutoresizingMaskIntoConstraints = NO;
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

    [NSLayoutConstraint activateConstraints:@[
        [demoLabel.topAnchor constraintEqualToAnchor:demoRow.topAnchor],
        [demoLabel.leadingAnchor constraintEqualToAnchor:demoRow.leadingAnchor],
        [demoLabel.bottomAnchor constraintEqualToAnchor:demoRow.bottomAnchor],
        [self.demoSwitch.trailingAnchor constraintEqualToAnchor:demoRow.trailingAnchor],
        [self.demoSwitch.centerYAnchor constraintEqualToAnchor:demoLabel.centerYAnchor],
    ]];

    // ── Column vertical layout: icon → card → demo ─────────────────────
    [NSLayoutConstraint activateConstraints:@[
        [iconView.topAnchor constraintEqualToAnchor:column.topAnchor],
        [iconView.centerXAnchor constraintEqualToAnchor:column.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:88],
        [iconView.heightAnchor constraintEqualToConstant:88],
        [self.cardView.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:24],
        [self.cardView.leadingAnchor constraintEqualToAnchor:column.leadingAnchor],
        [self.cardView.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],
        [demoRow.topAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:24],
        [demoRow.leadingAnchor constraintEqualToAnchor:column.leadingAnchor constant:4],
        [demoRow.trailingAnchor constraintEqualToAnchor:column.trailingAnchor constant:-4],
        [demoRow.bottomAnchor constraintEqualToAnchor:column.bottomAnchor],
    ]];
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
