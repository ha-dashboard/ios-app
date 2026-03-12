#import "HAAutoLayout.h"
#import "HACameraEntityCell.h"
#import "HAEntity.h"
#import "HAAuthManager.h"
#import "HADashboardConfig.h"
#import "HAConnectionManager.h"
#import "HAEntityDisplayHelper.h"
#import "HAIconMapper.h"
#import "HAMJPEGStreamParser.h"
#import "HALog.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "UIFont+HACompat.h"
#import "NSString+HACompat.h"

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

// Camera service buttons (power toggle + snapshot + fullscreen + volume)
@property (nonatomic, strong) UIButton *cameraPowerButton;
@property (nonatomic, strong) UIButton *cameraSnapshotButton;
@property (nonatomic, strong) UIButton *cameraFullscreenButton;
@property (nonatomic, strong) UIButton *cameraVolumeButton; // grid volume toggle (HLS only)

// Overlay action buttons
@property (nonatomic, strong) UIView *overlayBar;
@property (nonatomic, copy)   NSArray<NSDictionary *> *overlayElements; // [{entity_id, tap_action}, ...]
@property (nonatomic, strong) NSMutableArray<UIView *> *overlayButtons;
// Toggling snapshot-top constraint: below nameLabel or at contentView top
@property (nonatomic, strong) NSLayoutConstraint *snapshotTopWithName;
@property (nonatomic, strong) NSLayoutConstraint *snapshotTopNoName;

// MJPEG streaming
@property (nonatomic, strong) HAMJPEGStreamParser *streamParser;
@property (nonatomic, assign) BOOL useStreaming;       // default YES
@property (nonatomic, assign) BOOL streamFailed;       // fell back to snapshot polling

// HLS streaming (AVPlayer)
@property (nonatomic, strong) AVPlayer *hlsPlayer;
@property (nonatomic, strong) AVPlayerLayer *hlsPlayerLayer;
@property (nonatomic, assign) BOOL hlsFailed;
@property (nonatomic, assign) BOOL hlsRequestInFlight; // prevent duplicate WS requests
@property (nonatomic, assign) BOOL hlsStatusKVORegistered;  // track KVO registration
@property (nonatomic, assign) BOOL hlsReadyKVORegistered;   // track KVO registration

// Fullscreen mirror — when set, frames update both snapshotView and this view.
// Strong ref: the weak reference was zeroed during modal presentation animation.
@property (nonatomic, strong) UIImageView *fullscreenImageView;
@property (nonatomic, assign) NSUInteger frameCount; // diagnostic counter

// LIVE badge tracking — only show when frames are actually being delivered
@property (nonatomic, assign) BOOL receivingFrames;  // set YES on frame delivery, NO on stream stop
@property (nonatomic, strong) NSDate *lastFrameTime;  // for stale stream detection
@property (nonatomic, assign) BOOL hlsLive;           // HLS confirmed rendering (readyForDisplay)
@property (nonatomic, assign) NSUInteger recentFrameCount; // frames received in current window
@property (nonatomic, strong) NSDate *frameWindowStart;    // start of fps measurement window

// Stream resilience — auto-reconnect on interruption
@property (nonatomic, strong) NSTimer *healthCheckTimer;  // periodic stream health check
@property (nonatomic, assign) NSInteger reconnectAttempts; // exponential backoff counter

// Button layout constraints
@property (nonatomic, strong) NSLayoutConstraint *snapAfterPowerConstraint;
@property (nonatomic, strong) NSLayoutConstraint *snapAtEdgeConstraint;
@end

/// Stream mode override from developer settings
typedef NS_ENUM(NSInteger, HACameraStreamMode) {
    HACameraStreamModeAuto = 0,    // Pick best (HLS if STREAM feature, else MJPEG, else snapshot)
    HACameraStreamModeMJPEG,       // Force MJPEG
    HACameraStreamModeHLS,         // Force HLS
    HACameraStreamModeSnapshot,    // Force snapshot polling
};

static HACameraStreamMode currentStreamMode(void) {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"HADevStreamMode"];
    if ([mode isEqualToString:@"mjpeg"])    return HACameraStreamModeMJPEG;
    if ([mode isEqualToString:@"hls"])      return HACameraStreamModeHLS;
    if ([mode isEqualToString:@"snapshot"]) return HACameraStreamModeSnapshot;
    return HACameraStreamModeAuto;
}

