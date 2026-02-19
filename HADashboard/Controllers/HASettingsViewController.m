#import "HASettingsViewController.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HAConnectionFormView.h"
#import "HADashboardViewController.h"
#import "HALoginViewController.h"
#import "HATheme.h"

@interface HASettingsViewController () <HAConnectionFormDelegate>
// Connection
@property (nonatomic, strong) HAConnectionFormView *connectionForm;

// Section headers
@property (nonatomic, strong) UILabel *connectionSectionHeader;
@property (nonatomic, strong) UILabel *appearanceSectionHeader;
@property (nonatomic, strong) UILabel *displaySectionHeader;
@property (nonatomic, strong) UILabel *aboutSectionHeader;

// Theme
@property (nonatomic, strong) UIStackView *themeStack;
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

// About
@property (nonatomic, strong) UIView *aboutSection;

// Logout
@property (nonatomic, strong) UIButton *logoutButton;
@end

@implementation HASettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
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

- (void)setupUI {
    CGFloat padding = 20.0;
    CGFloat maxWidth = 500.0;

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
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

    // ── CONNECTION section ─────────────────────────────────────────────
    self.connectionSectionHeader = [self createSectionHeaderWithText:@"CONNECTION"];
    [container addSubview:self.connectionSectionHeader];

    self.connectionForm = [[HAConnectionFormView alloc] initWithFrame:CGRectZero];
    self.connectionForm.delegate = self;
    self.connectionForm.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.connectionForm];

    // ── APPEARANCE section ────────────────────────────────────────────
    self.appearanceSectionHeader = [self createSectionHeaderWithText:@"APPEARANCE"];
    [container addSubview:self.appearanceSectionHeader];

    self.themeStack = [[UIStackView alloc] init];
    self.themeStack.axis = UILayoutConstraintAxisVertical;
    self.themeStack.spacing = 12;
    self.themeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.themeStack];

    self.themeModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"Gradient", @"Dark", @"Light"]];
    self.themeModeSegment.selectedSegmentIndex = (NSInteger)[HATheme currentMode];
    [self.themeModeSegment addTarget:self action:@selector(themeModeChanged:) forControlEvents:UIControlEventValueChanged];
    self.themeModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.themeStack addArrangedSubview:self.themeModeSegment];

    // Gradient options
    self.gradientOptionsContainer = [[UIView alloc] init];
    self.gradientOptionsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.gradientOptionsContainer.hidden = ([HATheme currentMode] != HAThemeModeGradient);
    [self.themeStack addArrangedSubview:self.gradientOptionsContainer];

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
        [self.gradientPresetSegment.topAnchor constraintEqualToAnchor:presetLabel.bottomAnchor constant:8],
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

    // ── DISPLAY section ───────────────────────────────────────────────
    self.displaySectionHeader = [self createSectionHeaderWithText:@"DISPLAY"];
    [container addSubview:self.displaySectionHeader];

    // Kiosk mode
    UISwitch *kioskSw = nil;
    self.kioskSection = [self createToggleSection:@"Kiosk Mode"
        helpText:@"Hides navigation bar and prevents screen sleep. Triple-tap the top of the screen to temporarily show controls.\n\nFor full lockdown, enable Guided Access in iPad Settings \u2192 Accessibility \u2192 Guided Access, then triple-click the Home button while in the app."
        isOn:[[HAAuthManager sharedManager] isKioskMode]
        target:self action:@selector(kioskSwitchToggled:)
        switchOut:&kioskSw];
    self.kioskSwitch = kioskSw;
    [container addSubview:self.kioskSection];

    // Demo mode
    UISwitch *demoSw = nil;
    self.demoSection = [self createToggleSection:@"Demo Mode"
        helpText:@"Shows the app with demo data instead of connecting to a Home Assistant server. Useful for demonstrating the app's capabilities."
        isOn:[[HAAuthManager sharedManager] isDemoMode]
        target:self action:@selector(demoSwitchToggled:)
        switchOut:&demoSw];
    self.demoSwitch = demoSw;
    [container addSubview:self.demoSection];

    // ── ABOUT section ─────────────────────────────────────────────────
    self.aboutSectionHeader = [self createSectionHeaderWithText:@"ABOUT"];
    [container addSubview:self.aboutSectionHeader];

    self.aboutSection = [self createAboutSection];
    [container addSubview:self.aboutSection];

    // ── Log Out & Reset ───────────────────────────────────────────────
    self.logoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.logoutButton setTitle:@"Log Out & Reset" forState:UIControlStateNormal];
    self.logoutButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [self.logoutButton setTitleColor:[HATheme destructiveColor] forState:UIControlStateNormal];
    self.logoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logoutButton addTarget:self action:@selector(logoutTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.logoutButton];

    // ── Main vertical layout ───────────────────────────────────────────
    NSDictionary *views = @{
        @"connHdr":   self.connectionSectionHeader,
        @"form":      self.connectionForm,
        @"appHdr":    self.appearanceSectionHeader,
        @"themeStack":self.themeStack,
        @"dispHdr":   self.displaySectionHeader,
        @"kiosk":     self.kioskSection,
        @"demo":      self.demoSection,
        @"aboutHdr":  self.aboutSectionHeader,
        @"about":     self.aboutSection,
        @"logout":    self.logoutButton,
    };
    NSDictionary *metrics = @{@"p": @16, @"sh": @32, @"hg": @10, @"fh": @44};

    [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|[connHdr]-hg-[form]-sh-[appHdr]-hg-[themeStack]-sh-[dispHdr]-hg-[kiosk]-p-[demo]-sh-[aboutHdr]-hg-[about]-sh-[logout(fh)]|"
        options:0 metrics:metrics views:views]];

    for (NSString *name in views) {
        UIView *v = views[name];
        [container addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
        [container addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    }

    // ScrollView content constraints
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeTop multiplier:1 constant:24]];
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];

    // Horizontal: centered with max width
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [container addConstraint:[NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:maxWidth]];
}

