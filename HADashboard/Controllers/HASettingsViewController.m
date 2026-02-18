#import "HASettingsViewController.h"
#import "HAAuthManager.h"
#import "HAOAuthClient.h"
#import "HAAPIClient.h"
#import "HAConnectionManager.h"
#import "HADashboardViewController.h"
#import "HADiscoveryService.h"
#import "HADiscoveredServer.h"
#import "HATheme.h"

@interface HASettingsViewController () <UITextFieldDelegate, HADiscoveryServiceDelegate>
@property (nonatomic, strong) UITextField *serverURLField;
@property (nonatomic, strong) UISegmentedControl *authModeSegment;

// Token mode
@property (nonatomic, strong) UIView *tokenContainer;
@property (nonatomic, strong) UITextField *tokenField;

// Login mode
@property (nonatomic, strong) UIView *loginContainer;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *passwordField;

@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

// Discovery
@property (nonatomic, strong) HADiscoveryService *discoveryService;
@property (nonatomic, strong) UIView *discoverySection;
@property (nonatomic, strong) UIStackView *discoveryStack;
@property (nonatomic, strong) UILabel *discoveryLabel;

// Section headers
@property (nonatomic, strong) UILabel *connectionSectionHeader;
@property (nonatomic, strong) UILabel *appearanceSectionHeader;
@property (nonatomic, strong) UILabel *displaySectionHeader;

// Theme
@property (nonatomic, strong) UIView *themeSection;
@property (nonatomic, strong) UISegmentedControl *themeModeSegment;
@property (nonatomic, strong) UIView *gradientOptionsContainer;
@property (nonatomic, strong) UISegmentedControl *gradientPresetSegment;
@property (nonatomic, strong) UIView *customHexContainer;
@property (nonatomic, strong) UITextField *hex1Field;
@property (nonatomic, strong) UITextField *hex2Field;
@property (nonatomic, strong) UIView *gradientPreview;
@property (nonatomic, strong) CAGradientLayer *previewGradientLayer;

// Kiosk mode
@property (nonatomic, strong) UIView *kioskSection;
@property (nonatomic, strong) UISwitch *kioskSwitch;

// Demo mode
@property (nonatomic, strong) UIView *demoSection;
@property (nonatomic, strong) UISwitch *demoSwitch;

// Help text
@property (nonatomic, strong) UILabel *helpLabel;
@end

@implementation HASettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = [HATheme backgroundColor];

    [self setupUI];
    [self loadExistingCredentials];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Start server discovery
    self.discoveryService = [[HADiscoveryService alloc] init];
    self.discoveryService.delegate = self;
    [self.discoveryService startSearching];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.discoveryService stopSearching];
    self.discoveryService = nil;
}