@implementation HACameraEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;
    self.useStreaming = YES;

    // Retry HLS after WebSocket connects (cells often load before WS is authenticated)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(wsDidConnect:)
                                                 name:HAConnectionManagerDidConnectNotification
                                               object:nil];

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
    if (HAAutoLayoutAvailable()) {
        [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    }
    if (HAAutoLayoutAvailable()) {
        [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    }
    if (HAAutoLayoutAvailable()) {
        [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
    }

    // Two top constraints: below nameLabel (with title) or at contentView top (no title)
    self.snapshotTopWithName = [NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4];
    self.snapshotTopNoName = [NSLayoutConstraint constraintWithItem:self.snapshotView attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    // Default: no name (full-bleed camera)
    self.snapshotTopWithName.active = NO;
    self.snapshotTopNoName.active = YES;

    // Spinner: centered in snapshot view
    if (HAAutoLayoutAvailable()) {
        [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.loadingSpinner attribute:NSLayoutAttributeCenterX
            relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    }
    if (HAAutoLayoutAvailable()) {
        [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.loadingSpinner attribute:NSLayoutAttributeCenterY
            relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
    }

    // Error label: centered in snapshot view
    if (HAAutoLayoutAvailable()) {
        [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.errorLabel attribute:NSLayoutAttributeCenterX
            relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    }
    if (HAAutoLayoutAvailable()) {
        [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.errorLabel attribute:NSLayoutAttributeCenterY
            relatedBy:NSLayoutRelationEqual toItem:self.snapshotView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
    }
    if (HAAutoLayoutAvailable()) {
        [self.snapshotView addConstraint:[NSLayoutConstraint constraintWithItem:self.errorLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.snapshotView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    }

    // State badge (recording/streaming indicator, top-right corner)
    self.stateBadge = [[UILabel alloc] init];
    self.stateBadge.font = [UIFont ha_systemFontOfSize:9 weight:UIFontWeightBold];
    self.stateBadge.textColor = [UIColor whiteColor];
    self.stateBadge.textAlignment = NSTextAlignmentCenter;
    self.stateBadge.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
    self.stateBadge.layer.cornerRadius = 4;
    self.stateBadge.clipsToBounds = YES;
    self.stateBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateBadge.hidden = YES;
    [self.contentView addSubview:self.stateBadge];

    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.stateBadge.topAnchor constraintEqualToAnchor:self.snapshotView.topAnchor constant:6],
            [self.stateBadge.trailingAnchor constraintEqualToAnchor:self.snapshotView.trailingAnchor constant:-38],
            [self.stateBadge.heightAnchor constraintEqualToConstant:16],
            [self.stateBadge.widthAnchor constraintGreaterThanOrEqualToConstant:40],
        ]];
    }

    // Camera power toggle button (top-left of snapshot)
    self.cameraPowerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cameraPowerButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.cameraPowerButton.layer.cornerRadius = 14;
    self.cameraPowerButton.clipsToBounds = YES;
    self.cameraPowerButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraPowerButton.hidden = YES;
    [self.cameraPowerButton addTarget:self action:@selector(cameraPowerTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.cameraPowerButton];

    // Camera snapshot button (left of power)
    self.cameraSnapshotButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cameraSnapshotButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.cameraSnapshotButton.layer.cornerRadius = 14;
    self.cameraSnapshotButton.clipsToBounds = YES;
    self.cameraSnapshotButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraSnapshotButton.hidden = YES;
    [self.cameraSnapshotButton addTarget:self action:@selector(cameraSnapshotTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.cameraSnapshotButton];

    // Fullscreen button (top-right, next to LIVE badge)
    self.cameraFullscreenButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cameraFullscreenButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.cameraFullscreenButton.layer.cornerRadius = 14;
    self.cameraFullscreenButton.clipsToBounds = YES;
    self.cameraFullscreenButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cameraFullscreenButton addTarget:self action:@selector(cameraFullscreenTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.cameraFullscreenButton];

    // Volume toggle button (bottom-right, HLS only — hidden until HLS active)
    self.cameraVolumeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cameraVolumeButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.cameraVolumeButton.layer.cornerRadius = 14;
    self.cameraVolumeButton.clipsToBounds = YES;
    self.cameraVolumeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraVolumeButton.hidden = YES; // Hidden until HLS stream is active
    [self.cameraVolumeButton addTarget:self action:@selector(gridVolumeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.cameraVolumeButton];

    // Set icons via MDI glyphs
    NSString *powerGlyph = [HAIconMapper glyphForIconName:@"power"] ?: @"\u23FB";
    NSString *snapGlyph = [HAIconMapper glyphForIconName:@"camera-iris"] ?: [HAIconMapper glyphForIconName:@"camera"] ?: @"\U0001F4F7";
    NSString *fullscreenGlyph = [HAIconMapper glyphForIconName:@"fullscreen"] ?: @"\u26F6";
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:14];
    [self.cameraPowerButton setAttributedTitle:[[NSAttributedString alloc] initWithString:powerGlyph
        attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];
    [self.cameraSnapshotButton setAttributedTitle:[[NSAttributedString alloc] initWithString:snapGlyph
        attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];
    [self.cameraFullscreenButton setAttributedTitle:[[NSAttributedString alloc] initWithString:fullscreenGlyph
        attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];

    // Snapshot button leads from power button when visible, from snapshotView edge when hidden.
    // Use two constraints with different priorities — the active one wins.
    if (HAAutoLayoutAvailable()) {
        NSLayoutConstraint *snapAfterPower = [self.cameraSnapshotButton.leadingAnchor constraintEqualToAnchor:self.cameraPowerButton.trailingAnchor constant:4];
        snapAfterPower.priority = UILayoutPriorityDefaultHigh; // 750 — used when power visible
        NSLayoutConstraint *snapAtEdge = [self.cameraSnapshotButton.leadingAnchor constraintEqualToAnchor:self.snapshotView.leadingAnchor constant:6];
        snapAtEdge.priority = UILayoutPriorityDefaultLow; // 250 — used when power hidden
        self.snapAfterPowerConstraint = snapAfterPower;
        self.snapAtEdgeConstraint = snapAtEdge;
    }

    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.cameraPowerButton.topAnchor constraintEqualToAnchor:self.snapshotView.topAnchor constant:6],
            [self.cameraPowerButton.leadingAnchor constraintEqualToAnchor:self.snapshotView.leadingAnchor constant:6],
            [self.cameraPowerButton.widthAnchor constraintEqualToConstant:28],
            [self.cameraPowerButton.heightAnchor constraintEqualToConstant:28],
            [self.cameraSnapshotButton.topAnchor constraintEqualToAnchor:self.snapshotView.topAnchor constant:6],
            self.snapAfterPowerConstraint,
            self.snapAtEdgeConstraint,
            [self.cameraSnapshotButton.widthAnchor constraintEqualToConstant:28],
            [self.cameraSnapshotButton.heightAnchor constraintEqualToConstant:28],
            // Fullscreen button — top-right corner
            [self.cameraFullscreenButton.topAnchor constraintEqualToAnchor:self.snapshotView.topAnchor constant:6],
            [self.cameraFullscreenButton.trailingAnchor constraintEqualToAnchor:self.snapshotView.trailingAnchor constant:-6],
            [self.cameraFullscreenButton.widthAnchor constraintEqualToConstant:28],
            [self.cameraFullscreenButton.heightAnchor constraintEqualToConstant:28],
            // Volume button — bottom-right corner
            [self.cameraVolumeButton.bottomAnchor constraintEqualToAnchor:self.snapshotView.bottomAnchor constant:-6],
            [self.cameraVolumeButton.trailingAnchor constraintEqualToAnchor:self.snapshotView.trailingAnchor constant:-6],
            [self.cameraVolumeButton.widthAnchor constraintEqualToConstant:28],
            [self.cameraVolumeButton.heightAnchor constraintEqualToConstant:28],
        ]];
    }

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
    HALogD(@"cam", @"configure %p: %@ → %@ (changed=%d)", self,
          self.currentEntityId, entity.entityId, entityChanged);
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
    // Only show LIVE when we are actually receiving video frames — not just "connected"
    NSString *camState = entity.state;
    if ([camState isEqualToString:@"recording"]) {
        self.stateBadge.text = @" REC ";
        self.stateBadge.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
        self.stateBadge.hidden = NO;
    } else if (self.receivingFrames) {
        self.stateBadge.text = @" LIVE ";
        self.stateBadge.backgroundColor = [[UIColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:0.8] colorWithAlphaComponent:0.8];
        self.stateBadge.hidden = NO;
    } else {
        self.stateBadge.hidden = YES;
    }

    if (entityChanged) {
        // Different entity — tear down existing stream and reset
        [self stopRefresh];
        self.snapshotView.image = nil;
        self.consecutiveFailures = 0;
        self.streamFailed = NO;
        // On iOS <10, HLS is permanently disabled (crashes AVFoundation).
        // Don't reset hlsFailed — it was set once by startHLSStream.
        if ([[[UIDevice currentDevice] systemVersion] compare:@"10.0" options:NSNumericSearch] != NSOrderedAscending) {
            self.hlsFailed = NO;
        }
        self.needsSnapshotLoad = YES;
    }
    // Same entity: stream continues uninterrupted

    // Camera service buttons: show when entity supports ON_OFF and is available
    // CameraEntityFeature: ON_OFF = 1 (bit 0), STREAM = 2 (bit 1)
    NSInteger features = [entity supportedFeatures];
    BOOL supportsOnOff = (features & 1) != 0;
    BOOL powerVisible = supportsOnOff && entity.isAvailable;
    self.cameraPowerButton.hidden = !powerVisible;
    self.cameraSnapshotButton.hidden = !entity.isAvailable;
    // Collapse snapshot button to left edge when power button is hidden
    self.snapAfterPowerConstraint.priority = powerVisible ? UILayoutPriorityDefaultHigh : UILayoutPriorityDefaultLow;
    self.snapAtEdgeConstraint.priority = powerVisible ? UILayoutPriorityDefaultLow : UILayoutPriorityDefaultHigh;
    // Ensure buttons render above the image content
    // Buttons are contentView children — always above snapshotView's image layer
    [self.contentView bringSubviewToFront:self.cameraPowerButton];
    [self.contentView bringSubviewToFront:self.cameraSnapshotButton];
    [self.contentView bringSubviewToFront:self.cameraFullscreenButton];
    [self.contentView bringSubviewToFront:self.cameraVolumeButton];
    [self.contentView bringSubviewToFront:self.stateBadge];

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

/// Override hitTest to ensure button taps are consumed by the button,
/// not by the collection view's cell selection gesture recognizer.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Check fullscreen, snapshot, and power buttons first
    NSArray *buttons = @[self.cameraVolumeButton, self.cameraFullscreenButton, self.cameraSnapshotButton, self.cameraPowerButton];
    for (UIButton *btn in buttons) {
        if (btn.hidden || btn.alpha < 0.01) continue;
        CGPoint btnPoint = [self convertPoint:point toView:btn];
        if ([btn pointInside:btnPoint withEvent:event]) {
            return btn;
        }
    }
    return [super hitTest:point withEvent:event];
}

- (void)cameraFullscreenTapped {
    HALogD(@"cam", @"Fullscreen tapped for %@", self.currentEntityId);
    if (!self.entity) return;

    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) break;
    }
    UIViewController *vc = (UIViewController *)responder;
    if (!vc) return;

    UIViewController *fullscreen = [[UIViewController alloc] init];
    fullscreen.modalPresentationStyle = UIModalPresentationFullScreen;
    fullscreen.view.backgroundColor = [UIColor blackColor];

    // For HLS: move the AVPlayerLayer to fullscreen view
    // For MJPEG/snapshot: mirror frames via fullscreenImageView property
    UIImageView *imageView = [[UIImageView alloc] initWithImage:self.snapshotView.image];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.frame = fullscreen.view.bounds;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [fullscreen.view addSubview:imageView];

    // For HLS: create a SECOND AVPlayerLayer on the same AVPlayer.
    // One AVPlayer renders to multiple layers independently.
    // Moving the existing layer breaks rendering.
    AVPlayerLayer *fsLayer = nil;
    if (self.hlsPlayer) {
        fsLayer = [AVPlayerLayer playerLayerWithPlayer:self.hlsPlayer];
        fsLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [imageView.layer addSublayer:fsLayer];
    }

    // MJPEG/snapshot: mirror frames
    self.fullscreenImageView = imageView;
    HALogD(@"cam", @"Fullscreen opened for %@ — imageView=%p weak=%p streaming=%d hlsPlayer=%@",
          self.currentEntityId, imageView, self.fullscreenImageView,
          self.streamParser.isStreaming, self.hlsPlayer ? @"YES" : @"NO");

    // Close button — top-right
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    closeButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    closeButton.layer.cornerRadius = 18;
    closeButton.clipsToBounds = YES;
    NSString *closeGlyph = [HAIconMapper glyphForIconName:@"close"] ?: @"✕";
    UIFont *closeFont = [HAIconMapper mdiFontOfSize:18];
    [closeButton setAttributedTitle:[[NSAttributedString alloc] initWithString:closeGlyph
        attributes:@{NSFontAttributeName: closeFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];
    closeButton.frame = CGRectMake(fullscreen.view.bounds.size.width - 50, 40, 36, 36);
    closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [closeButton addTarget:self action:@selector(dismissFullscreenButton:) forControlEvents:UIControlEventTouchUpInside];
    [fullscreen.view addSubview:closeButton];

    // Camera name — bottom-left
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = [self.entity friendlyName] ?: self.currentEntityId;
    nameLabel.font = [UIFont ha_systemFontOfSize:16 weight:UIFontWeightMedium];
    nameLabel.textColor = [UIColor whiteColor];
    nameLabel.frame = CGRectMake(16, fullscreen.view.bounds.size.height - 50, fullscreen.view.bounds.size.width - 100, 30);
    nameLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [fullscreen.view addSubview:nameLabel];

    // Audio controls — bottom-right (HLS only, MJPEG has no audio)
    if (self.hlsPlayer) {
        BOOL globalMute = [[HAAuthManager sharedManager] cameraGlobalMute];
        UIFont *iconFont = [HAIconMapper mdiFontOfSize:18];
        NSString *muteGlyph = [HAIconMapper glyphForIconName:@"volume-off"] ?: @"🔇";
        NSString *unmuteGlyph = [HAIconMapper glyphForIconName:@"volume-high"] ?: @"🔊";

        // Load per-camera volume (or default to 0.5)
        NSString *volKey = [NSString stringWithFormat:@"HACameraVolume_%@", self.currentEntityId];
        CGFloat savedVol = [[NSUserDefaults standardUserDefaults] floatForKey:volKey];
        if (savedVol <= 0) savedVol = 0.5;

        // If global mute is OFF, start unmuted with saved per-camera volume
        BOOL startMuted = globalMute;
        if (!startMuted) {
            self.hlsPlayer.volume = savedVol;
        }

        NSString *initialGlyph = startMuted ? muteGlyph : unmuteGlyph;
        UIButton *muteButton = [UIButton buttonWithType:UIButtonTypeCustom];
        muteButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        muteButton.layer.cornerRadius = 18;
        muteButton.clipsToBounds = YES;
        muteButton.tag = 8001;
        [muteButton setAttributedTitle:[[NSAttributedString alloc] initWithString:initialGlyph
            attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
            forState:UIControlStateNormal];
        muteButton.frame = CGRectMake(fullscreen.view.bounds.size.width - 50,
                                      fullscreen.view.bounds.size.height - 50, 36, 36);
        muteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        [muteButton addTarget:self action:@selector(fullscreenMuteToggled:) forControlEvents:UIControlEventTouchUpInside];
        [fullscreen.view addSubview:muteButton];

        // Volume slider — horizontal, left of mute button
        UISlider *volumeSlider = [[UISlider alloc] init];
        volumeSlider.minimumValue = 0;
        volumeSlider.maximumValue = 1.0;
        volumeSlider.value = savedVol;
        volumeSlider.minimumTrackTintColor = [UIColor whiteColor];
        volumeSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.4 alpha:1];
        volumeSlider.frame = CGRectMake(fullscreen.view.bounds.size.width - 200,
                                        fullscreen.view.bounds.size.height - 46, 140, 28);
        volumeSlider.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        volumeSlider.hidden = startMuted; // Show if not muted
        volumeSlider.tag = 8002;
        [volumeSlider addTarget:self action:@selector(fullscreenVolumeChanged:) forControlEvents:UIControlEventValueChanged];
        [fullscreen.view addSubview:volumeSlider];
    }

    __weak AVPlayerLayer *weakFSLayer = fsLayer;
    [vc presentViewController:fullscreen animated:YES completion:^{
        __strong AVPlayerLayer *layer = weakFSLayer;
        if (layer) {
            layer.frame = imageView.bounds;
        }
    }];
}

- (void)dismissFullscreenButton:(UIButton *)sender {
    self.fullscreenImageView = nil;
    // Always re-mute when returning to grid view
    if (self.hlsPlayer) {
        self.hlsPlayer.volume = 0;
    }
    UIViewController *presented = sender.window.rootViewController.presentedViewController;
    [presented dismissViewControllerAnimated:YES completion:nil];
}

- (void)fullscreenMuteToggled:(UIButton *)sender {
    if (!self.hlsPlayer) return;

    BOOL wasMuted = (self.hlsPlayer.volume == 0);
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:18];
    NSString *volKey = [NSString stringWithFormat:@"HACameraVolume_%@", self.currentEntityId];

    if (wasMuted) {
        // Unmute — restore per-camera volume
        CGFloat vol = [[NSUserDefaults standardUserDefaults] floatForKey:volKey];
        if (vol <= 0) vol = 0.5;
        self.hlsPlayer.volume = vol;

        NSString *glyph = [HAIconMapper glyphForIconName:@"volume-high"] ?: @"🔊";
        [sender setAttributedTitle:[[NSAttributedString alloc] initWithString:glyph
            attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
            forState:UIControlStateNormal];

        // Show volume slider
        UIView *slider = [sender.superview viewWithTag:8002];
        slider.hidden = NO;
        if ([slider isKindOfClass:[UISlider class]]) {
            ((UISlider *)slider).value = vol;
        }
    } else {
        // Mute
        self.hlsPlayer.volume = 0;

        NSString *glyph = [HAIconMapper glyphForIconName:@"volume-off"] ?: @"🔇";
        [sender setAttributedTitle:[[NSAttributedString alloc] initWithString:glyph
            attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
            forState:UIControlStateNormal];

        // Hide volume slider
        UIView *slider = [sender.superview viewWithTag:8002];
        slider.hidden = YES;
    }
}

- (void)fullscreenVolumeChanged:(UISlider *)slider {
    if (!self.hlsPlayer) return;
    self.hlsPlayer.volume = slider.value;
    // Save per-camera volume
    NSString *volKey = [NSString stringWithFormat:@"HACameraVolume_%@", self.currentEntityId];
    [[NSUserDefaults standardUserDefaults] setFloat:slider.value forKey:volKey];

    // Update mute button icon based on volume level
    UIButton *muteBtn = (UIButton *)[slider.superview viewWithTag:8001];
    if (!muteBtn) return;
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:18];
    NSString *glyph;
    if (slider.value <= 0.01) {
        glyph = [HAIconMapper glyphForIconName:@"volume-off"] ?: @"🔇";
    } else if (slider.value < 0.5) {
        glyph = [HAIconMapper glyphForIconName:@"volume-medium"] ?: @"🔉";
    } else {
        glyph = [HAIconMapper glyphForIconName:@"volume-high"] ?: @"🔊";
    }
    [muteBtn setAttributedTitle:[[NSAttributedString alloc] initWithString:glyph
        attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];
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
        NSString *configIcon = elem[@"icon"]; // Icon override from dashboard config

        // Create circular button view
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

        // Enable tap for toggle and call-service actions
        if ([tapAction isEqualToString:@"toggle"] || [tapAction isEqualToString:@"call-service"]) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(overlayButtonTapped:)];
            [button addGestureRecognizer:tap];
            button.userInteractionEnabled = YES;
        } else {
            button.userInteractionEnabled = NO;
        }

        [self.overlayBar addSubview:button];
        [self.overlayButtons addObject:button];

        // Set icon: config override > entity icon > fallback
        if (configIcon) {
            // Use the icon specified in the dashboard card config
            NSString *iconName = configIcon;
            if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
            NSString *glyph = [HAIconMapper glyphForIconName:iconName];
            if (glyph) {
                UIFont *mdiFont = [HAIconMapper mdiFontOfSize:kOverlayIconFontSize];
                iconLabel.attributedText = [[NSAttributedString alloc] initWithString:glyph
                    attributes:@{NSFontAttributeName: mdiFont, NSForegroundColorAttributeName: [UIColor whiteColor]}];
            } else {
                iconLabel.text = @"?";
                iconLabel.font = [UIFont systemFontOfSize:kOverlayIconFontSize];
                iconLabel.textColor = [UIColor whiteColor];
            }
        } else if (entityId) {
            // Use entity's icon
            HAEntity *overlayEntity = [connMgr entityForId:entityId];
            [self updateButton:button forEntity:overlayEntity];
        }
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

    // Visual feedback
    button.alpha = 0.5;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        button.alpha = 1.0;
    });

    if ([tapAction isEqualToString:@"toggle"] && entityId) {
        [[HAConnectionManager sharedManager] callService:@"toggle"
                                                inDomain:@"homeassistant"
                                                withData:nil
                                                entityId:entityId];
    } else if ([tapAction isEqualToString:@"call-service"]) {
        NSDictionary *actionConfig = elem[@"tap_action_config"];
        NSString *service = actionConfig[@"service"]; // e.g. "button.press"
        NSDictionary *serviceData = actionConfig[@"data"];
        if ([service isKindOfClass:[NSString class]]) {
            // Split "button.press" into domain "button" and service "press"
            NSArray *parts = [service componentsSeparatedByString:@"."];
            if (parts.count == 2) {
                NSString *domain = parts[0];
                NSString *svc = parts[1];
                NSString *svcEntityId = serviceData[@"entity_id"];
                [[HAConnectionManager sharedManager] callService:svc
                                                        inDomain:domain
                                                        withData:nil
                                                        entityId:svcEntityId];
            }
        }
    }
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
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat padding = 10.0;

        // Snapshot view: full bleed or below name
        // Ensure translatesAutoresizingMaskIntoConstraints=YES so UIKit honours
        // our explicit frame and contentMode centers the scaled image correctly.
        // Without this, the view may have TAMIC=NO with no constraints, causing
        // the layer content gravity to anchor top-left instead of center.
        self.snapshotView.translatesAutoresizingMaskIntoConstraints = YES;
        CGFloat snapTop = self.nameLabel.hidden ? 0 : CGRectGetMaxY(self.nameLabel.frame) + 4;
        self.snapshotView.frame = CGRectMake(0, snapTop, w, h - snapTop);

        // Loading spinner: centered in snapshot
        CGSize spinSize = [self.loadingSpinner sizeThatFits:CGSizeMake(50, 50)];
        CGFloat snapMidX = w / 2.0;
        CGFloat snapMidY = snapTop + (h - snapTop) / 2.0;
        self.loadingSpinner.frame = CGRectMake(snapMidX - spinSize.width / 2.0, snapMidY - snapTop - spinSize.height / 2.0, spinSize.width, spinSize.height);

        // Error label: centered in snapshot
        CGSize errSize = [self.errorLabel sizeThatFits:CGSizeMake(w - padding * 2, CGFLOAT_MAX)];
        self.errorLabel.frame = CGRectMake(padding, (h - snapTop) / 2.0 - errSize.height / 2.0, w - padding * 2, errSize.height);

        // State badge: top-right of snapshot
        CGSize badgeSize = [self.stateBadge sizeThatFits:CGSizeMake(80, 16)];
        self.stateBadge.frame = CGRectMake(w - 38 - MAX(badgeSize.width, 40), snapTop + 6, MAX(badgeSize.width, 40), 16);

        // Camera buttons
        self.cameraPowerButton.frame = CGRectMake(6, snapTop + 6, 28, 28);
        CGFloat snapBtnX = self.cameraPowerButton.hidden ? 6 : 38;
        self.cameraSnapshotButton.frame = CGRectMake(snapBtnX, snapTop + 6, 28, 28);
        self.cameraFullscreenButton.frame = CGRectMake(w - 34, snapTop + 6, 28, 28);
        self.cameraVolumeButton.frame = CGRectMake(w - 34, h - 34, 28, 28);
    }
    [self layoutOverlayBar];
    // Keep HLS player layer frame in sync with snapshot view
    if (self.hlsPlayerLayer) {
        self.hlsPlayerLayer.frame = self.snapshotView.bounds;
    }
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
        CGSize sz = [label ha_sizeWithAttributes:attrs];
        [label ha_drawAtPoint:CGPointMake((w - sz.width) / 2, (h - sz.height) / 2) withAttributes:attrs];
        self.snapshotView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [self.loadingSpinner stopAnimating];
        return;
    }

    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (!auth.isConfigured) {
        HALogW(@"cam", @"fetchSnapshot: auth not configured for %@", self.currentEntityId);
        return;
    }

    NSString *proxyPath = [self.entity cameraProxyPath];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", auth.serverURL, proxyPath]];
    if (!url) {
        HALogW(@"cam", @"fetchSnapshot: invalid URL for %@", self.currentEntityId);
        return;
    }

    HALogD(@"cam", @"fetchSnapshot: %@ token=%@...", url,
          [auth.accessToken substringToIndex:MIN(10, auth.accessToken.length)]);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", auth.accessToken] forHTTPHeaderField:@"Authorization"];

    // Don't cancel an in-flight fetch for the same entity — let it complete
    if (self.currentTask && self.currentTask.state == NSURLSessionTaskStateRunning) {
        return;
    }
    [self.currentTask cancel];

    if (!self.snapshotView.image) {
        [self.loadingSpinner startAnimating];
    }

    __weak typeof(self) weakSelf = self;
    NSString *expectedEntityId = [self.currentEntityId copy];
    self.currentTask = [self.imageSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error && error.code == NSURLErrorCancelled) return;

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            BOOL fetchFailed = (error != nil) || (httpResponse.statusCode != 200) || !data;

            if (fetchFailed) {
                HALogE(@"cam", @"fetchSnapshot FAILED for %@: HTTP %ld, error=%@, dataLen=%lu",
                      expectedEntityId, (long)httpResponse.statusCode,
                      error.localizedDescription ?: @"(none)", (unsigned long)data.length);
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    if (![strongSelf.currentEntityId isEqualToString:expectedEntityId]) return;
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
                if (![strongSelf.currentEntityId isEqualToString:expectedEntityId]) return;
                [strongSelf.loadingSpinner stopAnimating];
                if (image) {
                    strongSelf.consecutiveFailures = 0;
                    strongSelf.snapshotView.image = image;
                    if (strongSelf.fullscreenImageView) {
                        strongSelf.fullscreenImageView.image = image;
                    }
                    strongSelf.errorLabel.hidden = YES;
                    [strongSelf layoutOverlayBar];
                }
            });
        }];
    [self.currentTask resume];
}

