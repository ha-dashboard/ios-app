#import "HASettingsViewController.h"
#import "HAAuthManager.h"
#import "HAPerfMonitor.h"
#import "HAConnectionManager.h"
#import "HAConnectionSettingsViewController.h"
#import "HAToastView.h"
#import "HADashboardViewController.h"
#import "HADeviceRegistration.h"
#import "HADeviceIntegrationManager.h"
#import "HALoginViewController.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HALog.h"
#import "HACacheManager.h"
#import "HAEntityStateCache.h"
#import "HAHistoryManager.h"


// NSUserDefaults keys for device integration
static NSString *const kDeviceNameOverride    = @"ha_device_name_override";

@interface HASettingsViewController ()
// Connection summary
@property (nonatomic, strong) UIView *connectionRow;
@property (nonatomic, strong) UILabel *connectionServerLabel;
@property (nonatomic, strong) UILabel *connectionModeLabel;

// Section headers
@property (nonatomic, strong) UILabel *connectionSectionHeader;
@property (nonatomic, strong) UILabel *appearanceSectionHeader;
@property (nonatomic, strong) UILabel *displaySectionHeader;
@property (nonatomic, strong) UILabel *aboutSectionHeader;

// Theme
@property (nonatomic, strong) UIStackView *themeStack;
@property (nonatomic, strong) UISegmentedControl *themeModeSegment;
@property (nonatomic, strong) UIView *sunEntityToggleRow;
@property (nonatomic, strong) UISwitch *sunEntitySwitch;
@property (nonatomic, strong) UIView *gradientToggleRow;
@property (nonatomic, strong) UISwitch *gradientSwitch;
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

// Wake on touch (sub-setting of kiosk mode)
@property (nonatomic, strong) UIView *proximityWakeSection;
@property (nonatomic, strong) UISwitch *proximityWakeSwitch;

// Demo mode
@property (nonatomic, strong) UIView *demoSection;
@property (nonatomic, strong) UISwitch *demoSwitch;

// Auto-reload dashboard
@property (nonatomic, strong) UIView *autoReloadSection;
@property (nonatomic, strong) UISwitch *autoReloadSwitch;

// Camera audio mute
@property (nonatomic, strong) UIView *cameraMuteSection;
@property (nonatomic, strong) UISwitch *cameraMuteSwitch;

// Clear cache
@property (nonatomic, strong) UIButton *clearCacheButton;

// Device Integration
@property (nonatomic, strong) UILabel *integrationSectionHeader;
@property (nonatomic, strong) UIView *integrationSection;
@property (nonatomic, strong) UISwitch *registrationSwitch;
@property (nonatomic, strong) UILabel *registrationStatusLabel;
@property (nonatomic, strong) UITextField *deviceNameField;

// About
@property (nonatomic, strong) UIView *aboutSection;

// Logout
@property (nonatomic, strong) UIButton *logoutButton;

// Developer mode
@property (nonatomic, strong) UILabel *developerSectionHeader;
@property (nonatomic, strong) UIView *developerSection;
@property (nonatomic, assign) NSInteger devTapCount;
@property (nonatomic, strong) NSDate *devTapStart;
@property (nonatomic, strong) UIView *versionRow; // for tap gesture
@end

