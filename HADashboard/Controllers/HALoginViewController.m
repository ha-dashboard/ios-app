#import "HALoginViewController.h"
#import "HAConnectionFormView.h"
#import "HADashboardViewController.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HATheme.h"

@interface HALoginViewController () <HAConnectionFormDelegate>
@property (nonatomic, strong) HAConnectionFormView *connectionForm;
@property (nonatomic, strong) UISwitch *demoSwitch;
@property (nonatomic, strong) UIView *cardView;
@end

@implementation HALoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HA Dashboard";
    self.view.backgroundColor = [HATheme backgroundColor];
    self.navigationController.navigationBarHidden = YES;

    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    [self.connectionForm startDiscovery];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.connectionForm stopDiscovery];
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

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    // Outer wrapper — used to vertically center content when it fits on screen
    UIView *outerWrapper = [[UIView alloc] init];
    outerWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:outerWrapper];

    // Pin outer wrapper to scroll content guide
    [NSLayoutConstraint activateConstraints:@[
        [outerWrapper.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [outerWrapper.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [outerWrapper.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [outerWrapper.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [outerWrapper.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
    ]];
    // Minimum height = screen height so content centers vertically
    NSLayoutConstraint *minHeight = [outerWrapper.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.frameLayoutGuide.heightAnchor];
    minHeight.active = YES;

    // Content column — centered horizontally + vertically within outer wrapper
    UIView *column = [[UIView alloc] init];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [outerWrapper addSubview:column];

    [NSLayoutConstraint activateConstraints:@[
        [column.centerXAnchor constraintEqualToAnchor:outerWrapper.centerXAnchor],
        [column.centerYAnchor constraintEqualToAnchor:outerWrapper.centerYAnchor],
        [column.topAnchor constraintGreaterThanOrEqualToAnchor:outerWrapper.topAnchor constant:40],
        [column.bottomAnchor constraintLessThanOrEqualToAnchor:outerWrapper.bottomAnchor constant:-24],
        [column.leadingAnchor constraintGreaterThanOrEqualToAnchor:outerWrapper.leadingAnchor constant:padding],
        [column.trailingAnchor constraintLessThanOrEqualToAnchor:outerWrapper.trailingAnchor constant:-padding],
        [column.widthAnchor constraintLessThanOrEqualToConstant:maxWidth],
    ]];
    // Prefer max width when space permits
    NSLayoutConstraint *preferWidth = [column.widthAnchor constraintEqualToConstant:maxWidth];
    preferWidth.priority = UILayoutPriorityDefaultHigh;
    preferWidth.active = YES;

    // ── App icon (loaded from bundle icon files) ──────────────────────
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

    // ── Card container ─────────────────────────────────────────────────
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [HATheme cellBackgroundColor];
    self.cardView.layer.cornerRadius = cardRadius;
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOpacity = [HATheme effectiveDarkMode] ? 0.4f : 0.12f;
    self.cardView.layer.shadowRadius = 20;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 4);
    [column addSubview:self.cardView];

    // ── "Connect to server" header inside card ─────────────────────────
    UILabel *cardTitle = [[UILabel alloc] init];
    cardTitle.text = @"Connect to your server";
    cardTitle.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    cardTitle.textColor = [HATheme primaryTextColor];
    cardTitle.textAlignment = NSTextAlignmentCenter;
    cardTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:cardTitle];

    // ── Connection form ────────────────────────────────────────────────
    self.connectionForm = [[HAConnectionFormView alloc] initWithFrame:CGRectZero];
    self.connectionForm.delegate = self;
    self.connectionForm.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:self.connectionForm];

    // Card internal layout
    [NSLayoutConstraint activateConstraints:@[
        [cardTitle.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:cardPadding],
        [cardTitle.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:cardPadding],
        [cardTitle.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-cardPadding],
        [self.connectionForm.topAnchor constraintEqualToAnchor:cardTitle.bottomAnchor constant:20],
        [self.connectionForm.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:cardPadding],
        [self.connectionForm.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-cardPadding],
        [self.connectionForm.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-cardPadding],
    ]];

    // ── Demo mode section (below card, subtle) ─────────────────────────
    UIView *demoRow = [[UIView alloc] init];
    demoRow.translatesAutoresizingMaskIntoConstraints = NO;
    [column addSubview:demoRow];

    UILabel *demoLabel = [[UILabel alloc] init];
    demoLabel.text = @"Try Demo Mode";
    demoLabel.font = [UIFont systemFontOfSize:14];
    demoLabel.textColor = [HATheme secondaryTextColor];
    demoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [demoRow addSubview:demoLabel];

    self.demoSwitch = [[UISwitch alloc] init];
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

    // ── Column vertical layout ─────────────────────────────────────────
    [NSLayoutConstraint activateConstraints:@[
        [iconView.topAnchor constraintEqualToAnchor:column.topAnchor],
        [iconView.centerXAnchor constraintEqualToAnchor:column.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:88],
        [iconView.heightAnchor constraintEqualToConstant:88],
        [self.cardView.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:24],
        [self.cardView.leadingAnchor constraintEqualToAnchor:column.leadingAnchor],
        [self.cardView.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],
        [demoRow.topAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:20],
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

@end