#pragma mark - MJPEG Streaming

- (void)startMJPEGStream {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (!auth.isConfigured || !self.entity) return;
    HALogD(@"cam", @"startMJPEG %@ (cell %p)", self.currentEntityId, self);

    NSString *streamPath = [self.entity cameraStreamPath];
    if (!streamPath) {
        self.streamFailed = YES;
        [self beginLoading]; // retry will use snapshot fallback
        return;
    }

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", auth.serverURL, streamPath]];
    if (!url) {
        self.streamFailed = YES;
        [self beginLoading];
        return;
    }

    HALogI(@"cam", @"Starting MJPEG stream: %@ (cell %p)", url, self);
    [self.loadingSpinner startAnimating];

    self.streamParser = [[HAMJPEGStreamParser alloc] init];
    __weak typeof(self) weakSelf = self;
    NSString *expectedEntityId = [self.currentEntityId copy];
    HAMJPEGStreamParser *expectedParser = self.streamParser;

    self.streamParser.frameHandler = ^(UIImage *frame) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // Guard: reject frames from a stale parser (cell was reused for a different entity)
        if (strongSelf.streamParser != expectedParser) return;
        if (![strongSelf.currentEntityId isEqualToString:expectedEntityId]) {
            HALogD(@"cam", @"Rejecting stale frame: expected %@ but cell is now %@ (cell %p)",
                  expectedEntityId, strongSelf.currentEntityId, strongSelf);
            return;
        }
        strongSelf.frameCount++;
        if (strongSelf.frameCount == 1 || strongSelf.frameCount % 30 == 0) {
            HALogD(@"cam", @"MJPEG frame %lu for %@", (unsigned long)strongSelf.frameCount, expectedEntityId);
        }
        strongSelf.snapshotView.image = frame;
        // Mirror to fullscreen view if presented
        UIImageView *fsIV = strongSelf.fullscreenImageView;
        if (fsIV) {
            fsIV.image = frame;
        }
        // Log every frame during fullscreen, every 30th otherwise
        if (fsIV || strongSelf.frameCount % 30 == 1) {
            HALogD(@"cam", @"Frame %lu for %@ — fs=%p card=%p streaming=%d",
                  (unsigned long)strongSelf.frameCount, expectedEntityId,
                  fsIV, strongSelf.snapshotView, strongSelf.streamParser.isStreaming);
        }
        [strongSelf.loadingSpinner stopAnimating];
        strongSelf.errorLabel.hidden = YES;
        strongSelf.consecutiveFailures = 0;
        strongSelf.reconnectAttempts = 0;
        strongSelf.lastFrameTime = [NSDate date];

        // Frame rate tracking for LIVE badge — only show LIVE for real video (>1fps).
        // HA proxies static cameras as MJPEG too, but they deliver frames very slowly.
        if (!strongSelf.frameWindowStart) {
            strongSelf.frameWindowStart = [NSDate date];
            strongSelf.recentFrameCount = 0;
        }
        strongSelf.recentFrameCount++;
        NSTimeInterval windowAge = -[strongSelf.frameWindowStart timeIntervalSinceNow];
        if (windowAge > 3.0) {
            // Evaluate: need >3 frames in 3 seconds (roughly >1fps) to count as live
            BOOL isLiveRate = (strongSelf.recentFrameCount >= 3);
            if (isLiveRate && !strongSelf.receivingFrames) {
                strongSelf.receivingFrames = YES;
                [strongSelf startHealthCheckTimer];
                HALogI(@"cam", @"MJPEG stream confirmed live for %@ (%lu frames in %.1fs)",
                      expectedEntityId, (unsigned long)strongSelf.recentFrameCount, windowAge);
            } else if (!isLiveRate && strongSelf.receivingFrames) {
                strongSelf.receivingFrames = NO;
            }
            // Reset window
            strongSelf.frameWindowStart = [NSDate date];
            strongSelf.recentFrameCount = 0;
            [strongSelf updateLiveBadge];
        }
    };

    self.streamParser.errorHandler = ^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.streamParser != expectedParser) return;
        HALogW(@"cam", @"MJPEG stream failed: %@ — attempting reconnect (cell %p)", error.localizedDescription, strongSelf);
        strongSelf.streamParser = nil;
        strongSelf.receivingFrames = NO;
        [strongSelf updateLiveBadge];
        [strongSelf attemptStreamReconnect];
    };

    [self.streamParser startWithURL:url authToken:auth.accessToken];
}