@implementation HASettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = [HATheme backgroundColor];

    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateConnectionSummary];
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

    self.connectionRow = [self createConnectionSummaryRow];
    [container addSubview:self.connectionRow];

    // ── APPEARANCE section ────────────────────────────────────────────
    self.appearanceSectionHeader = [self createSectionHeaderWithText:@"APPEARANCE"];
    [container addSubview:self.appearanceSectionHeader];

    self.themeStack = [[UIStackView alloc] init];
    self.themeStack.axis = UILayoutConstraintAxisVertical;
    self.themeStack.spacing = 12;
    self.themeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.themeStack];

    self.themeModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"Dark", @"Light"]];
    self.themeModeSegment.selectedSegmentIndex = (NSInteger)[HATheme currentMode];
    [self.themeModeSegment addTarget:self action:@selector(themeModeChanged:) forControlEvents:UIControlEventValueChanged];
    self.themeModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.themeStack addArrangedSubview:self.themeModeSegment];

    // Sun entity toggle (use HA sun.sun instead of system dark mode)
    UISwitch *sunSw = nil;
    self.sunEntityToggleRow = [self createToggleSection:@"Use Sun Entity"
        helpText:@"Use Home Assistant sun.sun entity for auto dark mode instead of system appearance."
        isOn:[HATheme forceSunEntity]
        target:self action:@selector(sunEntitySwitchToggled:)
        switchOut:&sunSw];
    self.sunEntitySwitch = sunSw;
    // Only visible when Auto mode is selected and device supports system appearance
    BOOL showSunToggle = ([HATheme currentMode] == HAThemeModeAuto
                          && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 13);
    self.sunEntityToggleRow.hidden = !showSunToggle;
    [self.themeStack addArrangedSubview:self.sunEntityToggleRow];

    // Gradient background toggle row
    self.gradientToggleRow = [[UIView alloc] init];
    self.gradientToggleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.themeStack addArrangedSubview:self.gradientToggleRow];

    UILabel *gradientLabel = [[UILabel alloc] init];
    gradientLabel.text = @"Gradient Background";
    gradientLabel.font = [UIFont systemFontOfSize:16];
    gradientLabel.textColor = [HATheme primaryTextColor];
    gradientLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gradientToggleRow addSubview:gradientLabel];

    self.gradientSwitch = [[HASwitch alloc] init];
    self.gradientSwitch.on = [HATheme isGradientEnabled];
    [self.gradientSwitch addTarget:self action:@selector(gradientSwitchToggled:) forControlEvents:UIControlEventValueChanged];
    self.gradientSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gradientToggleRow addSubview:self.gradientSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [gradientLabel.topAnchor constraintEqualToAnchor:self.gradientToggleRow.topAnchor],
        [gradientLabel.leadingAnchor constraintEqualToAnchor:self.gradientToggleRow.leadingAnchor],
        [gradientLabel.bottomAnchor constraintEqualToAnchor:self.gradientToggleRow.bottomAnchor],
        [self.gradientSwitch.trailingAnchor constraintEqualToAnchor:self.gradientToggleRow.trailingAnchor],
        [self.gradientSwitch.centerYAnchor constraintEqualToAnchor:gradientLabel.centerYAnchor],
    ]];

    // Gradient options (preset picker, custom hex, preview)
    self.gradientOptionsContainer = [[UIView alloc] init];
    self.gradientOptionsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.gradientOptionsContainer.hidden = ![HATheme isGradientEnabled];
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

    // Wake on touch — sub-setting shown below kiosk, disabled when kiosk is off
    BOOL kioskOn = [[HAAuthManager sharedManager] isKioskMode];
    UISwitch *proxWakeSw = nil;
    self.proximityWakeSection = [self createToggleSection:@"Wake on Touch"
        helpText:@"Dims the screen after 60 seconds of inactivity. Touch anywhere to wake."
        isOn:[[HAAuthManager sharedManager] proximityWakeEnabled]
        target:self action:@selector(proximityWakeSwitchToggled:)
        switchOut:&proxWakeSw];
    proxWakeSw.enabled = kioskOn;
    self.proximityWakeSection.alpha = kioskOn ? 1.0 : 0.4;
    self.proximityWakeSwitch = proxWakeSw;
    [container addSubview:self.proximityWakeSection];

    // Demo mode
    UISwitch *demoSw = nil;
    self.demoSection = [self createToggleSection:@"Demo Mode"
        helpText:@"Shows the app with demo data instead of connecting to a Home Assistant server. Useful for demonstrating the app's capabilities."
        isOn:[[HAAuthManager sharedManager] isDemoMode]
        target:self action:@selector(demoSwitchToggled:)
        switchOut:&demoSw];
    self.demoSwitch = demoSw;
    [container addSubview:self.demoSection];

    // Auto-reload dashboard
    UISwitch *autoReloadSw = nil;
    self.autoReloadSection = [self createToggleSection:@"Auto-Reload Dashboard"
        helpText:@"Automatically reload the dashboard when its configuration is changed on the Home Assistant server."
        isOn:[[HAAuthManager sharedManager] autoReloadDashboard]
        target:self action:@selector(autoReloadSwitchToggled:)
        switchOut:&autoReloadSw];
    self.autoReloadSwitch = autoReloadSw;
    [container addSubview:self.autoReloadSection];

    // Camera audio mute default
    UISwitch *camMuteSw = nil;
    self.cameraMuteSection = [self createToggleSection:@"Mute Camera Audio"
        helpText:@"Camera streams are muted by default. Turn this off to hear audio when opening fullscreen camera views (HLS streams only)."
        isOn:[[HAAuthManager sharedManager] cameraGlobalMute]
        target:self action:@selector(cameraMuteSwitchToggled:)
        switchOut:&camMuteSw];
    self.cameraMuteSwitch = camMuteSw;
    [container addSubview:self.cameraMuteSection];

    // Clear cache button
    self.clearCacheButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearCacheButton setTitle:@"Clear Cache & Reload" forState:UIControlStateNormal];
    self.clearCacheButton.titleLabel.font = [UIFont systemFontOfSize:16];
    self.clearCacheButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self.clearCacheButton setTitleColor:[HATheme destructiveColor] forState:UIControlStateNormal];
    self.clearCacheButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.clearCacheButton addTarget:self action:@selector(clearCacheTapped) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.clearCacheButton];

    // ── DEVICE INTEGRATION section ────────────────────────────────────
    self.integrationSectionHeader = [self createSectionHeaderWithText:@"DEVICE INTEGRATION"];
    [container addSubview:self.integrationSectionHeader];

    self.integrationSection = [self createDeviceIntegrationSection];
    [container addSubview:self.integrationSection];

    // ── ABOUT section ─────────────────────────────────────────────────
    self.aboutSectionHeader = [self createSectionHeaderWithText:@"ABOUT"];
    [container addSubview:self.aboutSectionHeader];

    self.aboutSection = [self createAboutSection];
    [container addSubview:self.aboutSection];

    // ── DEVELOPER section (placeholder for future options, hidden) ────
    self.developerSectionHeader = [self createSectionHeaderWithText:@"DEVELOPER"];
    self.developerSectionHeader.hidden = ![HATheme isDeveloperMode];
    [container addSubview:self.developerSectionHeader];
    {
        // Developer section: vertical stack of toggle rows
        UISwitch *blurSw, *perfSw;
        UIView *blurRow = [self createToggleSection:@"Disable Blur"
            helpText:@"Turn off frosted-glass card backgrounds for A/B perf testing"
            isOn:[HATheme blurDisabled]
            target:self action:@selector(blurDisabledToggled:)
            switchOut:&blurSw];
        UIView *perfRow = [self createToggleSection:@"Performance Monitor"
            helpText:@"Log FPS + timing to /tmp/perf.log (restart app to apply)"
            isOn:[[NSUserDefaults standardUserDefaults] boolForKey:@"HAPerfMonitorEnabled"]
            target:self action:@selector(perfMonitorToggled:)
            switchOut:&perfSw];

        // Camera stream mode selector
        UILabel *streamLabel = [[UILabel alloc] init];
        streamLabel.text = @"Camera Stream Mode";
        streamLabel.font = [UIFont systemFontOfSize:16];
        streamLabel.textColor = [HATheme primaryTextColor];
        streamLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UISegmentedControl *streamSeg = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"MJPEG", @"HLS", @"Snapshot"]];
        streamSeg.translatesAutoresizingMaskIntoConstraints = NO;
        NSString *savedMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"HADevStreamMode"];
        if ([savedMode isEqualToString:@"mjpeg"])    streamSeg.selectedSegmentIndex = 1;
        else if ([savedMode isEqualToString:@"hls"]) streamSeg.selectedSegmentIndex = 2;
        else if ([savedMode isEqualToString:@"snapshot"]) streamSeg.selectedSegmentIndex = 3;
        else streamSeg.selectedSegmentIndex = 0;
        [streamSeg addTarget:self action:@selector(streamModeChanged:) forControlEvents:UIControlEventValueChanged];

        UIStackView *streamRow = [[UIStackView alloc] initWithArrangedSubviews:@[streamLabel, streamSeg]];
        streamRow.axis = UILayoutConstraintAxisVertical;
        streamRow.spacing = 6;
        streamRow.translatesAutoresizingMaskIntoConstraints = NO;

        // Verbose logging toggle
        UISwitch *verboseSw;
        UIView *verboseRow = [self createToggleSection:@"Verbose Logging"
            helpText:@"Log debug-level messages (camera frames, polling, data sizes). Useful for diagnosing issues."
            isOn:([HALog minLevel] == HALogLevelDebug)
            target:self action:@selector(verboseLoggingToggled:)
            switchOut:&verboseSw];

        // Export logs button
        UIButton *exportBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [exportBtn setTitle:@"Export Logs" forState:UIControlStateNormal];
        exportBtn.titleLabel.font = [UIFont systemFontOfSize:16];
        exportBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        exportBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [exportBtn addTarget:self action:@selector(exportLogsTapped) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *devStack = [[UIStackView alloc] initWithArrangedSubviews:@[blurRow, perfRow, streamRow, verboseRow, exportBtn]];
        devStack.axis = UILayoutConstraintAxisVertical;
        devStack.spacing = 12;
        devStack.translatesAutoresizingMaskIntoConstraints = NO;

        self.developerSection = devStack;
        self.developerSection.hidden = ![HATheme isDeveloperMode];
        [container addSubview:self.developerSection];
    }

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
        @"connRow":   self.connectionRow,
        @"appHdr":    self.appearanceSectionHeader,
        @"themeStack":self.themeStack,
        @"dispHdr":   self.displaySectionHeader,
        @"kiosk":     self.kioskSection,
        @"proxWake":  self.proximityWakeSection,
        @"demo":      self.demoSection,
        @"autoReload":self.autoReloadSection,
        @"camMute":   self.cameraMuteSection,
        @"clrCache":  self.clearCacheButton,
        @"intHdr":    self.integrationSectionHeader,
        @"intSec":    self.integrationSection,
        @"aboutHdr":  self.aboutSectionHeader,
        @"about":     self.aboutSection,
        @"devHdr":    self.developerSectionHeader,
        @"dev":       self.developerSection,
        @"logout":    self.logoutButton,
    };
    NSDictionary *metrics = @{@"p": @16, @"sh": @32, @"hg": @10, @"fh": @44};

    [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|[connHdr]-hg-[connRow]-sh-[appHdr]-hg-[themeStack]-sh-[dispHdr]-hg-[kiosk]-p-[proxWake]-p-[demo]-p-[autoReload]-p-[camMute]-p-[clrCache(fh)]-sh-[intHdr]-hg-[intSec]-sh-[aboutHdr]-hg-[about]-sh-[devHdr]-hg-[dev]-sh-[logout(fh)]|"
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

    UISwitch *sw = [[HASwitch alloc] init];
    sw.on = isOn;
    sw.onTintColor = [HATheme switchTintColor];
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

- (UIView *)createDeviceIntegrationSection {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Registration toggle row ──
    UIView *regRow = [[UIView alloc] init];
    regRow.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:regRow];

    UILabel *regLabel = [[UILabel alloc] init];
    regLabel.text = @"Register with Home Assistant";
    regLabel.font = [UIFont systemFontOfSize:16];
    regLabel.textColor = [HATheme primaryTextColor];
    regLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [regRow addSubview:regLabel];

    self.registrationSwitch = [[HASwitch alloc] init];
    self.registrationSwitch.on = [HADeviceRegistration sharedManager].isRegistered;
    self.registrationSwitch.onTintColor = [HATheme switchTintColor];
    [self.registrationSwitch addTarget:self action:@selector(registrationSwitchToggled:) forControlEvents:UIControlEventValueChanged];
    self.registrationSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [regRow addSubview:self.registrationSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [regLabel.topAnchor constraintEqualToAnchor:regRow.topAnchor],
        [regLabel.leadingAnchor constraintEqualToAnchor:regRow.leadingAnchor],
        [regLabel.bottomAnchor constraintEqualToAnchor:regRow.bottomAnchor],
        [self.registrationSwitch.trailingAnchor constraintEqualToAnchor:regRow.trailingAnchor],
        [self.registrationSwitch.centerYAnchor constraintEqualToAnchor:regLabel.centerYAnchor],
    ]];

    // Status label
    self.registrationStatusLabel = [[UILabel alloc] init];
    self.registrationStatusLabel.font = [UIFont systemFontOfSize:12];
    self.registrationStatusLabel.textColor = [HATheme secondaryTextColor];
    self.registrationStatusLabel.numberOfLines = 0;
    self.registrationStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self updateRegistrationStatus];
    [stack addArrangedSubview:self.registrationStatusLabel];

    // ── Device name field ──
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = @"Device Name";
    nameLabel.font = [UIFont systemFontOfSize:12];
    nameLabel.textColor = [HATheme secondaryTextColor];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:nameLabel];

    self.deviceNameField = [[UITextField alloc] init];
    NSString *savedName = [[NSUserDefaults standardUserDefaults] stringForKey:kDeviceNameOverride];
    self.deviceNameField.text = savedName ?: [UIDevice currentDevice].name;
    self.deviceNameField.placeholder = [UIDevice currentDevice].name;
    self.deviceNameField.borderStyle = UITextBorderStyleRoundedRect;
    self.deviceNameField.font = [UIFont systemFontOfSize:14];
    self.deviceNameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.deviceNameField.returnKeyType = UIReturnKeyDone;
    self.deviceNameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.deviceNameField addTarget:self action:@selector(deviceNameChanged:) forControlEvents:UIControlEventEditingDidEnd];
    [stack addArrangedSubview:self.deviceNameField];
    [self.deviceNameField.heightAnchor constraintEqualToConstant:36].active = YES;

    return stack;
}