#pragma mark - Section Helpers

- (UILabel *)createSectionHeaderWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textColor = [HATheme secondaryTextColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UIView *)createToggleSection:(NSString *)title helpText:(NSString *)helpText isOn:(BOOL)isOn
                         target:(id)target action:(SEL)action switchOut:(UISwitch **)outSwitch {
    UIView *section = [[UIView alloc] init];
    section.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:16];
    label.textColor = [HATheme primaryTextColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [section addSubview:label];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = isOn;
    [sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [section addSubview:sw];
    if (outSwitch) *outSwitch = sw;

    UILabel *help = [[UILabel alloc] init];
    help.text = helpText;
    help.font = [UIFont systemFontOfSize:12];
    help.textColor = [HATheme secondaryTextColor];
    help.numberOfLines = 0;
    help.translatesAutoresizingMaskIntoConstraints = NO;
    [section addSubview:help];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:section.topAnchor],
        [label.leadingAnchor constraintEqualToAnchor:section.leadingAnchor],
        [sw.trailingAnchor constraintEqualToAnchor:section.trailingAnchor],
        [sw.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [help.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
        [help.leadingAnchor constraintEqualToAnchor:section.leadingAnchor],
        [help.trailingAnchor constraintEqualToAnchor:section.trailingAnchor],
        [help.bottomAnchor constraintEqualToAnchor:section.bottomAnchor],
    ]];

    return section;
}

- (UIView *)createAboutSection {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    // Version + build
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"0.0.0";
    NSString *build = info[@"CFBundleVersion"] ?: @"0";
    [stack addArrangedSubview:[self aboutRow:@"Version" value:[NSString stringWithFormat:@"%@ (%@)", version, build]]];

    // Connected server
    NSString *serverURL = [[HAAuthManager sharedManager] serverURL] ?: @"Not connected";
    [stack addArrangedSubview:[self aboutRow:@"Server" value:serverURL]];

    // GitHub
    UIButton *githubButton = [self aboutLinkButton:@"GitHub Repository" url:@"https://github.com/ha-dashboard/ios-app"];
    [stack addArrangedSubview:githubButton];

    // License
    UIButton *licenseButton = [self aboutLinkButton:@"License: Apache 2.0" url:@"https://github.com/ha-dashboard/ios-app/blob/main/LICENSE"];
    [stack addArrangedSubview:licenseButton];

    // Privacy
    UIButton *privacyButton = [self aboutLinkButton:@"Privacy Policy" url:@"https://github.com/ha-dashboard/ios-app/blob/main/PRIVACY.md"];
    [stack addArrangedSubview:privacyButton];

    // Open source acknowledgements
    UILabel *oss = [[UILabel alloc] init];
    oss.text = @"Built with SocketRocket, Lottie, and Material Design Icons.";
    oss.font = [UIFont systemFontOfSize:12];
    oss.textColor = [HATheme tertiaryTextColor];
    oss.numberOfLines = 0;
    oss.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:oss];

    return stack;
}

- (UIView *)aboutRow:(NSString *)label value:(NSString *)value {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = label;
    lbl.font = [UIFont systemFontOfSize:14];
    lbl.textColor = [HATheme secondaryTextColor];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:lbl];

    UILabel *val = [[UILabel alloc] init];
    val.text = value;
    val.font = [UIFont systemFontOfSize:14];
    val.textColor = [HATheme primaryTextColor];
    val.textAlignment = NSTextAlignmentRight;
    val.numberOfLines = 1;
    val.lineBreakMode = NSLineBreakByTruncatingMiddle;
    val.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:val];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.topAnchor constraintEqualToAnchor:row.topAnchor],
        [lbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [lbl.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [val.topAnchor constraintEqualToAnchor:row.topAnchor],
        [val.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [val.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [val.leadingAnchor constraintGreaterThanOrEqualToAnchor:lbl.trailingAnchor constant:12],
    ]];
    // Give value label higher compression resistance
    [lbl setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [val setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    return row;
}

- (UIButton *)aboutLinkButton:(NSString *)title url:(NSString *)urlString {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    // Store URL in accessibility hint (simple approach without subclassing)
    btn.accessibilityHint = urlString;
    [btn addTarget:self action:@selector(aboutLinkTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)aboutLinkTapped:(UIButton *)sender {
    NSString *urlString = sender.accessibilityHint;
    if (!urlString) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

#pragma mark - HAConnectionFormDelegate

- (void)connectionFormDidConnect:(HAConnectionFormView *)form {
    [self navigateToDashboard];
}

#pragma mark - Navigation

- (void)navigateToDashboard {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        HADashboardViewController *dashVC = [[HADashboardViewController alloc] init];
        UINavigationController *nav = self.navigationController;
        [nav setViewControllers:@[dashVC] animated:YES];
    });
}

#pragma mark - Toggle Actions

- (void)kioskSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setKioskMode:sender.isOn];
}

- (void)demoSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setDemoMode:sender.isOn];
    if (sender.isOn) {
        [[HAConnectionManager sharedManager] disconnect];
        [self navigateToDashboard];
    }
}

#pragma mark - Logout

- (void)logoutTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Log Out & Reset"
        message:@"This will remove all saved credentials, settings, and return the app to its initial state."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Log Out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[HAConnectionManager sharedManager] disconnect];
        [[HAAuthManager sharedManager] clearCredentials];

        // Navigate to login screen
        HALoginViewController *loginVC = [[HALoginViewController alloc] init];
        UINavigationController *nav = self.navigationController;
        [nav setViewControllers:@[loginVC] animated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

@end
