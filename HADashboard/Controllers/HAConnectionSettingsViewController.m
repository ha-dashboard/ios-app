#import "HAConnectionSettingsViewController.h"
#import "HAConnectionFormView.h"
#import "HAConnectionManager.h"
#import "HADashboardViewController.h"
#import "HATheme.h"

@interface HAConnectionSettingsViewController () <HAConnectionFormDelegate>
@property (nonatomic, strong) HAConnectionFormView *connectionForm;
@end

@implementation HAConnectionSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Connection";
    self.view.backgroundColor = [HATheme backgroundColor];

    [self setupUI];
    [self.connectionForm loadExistingCredentials];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.connectionForm startDiscovery];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.connectionForm stopDiscovery];
}

#pragma mark - UI Setup

- (void)setupUI {
    CGFloat padding = 20.0;
    CGFloat maxWidth = 500.0;

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:container];

    self.connectionForm = [[HAConnectionFormView alloc] initWithFrame:CGRectZero];
    self.connectionForm.delegate = self;
    self.connectionForm.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.connectionForm];

    [NSLayoutConstraint activateConstraints:@[
        [self.connectionForm.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.connectionForm.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.connectionForm.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.connectionForm.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    // ScrollView content: container pinned to scroll edges
    [NSLayoutConstraint activateConstraints:@[
        [container.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:24],
        [container.bottomAnchor constraintLessThanOrEqualToAnchor:scrollView.bottomAnchor constant:-padding],
        [container.widthAnchor constraintLessThanOrEqualToConstant:maxWidth],
    ]];

    // Horizontal: centered with max width
    NSLayoutConstraint *centerX = [container.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor];
    centerX.active = YES;
    NSLayoutConstraint *leadingGE = [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:padding];
    leadingGE.active = YES;
    NSLayoutConstraint *trailingLE = [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-padding];
    trailingLE.active = YES;
    NSLayoutConstraint *preferWidth = [container.widthAnchor constraintEqualToConstant:maxWidth];
    preferWidth.priority = UILayoutPriorityDefaultHigh;
    preferWidth.active = YES;

    // iOS 9 scroll content width: pin container width to scroll view width
    // (on iOS 11+ this would use frameLayoutGuide, but we keep it simple)
    NSLayoutConstraint *scrollWidth = [container.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:padding];
    scrollWidth.priority = UILayoutPriorityDefaultLow;
    scrollWidth.active = YES;
}

#pragma mark - HAConnectionFormDelegate

- (void)connectionFormDidConnect:(HAConnectionFormView *)form {
    // Disconnect first to clear stale entities/registries from previous server
    [[HAConnectionManager sharedManager] disconnect];

    // Navigate to dashboard
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        HADashboardViewController *dashVC = [[HADashboardViewController alloc] init];
        UINavigationController *nav = self.navigationController;
        [nav setViewControllers:@[dashVC] animated:YES];
    });
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

@end