- (void)updateRegistrationStatus {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    if (reg.isRegistered) {
        NSString *truncatedId = reg.webhookId;
        if (truncatedId.length > 12) {
            truncatedId = [NSString stringWithFormat:@"%@\u2026", [truncatedId substringToIndex:12]];
        }
        self.registrationStatusLabel.text = [NSString stringWithFormat:@"Registered \u2014 Webhook: %@", truncatedId];
    } else {
        self.registrationStatusLabel.text = @"Not registered. Enable to send device sensors to Home Assistant.";
    }
}

#pragma mark - Device Integration Actions

- (void)registrationSwitchToggled:(UISwitch *)sender {
    if (sender.isOn) {
        sender.enabled = NO;
        self.registrationStatusLabel.text = @"Registering\u2026";
        [[HADeviceRegistration sharedManager] registerWithCompletion:^(BOOL success, NSError *error) {
            sender.enabled = YES;
            if (success) {
                // Enable integration manager so sensors start reporting
                [HADeviceIntegrationManager sharedManager].enabled = YES;
                [self updateRegistrationStatus];
            } else {
                sender.on = NO;
                self.registrationStatusLabel.text = [NSString stringWithFormat:@"Registration failed: %@",
                    error.localizedDescription ?: @"Unknown error"];
            }
        }];
    } else {
        [HADeviceIntegrationManager sharedManager].enabled = NO;
        [[HADeviceRegistration sharedManager] unregister];
        [self updateRegistrationStatus];
    }
}