#pragma mark - HLS Streaming (AVPlayer)

- (void)startHLSStream {
    if (!self.entity || !self.entity.entityId) {
        self.hlsFailed = YES;
        [self beginLoading];
        return;
    }
    // Skip HLS on iOS 9 — AVPlayer HLS crashes on iPad 2 (armv7, iOS 9.3.5).
    // HA's ffmpeg transcoder output is incompatible with iOS 9's AVFoundation.
    // MJPEG works fine on these devices.
    if ([[[UIDevice currentDevice] systemVersion] compare:@"10.0" options:NSNumericSearch] == NSOrderedAscending) {
        HALogI(@"cam", @"Skipping HLS on iOS %@ — using MJPEG only",
              [[UIDevice currentDevice] systemVersion]);
        self.hlsFailed = YES;
        self.needsSnapshotLoad = YES;
        [self beginLoading];
        return;
    }
    if (self.hlsRequestInFlight) return; // Already requesting

    self.hlsRequestInFlight = YES;
    HALogI(@"cam", @"Requesting HLS stream for %@ (cell %p)", self.entity.entityId, self);
    [self.loadingSpinner startAnimating];

    NSDictionary *command = @{
        @"type": @"camera/stream",
        @"entity_id": self.entity.entityId,
    };
    __weak typeof(self) weakSelf = self;
    NSString *expectedEntityId = [self.currentEntityId copy];
    [[HAConnectionManager sharedManager] sendCommand:command completion:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.hlsRequestInFlight = NO;
        if (![strongSelf.currentEntityId isEqualToString:expectedEntityId]) return;

        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            HALogW(@"cam", @"HLS stream request failed: %@ — falling back to MJPEG",
                  error.localizedDescription ?: @"unexpected response");
            strongSelf.hlsFailed = YES;
            strongSelf.needsSnapshotLoad = YES;
            [strongSelf beginLoading]; // Will fall through to MJPEG
            return;
        }

        NSString *hlsURL = result[@"url"];
        if (![hlsURL isKindOfClass:[NSString class]] || hlsURL.length == 0) {
            HALogW(@"cam", @"HLS stream: no URL in response");
            strongSelf.hlsFailed = YES;
            strongSelf.needsSnapshotLoad = YES;
            [strongSelf beginLoading];
            return;
        }

        // Resolve relative URLs against HA server
        NSURL *streamURL;
        if ([hlsURL hasPrefix:@"http://"] || [hlsURL hasPrefix:@"https://"]) {
            streamURL = [NSURL URLWithString:hlsURL];
        } else {
            HAAuthManager *auth = [HAAuthManager sharedManager];
            streamURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", auth.serverURL, hlsURL]];
        }
        if (!streamURL) {
            strongSelf.hlsFailed = YES;
            [strongSelf beginLoading];
            return;
        }

        HALogI(@"cam", @"Starting HLS playback: %@", streamURL);
        [strongSelf playHLSURL:streamURL];
    }];
}

