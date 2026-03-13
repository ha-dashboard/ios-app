#import "HAAutoLayout.h"
#import "HAConnectionSettingsViewController.h"
#import "HAAuthManager.h"
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
    scrollView.tag = 100;
    [self.view addSubview:scrollView];
    HAActivateConstraints(@[
        HACon([scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor]),
        HACon([scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]),
        HACon([scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor]),
        HACon([scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]),
    ]);

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.tag = 101;
    [scrollView addSubview:container];

    self.connectionForm = [[HAConnectionFormView alloc] initWithFrame:CGRectZero];
    self.connectionForm.delegate = self;
    self.connectionForm.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.connectionForm];

    HAPinEdgesFlush(self.connectionForm, container);

    // ScrollView content: container pinned to scroll edges
    HAActivateConstraints(@[
        HACon([container.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:24]),
        HACon([container.bottomAnchor constraintLessThanOrEqualToAnchor:scrollView.bottomAnchor constant:-padding]),
        HACon([container.widthAnchor constraintLessThanOrEqualToConstant:maxWidth]),
    ]);

    // Horizontal: centered with max width
    HASetConstraintActive([container.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], YES);
    HASetConstraintActive([container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:padding], YES);
    HASetConstraintActive([container.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-padding], YES);

    NSLayoutConstraint *preferWidth = HAMakeConstraint([container.widthAnchor constraintEqualToConstant:maxWidth]);
    if (preferWidth) {
        preferWidth.priority = UILayoutPriorityDefaultHigh;
        HASetConstraintActive(preferWidth, YES);
    }

    // iOS 9 scroll content width: pin container width to scroll view width
    // (on iOS 11+ this would use frameLayoutGuide, but we keep it simple)
    NSLayoutConstraint *scrollWidth = HAMakeConstraint([container.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:padding]);
    if (scrollWidth) {
        scrollWidth.priority = UILayoutPriorityDefaultLow;
        HASetConstraintActive(scrollWidth, YES);
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGRect bounds = self.view.bounds;
        CGFloat padding = 20.0;
        CGFloat maxWidth = 500.0;

        UIScrollView *scrollView = (UIScrollView *)[self.view viewWithTag:100];
        scrollView.frame = bounds;

        UIView *container = [scrollView viewWithTag:101];
        CGFloat containerWidth = MIN(maxWidth, bounds.size.width - padding * 2);
        CGFloat containerX = (bounds.size.width - containerWidth) / 2;

        // Connection form fills container
        CGSize formSize = [self.connectionForm sizeThatFits:CGSizeMake(containerWidth, CGFLOAT_MAX)];
        self.connectionForm.frame = CGRectMake(0, 0, containerWidth, formSize.height);

        CGFloat containerHeight = formSize.height;
        container.frame = CGRectMake(containerX, 24, containerWidth, containerHeight);
        scrollView.contentSize = CGSizeMake(bounds.size.width, 24 + containerHeight + padding);
    }
}

#pragma mark - HAConnectionFormDelegate

- (void)connectionFormDidConnect:(HAConnectionFormView *)form {
    // Disconnect first to clear stale entities/registries from previous server
    [[HAConnectionManager sharedManager] disconnect];

    // Clear selected dashboard path — the new server may not have the same dashboards
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:nil];

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