- (void)deviceNameChanged:(UITextField *)sender {
    NSString *name = sender.text;
    if (name.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:name forKey:kDeviceNameOverride];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDeviceNameOverride];
        sender.text = [UIDevice currentDevice].name;
    }

    // Push name change to HA if registered
    if ([HADeviceRegistration sharedManager].isRegistered) {
        NSDictionary *update = @{
            @"device_name": [HADeviceRegistration sharedManager].deviceName,
            @"app_version": [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: @"0.0.0",
        };
        [[HADeviceRegistration sharedManager] sendWebhookWithType:@"update_registration" data:update completion:nil];
    }
}

- (UIView *)createAboutSection {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    // Version + build (tappable for developer mode activation)
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"0.0.0";
    NSString *build = info[@"CFBundleVersion"] ?: @"0";
    self.versionRow = [self aboutRow:@"Version" value:[NSString stringWithFormat:@"%@ (%@)", version, build]];
    self.versionRow.userInteractionEnabled = YES;
    UITapGestureRecognizer *devTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(versionTapped)];
    [self.versionRow addGestureRecognizer:devTap];
    [stack addArrangedSubview:self.versionRow];

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
        // iOS 9 compatible — openURL:options:completionHandler: is iOS 10+
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [[UIApplication sharedApplication] openURL:url];
#pragma clang diagnostic pop
    }
}

