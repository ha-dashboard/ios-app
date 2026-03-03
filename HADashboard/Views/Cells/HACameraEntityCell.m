#import "HACameraEntityCell.h"
#import "HAEntity.h"
#import "HAAuthManager.h"
#import "HADashboardConfig.h"
#import "HAConnectionManager.h"
#import "HAEntityDisplayHelper.h"
#import "HAIconMapper.h"

static const NSTimeInterval kSnapshotRefreshInterval = 5.0;
static const NSInteger kMaxConsecutiveFailuresBeforeClear = 3;

// Overlay button layout constants
static const CGFloat kOverlayButtonSize     = 28.0;
static const CGFloat kOverlayButtonSpacing  = 4.0;
static const CGFloat kOverlayBarPadding     = 6.0;
static const CGFloat kOverlayBarBottomInset = 6.0;
static const CGFloat kOverlayIconFontSize   = 14.0;

/// Tag base for overlay buttons so we can identify them
static const NSInteger kOverlayButtonTagBase = 9000;

@interface HACameraEntityCell ()
@property (nonatomic, strong) UIImageView *snapshotView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UILabel *stateBadge;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) NSURLSession *imageSession;
@property (nonatomic, strong) NSURLSessionDataTask *currentTask;
@property (nonatomic, copy)   NSString *currentEntityId;
@property (nonatomic, assign) BOOL needsSnapshotLoad;
@property (nonatomic, assign) NSInteger consecutiveFailures;

// Camera service buttons (power toggle + snapshot)
@property (nonatomic, strong) UIButton *cameraPowerButton;
@property (nonatomic, strong) UIButton *cameraSnapshotButton;

// Overlay action buttons
@property (nonatomic, strong) UIView *overlayBar;
@property (nonatomic, copy)   NSArray<NSDictionary *> *overlayElements; // [{entity_id, tap_action}, ...]
@property (nonatomic, strong) NSMutableArray<UIView *> *overlayButtons;
// Toggling snapshot-top constraint: below nameLabel or at contentView top
@property (nonatomic, strong) NSLayoutConstraint *snapshotTopWithName;
@property (nonatomic, strong) NSLayoutConstraint *snapshotTopNoName;
@end