- (void)playHLSURL:(NSURL *)url {
    // HLS streams from HA include auth token as query param — no additional auth headers needed
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.hlsPlayer = [AVPlayer playerWithPlayerItem:item];

    // Apply volume: if global mute is OFF, play audio at per-camera volume
    BOOL globalMute = [[HAAuthManager sharedManager] cameraGlobalMute];
    if (globalMute) {
        self.hlsPlayer.volume = 0;
    } else {
        NSString *volKey = [NSString stringWithFormat:@"HACameraVolume_%@", self.currentEntityId];
        CGFloat savedVol = [[NSUserDefaults standardUserDefaults] floatForKey:volKey];
        self.hlsPlayer.volume = (savedVol > 0) ? savedVol : 0.5;
    }

    // Observe playback errors
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hlsPlaybackFailed:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:item];
    // Observe stalls for resilience
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hlsPlaybackStalled:)
                                                 name:AVPlayerItemPlaybackStalledNotification
                                               object:item];
    // Observe status for initial load failure AND readyToPlay
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
    self.hlsStatusKVORegistered = YES;

    self.hlsPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.hlsPlayer];
    // Observe readyForDisplay — the definitive signal that video is rendering (iOS 6+)
    // Do NOT use NSKeyValueObservingOptionInitial — it fires synchronously during
    // addObserver: which can trigger a CALayer transaction during layout, crashing
    // with NSInternalInconsistencyException on iOS 26.
    [self.hlsPlayerLayer addObserver:self forKeyPath:@"readyForDisplay"
                             options:NSKeyValueObservingOptionNew context:NULL];
    self.hlsReadyKVORegistered = YES;
    self.hlsPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.hlsPlayerLayer.frame = self.snapshotView.bounds;
    // DON'T add the layer to the view yet — wait until readyForDisplay confirms
    // video is actually rendering. This prevents a blank HLS layer from covering
    // MJPEG frames on devices where HLS fails (e.g. iPad 2).

    [self.hlsPlayer play];
    [self.loadingSpinner stopAnimating];

    // Start polling for readyForDisplay since we don't use NSKeyValueObservingOptionInitial
    // (it causes crashes during layout cycles on iOS 26)
    [self pollReadyForDisplay:10];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"] && [object isKindOfClass:[AVPlayerItem class]]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusFailed) {
            HALogE(@"cam", @"HLS playback error: %@", item.error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopHLSPlayer];
                self.hlsFailed = YES;
                // If MJPEG is still running in parallel, let it continue
                if (self.streamParser.isStreaming) {
                    HALogI(@"cam", @"HLS failed but MJPEG still active — keeping MJPEG");
                    return;
                }
                self.needsSnapshotLoad = YES;
                [self beginLoading]; // Fallback to MJPEG
            });
        } else if (item.status == AVPlayerItemStatusReadyToPlay) {
            HALogI(@"cam", @"HLS ready to play for %@", self.currentEntityId);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startHealthCheckTimer];
                // readyForDisplay KVO may have already fired (or missed) — poll briefly
                if (!self.receivingFrames) {
                    [self pollReadyForDisplay:5];
                }
            });
        }
    } else if ([keyPath isEqualToString:@"readyForDisplay"] && [object isKindOfClass:[AVPlayerLayer class]]) {
        BOOL ready = [change[NSKeyValueChangeNewKey] boolValue];
        if (ready) {
            HALogI(@"cam", @"HLS rendering video for %@", self.currentEntityId);
            dispatch_async(dispatch_get_main_queue(), ^{
                // HLS is confirmed rendering — NOW insert the layer into the view
                if (self.hlsPlayerLayer && !self.hlsPlayerLayer.superlayer) {
                    self.hlsPlayerLayer.frame = self.snapshotView.bounds;
                    [self.snapshotView.layer insertSublayer:self.hlsPlayerLayer atIndex:0];
                }
                // Stop MJPEG if it was running in parallel
                if (self.streamParser) {
                    HALogI(@"cam", @"HLS confirmed — stopping parallel MJPEG for %@", self.currentEntityId);
                    [self.streamParser stop];
                    self.streamParser = nil;
                }
                self.receivingFrames = YES;
                self.hlsLive = YES;
                self.lastFrameTime = [NSDate date];
                self.reconnectAttempts = 0;
                [self updateLiveBadge];
                [self.loadingSpinner stopAnimating];
                self.errorLabel.hidden = YES;
            });
        }
    }
}