#pragma mark - Connection Summary

- (UIView *)createConnectionSummaryRow {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [HATheme controlBackgroundColor];
    row.layer.cornerRadius = 10.0;
    [row addTarget:self action:@selector(connectionRowTapped) forControlEvents:UIControlEventTouchUpInside];

    // Server icon
    UIImageView *icon = [[UIImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = [HATheme accentColor];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
        icon.image = [UIImage systemImageNamed:@"server.rack" withConfiguration:config];
    }
    icon.userInteractionEnabled = NO;
    [row addSubview:icon];

    // Server URL label
    self.connectionServerLabel = [[UILabel alloc] init];
    self.connectionServerLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.connectionServerLabel.textColor = [HATheme primaryTextColor];
    self.connectionServerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.connectionServerLabel.userInteractionEnabled = NO;
    [row addSubview:self.connectionServerLabel];

    // Auth mode label
    self.connectionModeLabel = [[UILabel alloc] init];
    self.connectionModeLabel.font = [UIFont systemFontOfSize:12];
    self.connectionModeLabel.textColor = [HATheme secondaryTextColor];
    self.connectionModeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.connectionModeLabel.userInteractionEnabled = NO;
    [row addSubview:self.connectionModeLabel];

    // Chevron
    UIImageView *chevron = [[UIImageView alloc] init];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.tintColor = [HATheme secondaryTextColor];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium];
        chevron.image = [UIImage systemImageNamed:@"chevron.right" withConfiguration:config];
    }
    chevron.userInteractionEnabled = NO;
    [row addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:56],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [self.connectionServerLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [self.connectionServerLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [self.connectionServerLabel.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],
        [self.connectionModeLabel.leadingAnchor constraintEqualToAnchor:self.connectionServerLabel.leadingAnchor],
        [self.connectionModeLabel.topAnchor constraintEqualToAnchor:self.connectionServerLabel.bottomAnchor constant:2],
        [self.connectionModeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:12],
    ]];

    return row;
}

