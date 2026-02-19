#import "HAConnectionFormView.h"
#import "HAAuthManager.h"
#import "HAOAuthClient.h"
#import "HAAPIClient.h"
#import "HAConnectionManager.h"
#import "HADiscoveryService.h"
#import "HADiscoveredServer.h"
#import "HATheme.h"

@interface HAConnectionFormView () <UITextFieldDelegate, HADiscoveryServiceDelegate>
@property (nonatomic, strong) UITextField *serverURLField;
@property (nonatomic, strong) UISegmentedControl *authModeSegment;

// Login mode (index 0 — shown first)
@property (nonatomic, strong) UIView *loginContainer;
@property (nonatomic, strong) UIStackView *authFieldsStack;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *passwordField;

// Token mode (index 1)
@property (nonatomic, strong) UIView *tokenContainer;
@property (nonatomic, strong) UITextField *tokenField;

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
        [self setupUI];
    }
    return self;
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

    // ── Auth mode segmented control (Login first, Token second) ────────
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

    // ── Login mode container (shown first) ─────────────────────────────
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
        [loginHint.topAnchor constraintEqualToAnchor:self.passwordField.bottomAnchor constant:4],
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
        [self.tokenField.topAnchor constraintEqualToAnchor:tokenLabel.bottomAnchor constant:4],
        [self.tokenField.leadingAnchor constraintEqualToAnchor:self.tokenContainer.leadingAnchor],
        [self.tokenField.trailingAnchor constraintEqualToAnchor:self.tokenContainer.trailingAnchor],
        [self.tokenField.heightAnchor constraintEqualToConstant:fieldHeight],
        [tokenHint.topAnchor constraintEqualToAnchor:self.tokenField.bottomAnchor constant:4],
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
    NSDictionary *views = @{
        @"disc": self.discoverySection,
        @"urlLabel": urlLabel,
        @"urlField": self.serverURLField,
        @"authSeg": self.authModeSegment,
        @"authStack": self.authFieldsStack,
        @"button": self.connectButton,
        @"status": self.statusLabel,
        @"spinner": self.spinner,
    };
    NSDictionary *metrics = @{@"p": @8, @"fh": @(fieldHeight)};

    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|[disc]-p-[urlLabel]-4-[urlField(fh)]-p-[authSeg]-p-[authStack]-p-[button(fh)]-8-[status]-4-[spinner]|"
        options:0 metrics:metrics views:views]];

    for (NSString *name in @[@"disc", @"urlLabel", @"urlField", @"authSeg", @"authStack", @"button", @"status"]) {
        UIView *v = views[name];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:v attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    }

    [self addConstraint:[NSLayoutConstraint constraintWithItem:self.spinner attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
}

#pragma mark - Public

- (void)loadExistingCredentials {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (auth.serverURL) {
        self.serverURLField.text = auth.serverURL;
    }

    // Segment 0 = Username/Password (OAuth), Segment 1 = Access Token
    if (auth.authMode == HAAuthModeOAuth) {
        self.authModeSegment.selectedSegmentIndex = 0;
        [self authModeChanged:self.authModeSegment];
    } else {
        if (auth.accessToken) {
            self.tokenField.text = auth.accessToken;
        }
        self.authModeSegment.selectedSegmentIndex = 1;
        [self authModeChanged:self.authModeSegment];
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
}

#pragma mark - Auth Mode Switching

- (void)authModeChanged:(UISegmentedControl *)sender {
    // Segment 0 = Username/Password, Segment 1 = Access Token
    BOOL isLoginMode = (sender.selectedSegmentIndex == 0);
    self.loginContainer.hidden = !isLoginMode;
    self.tokenContainer.hidden = isLoginMode;
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

    // Name label
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = server.name ?: @"Home Assistant";
    nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    nameLabel.textColor = [HATheme primaryTextColor];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.userInteractionEnabled = NO;
    [row addSubview:nameLabel];

    // Version label
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = server.version ? [NSString stringWithFormat:@"v%@", server.version] : @"";
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [HATheme secondaryTextColor];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.userInteractionEnabled = NO;
    [row addSubview:versionLabel];

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

    // Segment 0 = Username/Password, Segment 1 = Access Token
    BOOL isTokenMode = (self.authModeSegment.selectedSegmentIndex == 1);

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
    }];
}

- (void)showStatus:(NSString *)text isError:(BOOL)isError {
    self.statusLabel.text = text;
    self.statusLabel.textColor = isError ? [HATheme destructiveColor] : [HATheme primaryTextColor];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.serverURLField) {
        // Segment 0 = Login, Segment 1 = Token
        if (self.authModeSegment.selectedSegmentIndex == 0) {
            [self.usernameField becomeFirstResponder];
        } else {
            [self.tokenField becomeFirstResponder];
        }
    } else if (textField == self.usernameField) {
        [self.passwordField becomeFirstResponder];
    } else if (textField == self.tokenField || textField == self.passwordField) {
        [textField resignFirstResponder];
        [self connectTapped];
    }
    return YES;
}

@end