- (void)hlsPlaybackFailed:(NSNotification *)note {
    HALogE(@"cam", @"HLS playback failed to end time for %@", self.currentEntityId);
    [self stopHLSPlayer];
    self.hlsFailed = YES;
    // If MJPEG is still running in parallel, let it continue — don't reconnect
    if (self.streamParser.isStreaming) {
        HALogI(@"cam", @"HLS failed but MJPEG still active for %@ — keeping MJPEG", self.currentEntityId);
        return;
    }
    self.receivingFrames = NO;
    [self updateLiveBadge];
    self.needsSnapshotLoad = YES;
    [self beginLoading]; // Falls through to MJPEG since hlsFailed=YES
}

- (void)hlsPlaybackStalled:(NSNotification *)note {
    HALogW(@"cam", @"HLS playback stalled for %@ — will auto-resume on buffer refill",
          self.currentEntityId);
    // AVPlayer auto-resumes when buffer refills (isPlaybackLikelyToKeepUp becomes YES).
    // Mark as not receiving frames so LIVE badge reflects reality.
    self.receivingFrames = NO;
    [self updateLiveBadge];
    // Ensure player keeps trying to play
    if (self.hlsPlayer && self.hlsPlayer.rate == 0) {
        [self.hlsPlayer play];
    }
}