- (void)updateConnectionSummary {
    HAAuthManager *auth = [HAAuthManager sharedManager];

    if (auth.isDemoMode) {
        self.connectionServerLabel.text = @"Demo Mode";
        self.connectionModeLabel.text = @"Using sample data";
    } else if (auth.isConfigured) {
        self.connectionServerLabel.text = auth.serverURL ?: @"Connected";
        switch (auth.authMode) {
            case HAAuthModeOAuth:
                self.connectionModeLabel.text = @"Username/Password";
                break;
            case HAAuthModeToken:
                self.connectionModeLabel.text = @"Access Token";
                break;
        }
    } else {
        self.connectionServerLabel.text = @"Not connected";
        self.connectionModeLabel.text = @"Tap to configure";
    }
}

- (void)connectionRowTapped {
    HAConnectionSettingsViewController *connVC = [[HAConnectionSettingsViewController alloc] init];
    [self.navigationController pushViewController:connVC animated:YES];
}

#pragma mark - Toggle Actions

- (void)kioskSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setKioskMode:sender.isOn];
    // Enable/disable the dependent wake-on-touch sub-setting
    self.proximityWakeSwitch.enabled = sender.isOn;
    [UIView animateWithDuration:0.2 animations:^{
        self.proximityWakeSection.alpha = sender.isOn ? 1.0 : 0.4;
    }];
    if (!sender.isOn && self.proximityWakeSwitch.isOn) {
        // Turn off wake-on-touch when kiosk is disabled
        [self.proximityWakeSwitch setOn:NO animated:YES];
        [[HAAuthManager sharedManager] setProximityWakeEnabled:NO];
    }
}

