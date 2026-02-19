#import "HAConnectionFormView.h"
#import "HAAuthManager.h"
#import "HAOAuthClient.h"
#import "HAAPIClient.h"
#import "HAConnectionManager.h"
#import "HADiscoveryService.h"
#import "HADiscoveredServer.h"
#import "HATheme.h"

static NSString *const kModeTrusted = @"trusted";
static NSString *const kModeLogin   = @"login";
static NSString *const kModeToken   = @"token";

@interface HAConnectionFormView () <UITextFieldDelegate, HADiscoveryServiceDelegate>
@property (nonatomic, strong) UITextField *serverURLField;
@property (nonatomic, strong) UISegmentedControl *authModeSegment;

// Segment index → mode mapping (rebuilt when providers change)
@property (nonatomic, copy) NSArray<NSString *> *authModes;

// Login mode container
@property (nonatomic, strong) UIView *loginContainer;
@property (nonatomic, strong) UIStackView *authFieldsStack;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *passwordField;

// Token mode container
@property (nonatomic, strong) UIView *tokenContainer;
@property (nonatomic, strong) UITextField *tokenField;

// Trusted network container
@property (nonatomic, strong) UIView *trustedContainer;

// Auth provider probing
@property (nonatomic, copy) NSString *lastProbedURL;
@property (nonatomic, assign) BOOL hasHomeAssistantProvider;
@property (nonatomic, assign) BOOL hasTrustedNetworkProvider;

@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

// Discovery
@property (nonatomic, strong) HADiscoveryService *discoveryService;
@property (nonatomic, strong) UIView *discoverySection;
@property (nonatomic, strong) UIStackView *discoveryStack;
@end

@implementation HAConnectionFormView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _hasHomeAssistantProvider = YES;
        _hasTrustedNetworkProvider = NO;
        _authModes = @[kModeLogin, kModeToken];
        [self setupUI];
    }
    return self;
}

#pragma mark - Current Mode

- (NSString *)currentMode {
    NSInteger idx = self.authModeSegment.selectedSegmentIndex;
    if (idx >= 0 && idx < (NSInteger)self.authModes.count) {
        return self.authModes[idx];
    }
    return kModeLogin;
}

#pragma mark - UI Setup