#pragma mark - LIVE Badge

- (void)updateLiveBadge {
    if (self.receivingFrames) {
        self.stateBadge.text = @" LIVE ";
        self.stateBadge.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:0.8];
        self.stateBadge.hidden = NO;
        [self.contentView bringSubviewToFront:self.stateBadge];
    } else if ([self.entity.state isEqualToString:@"recording"]) {
        self.stateBadge.text = @" REC ";
        self.stateBadge.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
        self.stateBadge.hidden = NO;
        [self.contentView bringSubviewToFront:self.stateBadge];
    } else {
        self.stateBadge.hidden = YES;
    }

    // Show volume button only for active HLS streams
    BOOL showVolume = (self.hlsPlayer != nil && self.receivingFrames);
    self.cameraVolumeButton.hidden = !showVolume;
    if (showVolume) {
        [self updateGridVolumeIcon];
        [self.contentView bringSubviewToFront:self.cameraVolumeButton];
    }
}

- (void)updateGridVolumeIcon {
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:14];
    NSString *glyph;
    if (self.hlsPlayer.volume <= 0.01) {
        glyph = [HAIconMapper glyphForIconName:@"volume-off"] ?: @"M";
    } else {
        glyph = [HAIconMapper glyphForIconName:@"volume-high"] ?: @"V";
    }
    [self.cameraVolumeButton setAttributedTitle:[[NSAttributedString alloc] initWithString:glyph
        attributes:@{NSFontAttributeName: iconFont, NSForegroundColorAttributeName: [UIColor whiteColor]}]
        forState:UIControlStateNormal];
}

- (void)gridVolumeTapped {
    if (!self.hlsPlayer) return;

    NSString *volKey = [NSString stringWithFormat:@"HACameraVolume_%@", self.currentEntityId];
    if (self.hlsPlayer.volume > 0.01) {
        // Mute
        self.hlsPlayer.volume = 0;
    } else {
        // Unmute to per-camera volume
        CGFloat vol = [[NSUserDefaults standardUserDefaults] floatForKey:volKey];
        if (vol <= 0) vol = 0.5;
        self.hlsPlayer.volume = vol;
    }
    [self updateGridVolumeIcon];
}

/// Poll readyForDisplay a few times in case KVO missed the transition
- (void)pollReadyForDisplay:(NSInteger)remaining {
    if (remaining <= 0 || !self.hlsPlayerLayer || self.receivingFrames) return;
    if (self.hlsPlayerLayer.readyForDisplay) {
        HALogI(@"cam", @"HLS readyForDisplay confirmed via poll for %@", self.currentEntityId);
        if (self.hlsPlayerLayer && !self.hlsPlayerLayer.superlayer) {
            self.hlsPlayerLayer.frame = self.snapshotView.bounds;
            [self.snapshotView.layer insertSublayer:self.hlsPlayerLayer atIndex:0];
        }
        if (self.streamParser) {
            [self.streamParser stop];
            self.streamParser = nil;
        }
        self.receivingFrames = YES;
        self.hlsLive = YES;
        self.lastFrameTime = [NSDate date];
        self.reconnectAttempts = 0;
        [self updateLiveBadge];
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf pollReadyForDisplay:remaining - 1];
    });
}

#pragma mark - Stream Health Check

- (void)startHealthCheckTimer {
    [self.healthCheckTimer invalidate];
    self.healthCheckTimer = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                            target:self
                                                          selector:@selector(healthCheckFired)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)healthCheckFired {
    if (!self.currentEntityId || !self.window) {
        [self.healthCheckTimer invalidate];
        self.healthCheckTimer = nil;
        return;
    }

    // Check HLS health: player exists but rate is 0 and not buffering
    if (self.hlsPlayer) {
        AVPlayerItem *item = self.hlsPlayer.currentItem;
        BOOL stalled = (self.hlsPlayer.rate == 0 && item && item.status == AVPlayerItemStatusReadyToPlay);
        if (stalled && self.receivingFrames) {
            HALogW(@"cam", @"Health check: HLS stalled for %@ — attempting resume", self.currentEntityId);
            [self.hlsPlayer play];
            // If still stalled after next health check, reconnect
        } else if (stalled && !self.receivingFrames) {
            HALogW(@"cam", @"Health check: HLS dead for %@ — reconnecting", self.currentEntityId);
            [self attemptStreamReconnect];
        }
        return;
    }

    // Check MJPEG health: parser claims streaming but no frames recently
    if (self.streamParser.isStreaming && self.lastFrameTime) {
        NSTimeInterval age = -[self.lastFrameTime timeIntervalSinceNow];
        if (age > 30.0) {
            HALogW(@"cam", @"Health check: MJPEG stale for %@ (%.0fs since last frame) — reconnecting",
                  self.currentEntityId, age);
            [self attemptStreamReconnect];
        }
    }
}

#pragma mark - Stream Reconnection