- (void)proximityWakeSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setProximityWakeEnabled:sender.isOn];
}

- (void)autoReloadSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setAutoReloadDashboard:sender.isOn];
}

- (void)cameraMuteSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setCameraGlobalMute:sender.isOn];
}

- (void)blurDisabledToggled:(UISwitch *)sender {
    [HATheme setBlurDisabled:sender.isOn];
}

- (void)perfMonitorToggled:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:@"HAPerfMonitorEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (sender.isOn) {
        [[HAPerfMonitor sharedMonitor] start];
    } else {
        [[HAPerfMonitor sharedMonitor] stop];
    }
}

- (void)streamModeChanged:(UISegmentedControl *)seg {
    NSArray *modes = @[@"auto", @"mjpeg", @"hls", @"snapshot"];
    NSString *mode = modes[seg.selectedSegmentIndex];
    [[NSUserDefaults standardUserDefaults] setObject:mode forKey:@"HADevStreamMode"];
    HALogI(@"settings", @"Camera stream mode: %@", mode);
}

- (void)verboseLoggingToggled:(UISwitch *)sender {
    [HALog setMinLevel:sender.isOn ? HALogLevelDebug : HALogLevelInfo];
}

- (void)exportLogsTapped {
    [HALog flush];

    NSMutableArray *items = [NSMutableArray array];
    NSString *current = [HALog currentLogFilePath];
    if (current && [[NSFileManager defaultManager] fileExistsAtPath:current]) {
        [items addObject:[NSURL fileURLWithPath:current]];
    }
    NSString *previous = [HALog previousLogFilePath];
    if (previous && [[NSFileManager defaultManager] fileExistsAtPath:previous]) {
        [items addObject:[NSURL fileURLWithPath:previous]];
    }

    if (items.count == 0) return;

    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    avc.popoverPresentationController.sourceView = self.view;
    avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)demoSwitchToggled:(UISwitch *)sender {
    [[HAAuthManager sharedManager] setDemoMode:sender.isOn];
    if (sender.isOn) {
        [[HAConnectionManager sharedManager] disconnect];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            HADashboardViewController *dashVC = [[HADashboardViewController alloc] init];
            UINavigationController *nav = self.navigationController;
            [nav setViewControllers:@[dashVC] animated:YES];
        });
    }
    [self updateConnectionSummary];
}

#pragma mark - Clear Cache

- (void)clearCacheTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Cache"
        message:@"This will clear all cached entity states and dashboard configs, then reload from the current source."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear & Reload" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // Clear persistent disk caches
        [[HACacheManager sharedManager] clearAllCaches];

        // Clear in-memory caches
        [[HAHistoryManager sharedManager] clearCache];

        // Disconnect and clear in-memory entity store
        HAConnectionManager *conn = [HAConnectionManager sharedManager];
        [conn disconnect];
        [conn clearEntityStore];

        // Reconnect — loads from demo provider or real server depending on mode
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [conn connect];
        });

        HALogI(@"settings", @"Cache cleared and reload triggered");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
    [self refreshThemeColors];

    // Show sun entity toggle only in Auto mode on iOS 13+
    BOOL showSun = (mode == HAThemeModeAuto
                    && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 13);
    [UIView animateWithDuration:0.25 animations:^{
        self.sunEntityToggleRow.hidden = !showSun;
    }];
}