- (void)setupUI {
    CGFloat padding = 20.0;
    CGFloat fieldHeight = 44.0;
    CGFloat maxWidth = 500.0;

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[sv]|"
        options:0 metrics:nil views:@{@"sv": scrollView}]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[sv]|"
        options:0 metrics:nil views:@{@"sv": scrollView}]];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:container];

    // ── CONNECTION section header ──────────────────────────────────────
    self.connectionSectionHeader = [self createSectionHeaderWithText:@"CONNECTION"];
    [container addSubview:self.connectionSectionHeader];

    // ── Discovery section ──────────────────────────────────────────────
    self.discoverySection = [[UIView alloc] init];
    self.discoverySection.translatesAutoresizingMaskIntoConstraints = NO;
    self.discoverySection.hidden = YES;
    [container addSubview:self.discoverySection];

    self.discoveryLabel = [[UILabel alloc] init];
    self.discoveryLabel.text = @"Discovered Servers";
    self.discoveryLabel.font = [UIFont systemFontOfSize:14];
    self.discoveryLabel.textColor = [HATheme secondaryTextColor];
    self.discoveryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.discoverySection addSubview:self.discoveryLabel];

    self.discoveryStack = [[UIStackView alloc] init];
    self.discoveryStack.axis = UILayoutConstraintAxisVertical;
    self.discoveryStack.spacing = 8;
    self.discoveryStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.discoverySection addSubview:self.discoveryStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.discoveryLabel.topAnchor constraintEqualToAnchor:self.discoverySection.topAnchor],
        [self.discoveryLabel.leadingAnchor constraintEqualToAnchor:self.discoverySection.leadingAnchor],
        [self.discoveryStack.topAnchor constraintEqualToAnchor:self.discoveryLabel.bottomAnchor constant:8],
        [self.discoveryStack.leadingAnchor constraintEqualToAnchor:self.discoverySection.leadingAnchor],
        [self.discoveryStack.trailingAnchor constraintEqualToAnchor:self.discoverySection.trailingAnchor],
        [self.discoveryStack.bottomAnchor constraintEqualToAnchor:self.discoverySection.bottomAnchor],
    ]];

    // ── Server URL ─────────────────────────────────────────────────────
    UILabel *urlLabel = [[UILabel alloc] init];
    urlLabel.text = @"Server URL";
    urlLabel.font = [UIFont systemFontOfSize:14];
    urlLabel.textColor = [HATheme secondaryTextColor];
    urlLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:urlLabel];

    self.serverURLField = [[UITextField alloc] init];
    self.serverURLField.placeholder = @"http://192.168.1.100:8123";
    self.serverURLField.borderStyle = UITextBorderStyleRoundedRect;
    self.serverURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.serverURLField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.serverURLField.keyboardType = UIKeyboardTypeURL;
    self.serverURLField.returnKeyType = UIReturnKeyNext;
    self.serverURLField.delegate = self;
    self.serverURLField.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.serverURLField];

    // ── Auth mode segmented control ────────────────────────────────────
    self.authModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Access Token", @"Username/Password"]];
    self.authModeSegment.selectedSegmentIndex = 0;
    [self.authModeSegment addTarget:self action:@selector(authModeChanged:) forControlEvents:UIControlEventValueChanged];
    self.authModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.authModeSegment];

    // ── Token mode container ───────────────────────────────────────────
    self.tokenContainer = [[UIView alloc] init];
    self.tokenContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.tokenContainer];

    UILabel *tokenLabel = [[UILabel alloc] init];
    tokenLabel.text = @"Long-Lived Access Token";
    tokenLabel.font = [UIFont systemFontOfSize:14];
    tokenLabel.textColor = [HATheme secondaryTextColor];
    tokenLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tokenContainer addSubview:tokenLabel];

    self.tokenField = [[UITextField alloc] init];
    self.tokenField.placeholder = @"Paste your access token here";
    self.tokenField.borderStyle = UITextBorderStyleRoundedRect;
    self.tokenField.secureTextEntry = YES;
    self.tokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tokenField.returnKeyType = UIReturnKeyDone;
    self.tokenField.delegate = self;
    self.tokenField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tokenContainer addSubview:self.tokenField];

    [NSLayoutConstraint activateConstraints:@[
        [tokenLabel.topAnchor constraintEqualToAnchor:self.tokenContainer.topAnchor],
        [tokenLabel.leadingAnchor constraintEqualToAnchor:self.tokenContainer.leadingAnchor],
        [tokenLabel.trailingAnchor constraintEqualToAnchor:self.tokenContainer.trailingAnchor],
        [self.tokenField.topAnchor constraintEqualToAnchor:tokenLabel.bottomAnchor constant:4],
        [self.tokenField.leadingAnchor constraintEqualToAnchor:self.tokenContainer.leadingAnchor],
        [self.tokenField.trailingAnchor constraintEqualToAnchor:self.tokenContainer.trailingAnchor],
        [self.tokenField.heightAnchor constraintEqualToConstant:fieldHeight],
        [self.tokenField.bottomAnchor constraintEqualToAnchor:self.tokenContainer.bottomAnchor],
    ]];

    // ── Login mode container ───────────────────────────────────────────
    self.loginContainer = [[UIView alloc] init];
    self.loginContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginContainer.hidden = YES;
    [container addSubview:self.loginContainer];

    UILabel *userLabel = [[UILabel alloc] init];
    userLabel.text = @"Username";
    userLabel.font = [UIFont systemFontOfSize:14];
    userLabel.textColor = [HATheme secondaryTextColor];
    userLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginContainer addSubview:userLabel];

    self.usernameField = [[UITextField alloc] init];
    self.usernameField.placeholder = @"Home Assistant username";
    self.usernameField.borderStyle = UITextBorderStyleRoundedRect;
    self.usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.usernameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.usernameField.returnKeyType = UIReturnKeyNext;
    self.usernameField.delegate = self;
    self.usernameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginContainer addSubview:self.usernameField];

    UILabel *passLabel = [[UILabel alloc] init];
    passLabel.text = @"Password";
    passLabel.font = [UIFont systemFontOfSize:14];
    passLabel.textColor = [HATheme secondaryTextColor];
    passLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginContainer addSubview:passLabel];

    self.passwordField = [[UITextField alloc] init];
    self.passwordField.placeholder = @"Password";
    self.passwordField.borderStyle = UITextBorderStyleRoundedRect;
    self.passwordField.secureTextEntry = YES;
    self.passwordField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.passwordField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.passwordField.returnKeyType = UIReturnKeyDone;
    self.passwordField.delegate = self;
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginContainer addSubview:self.passwordField];

    [NSLayoutConstraint activateConstraints:@[
        [userLabel.topAnchor constraintEqualToAnchor:self.loginContainer.topAnchor],
        [userLabel.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.usernameField.topAnchor constraintEqualToAnchor:userLabel.bottomAnchor constant:4],
        [self.usernameField.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.usernameField.trailingAnchor constraintEqualToAnchor:self.loginContainer.trailingAnchor],
        [self.usernameField.heightAnchor constraintEqualToConstant:fieldHeight],
        [passLabel.topAnchor constraintEqualToAnchor:self.usernameField.bottomAnchor constant:12],
        [passLabel.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.passwordField.topAnchor constraintEqualToAnchor:passLabel.bottomAnchor constant:4],
        [self.passwordField.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.passwordField.trailingAnchor constraintEqualToAnchor:self.loginContainer.trailingAnchor],
        [self.passwordField.heightAnchor constraintEqualToConstant:fieldHeight],
        [self.passwordField.bottomAnchor constraintEqualToAnchor:self.loginContainer.bottomAnchor],
    ]];

    // ── Connect button ─────────────────────────────────────────────────
    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.connectButton setTitle:@"Connect" forState:UIControlStateNormal];
    self.connectButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.connectButton.backgroundColor = [HATheme accentColor];
    [self.connectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.connectButton.layer.cornerRadius = 8.0;
    [self.connectButton addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    self.connectButton.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.connectButton];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.statusLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.spinner];

    // ── APPEARANCE section header ────────────────────────────────────
    self.appearanceSectionHeader = [self createSectionHeaderWithText:@"APPEARANCE"];
    [container addSubview:self.appearanceSectionHeader];

    // ── Theme section ────────────────────────────────────────────────
    self.themeSection = [[UIView alloc] init];
    self.themeSection.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.themeSection];

    self.themeModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"Gradient", @"Dark", @"Light"]];
    self.themeModeSegment.selectedSegmentIndex = (NSInteger)[HATheme currentMode];
    [self.themeModeSegment addTarget:self action:@selector(themeModeChanged:) forControlEvents:UIControlEventValueChanged];
    self.themeModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.themeSection addSubview:self.themeModeSegment];

    // Gradient options (shown when Gradient selected)
    self.gradientOptionsContainer = [[UIView alloc] init];
    self.gradientOptionsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.gradientOptionsContainer.hidden = ([HATheme currentMode] != HAThemeModeGradient);
    [self.themeSection addSubview:self.gradientOptionsContainer];

    UILabel *presetLabel = [[UILabel alloc] init];
    presetLabel.text = @"Gradient Preset";
    presetLabel.font = [UIFont systemFontOfSize:12];
    presetLabel.textColor = [HATheme secondaryTextColor];
    presetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gradientOptionsContainer addSubview:presetLabel];

    self.gradientPresetSegment = [[UISegmentedControl alloc] initWithItems:@[@"Purple", @"Ocean", @"Sunset", @"Forest", @"Night", @"Custom"]];
    self.gradientPresetSegment.selectedSegmentIndex = (NSInteger)[HATheme gradientPreset];
    [self.gradientPresetSegment addTarget:self action:@selector(gradientPresetChanged:) forControlEvents:UIControlEventValueChanged];
    self.gradientPresetSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gradientOptionsContainer addSubview:self.gradientPresetSegment];

    // Custom hex fields
    self.customHexContainer = [[UIView alloc] init];
    self.customHexContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.customHexContainer.hidden = ([HATheme gradientPreset] != HAGradientPresetCustom);
    [self.gradientOptionsContainer addSubview:self.customHexContainer];

    self.hex1Field = [[UITextField alloc] init];
    self.hex1Field.placeholder = @"#1a0533";
    self.hex1Field.text = [HATheme customGradientHex1] ?: @"";
    self.hex1Field.borderStyle = UITextBorderStyleRoundedRect;
    self.hex1Field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.hex1Field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.hex1Field.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.hex1Field.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hex1Field addTarget:self action:@selector(hexFieldChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [self.customHexContainer addSubview:self.hex1Field];

    UILabel *arrowLabel = [[UILabel alloc] init];
    arrowLabel.text = @"\u2192";
    arrowLabel.textAlignment = NSTextAlignmentCenter;
    arrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.customHexContainer addSubview:arrowLabel];

    self.hex2Field = [[UITextField alloc] init];
    self.hex2Field.placeholder = @"#0f0f2e";
    self.hex2Field.text = [HATheme customGradientHex2] ?: @"";
    self.hex2Field.borderStyle = UITextBorderStyleRoundedRect;
    self.hex2Field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.hex2Field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.hex2Field.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.hex2Field.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hex2Field addTarget:self action:@selector(hexFieldChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [self.customHexContainer addSubview:self.hex2Field];

    [NSLayoutConstraint activateConstraints:@[
        [self.hex1Field.topAnchor constraintEqualToAnchor:self.customHexContainer.topAnchor],
        [self.hex1Field.leadingAnchor constraintEqualToAnchor:self.customHexContainer.leadingAnchor],
        [self.hex1Field.heightAnchor constraintEqualToConstant:36],
        [arrowLabel.centerYAnchor constraintEqualToAnchor:self.hex1Field.centerYAnchor],
        [arrowLabel.leadingAnchor constraintEqualToAnchor:self.hex1Field.trailingAnchor constant:8],
        [arrowLabel.widthAnchor constraintEqualToConstant:20],
        [self.hex2Field.topAnchor constraintEqualToAnchor:self.customHexContainer.topAnchor],
        [self.hex2Field.leadingAnchor constraintEqualToAnchor:arrowLabel.trailingAnchor constant:8],
        [self.hex2Field.trailingAnchor constraintEqualToAnchor:self.customHexContainer.trailingAnchor],
        [self.hex2Field.heightAnchor constraintEqualToConstant:36],
        [self.hex1Field.widthAnchor constraintEqualToAnchor:self.hex2Field.widthAnchor],
        [self.hex2Field.bottomAnchor constraintEqualToAnchor:self.customHexContainer.bottomAnchor],
    ]];

    // Gradient preview
    self.gradientPreview = [[UIView alloc] init];
    self.gradientPreview.layer.cornerRadius = 8.0;
    self.gradientPreview.layer.masksToBounds = YES;
    self.gradientPreview.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gradientOptionsContainer addSubview:self.gradientPreview];

    self.previewGradientLayer = [CAGradientLayer layer];
    self.previewGradientLayer.startPoint = CGPointMake(0.5, 0);
    self.previewGradientLayer.endPoint = CGPointMake(0.5, 1);
    [self.gradientPreview.layer addSublayer:self.previewGradientLayer];
    [self updateGradientPreview];

    [NSLayoutConstraint activateConstraints:@[
        [presetLabel.topAnchor constraintEqualToAnchor:self.gradientOptionsContainer.topAnchor],
        [presetLabel.leadingAnchor constraintEqualToAnchor:self.gradientOptionsContainer.leadingAnchor],
        [self.gradientPresetSegment.topAnchor constraintEqualToAnchor:presetLabel.bottomAnchor constant:4],
        [self.gradientPresetSegment.leadingAnchor constraintEqualToAnchor:self.gradientOptionsContainer.leadingAnchor],
        [self.gradientPresetSegment.trailingAnchor constraintEqualToAnchor:self.gradientOptionsContainer.trailingAnchor],
        [self.customHexContainer.topAnchor constraintEqualToAnchor:self.gradientPresetSegment.bottomAnchor constant:8],
        [self.customHexContainer.leadingAnchor constraintEqualToAnchor:self.gradientOptionsContainer.leadingAnchor],
        [self.customHexContainer.trailingAnchor constraintEqualToAnchor:self.gradientOptionsContainer.trailingAnchor],
        [self.gradientPreview.topAnchor constraintEqualToAnchor:self.customHexContainer.bottomAnchor constant:8],
        [self.gradientPreview.leadingAnchor constraintEqualToAnchor:self.gradientOptionsContainer.leadingAnchor],
        [self.gradientPreview.trailingAnchor constraintEqualToAnchor:self.gradientOptionsContainer.trailingAnchor],
        [self.gradientPreview.heightAnchor constraintEqualToConstant:60],
        [self.gradientPreview.bottomAnchor constraintEqualToAnchor:self.gradientOptionsContainer.bottomAnchor],
    ]];

    // Theme section vertical layout
    NSDictionary *tViews = @{@"seg": self.themeModeSegment, @"opts": self.gradientOptionsContainer};
    [self.themeSection addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|[seg]-8-[opts]|" options:0 metrics:nil views:tViews]];
    for (UIView *v in @[self.themeModeSegment, self.gradientOptionsContainer]) {
        [self.themeSection addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.themeSection attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
        [self.themeSection addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.themeSection attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    }

    // ── DISPLAY section header ─────────────────────────────────────────
    self.displaySectionHeader = [self createSectionHeaderWithText:@"DISPLAY"];
    [container addSubview:self.displaySectionHeader];

    // ── Kiosk mode section ─────────────────────────────────────────────
    self.kioskSection = [[UIView alloc] init];
    self.kioskSection.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.kioskSection];

    UILabel *kioskLabel = [[UILabel alloc] init];
    kioskLabel.text = @"Kiosk Mode";
    kioskLabel.font = [UIFont systemFontOfSize:16];
    kioskLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.kioskSection addSubview:kioskLabel];

    self.kioskSwitch = [[UISwitch alloc] init];
    self.kioskSwitch.on = [[HAAuthManager sharedManager] isKioskMode];
    [self.kioskSwitch addTarget:self action:@selector(kioskSwitchToggled:) forControlEvents:UIControlEventValueChanged];
    self.kioskSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.kioskSection addSubview:self.kioskSwitch];

    UILabel *kioskHelp = [[UILabel alloc] init];
    kioskHelp.text = @"Hides navigation bar and prevents screen sleep. Triple-tap the top of the screen to temporarily show controls.\n\nFor full lockdown, enable Guided Access in iPad Settings \u2192 Accessibility \u2192 Guided Access, then triple-click the Home button while in the app.";
    kioskHelp.font = [UIFont systemFontOfSize:12];
    kioskHelp.textColor = [HATheme secondaryTextColor];
    kioskHelp.numberOfLines = 0;
    kioskHelp.translatesAutoresizingMaskIntoConstraints = NO;
    [self.kioskSection addSubview:kioskHelp];

    NSDictionary *kViews = @{@"lbl": kioskLabel, @"sw": self.kioskSwitch, @"help": kioskHelp};
    [self.kioskSection addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|[lbl]-8-[help]|" options:0 metrics:nil views:kViews]];
    [self.kioskSection addConstraint:[NSLayoutConstraint constraintWithItem:kioskHelp attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.kioskSection attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.kioskSection addConstraint:[NSLayoutConstraint constraintWithItem:kioskHelp attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.kioskSection attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    [self.kioskSection addConstraint:[NSLayoutConstraint constraintWithItem:kioskLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.kioskSection attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.kioskSection addConstraint:[NSLayoutConstraint constraintWithItem:self.kioskSwitch attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.kioskSection attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    [self.kioskSection addConstraint:[NSLayoutConstraint constraintWithItem:self.kioskSwitch attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:kioskLabel attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

    // ── Demo mode section ─────────────────────────────────────────────
    self.demoSection = [[UIView alloc] init];
    self.demoSection.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.demoSection];

    UILabel *demoLabel = [[UILabel alloc] init];
    demoLabel.text = @"Demo Mode";
    demoLabel.font = [UIFont systemFontOfSize:16];
    demoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.demoSection addSubview:demoLabel];

    self.demoSwitch = [[UISwitch alloc] init];
    self.demoSwitch.on = [[HAAuthManager sharedManager] isDemoMode];
    [self.demoSwitch addTarget:self action:@selector(demoSwitchToggled:) forControlEvents:UIControlEventValueChanged];
    self.demoSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.demoSection addSubview:self.demoSwitch];

    UILabel *demoHelp = [[UILabel alloc] init];
    demoHelp.text = @"Shows the app with demo data instead of connecting to a Home Assistant server. Useful for demonstrating the app's capabilities.";
    demoHelp.font = [UIFont systemFontOfSize:12];
    demoHelp.textColor = [HATheme secondaryTextColor];
    demoHelp.numberOfLines = 0;
    demoHelp.translatesAutoresizingMaskIntoConstraints = NO;
    [self.demoSection addSubview:demoHelp];

    NSDictionary *dViews = @{@"lbl": demoLabel, @"sw": self.demoSwitch, @"help": demoHelp};
    [self.demoSection addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|[lbl]-8-[help]|" options:0 metrics:nil views:dViews]];
    [self.demoSection addConstraint:[NSLayoutConstraint constraintWithItem:demoHelp attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.demoSection attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.demoSection addConstraint:[NSLayoutConstraint constraintWithItem:demoHelp attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.demoSection attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    [self.demoSection addConstraint:[NSLayoutConstraint constraintWithItem:demoLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.demoSection attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.demoSection addConstraint:[NSLayoutConstraint constraintWithItem:self.demoSwitch attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.demoSection attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    [self.demoSection addConstraint:[NSLayoutConstraint constraintWithItem:self.demoSwitch attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:demoLabel attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

    // ── Help text ──────────────────────────────────────────────────────
    self.helpLabel = [[UILabel alloc] init];
    self.helpLabel.text = @"Generate a Long-Lived Access Token in your Home Assistant profile:\nSettings > People > [Your User] > Long-Lived Access Tokens";
    self.helpLabel.font = [UIFont systemFontOfSize:12];
    self.helpLabel.textColor = [HATheme secondaryTextColor];
    self.helpLabel.numberOfLines = 0;
    self.helpLabel.textAlignment = NSTextAlignmentCenter;
    self.helpLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.helpLabel];

    // ── Main vertical layout ───────────────────────────────────────────
    NSDictionary *views = @{
        @"connHdr": self.connectionSectionHeader,
        @"disc": self.discoverySection,
        @"urlLabel": urlLabel,
        @"urlField": self.serverURLField,
        @"authSeg": self.authModeSegment,
        @"tokenC": self.tokenContainer,
        @"loginC": self.loginContainer,
        @"button": self.connectButton,
        @"status": self.statusLabel,
        @"spinner": self.spinner,
        @"appHdr": self.appearanceSectionHeader,
        @"themeSection": self.themeSection,
        @"dispHdr": self.displaySectionHeader,
        @"kioskSection": self.kioskSection,
        @"demoSection": self.demoSection,
        @"help": self.helpLabel,
    };
    NSDictionary *metrics = @{@"p": @(padding), @"fh": @(fieldHeight), @"sh": @24};

    [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|[connHdr]-12-[disc]-p-[urlLabel]-4-[urlField(fh)]-p-[authSeg]-p-[tokenC][loginC]-p-[button(fh)]-p-[status]-8-[spinner]-sh-[appHdr]-12-[themeSection]-sh-[dispHdr]-12-[kioskSection]-p-[demoSection]-p-[help]|"
        options:0 metrics:metrics views:views]];

    for (NSString *name in @[@"connHdr", @"disc", @"urlLabel", @"urlField", @"authSeg", @"tokenC", @"loginC", @"button", @"status", @"appHdr", @"themeSection", @"dispHdr", @"kioskSection", @"demoSection", @"help"]) {
        UIView *v = views[name];
        [container addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
        [container addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    }

    [container addConstraint:[NSLayoutConstraint constraintWithItem:self.spinner attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];

    // Vertical: pin to scroll view content edges (defines scrollable content size)
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeTop multiplier:1 constant:40]];
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];

    // Horizontal: pin leading/trailing to self.view with padding, max width for iPad
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [container addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:maxWidth]];
}

- (UILabel *)createSectionHeaderWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textColor = [HATheme secondaryTextColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)loadExistingCredentials {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (auth.serverURL) {
        self.serverURLField.text = auth.serverURL;
    }

    if (auth.authMode == HAAuthModeOAuth) {
        self.authModeSegment.selectedSegmentIndex = 1;
        [self authModeChanged:self.authModeSegment];
    } else {
        if (auth.accessToken) {
            self.tokenField.text = auth.accessToken;
        }
    }

}

#pragma mark - Auth Mode Switching

- (void)authModeChanged:(UISegmentedControl *)sender {
    BOOL isTokenMode = (sender.selectedSegmentIndex == 0);
    self.tokenContainer.hidden = !isTokenMode;
    self.loginContainer.hidden = isTokenMode;

    if (isTokenMode) {
        self.helpLabel.text = @"Generate a Long-Lived Access Token in your Home Assistant profile:\nSettings > People > [Your User] > Long-Lived Access Tokens";
    } else {
        self.helpLabel.text = @"Enter your Home Assistant username and password.\nThe app will securely obtain and refresh access tokens.";
    }
}

#pragma mark - Discovery

- (void)discoveryService:(HADiscoveryService *)service didDiscoverServer:(HADiscoveredServer *)server {
    self.discoverySection.hidden = NO;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *title = server.name ?: @"Home Assistant";
    if (server.version) {
        title = [NSString stringWithFormat:@"%@ (v%@)", title, server.version];
    }
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.backgroundColor = [HATheme controlBackgroundColor];
    btn.layer.cornerRadius = 8.0;
    btn.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    btn.tag = self.discoveryService.discoveredServers.count - 1;
    [btn addTarget:self action:@selector(discoveredServerTapped:) forControlEvents:UIControlEventTouchUpInside];

    [self.discoveryStack addArrangedSubview:btn];
}

- (void)discoveryService:(HADiscoveryService *)service didRemoveServer:(HADiscoveredServer *)server {
    for (UIView *v in self.discoveryStack.arrangedSubviews) {
        [self.discoveryStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSUInteger i = 0; i < service.discoveredServers.count; i++) {
        [self discoveryService:service didDiscoverServer:service.discoveredServers[i]];
    }
    self.discoverySection.hidden = (service.discoveredServers.count == 0);
}

- (void)discoveredServerTapped:(UIButton *)sender {
    NSUInteger idx = (NSUInteger)sender.tag;
    NSArray *servers = self.discoveryService.discoveredServers;
    if (idx >= servers.count) return;

    HADiscoveredServer *server = servers[idx];
    self.serverURLField.text = server.baseURL;
}

#pragma mark - Connect

- (void)connectTapped {
    NSString *urlString = [self.serverURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (urlString.length == 0) {
        [self showStatus:@"Please enter a server URL" isError:YES];
        return;
    }

    while ([urlString hasSuffix:@"/"]) {
        urlString = [urlString substringToIndex:urlString.length - 1];
    }

    BOOL isTokenMode = (self.authModeSegment.selectedSegmentIndex == 0);

    if (isTokenMode) {
        [self connectWithToken:urlString];
    } else {
        [self connectWithLogin:urlString];
    }
}

- (void)connectWithToken:(NSString *)urlString {
    NSString *token = [self.tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (token.length == 0) {
        [self showStatus:@"Please enter an access token" isError:YES];
        return;
    }

    self.connectButton.enabled = NO;
    [self.spinner startAnimating];
    [self showStatus:@"Testing connection..." isError:NO];

    NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api", urlString]];
    HAAPIClient *testClient = [[HAAPIClient alloc] initWithBaseURL:baseURL token:token];

    [testClient checkAPIWithCompletion:^(id response, NSError *error) {
        self.connectButton.enabled = YES;
        [self.spinner stopAnimating];

        if (error) {
            [self showStatus:[NSString stringWithFormat:@"Connection failed: %@", error.localizedDescription] isError:YES];
            return;
        }

        [[HAAuthManager sharedManager] saveServerURL:urlString token:token];
        [self showStatus:@"Connected!" isError:NO];
        [self navigateToDashboard];
    }];
}

- (void)connectWithLogin:(NSString *)urlString {
    NSString *username = [self.usernameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = self.passwordField.text;

    if (username.length == 0) {
        [self showStatus:@"Please enter a username" isError:YES];
        return;
    }
    if (password.length == 0) {
        [self showStatus:@"Please enter a password" isError:YES];
        return;
    }

    self.connectButton.enabled = NO;
    [self.spinner startAnimating];
    [self showStatus:@"Logging in..." isError:NO];

    HAOAuthClient *oauth = [[HAOAuthClient alloc] initWithServerURL:urlString];

    [oauth loginWithUsername:username password:password completion:^(NSString *authCode, NSError *loginError) {
        if (loginError) {
            self.connectButton.enabled = YES;
            [self.spinner stopAnimating];
            [self showStatus:[NSString stringWithFormat:@"Login failed: %@", loginError.localizedDescription] isError:YES];
            return;
        }

        [self showStatus:@"Obtaining token..." isError:NO];

        [oauth exchangeAuthCode:authCode completion:^(NSDictionary *tokenResponse, NSError *tokenError) {
            self.connectButton.enabled = YES;
            [self.spinner stopAnimating];

            if (tokenError || !tokenResponse[@"access_token"]) {
                [self showStatus:[NSString stringWithFormat:@"Token exchange failed: %@",
                    tokenError.localizedDescription ?: @"no access token"] isError:YES];
                return;
            }

            NSString *accessToken = tokenResponse[@"access_token"];
            NSString *refreshToken = tokenResponse[@"refresh_token"];
            NSTimeInterval expiresIn = [tokenResponse[@"expires_in"] doubleValue];
            if (expiresIn <= 0) expiresIn = 1800;

            [[HAAuthManager sharedManager] saveOAuthCredentials:urlString
                                                   accessToken:accessToken
                                                  refreshToken:refreshToken
                                                     expiresIn:expiresIn];
            [self showStatus:@"Connected!" isError:NO];
            [self navigateToDashboard];
        }];
    }];
}

- (void)navigateToDashboard {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        HADashboardViewController *dashVC = [[HADashboardViewController alloc] init];
        UINavigationController *nav = self.navigationController;
        [nav setViewControllers:@[dashVC] animated:YES];
    });
}

- (void)kioskSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setKioskMode:sender.isOn];
}

- (void)demoSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setDemoMode:sender.isOn];
    if (sender.isOn) {
        // Navigate back to dashboard to show demo mode
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - Theme

- (void)themeModeChanged:(UISegmentedControl *)sender {
    HAThemeMode mode = (HAThemeMode)sender.selectedSegmentIndex;
    [HATheme setCurrentMode:mode];

    BOOL showGradient = (mode == HAThemeModeGradient);
    [UIView animateWithDuration:0.25 animations:^{
        self.gradientOptionsContainer.hidden = !showGradient;
        self.gradientOptionsContainer.alpha = showGradient ? 1.0 : 0.0;
    }];
    self.view.backgroundColor = [HATheme backgroundColor];
}

- (void)gradientPresetChanged:(UISegmentedControl *)sender {
    HAGradientPreset preset = (HAGradientPreset)sender.selectedSegmentIndex;
    [HATheme setGradientPreset:preset];

    BOOL showCustom = (preset == HAGradientPresetCustom);
    [UIView animateWithDuration:0.25 animations:^{
        self.customHexContainer.hidden = !showCustom;
        self.customHexContainer.alpha = showCustom ? 1.0 : 0.0;
    }];
    [self updateGradientPreview];
}

- (void)hexFieldChanged:(UITextField *)sender {
    NSString *h1 = self.hex1Field.text ?: @"";
    NSString *h2 = self.hex2Field.text ?: @"";
    if (h1.length > 0 && h2.length > 0) {
        [HATheme setCustomGradientHex1:h1 hex2:h2];
        [self updateGradientPreview];
    }
}

- (void)updateGradientPreview {
    NSArray<UIColor *> *colors = [HATheme gradientColors];
    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *c in colors) [cgColors addObject:(id)c.CGColor];
    self.previewGradientLayer.colors = cgColors;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.previewGradientLayer.frame = self.gradientPreview.bounds;
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewGradientLayer.frame = self.gradientPreview.bounds;
}

- (void)showStatus:(NSString *)text isError:(BOOL)isError {
    self.statusLabel.text = text;
    self.statusLabel.textColor = isError ? [HATheme destructiveColor] : [HATheme primaryTextColor];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.serverURLField) {
        if (self.authModeSegment.selectedSegmentIndex == 0) {
            [self.tokenField becomeFirstResponder];
        } else {
            [self.usernameField becomeFirstResponder];
        }
    } else if (textField == self.usernameField) {
        [self.passwordField becomeFirstResponder];
    } else if (textField == self.tokenField || textField == self.passwordField) {
        [textField resignFirstResponder];
        [self connectTapped];
    }
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

@end