@implementation HACameraEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    // Snapshot image view — fills the cell below the name label
    self.snapshotView = [[UIImageView alloc] init];
    self.snapshotView.contentMode = UIViewContentModeScaleAspectFill;
    self.snapshotView.clipsToBounds = YES;
    self.snapshotView.backgroundColor = [UIColor blackColor];
    self.snapshotView.userInteractionEnabled = YES; // enable overlay button taps
    self.snapshotView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.snapshotView];

    // Loading spinner centered on image
    self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.loadingSpinner.hidesWhenStopped = YES;
    self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.snapshotView addSubview:self.loadingSpinner];

    // Error label for unavailable cameras
    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.font = [UIFont systemFontOfSize:11];
    self.errorLabel.textColor = [UIColor lightGrayColor];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.hidden = YES;
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.snapshotView addSubview:self.errorLabel];

    // Overlay bar: semi-transparent container at bottom of snapshot
    self.overlayBar = [[UIView alloc] init];
    self.overlayBar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.overlayBar.layer.cornerRadius = (kOverlayButtonSize + kOverlayBarPadding) / 2.0;
    self.overlayBar.layer.masksToBounds = YES;
    self.overlayBar.hidden = YES;
    // Will be positioned manually in layoutSubviews (iOS 9 compatible)
    [self.snapshotView addSubview:self.overlayBar];

    self.overlayButtons = [NSMutableArray array];

    CGFloat padding = 10.0;

    // Image view: fills cell, with toggling top constraint for name visibility
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];

    // Two top constraints: below nameLabel (with title) or at contentView top (no title)
    self.snapshotTopWithName = [NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4];
    self.snapshotTopNoName = [NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    // Default: no name (full-bleed camera)
    self.snapshotTopWithName.active = NO;
    self.snapshotTopNoName.active = YES;

    // Spinner: centered in snapshot view
    [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.loadingSpinner attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.loadingSpinner attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

    // Error label: centered in snapshot view
    [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.errorLabel attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.errorLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
    [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.errorLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.snapshotView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];

    // State badge (recording/streaming indicator, top-right corner)
    self.stateBadge = [[UILabel alloc] init];
    self.stateBadge.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    self.stateBadge.textColor = [UIColor whiteColor];
    self.stateBadge.textAlignment = NSTextAlignmentCenter;
    self.stateBadge.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
    self.stateBadge.layer.cornerRadius = 4;
    self.stateBadge.clipsToBounds = YES;
    self.stateBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateBadge.hidden = YES;
    [self.snapshotView addSubview:self.stateBadge];

    [NSLayoutConstraint activateConstraints:@[
        [self.stateBadge.topAnchor constraintEqualToAnchor:self.snapshotView.topAnchor constant:6],
        [self.stateBadge.trailingAnchor constraintEqualToAnchor:self.snapshotView.trailingAnchor constant:-6],
        [self.stateBadge.heightAnchor constraintEqualToConstant:16],
        [self.stateBadge.widthAnchor constraintGreaterThanOrEqualToConstant:40],
    ]];

    // Camera power toggle button (top-left of snapshot)
    self.cameraPowerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cameraPowerButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.cameraPowerButton.layer.cornerRadius = 14;
    self.cameraPowerButton.clipsToBounds = YES;
    self.cameraPowerButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraPowerButton.hidden = YES;
    [self.cameraPowerButton addTarget:self action:@selector(cameraPowerTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.snapshotView addSubview:self.cameraPowerButton];

    // Camera snapshot button (left of power)
    self.cameraSnapshotButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cameraSnapshotButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.cameraSnapshotButton.layer.cornerRadius = 14;
    self.cameraSnapshotButton.clipsToBounds = YES;
    self.cameraSnapshotButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraSnapshotButton.hidden = YES;
    [self.cameraSnapshotButton addTarget:self action:@selector(cameraSnapshotTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.snapshotView addSubview:self.cameraSnapshotButton];

    // Set icons via MDI glyphs
    NSString *powerGlyph = [HAIconMapper glyphForIconName:@"power"] ?: @"\u23FB";
    NSString *snapGlyph = [HAIconMapper glyphForIconName:@"camera"] ?: @"\U0001F4F7";
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:14];
    [self.cameraPowerButton setAttributedTitle:[[NSAttributedString alloc] initWithString:powerGlyph
        attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];
    [self.cameraSnapshotButton setAttributedTitle:[[NSAttributedString alloc] initWithString:snapGlyph
        attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];

    [NSLayoutConstraint activateConstraints:@[
        [self.cameraPowerButton.topAnchor constraintEqualToAnchor:self.snapshotView.topAnchor constant:6],
        [self.cameraPowerButton.leadingAnchor constraintEqualToAnchor:self.snapshotView.leadingAnchor constant:6],
        [self.cameraPowerButton.widthAnchor constraintEqualToConstant:28],
        [self.cameraPowerButton.heightAnchor constraintEqualToConstant:28],
        [self.cameraSnapshotButton.topAnchor constraintEqualToAnchor:self.snapshotView.topAnchor constant:6],
        [self.cameraSnapshotButton.leadingAnchor constraintEqualToAnchor:self.cameraPowerButton.trailingAnchor constant:4],
        [self.cameraSnapshotButton.widthAnchor constraintEqualToConstant:28],
        [self.cameraSnapshotButton.heightAnchor constraintEqualToConstant:28],
    ]];

    // Shared session for image fetches — no caching to always get fresh frames
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 8.0;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.imageSession = [NSURLSession sessionWithConfiguration:config];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    // Hide camera name unless explicitly configured — camera feeds are self-evident
    NSString *camNameOvr = configItem.customProperties[@"nameOverride"];
    BOOL hasExplicitName = (camNameOvr.length > 0) ||
                           (configItem.displayName.length > 0 &&
                            configItem.customProperties[@"headingIcon"] == nil);
    if (hasExplicitName) {
        self.nameLabel.hidden = NO;
        self.snapshotTopNoName.active = NO;
        self.snapshotTopWithName.active = YES;
    } else {
        self.nameLabel.hidden = YES;
        self.snapshotTopWithName.active = NO;
        self.snapshotTopNoName.active = YES;
    }

    // If entity changed, reset image and restart refresh cycle
    BOOL entityChanged = ![self.currentEntityId isEqualToString:entity.entityId];
    self.currentEntityId = entity.entityId;

    if (!entity.isAvailable) {
        [self stopRefresh];
        self.snapshotView.image = nil;
        self.errorLabel.text = @"Unavailable";
        self.errorLabel.hidden = NO;
        return;
    }

    self.errorLabel.hidden = YES;

    // State badge: show recording/streaming indicator
    NSString *camState = entity.state;
    if ([camState isEqualToString:@"recording"]) {
        self.stateBadge.text = @" REC ";
        self.stateBadge.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
        self.stateBadge.hidden = NO;
    } else if ([camState isEqualToString:@"streaming"]) {
        self.stateBadge.text = @" LIVE ";
        self.stateBadge.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.8];
        self.stateBadge.hidden = NO;
    } else {
        self.stateBadge.hidden = YES;
    }

    if (entityChanged) {
        self.snapshotView.image = nil;
        self.consecutiveFailures = 0;
        // Defer fetch until cell is visible (beginLoading)
        self.needsSnapshotLoad = YES;
    }

    // Camera service buttons: show when entity is available
    NSInteger features = [entity supportedFeatures];
    BOOL supportsTurnOn = (features & 1) != 0;
    BOOL supportsTurnOff = (features & 2) != 0;
    self.cameraPowerButton.hidden = !(supportsTurnOn || supportsTurnOff) || !entity.isAvailable;
    // Snapshot is always available for cameras
    self.cameraSnapshotButton.hidden = !entity.isAvailable;

    // Configure overlay action buttons from customProperties
    [self configureOverlayElementsFromConfigItem:configItem];
}

#pragma mark - Camera Service Actions

- (void)cameraPowerTapped {
    if (!self.entity) return;
    NSString *state = self.entity.state;
    NSString *service = [state isEqualToString:@"off"] ? @"turn_on" : @"turn_off";
    [self callService:service inDomain:@"camera"];
}

- (void)cameraSnapshotTapped {
    if (!self.entity) return;
    [self callService:@"snapshot" inDomain:@"camera" withData:@{@"filename": @"/config/www/snapshot.jpg"}];
}

#pragma mark - Overlay Action Buttons

- (void)configureOverlayElementsFromConfigItem:(HADashboardConfigItem *)configItem {
    NSArray *elements = configItem.customProperties[@"overlayElements"];

    // Remove old notification observer if we had overlay elements before
    if (self.overlayElements.count > 0) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
            name:HAConnectionManagerEntityDidUpdateNotification object:nil];
    }

    // Clear existing buttons
    for (UIView *btn in self.overlayButtons) {
        [btn removeFromSuperview];
    }
    [self.overlayButtons removeAllObjects];

    if (![elements isKindOfClass:[NSArray class]] || elements.count == 0) {
        self.overlayElements = nil;
        self.overlayBar.hidden = YES;
        return;
    }

    self.overlayElements = elements;
    self.overlayBar.hidden = NO;

    HAConnectionManager *connMgr = [HAConnectionManager sharedManager];

    for (NSUInteger i = 0; i < elements.count; i++) {
        NSDictionary *elem = elements[i];
        NSString *entityId = elem[@"entity_id"];
        NSString *tapAction = elem[@"tap_action"];

        // Create circular button view — more opaque for visibility over camera feeds
        UIView *button = [[UIView alloc] init];
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        button.layer.cornerRadius = kOverlayButtonSize / 2.0;
        button.layer.masksToBounds = YES;
        button.tag = kOverlayButtonTagBase + (NSInteger)i;

        // Icon label — frame set explicitly in layoutOverlayBar
        UILabel *iconLabel = [[UILabel alloc] init];
        iconLabel.textAlignment = NSTextAlignmentCenter;
        iconLabel.tag = 1;
        [button addSubview:iconLabel];

        // Add tap gesture if element has toggle action
        if ([tapAction isEqualToString:@"toggle"]) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(overlayButtonTapped:)];
            [button addGestureRecognizer:tap];
            button.userInteractionEnabled = YES;
        } else {
            button.userInteractionEnabled = NO;
        }

        [self.overlayBar addSubview:button];
        [self.overlayButtons addObject:button];

        // Set initial icon state from current entity
        HAEntity *overlayEntity = [connMgr entityForId:entityId];
        [self updateButton:button forEntity:overlayEntity];
    }

    // Observe entity updates so overlay buttons reflect current state
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(overlayEntityDidUpdate:)
        name:HAConnectionManagerEntityDidUpdateNotification object:nil];

    [self setNeedsLayout];
}