- (void)attemptStreamReconnect {
    if (!self.currentEntityId || !self.window) return;

    self.reconnectAttempts++;
    // Exponential backoff: 0s, 2s, 5s, then give up and fall back
    NSTimeInterval delays[] = {0, 2.0, 5.0};
    NSInteger maxAttempts = 3;

    if (self.reconnectAttempts > maxAttempts) {
        HALogW(@"cam", @"Max reconnect attempts (%ld) for %@ — falling back to snapshot polling",
              (long)maxAttempts, self.currentEntityId);
        [self stopHLSPlayer];
        [self.streamParser stop];
        self.streamParser = nil;
        self.receivingFrames = NO;
        [self updateLiveBadge];
        // Mark BOTH stream modes as failed so beginLoading falls through to snapshot polling
        self.hlsFailed = YES;
        self.streamFailed = YES;
        self.needsSnapshotLoad = YES;
        [self beginLoading]; // Will skip HLS + MJPEG, start snapshot refresh timer
        return;
    }

    NSTimeInterval delay = delays[MIN(self.reconnectAttempts - 1, 2)];
    HALogI(@"cam", @"Reconnect attempt %ld for %@ (delay=%.0fs)",
          (long)self.reconnectAttempts, self.currentEntityId, delay);

    __weak typeof(self) weakSelf = self;
    NSString *expectedEntityId = [self.currentEntityId copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.currentEntityId isEqualToString:expectedEntityId]) return;
        if (!strongSelf.window) return;

        // Tear down current stream
        [strongSelf stopHLSPlayer];
        [strongSelf.streamParser stop];
        strongSelf.streamParser = nil;
        strongSelf.receivingFrames = NO;
        [strongSelf updateLiveBadge];

        // Reset failed flags to allow fresh attempt (but not HLS on iOS 9)
        if ([[[UIDevice currentDevice] systemVersion] compare:@"10.0" options:NSNumericSearch] != NSOrderedAscending) {
            strongSelf.hlsFailed = NO;
        }
        strongSelf.streamFailed = NO;
        strongSelf.needsSnapshotLoad = YES;
        [strongSelf beginLoading];
    });
}

- (void)stopHLSPlayer {
    self.hlsLive = NO;
    if (self.hlsPlayer) {
        [self.hlsPlayer pause];
        AVPlayerItem *item = self.hlsPlayer.currentItem;
        if (item) {
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                          object:item];
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:AVPlayerItemPlaybackStalledNotification
                                                          object:item];
            if (self.hlsStatusKVORegistered) {
                [item removeObserver:self forKeyPath:@"status"];
                self.hlsStatusKVORegistered = NO;
            }
        }
        self.hlsPlayer = nil;
    }
    if (self.hlsPlayerLayer) {
        if (self.hlsReadyKVORegistered) {
            [self.hlsPlayerLayer removeObserver:self forKeyPath:@"readyForDisplay"];
            self.hlsReadyKVORegistered = NO;
        }
        [self.hlsPlayerLayer removeFromSuperlayer];
        self.hlsPlayerLayer = nil;
    }
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
    // Self-invalidate when removed from window (matches healthCheckFired pattern).
    // Breaks the NSTimer → self retain cycle on section removal.
    if (!self.currentEntityId || !self.window) {
        [self.refreshTimer invalidate];
        self.refreshTimer = nil;
        return;
    }
    [self fetchSnapshot];
}

- (void)beginLoading {
    if (!self.currentEntityId) return;

    HALogD(@"cam", @"beginLoading %@ hlsPlayer=%d hlsReq=%d mjpeg=%d hlsFail=%d streamFail=%d",
              self.currentEntityId, self.hlsPlayer != nil, self.hlsRequestInFlight,
              self.streamParser.isStreaming, self.hlsFailed, self.streamFailed);

    // Already have HLS or requesting — don't restart anything
    if (self.hlsPlayer || self.hlsRequestInFlight) return;

    // 1. Snapshot immediately for fast initial display
    if (!self.snapshotView.image && self.needsSnapshotLoad) {
        self.needsSnapshotLoad = NO;
        [self fetchSnapshot];
    }

    // Already have MJPEG — don't start another (HLS upgrade handled by wsDidConnect)
    if (self.streamParser.isStreaming) return;

    HACameraStreamMode mode = currentStreamMode();
    BOOL entitySupportsStream = ([self.entity supportedFeatures] & 2) != 0;
    BOOL wsConnected = [HAConnectionManager sharedManager].isConnected;

    // 2. Try HLS if WS is connected. If HLS fails, error handler falls through to MJPEG.
    //    The HLS player layer is NOT inserted into the view until readyForDisplay confirms,
    //    so it won't cover MJPEG/snapshot frames on devices where HLS fails (iPad 2).
    if (mode == HACameraStreamModeHLS ||
        (mode == HACameraStreamModeAuto && entitySupportsStream && wsConnected && !self.hlsFailed)) {
        [self startHLSStream];
        return;
    }

    // 3. MJPEG as interim (will be upgraded to HLS by wsDidConnect if applicable)
    if (mode != HACameraStreamModeSnapshot && !self.streamFailed) {
        [self startMJPEGStream];
        return;
    }

    // 4. Snapshot polling as last resort
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
    [self.healthCheckTimer invalidate];
    self.healthCheckTimer = nil;
    [self.currentTask cancel];
    self.currentTask = nil;
    [self.streamParser stop];
    self.streamParser = nil;
    [self stopHLSPlayer];
    self.receivingFrames = NO;
    self.hlsLive = NO;
    self.lastFrameTime = nil;
    self.reconnectAttempts = 0;
    self.hlsRequestInFlight = NO;
    self.recentFrameCount = 0;
    self.frameWindowStart = nil;
}

- (void)wsDidConnect:(NSNotification *)note {
    if (!self.currentEntityId || !self.window) return;
    // Already on HLS — nothing to do
    if (self.hlsPlayer) return;

    // WS reconnect clears HLS failure flag — allows fresh attempt.
    // But NOT on iOS 9 where HLS is permanently disabled.
    if ([[[UIDevice currentDevice] systemVersion] compare:@"10.0" options:NSNumericSearch] != NSOrderedAscending) {
        self.hlsFailed = NO;
    }
    self.reconnectAttempts = 0;

    HACameraStreamMode mode = currentStreamMode();
    BOOL entitySupportsStream = ([self.entity supportedFeatures] & 2) != 0;

    // In Auto mode: upgrade MJPEG → HLS if entity supports it
    // In forced HLS mode: always try
    BOOL shouldTryHLS = (mode == HACameraStreamModeHLS) ||
                        (mode == HACameraStreamModeAuto && entitySupportsStream);
    if (!shouldTryHLS) return;

    HALogI(@"cam", @"WS connected — attempting HLS upgrade for %@ (MJPEG streaming=%d)",
          self.currentEntityId, self.streamParser.isStreaming);
    // Don't stop MJPEG yet — let HLS start in parallel. Once HLS confirms
    // readyForDisplay, we'll stop MJPEG. If HLS fails, MJPEG continues uninterrupted.
    [self startHLSStream];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        // Don't stop the stream if fullscreen is presented — the cell loses its
        // window during modal presentation but the stream must continue to deliver
        // frames to fullscreenImageView.
        if (self.fullscreenImageView) {
            HALogD(@"cam", @"Cell lost window but fullscreen is active — keeping stream alive for %@", self.currentEntityId);
            return;
        }
        [self stopRefresh];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Do NOT stop the MJPEG/HLS stream here. If the same entity rebinds
    // (common during collection view reloads), the stream continues
    // uninterrupted. Entity ID guards in frame/error callbacks prevent
    // cross-contamination if a different entity binds.
    // Only cancel lightweight snapshot operations.
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    [self.currentTask cancel];
    self.currentTask = nil;
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
    [self.healthCheckTimer invalidate];
    [self stopRefresh];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