- (void)sunEntitySwitchToggled:(UISwitch *)sender {
    [HATheme setForceSunEntity:sender.isOn];
    [self refreshThemeColors];
}

/// Re-apply theme colors to all labels and backgrounds in the settings page.
/// Needed on iOS 9-12 where there's no system trait-based color resolution.
- (void)refreshThemeColors {
    self.view.backgroundColor = [HATheme backgroundColor];
    self.connectionRow.backgroundColor = [HATheme controlBackgroundColor];
    [self updateGradientPreview];

    // Navigation bar (iOS 9-12 needs manual styling)
    if (@available(iOS 13.0, *)) {
        // Handled by overrideUserInterfaceStyle
    } else {
        UINavigationBar *navBar = self.navigationController.navigationBar;
        BOOL dark = [HATheme isDarkMode];
        navBar.barStyle = dark ? UIBarStyleBlack : UIBarStyleDefault;
        navBar.barTintColor = dark
            ? [UIColor colorWithRed:0.11 green:0.11 blue:0.13 alpha:1.0]
            : nil;
        navBar.tintColor = [HATheme primaryTextColor];
    }

    // Walk all labels and re-apply text colors based on font size convention:
    // 16pt = primary, 12pt/11pt = secondary, 10pt = tertiary
    [self applyThemeColorsToSubviewsOf:self.view];
}

- (void)applyThemeColorsToSubviewsOf:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)sub;
            CGFloat size = label.font.pointSize;
            if (size >= 15) {
                label.textColor = [HATheme primaryTextColor];
            } else if (size >= 11) {
                label.textColor = [HATheme secondaryTextColor];
            } else {
                label.textColor = [HATheme tertiaryTextColor];
            }
        }
        [self applyThemeColorsToSubviewsOf:sub];
    }
}

- (void)gradientSwitchToggled:(UISwitch *)sender {
    [HATheme setGradientEnabled:sender.isOn];
    [UIView animateWithDuration:0.25 animations:^{
        self.gradientOptionsContainer.hidden = !sender.isOn;
        self.gradientOptionsContainer.alpha = sender.isOn ? 1.0 : 0.0;
    }];
    [self refreshThemeColors];
}

- (void)gradientPresetChanged:(UISegmentedControl *)sender {
    HAGradientPreset preset = (HAGradientPreset)sender.selectedSegmentIndex;
    [HATheme setGradientPreset:preset];

    BOOL showCustom = (preset == HAGradientPresetCustom);
    [UIView animateWithDuration:0.25 animations:^{
        self.customHexContainer.hidden = !showCustom;
        self.customHexContainer.alpha = showCustom ? 1.0 : 0.0;
    }];
    [self refreshThemeColors];
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

#pragma mark - Developer Mode

- (void)versionTapped {
    NSDate *now = [NSDate date];

    // Reset counter if more than 3 seconds since first tap
    if (!self.devTapStart || [now timeIntervalSinceDate:self.devTapStart] > 3.0) {
        self.devTapCount = 0;
        self.devTapStart = now;
    }

    self.devTapCount++;

    if (self.devTapCount >= 5) {
        self.devTapCount = 0;
        self.devTapStart = nil;

        BOOL newState = ![HATheme isDeveloperMode];
        [HATheme setDeveloperMode:newState];

        // Show/hide developer section
        [UIView animateWithDuration:0.3 animations:^{
            self.developerSectionHeader.hidden = !newState;
            self.developerSection.hidden = !newState;
        }];

        // Toast feedback
        NSString *message = newState ? @"Developer Mode Enabled" : @"Developer Mode Disabled";
        [HAToastView showInView:self.navigationController.view ?: self.view
                        message:message
                       subtitle:nil
                       duration:1.5
                      tapAction:nil];
    }
}

@end