- (void)updateButton:(UIView *)button forEntity:(HAEntity *)entity {
    UILabel *iconLabel = [button viewWithTag:1];
    if (!iconLabel) return;

    NSString *glyph = [HAEntityDisplayHelper iconGlyphForEntity:entity];
    UIColor *iconColor;

    if (entity) {
        iconColor = [self overlayIconColorForEntity:entity];
    } else {
        // Entity not loaded yet — white placeholder (visible on dark camera feed)
        iconColor = [UIColor whiteColor];
    }

    if (glyph) {
        UIFont *mdiFont = [HAIconMapper mdiFontOfSize:kOverlayIconFontSize];
        iconLabel.attributedText = [[NSAttributedString alloc] initWithString:glyph
            attributes:@{NSFontAttributeName: mdiFont, NSForegroundColorAttributeName: iconColor}];
    } else {
        iconLabel.attributedText = nil;
        iconLabel.text = @"?";
        iconLabel.font = [UIFont systemFontOfSize:kOverlayIconFontSize];
        iconLabel.textColor = iconColor;
    }
}

/// Determine icon color for overlay button entities.
/// Uses bright colors on dark backgrounds for visibility over camera feeds.
/// Active: yellow/amber. Inactive: white.
- (UIColor *)overlayIconColorForEntity:(HAEntity *)entity {
    if (!entity) return [UIColor whiteColor];

    BOOL isActive = [entity isOn];
    if (isActive) {
        return [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; // Yellow/amber
    }
    return [UIColor whiteColor]; // White on dark background for visibility
}

- (void)overlayButtonTapped:(UITapGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    NSInteger index = button.tag - kOverlayButtonTagBase;

    if (index < 0 || index >= (NSInteger)self.overlayElements.count) return;

    NSDictionary *elem = self.overlayElements[index];
    NSString *entityId = elem[@"entity_id"];
    NSString *tapAction = elem[@"tap_action"];

    if (![tapAction isEqualToString:@"toggle"] || !entityId) return;

    // Visual feedback: briefly dim the button
    button.alpha = 0.5;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        button.alpha = 1.0;
    });

    [[HAConnectionManager sharedManager] callService:@"toggle"
                                            inDomain:@"homeassistant"
                                            withData:nil
                                            entityId:entityId];
}