- (void)setupUI {
    CGFloat fieldHeight = 44.0;

    // ── Discovery section ──────────────────────────────────────────────
    self.discoverySection = [[UIView alloc] init];
    self.discoverySection.translatesAutoresizingMaskIntoConstraints = NO;
    self.discoverySection.hidden = YES;
    [self addSubview:self.discoverySection];

    UILabel *discoveryTitle = [[UILabel alloc] init];
    discoveryTitle.text = @"Servers found on your network";
    discoveryTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    discoveryTitle.textColor = [HATheme secondaryTextColor];
    discoveryTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.discoverySection addSubview:discoveryTitle];

    self.discoveryStack = [[UIStackView alloc] init];
    self.discoveryStack.axis = UILayoutConstraintAxisVertical;
    self.discoveryStack.spacing = 6;
    self.discoveryStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.discoverySection addSubview:self.discoveryStack];

    [NSLayoutConstraint activateConstraints:@[
        [discoveryTitle.topAnchor constraintEqualToAnchor:self.discoverySection.topAnchor],
        [discoveryTitle.leadingAnchor constraintEqualToAnchor:self.discoverySection.leadingAnchor],
        [discoveryTitle.trailingAnchor constraintEqualToAnchor:self.discoverySection.trailingAnchor],
        [self.discoveryStack.topAnchor constraintEqualToAnchor:discoveryTitle.bottomAnchor constant:6],
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
    [self addSubview:urlLabel];

    self.serverURLField = [[UITextField alloc] init];
    self.serverURLField.placeholder = @"http://192.168.1.100:8123";
    self.serverURLField.borderStyle = UITextBorderStyleRoundedRect;
    self.serverURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.serverURLField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.serverURLField.keyboardType = UIKeyboardTypeURL;
    self.serverURLField.returnKeyType = UIReturnKeyNext;
    self.serverURLField.delegate = self;
    self.serverURLField.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.serverURLField];

    // ── Auth mode segmented control ────────────────────────────────────
    self.authModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Username/Password", @"Access Token"]];
    self.authModeSegment.selectedSegmentIndex = 0;
    [self.authModeSegment addTarget:self action:@selector(authModeChanged:) forControlEvents:UIControlEventValueChanged];
    self.authModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.authModeSegment];

    // ── Auth fields stack ──────────────────────────────────────────────
    self.authFieldsStack = [[UIStackView alloc] init];
    self.authFieldsStack.axis = UILayoutConstraintAxisVertical;
    self.authFieldsStack.spacing = 0;
    self.authFieldsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.authFieldsStack];

    // ── Trusted network container (hidden, added to stack) ─────────────
    self.trustedContainer = [[UIView alloc] init];
    self.trustedContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.trustedContainer.hidden = YES;
    [self.authFieldsStack addArrangedSubview:self.trustedContainer];

    UILabel *trustedHint = [[UILabel alloc] init];
    trustedHint.text = @"No password required.\nYour device is on a trusted network.";
    trustedHint.font = [UIFont systemFontOfSize:13];
    trustedHint.textColor = [HATheme secondaryTextColor];
    trustedHint.textAlignment = NSTextAlignmentCenter;
    trustedHint.numberOfLines = 0;
    trustedHint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.trustedContainer addSubview:trustedHint];

    [NSLayoutConstraint activateConstraints:@[
        [trustedHint.topAnchor constraintEqualToAnchor:self.trustedContainer.topAnchor constant:8],
        [trustedHint.leadingAnchor constraintEqualToAnchor:self.trustedContainer.leadingAnchor],
        [trustedHint.trailingAnchor constraintEqualToAnchor:self.trustedContainer.trailingAnchor],
        [trustedHint.bottomAnchor constraintEqualToAnchor:self.trustedContainer.bottomAnchor constant:-4],
    ]];

    // ── Login mode container ───────────────────────────────────────────
    self.loginContainer = [[UIView alloc] init];
    self.loginContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.authFieldsStack addArrangedSubview:self.loginContainer];

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

    UILabel *loginHint = [[UILabel alloc] init];
    loginHint.text = @"The app will securely obtain and refresh access tokens.";
    loginHint.font = [UIFont systemFontOfSize:11];
    loginHint.textColor = [HATheme secondaryTextColor];
    loginHint.numberOfLines = 0;
    loginHint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginContainer addSubview:loginHint];

    [NSLayoutConstraint activateConstraints:@[
        [userLabel.topAnchor constraintEqualToAnchor:self.loginContainer.topAnchor],
        [userLabel.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.usernameField.topAnchor constraintEqualToAnchor:userLabel.bottomAnchor constant:6],
        [self.usernameField.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.usernameField.trailingAnchor constraintEqualToAnchor:self.loginContainer.trailingAnchor],
        [self.usernameField.heightAnchor constraintEqualToConstant:fieldHeight],
        [passLabel.topAnchor constraintEqualToAnchor:self.usernameField.bottomAnchor constant:16],
        [passLabel.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.passwordField.topAnchor constraintEqualToAnchor:passLabel.bottomAnchor constant:6],
        [self.passwordField.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [self.passwordField.trailingAnchor constraintEqualToAnchor:self.loginContainer.trailingAnchor],
        [self.passwordField.heightAnchor constraintEqualToConstant:fieldHeight],
        [loginHint.topAnchor constraintEqualToAnchor:self.passwordField.bottomAnchor constant:8],
        [loginHint.leadingAnchor constraintEqualToAnchor:self.loginContainer.leadingAnchor],
        [loginHint.trailingAnchor constraintEqualToAnchor:self.loginContainer.trailingAnchor],
        [loginHint.bottomAnchor constraintEqualToAnchor:self.loginContainer.bottomAnchor],
    ]];

    // ── Token mode container (hidden initially) ────────────────────────
    self.tokenContainer = [[UIView alloc] init];
    self.tokenContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.tokenContainer.hidden = YES;
    [self.authFieldsStack addArrangedSubview:self.tokenContainer];

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

    UILabel *tokenHint = [[UILabel alloc] init];
    tokenHint.text = @"Generate in HA: Settings \u2192 People \u2192 [User] \u2192 Long-Lived Access Tokens";
    tokenHint.font = [UIFont systemFontOfSize:11];
    tokenHint.textColor = [HATheme secondaryTextColor];
    tokenHint.numberOfLines = 0;
    tokenHint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tokenContainer addSubview:tokenHint];

    [NSLayoutConstraint activateConstraints:@[
        [tokenLabel.topAnchor constraintEqualToAnchor:self.tokenContainer.topAnchor],
        [tokenLabel.leadingAnchor constraintEqualToAnchor:self.tokenContainer.leadingAnchor],
        [tokenLabel.trailingAnchor constraintEqualToAnchor:self.tokenContainer.trailingAnchor],
        [self.tokenField.topAnchor constraintEqualToAnchor:tokenLabel.bottomAnchor constant:6],
        [self.tokenField.leadingAnchor constraintEqualToAnchor:self.tokenContainer.leadingAnchor],
        [self.tokenField.trailingAnchor constraintEqualToAnchor:self.tokenContainer.trailingAnchor],
        [self.tokenField.heightAnchor constraintEqualToConstant:fieldHeight],
        [tokenHint.topAnchor constraintEqualToAnchor:self.tokenField.bottomAnchor constant:8],
        [tokenHint.leadingAnchor constraintEqualToAnchor:self.tokenContainer.leadingAnchor],
        [tokenHint.trailingAnchor constraintEqualToAnchor:self.tokenContainer.trailingAnchor],
        [tokenHint.bottomAnchor constraintEqualToAnchor:self.tokenContainer.bottomAnchor],
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
    [self addSubview:self.connectButton];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.statusLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.spinner];

    // ── Main vertical layout ───────────────────────────────────────────
    CGFloat sectionGap = 20.0;  // Between major sections
    CGFloat labelGap = 6.0;     // Between label and its field

    NSArray *fullWidthViews = @[
        self.discoverySection, urlLabel, self.serverURLField,
        self.authModeSegment, self.authFieldsStack,
        self.connectButton, self.statusLabel,
    ];
    for (UIView *v in fullWidthViews) {
        [NSLayoutConstraint activateConstraints:@[
            [v.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [v.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }

    // Status + spinner sit below the connect button but collapse when empty.
    // The bottom of the form is pinned to the connect button; the status area
    // hangs below and only takes space when populated.
    [NSLayoutConstraint activateConstraints:@[
        [self.discoverySection.topAnchor constraintEqualToAnchor:self.topAnchor],
        [urlLabel.topAnchor constraintEqualToAnchor:self.discoverySection.bottomAnchor constant:sectionGap],
        [self.serverURLField.topAnchor constraintEqualToAnchor:urlLabel.bottomAnchor constant:labelGap],
        [self.serverURLField.heightAnchor constraintEqualToConstant:fieldHeight],
        [self.authModeSegment.topAnchor constraintEqualToAnchor:self.serverURLField.bottomAnchor constant:sectionGap],
        [self.authFieldsStack.topAnchor constraintEqualToAnchor:self.authModeSegment.bottomAnchor constant:sectionGap],
        [self.connectButton.topAnchor constraintEqualToAnchor:self.authFieldsStack.bottomAnchor constant:24],
        [self.connectButton.heightAnchor constraintEqualToConstant:fieldHeight],
        [self.connectButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.connectButton.bottomAnchor constant:12],
        [self.spinner.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:6],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    ]];
}

#pragma mark - Public

- (void)loadExistingCredentials {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (auth.serverURL) {
        self.serverURLField.text = auth.serverURL;
        [self probeAuthProvidersForURL:auth.serverURL];
    }

    if (auth.authMode == HAAuthModeOAuth) {
        [self selectMode:kModeLogin];
    } else {
        if (auth.accessToken) {
            self.tokenField.text = auth.accessToken;
        }
        [self selectMode:kModeToken];
    }
}

- (void)startDiscovery {
    self.discoveryService = [[HADiscoveryService alloc] init];
    self.discoveryService.delegate = self;
    [self.discoveryService startSearching];
}

- (void)stopDiscovery {
    [self.discoveryService stopSearching];
    self.discoveryService = nil;
}

- (void)clearFields {
    self.serverURLField.text = @"";
    self.tokenField.text = @"";
    self.usernameField.text = @"";
    self.passwordField.text = @"";
    self.statusLabel.text = @"";
    self.hasTrustedNetworkProvider = NO;
    self.hasHomeAssistantProvider = YES;
    self.lastProbedURL = nil;
    [self rebuildSegments];
}

#pragma mark - Auth Provider Probing

- (void)probeAuthProvidersForURL:(NSString *)urlString {
    if (urlString.length == 0) return;

    NSString *normalized = [HAAuthManager normalizedURL:urlString];
    if ([self.lastProbedURL isEqualToString:normalized]) return;
    self.lastProbedURL = normalized;

    HAOAuthClient *oauth = [[HAOAuthClient alloc] initWithServerURL:normalized];
    [oauth fetchAuthProviders:^(NSArray *providers, NSError *error) {
        if (error || !providers) {
            self.hasHomeAssistantProvider = YES;
            self.hasTrustedNetworkProvider = NO;
            [self rebuildSegments];
            return;
        }

        BOOL foundHA = NO;
        BOOL foundTrusted = NO;
        for (NSDictionary *provider in providers) {
            if (![provider isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = provider[@"type"];
            if ([type isEqualToString:@"homeassistant"]) foundHA = YES;
            if ([type isEqualToString:@"trusted_networks"]) foundTrusted = YES;
        }

        self.hasHomeAssistantProvider = foundHA;
        self.hasTrustedNetworkProvider = foundTrusted;
        [self rebuildSegments];

        // Auto-select trusted network if it just appeared
        if (foundTrusted) {
            [self selectMode:kModeTrusted];
        }
    }];
}

#pragma mark - Segment Rebuilding

- (void)rebuildSegments {
    NSString *previousMode = [self currentMode];

    // Build mode list based on available providers
    NSMutableArray *modes = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];

    if (self.hasTrustedNetworkProvider) {
        [modes addObject:kModeTrusted];
        [titles addObject:@"Trusted Network"];
    }
    if (self.hasHomeAssistantProvider) {
        [modes addObject:kModeLogin];
        [titles addObject:@"Username/Password"];
    }
    // Access Token is always available
    [modes addObject:kModeToken];
    [titles addObject:@"Access Token"];

    self.authModes = [modes copy];

    // Rebuild the segmented control
    [self.authModeSegment removeAllSegments];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [self.authModeSegment insertSegmentWithTitle:titles[i] atIndex:i animated:NO];
    }

    // Restore previous selection if still available, otherwise pick first
    [self selectMode:([modes containsObject:previousMode] ? previousMode : modes.firstObject)];
}

- (void)selectMode:(NSString *)mode {
    NSUInteger idx = [self.authModes indexOfObject:mode];
    if (idx == NSNotFound) idx = 0;
    self.authModeSegment.selectedSegmentIndex = idx;
    [self authModeChanged:self.authModeSegment];
}

#pragma mark - Auth Mode Switching

- (void)authModeChanged:(UISegmentedControl *)sender {
    NSString *mode = [self currentMode];
    self.trustedContainer.hidden = ![mode isEqualToString:kModeTrusted];
    self.loginContainer.hidden   = ![mode isEqualToString:kModeLogin];
    self.tokenContainer.hidden   = ![mode isEqualToString:kModeToken];
}

#pragma mark - Discovery

- (void)discoveryService:(HADiscoveryService *)service didDiscoverServer:(HADiscoveredServer *)server {
    self.discoverySection.hidden = NO;

    UIView *row = [self createServerRow:server index:self.discoveryService.discoveredServers.count - 1];
    [self.discoveryStack addArrangedSubview:row];
}

- (void)discoveryService:(HADiscoveryService *)service didRemoveServer:(HADiscoveredServer *)server {
    for (UIView *v in [self.discoveryStack.arrangedSubviews copy]) {
        [self.discoveryStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSUInteger i = 0; i < service.discoveredServers.count; i++) {
        UIView *row = [self createServerRow:service.discoveredServers[i] index:i];
        [self.discoveryStack addArrangedSubview:row];
    }
    self.discoverySection.hidden = (service.discoveredServers.count == 0);
}

- (UIView *)createServerRow:(HADiscoveredServer *)server index:(NSUInteger)idx {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [HATheme controlBackgroundColor];
    row.layer.cornerRadius = 10.0;
    row.tag = idx;
    [row addTarget:self action:@selector(discoveredServerTapped:) forControlEvents:UIControlEventTouchUpInside];

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

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = server.name ?: @"Home Assistant";
    nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    nameLabel.textColor = [HATheme primaryTextColor];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.userInteractionEnabled = NO;
    [row addSubview:nameLabel];

    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = server.version ? [NSString stringWithFormat:@"v%@", server.version] : @"";
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [HATheme secondaryTextColor];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.userInteractionEnabled = NO;
    [row addSubview:versionLabel];

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
        [row.heightAnchor constraintEqualToConstant:48],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [nameLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [nameLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [versionLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:nameLabel.trailingAnchor constant:8],
        [versionLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.leadingAnchor constraintEqualToAnchor:versionLabel.trailingAnchor constant:8],
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:12],
    ]];

    return row;
}

- (void)discoveredServerTapped:(UIButton *)sender {
    NSUInteger idx = (NSUInteger)sender.tag;
    NSArray *servers = self.discoveryService.discoveredServers;
    if (idx >= servers.count) return;

    HADiscoveredServer *server = servers[idx];
    self.serverURLField.text = server.baseURL;
    [self probeAuthProvidersForURL:server.baseURL];
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

    NSString *mode = [self currentMode];
    if ([mode isEqualToString:kModeTrusted]) {
        [self connectWithTrustedNetwork:urlString];
    } else if ([mode isEqualToString:kModeToken]) {
        [self connectWithToken:urlString];
    } else {
        [self connectWithLogin:urlString];
    }
}

- (void)connectWithTrustedNetwork:(NSString *)urlString {
    self.connectButton.enabled = NO;
    [self.spinner startAnimating];
    [self showStatus:@"Logging in..." isError:NO];

    HAOAuthClient *oauth = [[HAOAuthClient alloc] initWithServerURL:urlString];

    [oauth loginWithTrustedNetworkUser:nil flowId:nil completion:^(NSString *authCode, NSDictionary *usersOrNil, NSString *flowIdOrNil, NSError *error) {
        if (error) {
            self.connectButton.enabled = YES;
            [self.spinner stopAnimating];
            [self showStatus:[NSString stringWithFormat:@"Login failed: %@", error.localizedDescription] isError:YES];
            return;
        }

        if (authCode) {
            [self exchangeAuthCode:authCode withOAuthClient:oauth serverURL:urlString];
            return;
        }

        if (usersOrNil && flowIdOrNil) {
            [self.spinner stopAnimating];
            [self showStatus:@"" isError:NO];
            [self presentUserPicker:usersOrNil flowId:flowIdOrNil oauthClient:oauth serverURL:urlString];
            return;
        }

        self.connectButton.enabled = YES;
        [self.spinner stopAnimating];
        [self showStatus:@"Unexpected response from server" isError:YES];
    }];
}

- (void)presentUserPicker:(NSDictionary *)users
                   flowId:(NSString *)flowId
              oauthClient:(HAOAuthClient *)oauth
                serverURL:(NSString *)urlString {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select User"
                                                                  message:@"Choose which user to log in as"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *userId in users) {
        NSString *displayName = users[userId];
        [alert addAction:[UIAlertAction actionWithTitle:displayName style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self.spinner startAnimating];
            [self showStatus:@"Logging in..." isError:NO];

            [oauth loginWithTrustedNetworkUser:userId flowId:flowId completion:^(NSString *authCode, NSDictionary *usersOrNil, NSString *flowIdOrNil, NSError *error) {
                if (error || !authCode) {
                    self.connectButton.enabled = YES;
                    [self.spinner stopAnimating];
                    [self showStatus:[NSString stringWithFormat:@"Login failed: %@",
                        error.localizedDescription ?: @"no auth code"] isError:YES];
                    return;
                }
                [self exchangeAuthCode:authCode withOAuthClient:oauth serverURL:urlString];
            }];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        self.connectButton.enabled = YES;
    }]];

    UIViewController *presenter = [self firstAvailableViewController];
    if (presenter) {
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.connectButton;
            alert.popoverPresentationController.sourceRect = self.connectButton.bounds;
        }
        [presenter presentViewController:alert animated:YES completion:nil];
    }
}

- (UIViewController *)firstAvailableViewController {
    UIResponder *responder = self;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}

- (void)exchangeAuthCode:(NSString *)authCode
         withOAuthClient:(HAOAuthClient *)oauth
               serverURL:(NSString *)urlString {
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
        [self.delegate connectionFormDidConnect:self];
    }];
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
        [self.delegate connectionFormDidConnect:self];
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

        [self exchangeAuthCode:authCode withOAuthClient:oauth serverURL:urlString];
    }];
}

- (void)showStatus:(NSString *)text isError:(BOOL)isError {
    self.statusLabel.text = text;
    self.statusLabel.textColor = isError ? [HATheme destructiveColor] : [HATheme primaryTextColor];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.serverURLField) {
        NSString *mode = [self currentMode];
        if ([mode isEqualToString:kModeLogin]) {
            [self.usernameField becomeFirstResponder];
        } else if ([mode isEqualToString:kModeToken]) {
            [self.tokenField becomeFirstResponder];
        } else {
            [textField resignFirstResponder];
            [self connectTapped];
        }
    } else if (textField == self.usernameField) {
        [self.passwordField becomeFirstResponder];
    } else if (textField == self.tokenField || textField == self.passwordField) {
        [textField resignFirstResponder];
        [self connectTapped];
    }
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.serverURLField) {
        [self probeAuthProvidersForURL:textField.text];
    }
}

@end