- (void)overlayEntityDidUpdate:(NSNotification *)notification {
    HAEntity *updatedEntity = notification.userInfo[@"entity"];
    if (!updatedEntity || !updatedEntity.entityId) return;

    // Check if the updated entity is one of our overlay elements
    for (NSUInteger i = 0; i < self.overlayElements.count; i++) {
        NSDictionary *elem = self.overlayElements[i];
        if ([elem[@"entity_id"] isEqualToString:updatedEntity.entityId]) {
            if (i < self.overlayButtons.count) {
                [self updateButton:self.overlayButtons[i] forEntity:updatedEntity];
            }
            break;
        }
    }
}

- (void)layoutOverlayBar {
    NSUInteger count = self.overlayButtons.count;
    if (count == 0) {
        self.overlayBar.hidden = YES;
        return;
    }

    CGFloat snapshotW = self.snapshotView.bounds.size.width;
    CGFloat snapshotH = self.snapshotView.bounds.size.height;
    if (snapshotW <= 0 || snapshotH <= 0) return;

    // Calculate bar dimensions
    CGFloat buttonsWidth = count * kOverlayButtonSize + (count - 1) * kOverlayButtonSpacing;
    CGFloat barWidth = buttonsWidth + kOverlayBarPadding * 2;
    CGFloat barHeight = kOverlayButtonSize + kOverlayBarPadding;

    // Center bar horizontally at bottom of snapshot
    CGFloat barX = (snapshotW - barWidth) / 2.0;
    CGFloat barY = snapshotH - barHeight - kOverlayBarBottomInset;
    self.overlayBar.frame = CGRectMake(barX, barY, barWidth, barHeight);

    // Layout buttons and their icon labels inside bar
    CGFloat btnY = (barHeight - kOverlayButtonSize) / 2.0;
    CGRect iconBounds = CGRectMake(0, 0, kOverlayButtonSize, kOverlayButtonSize);
    for (NSUInteger i = 0; i < count; i++) {
        UIView *button = self.overlayButtons[i];
        CGFloat btnX = kOverlayBarPadding + i * (kOverlayButtonSize + kOverlayButtonSpacing);
        button.frame = CGRectMake(btnX, btnY, kOverlayButtonSize, kOverlayButtonSize);
        UILabel *iconLabel = [button viewWithTag:1];
        iconLabel.frame = iconBounds;
    }
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutOverlayBar];
}

#pragma mark - Snapshot Fetching

- (void)fetchSnapshot {
    if (!self.entity || !self.entity.entityId) return;

    // Demo mode: entity_picture starts with demo:// — use placeholder
    NSString *ep = HAAttrString(self.entity.attributes, @"entity_picture");
    if ([ep hasPrefix:@"demo://"]) {
        CGFloat w = MAX(self.snapshotView.bounds.size.width, 200);
        CGFloat h = MAX(self.snapshotView.bounds.size.height, 150);
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, h), YES, 0);
        [[UIColor colorWithRed:0.1 green:0.12 blue:0.15 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, w, h));
        NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:14], NSForegroundColorAttributeName: [UIColor colorWithWhite:0.5 alpha:1]};
        NSString *label = [NSString stringWithFormat:@"📷 %@", [self.entity friendlyName] ?: @"Camera"];
        CGSize sz = [label sizeWithAttributes:attrs];
        [label drawAtPoint:CGPointMake((w - sz.width) / 2, (h - sz.height) / 2) withAttributes:attrs];
        self.snapshotView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [self.loadingSpinner stopAnimating];
        return;
    }

    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (!auth.isConfigured) return;

    NSString *proxyPath = [self.entity cameraProxyPath];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", auth.serverURL, proxyPath]];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", auth.accessToken] forHTTPHeaderField:@"Authorization"];

    // Cancel previous fetch if still in progress
    [self.currentTask cancel];

    if (!self.snapshotView.image) {
        [self.loadingSpinner startAnimating];
    }

    __weak typeof(self) weakSelf = self;
    self.currentTask = [self.imageSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // Handle errors on main thread (lightweight)
            if (error && error.code == NSURLErrorCancelled) return;

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            BOOL fetchFailed = (error != nil) || (httpResponse.statusCode != 200) || !data;

            if (fetchFailed) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf.loadingSpinner stopAnimating];
                    strongSelf.consecutiveFailures++;
                    BOOL hasExistingImage = (strongSelf.snapshotView.image != nil);
                    if (!hasExistingImage) {
                        strongSelf.errorLabel.text = @"No signal";
                        strongSelf.errorLabel.hidden = NO;
                    } else if (strongSelf.consecutiveFailures >= kMaxConsecutiveFailuresBeforeClear) {
                        strongSelf.errorLabel.text = @"No signal";
                        strongSelf.errorLabel.hidden = NO;
                    }
                });
                return;
            }

            // Force-decode JPEG on this background thread. UIImage imageWithData:
            // creates a lazily-decoded image — actual pixel decode happens on first
            // render (main thread). Drawing into a throwaway context forces immediate
            // decode here, so the main thread just blits pre-decoded pixels.
            UIImage *lazyImage = [UIImage imageWithData:data];
            UIImage *image = nil;
            if (lazyImage) {
                UIGraphicsBeginImageContextWithOptions(lazyImage.size, YES, lazyImage.scale);
                [lazyImage drawAtPoint:CGPointZero];
                image = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf.loadingSpinner stopAnimating];
                if (image) {
                    strongSelf.consecutiveFailures = 0;
                    strongSelf.snapshotView.image = image;
                    strongSelf.errorLabel.hidden = YES;
                    [strongSelf layoutOverlayBar];
                }
            });
        }];
    [self.currentTask resume];
}

#pragma mark - Refresh Timer

- (void)startRefreshTimer {
    [self stopRefresh];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:kSnapshotRefreshInterval
                                                        target:self
                                                      selector:@selector(refreshTimerFired)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)refreshTimerFired {
    [self fetchSnapshot];
}

- (void)beginLoading {
    if (!self.currentEntityId) return;

    if (self.needsSnapshotLoad) {
        // New entity — fetch immediately
        self.needsSnapshotLoad = NO;
        [self fetchSnapshot];
    }

    // Always ensure the refresh timer is running. Cell reloads (from entity
    // state updates on overlay entities) kill the timer in prepareForReuse
    // but don't set needsSnapshotLoad, so the timer must be restarted here.
    if (!self.refreshTimer) {
        [self startRefreshTimer];
    }
}

- (void)cancelLoading {
    [self stopRefresh];
}

- (void)stopRefresh {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    [self.currentTask cancel];
    self.currentTask = nil;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stopRefresh];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self stopRefresh];
    // Keep snapshotView.image and currentEntityId — the last good frame stays
    // visible. If the same entity rebinds, entityChanged will be NO and we skip
    // the image clear. If a different entity binds, configureWithEntity: nils it.
    self.errorLabel.hidden = YES;
    self.errorLabel.text = nil;
    self.consecutiveFailures = 0;
    // Reset to full-bleed (no name) layout
    self.snapshotTopWithName.active = NO;
    self.snapshotTopNoName.active = YES;

    // Clean up overlay buttons
    if (self.overlayElements.count > 0) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
            name:HAConnectionManagerEntityDidUpdateNotification object:nil];
    }
    for (UIView *btn in self.overlayButtons) {
        [btn removeFromSuperview];
    }
    [self.overlayButtons removeAllObjects];
    self.overlayElements = nil;
    self.overlayBar.hidden = YES;
}

- (void)dealloc {
    [self stopRefresh];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
