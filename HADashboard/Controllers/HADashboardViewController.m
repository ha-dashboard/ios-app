#import "HADashboardViewController.h"
#import "HALog.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HAPerfMonitor.h"
#import "HAEntityCellFactory.h"
#import "HABaseEntityCell.h"
#import "HASettingsViewController.h"
#import "HALovelaceParser.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAHaptics.h"
#import "HAEntityDetailViewController.h"
#import "HABottomSheetTransitioningDelegate.h"
#import "HABottomSheetPresentationController.h"
#import "HAEntitiesCardCell.h"
#import "HASkeletonView.h"
#import "HAEntityRowView.h"
#import "HAThermostatGaugeCell.h"
#import "HASectionHeaderView.h"
#import "HAColumnarLayout.h"
#import "HAMasonryLayout.h"
#import "HAPanelLayout.h"
#import "HASidebarLayout.h"
#import "HABadgeRowCell.h"
#import "HAGraphCardCell.h"
#import "HAHeadingCell.h"
#import "HACameraEntityCell.h"
#import "HAClockWeatherCell.h"
#import "HAGlanceCardCell.h"
#import "HAAction.h"
#import "HAActionDispatcher.h"
#import "HAMarkdownCardCell.h"
#import "HAWeatherEntityCell.h"
#import "HAGaugeCardCell.h"
#import "HAAlarmEntityCell.h"
#import "HAMediaPlayerEntityCell.h"
#import "HATileEntityCell.h"
#import "HACalendarCardCell.h"
#import "HALogbookCardCell.h"
#import "HATopAlignedFlowLayout.h"
#import "HAHistoryManager.h"
#import "HASunBasedTheme.h"
#import "HAToastView.h"
#import "HAProximityWakeController.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kSectionHeaderReuseId = @"HASectionHeader";

@interface HADashboardViewController () <UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout, HAColumnarLayoutDelegate, HAMasonryLayoutDelegate, HAPanelLayoutDelegate,
    HASidebarLayoutDelegate, HAConnectionManagerDelegate, HAEntityDetailDelegate,
    UIGestureRecognizerDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UISegmentedControl *viewPicker;
@property (nonatomic, strong) UIView *connectionBar;
@property (nonatomic, strong) UILabel *connectionLabel;
@property (nonatomic, strong) NSLayoutConstraint *connectionBarHeight;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) HADashboardConfig *dashboardConfig;
@property (nonatomic, strong) NSSet<NSString *> *conditionEntityIds; // entity IDs used in visibility conditions
@property (nonatomic, strong) HALovelaceDashboard *lovelaceDashboard;
@property (nonatomic, assign) NSUInteger selectedViewIndex;
@property (nonatomic, assign) BOOL statesLoaded;
@property (nonatomic, assign) BOOL lovelaceLoaded;
@property (nonatomic, assign) BOOL lovelaceFetchDone; // YES after fetch succeeds or fails
@property (nonatomic, assign) BOOL usesColumnarLayout;
@property (nonatomic, strong) UITapGestureRecognizer *kioskExitTap;
@property (nonatomic, strong) NSTimer *kioskHideTimer;
@property (nonatomic, strong) HAProximityWakeController *proximityWakeController;
@property (nonatomic, strong) NSLayoutConstraint *viewPickerTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *collectionViewTopToPickerConstraint;
@property (nonatomic, strong) NSLayoutConstraint *collectionViewTopToViewConstraint;
@property (nonatomic, strong) NSLayoutConstraint *collectionViewTopToSafeAreaConstraint;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *pendingReloadPaths;
@property (nonatomic, strong) NSTimer *reloadCoalesceTimer;
@property (nonatomic, strong) CAGradientLayer *backgroundGradient;
@property (nonatomic, strong) HABottomSheetTransitioningDelegate *bottomSheetDelegate;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;
@property (nonatomic, assign) CGPoint lastTapPoint;
@property (nonatomic, strong) HASkeletonView *skeletonView;
@property (nonatomic, strong) UIButton *titleButton;
@property (nonatomic, strong) NSArray<NSDictionary *> *availableDashboards;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSIndexPath *> *> *entityToIndexPaths;
@property (nonatomic, assign) BOOL screenshotScheduled;
@property (nonatomic, strong) HAToastView *kioskToast;
@end

@implementation HADashboardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [HATheme backgroundColor];

    // Gradient background layer (behind everything, shown only in Gradient mode)
    self.backgroundGradient = [CAGradientLayer layer];
    self.backgroundGradient.startPoint = CGPointMake(0, 0);
    self.backgroundGradient.endPoint = CGPointMake(1, 1);
    [self.view.layer insertSublayer:self.backgroundGradient atIndex:0];
    [self applyTheme];

    // Compact nav bar
    if (@available(iOS 11.0, *)) {
        self.navigationController.navigationBar.prefersLargeTitles = NO;
    }

    // Tappable title button — shows current dashboard name with chevron
    self.titleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self updateTitleButtonText:@"Dashboard"];
    self.titleButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleButton.tintColor = [HATheme primaryTextColor];
    [self.titleButton addTarget:self action:@selector(titleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.titleButton sizeToFit];
    UIBarButtonItem *titleItem = [[UIBarButtonItem alloc] initWithCustomView:self.titleButton];
    self.navigationItem.leftBarButtonItem = titleItem;

    // Settings button (gear icon)
    UIBarButtonItem *settingsButton;
    if (@available(iOS 13.0, *)) {
        UIImage *gearImage = [UIImage systemImageNamed:@"gearshape"];
        settingsButton = [[UIBarButtonItem alloc] initWithImage:gearImage style:UIBarButtonItemStylePlain
            target:self action:@selector(settingsTapped)];
    } else {
        // Render MDI cog glyph as a template image for a clean monochrome icon on iOS 9-12
        UIImage *cogImage = [self renderMDIIcon:@"cog" size:22];
        if (cogImage) {
            settingsButton = [[UIBarButtonItem alloc] initWithImage:cogImage style:UIBarButtonItemStylePlain
                target:self action:@selector(settingsTapped)];
        } else {
            settingsButton = [[UIBarButtonItem alloc] initWithTitle:@"Settings"
                style:UIBarButtonItemStylePlain target:self action:@selector(settingsTapped)];
        }
    }
    settingsButton.tintColor = [HATheme primaryTextColor];
    self.navigationItem.rightBarButtonItem = settingsButton;

    [self setupViewPicker];
    [self setupConnectionBar];
    [self setupCollectionView];
    [self setupStatusView];

    // Register cell classes
    [HAEntityCellFactory registerCellClassesWithCollectionView:self.collectionView];

    // Register section header
    [self.collectionView registerClass:[HASectionHeaderView class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:kSectionHeaderReuseId];

    // Kiosk exit gesture: triple-tap anywhere to temporarily show nav bar
    self.kioskExitTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(kioskExitTapped)];
    self.kioskExitTap.numberOfTapsRequired = 3;
    {
        // Invisible tap target at the top of the screen.
        // Inserted BELOW the view picker in z-order so it does not steal
        // touches from the segmented control (which sits at y 68–100).
        UIView *tapArea = [[UIView alloc] init];
        tapArea.translatesAutoresizingMaskIntoConstraints = NO;
        tapArea.backgroundColor = [UIColor clearColor];
        [self.view insertSubview:tapArea belowSubview:self.viewPicker];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[t]|" options:0 metrics:nil views:@{@"t": tapArea}]];
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:tapArea attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:tapArea attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:120]];
        [tapArea addGestureRecognizer:self.kioskExitTap];
    }

    // Bottom sheet delegate for entity detail modals (iOS 9-14)
    self.bottomSheetDelegate = [[HABottomSheetTransitioningDelegate alloc] init];

    // Track tap point for resolving entity rows in composite cards
    UITapGestureRecognizer *tapTracker = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(trackTapPoint:)];
    tapTracker.cancelsTouchesInView = NO;
    tapTracker.delaysTouchesEnded = NO;
    [self.collectionView addGestureRecognizer:tapTracker];

    // Double tap on collection view cells: fires double_tap_action if configured.
    // gestureRecognizerShouldBegin: returns NO when the tapped cell has no
    // double_tap_action, so the gesture fails immediately and single-tap fires
    // with zero delay in the common case.
    self.doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapGesture.numberOfTapsRequired = 2;
    self.doubleTapGesture.delegate = self;
    [self.collectionView addGestureRecognizer:self.doubleTapGesture];

    // Make the collection view's internal tap recognizer wait for double-tap to fail.
    // When gestureRecognizerShouldBegin: returns NO (no double_tap_action), the
    // double-tap fails immediately so single-tap fires with no perceivable delay.
    for (UIGestureRecognizer *gr in self.collectionView.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]] && gr != self.doubleTapGesture) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gr;
            if (tap.numberOfTapsRequired == 1) {
                [tap requireGestureRecognizerToFail:self.doubleTapGesture];
            }
        }
    }

    // Long press on collection view cells: open entity detail
    self.longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.longPressGesture.minimumPressDuration = 0.5;
    [self.collectionView addGestureRecognizer:self.longPressGesture];

    // Listen for entity updates
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    conn.delegate = self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Re-apply theme when returning from Settings (or any pushed VC)
    // to pick up gradient background and cell opacity changes that
    // dynamic colors alone don't cover.
    [self applyTheme];

    [self applyKioskMode];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(entityDidUpdate:)
        name:HAConnectionManagerEntityDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(authDidUpdate:)
        name:HAAuthManagerDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(registriesDidLoad:)
        name:HAConnectionManagerDidReceiveRegistriesNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(themeDidChange:)
        name:HAThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(dashboardListReceived:)
        name:HAConnectionManagerDidReceiveDashboardListNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(actionMoreInfoRequested:)
        name:@"HAActionMoreInfoNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(actionNavigateRequested:)
        name:HAActionNavigateNotification object:nil];

    // Connect if not already
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    if (!conn.isConnected) {
        // Preserve view index across reconnects — save before resetting flags
        NSUInteger savedViewIndex = self.selectedViewIndex;
        self.statesLoaded = NO;
        self.lovelaceLoaded = NO;
        self.lovelaceFetchDone = NO;
        self.selectedViewIndex = savedViewIndex;

        // Cache-first: load cached data for instant launch before connecting
        if ([conn loadCachedStateIfAvailable] && conn.lovelaceDashboard) {
            self.statesLoaded = YES;
            self.lovelaceLoaded = YES;
            self.lovelaceFetchDone = YES;
            self.lovelaceDashboard = conn.lovelaceDashboard;
            [[HASunBasedTheme sharedInstance] start];
            [self rebuildDashboard];
            [self showLoading:NO message:nil];
            // Show subtle "Connecting..." in connection bar while we establish live connection
            [self showConnectionBar:YES message:@"Connecting..."];
        } else {
            HALogI(@"dash", @"Instant launch MISSED — cachedStates=%d, cachedDashboard=%d",
                   (conn.allEntities.count > 0), (conn.lovelaceDashboard != nil));
            [self showLoading:YES message:@"Connecting..."];
        }
        [conn connect];
    } else if (self.statesLoaded) {
        // Returning from a pushed VC (e.g. Settings) with connection still up.
        // Entity store is current (websocket pushes state changes in real time),
        // so just rebuild from cached data — no re-fetch needed.
        [self showLoading:NO message:nil];
        [conn fetchDashboardList];
        [self rebuildDashboard];
    } else {
        [self showLoading:YES message:@"Loading dashboard..."];
        [conn fetchAllStates];
        [conn fetchDashboardList];
        // Fetch Lovelace config — this VC may have been created after the
        // initial connect already fetched it for a previous VC instance.
        NSString *selectedDashboard = [[HAAuthManager sharedManager] selectedDashboardPath];
        [conn fetchLovelaceConfig:selectedDashboard];
    }

    // Seed available dashboards from cache if present
    if (conn.availableDashboards.count > 0) {
        self.availableDashboards = conn.availableDashboards;
        NSString *currentPath = [[HAAuthManager sharedManager] selectedDashboardPath];
        NSString *name = [self dashboardNameForPath:currentPath];
        if (name) [self updateTitleButtonText:name];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // viewWillAppear may fire before the view is in a window on iOS 9 (self.view.window is nil).
    // Start the proximity wake controller now if it wasn't started there.
    if (!self.proximityWakeController
            && [[HAAuthManager sharedManager] isKioskMode]
            && [[HAAuthManager sharedManager] proximityWakeEnabled]) {
        self.proximityWakeController = [[HAProximityWakeController alloc]
            initWithWindow:self.view.window];
        [self.proximityWakeController start];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.kioskHideTimer invalidate];
    self.kioskHideTimer = nil;
    [self.proximityWakeController stop];
    self.proximityWakeController = nil;

    // Restore idle timer and nav bar when leaving dashboard
#if !TARGET_OS_MACCATALYST
    [UIApplication sharedApplication].idleTimerDisabled = NO;
#endif
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.backgroundGradient.frame = self.view.bounds;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [[HAHistoryManager sharedManager] clearCache];
    HALogW(@"dash", @"Memory warning received, caches cleared");
}

- (BOOL)prefersStatusBarHidden {
    return [[HAAuthManager sharedManager] isKioskMode];
}

#pragma mark - Theme

- (void)applyTheme {
    BOOL isGradient = [HATheme isGradientEnabled];
    if (isGradient) {
        self.view.backgroundColor = [HATheme effectiveDarkMode] ? [UIColor blackColor] : [UIColor whiteColor];
        NSArray<UIColor *> *colors = [HATheme gradientColors];
        NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
        for (UIColor *c in colors) [cgColors addObject:(id)c.CGColor];
        self.backgroundGradient.colors = cgColors;
        self.backgroundGradient.hidden = NO;
    } else {
        self.view.backgroundColor = [HATheme backgroundColor];
        self.backgroundGradient.hidden = YES;
    }
    // vImage blur cache for non-Metal devices — capture background for frosted effect
    if (![HATheme canBlur]) {
        if (!self.backgroundGradient.hidden) {
            self.backgroundGradient.frame = self.view.bounds;
            [HATheme updateBlurredGradientFromLayer:self.backgroundGradient size:self.view.bounds.size];
        } else {
            // No gradient — solid fallback will be used (nothing to blur)
            [HATheme updateBlurredGradientFromLayer:nil size:CGSizeZero];
        }
    }
    self.connectionBar.backgroundColor = [HATheme connectionBarColor];
    self.statusLabel.textColor = [HATheme secondaryTextColor];
    self.titleButton.tintColor = [HATheme primaryTextColor];
    self.navigationItem.rightBarButtonItem.tintColor = [HATheme primaryTextColor];

    // On iOS 9-12, manually style the navigation bar since there is no
    // overrideUserInterfaceStyle to drive appearance automatically.
    if (@available(iOS 13.0, *)) {
        // Handled by overrideUserInterfaceStyle set in [HATheme applyInterfaceStyle]
    } else {
        UINavigationBar *navBar = self.navigationController.navigationBar;
        BOOL dark = [HATheme isDarkMode];
        navBar.barStyle = dark ? UIBarStyleBlack : UIBarStyleDefault;
        navBar.barTintColor = dark
            ? [UIColor colorWithRed:0.11 green:0.11 blue:0.13 alpha:1.0]
            : nil;
        navBar.tintColor = [HATheme primaryTextColor];
    }
}

- (void)themeDidChange:(NSNotification *)notification {
    [self applyTheme];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
}

// System appearance changes are now handled globally by HAThemeAwareWindow,
// which posts HAThemeDidChangeNotification — caught by themeDidChange: above.

#pragma mark - UI Setup

- (void)setupConnectionBar {
    self.connectionBar = [[UIView alloc] init];
    self.connectionBar.backgroundColor = [HATheme connectionBarColor];
    self.connectionBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.connectionBar.clipsToBounds = YES;
    [self.view addSubview:self.connectionBar];

    self.connectionLabel = [[UILabel alloc] init];
    self.connectionLabel.font = [UIFont boldSystemFontOfSize:12];
    self.connectionLabel.textColor = [UIColor whiteColor];
    self.connectionLabel.textAlignment = NSTextAlignmentCenter;
    self.connectionLabel.text = @"Disconnected";
    self.connectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.connectionBar addSubview:self.connectionLabel];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.connectionBar attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.connectionBar attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.connectionBar attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:64]];

    self.connectionBarHeight = [NSLayoutConstraint constraintWithItem:self.connectionBar attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:0];
    [self.connectionBar addConstraint:self.connectionBarHeight];

    [self.connectionBar addConstraint:[NSLayoutConstraint constraintWithItem:self.connectionLabel attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.connectionBar attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [self.connectionBar addConstraint:[NSLayoutConstraint constraintWithItem:self.connectionLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.connectionBar attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
}

- (void)showConnectionBar:(BOOL)show message:(NSString *)message {
    self.connectionLabel.text = message;
    CGFloat targetHeight = show ? 24.0 : 0.0;

    if (self.connectionBarHeight.constant == targetHeight) return;

    [UIView animateWithDuration:0.3 animations:^{
        self.connectionBarHeight.constant = targetHeight;
        [self.view layoutIfNeeded];
    }];
}

- (void)setupViewPicker {
    self.viewPicker = [[UISegmentedControl alloc] init];
    self.viewPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.viewPicker.hidden = YES; // Hidden until Lovelace views are loaded
    [self.viewPicker addTarget:self action:@selector(viewPickerChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.viewPicker];

    // Pin below safe area with padding (reduced on iPad to save vertical space)
    CGFloat pickerTopPadding = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 8 : 16;
    if (@available(iOS 11.0, *)) {
        self.viewPickerTopConstraint = [self.viewPicker.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:pickerTopPadding];
    } else {
        self.viewPickerTopConstraint = [self.viewPicker.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:pickerTopPadding];
    }
    [self.view addConstraint:self.viewPickerTopConstraint];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.viewPicker attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:12]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.viewPicker attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:-12]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.viewPicker attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:32]];
}

- (void)setupCollectionView {
    // Start with flow layout; will switch to columnar when sections view is detected
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 6;
    layout.minimumLineSpacing = 6;
    layout.sectionInset = UIEdgeInsetsMake(4, 8, 8, 8);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.collectionView];

    // Pull-to-refresh (UIRefreshControl available since iOS 6)
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
    [self.collectionView addSubview:self.refreshControl];
    self.collectionView.alwaysBounceVertical = YES;

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTrailing multiplier:1 constant:0]];

    // Two competing top constraints: one below picker (normal), one at safe area top (kiosk)
    CGFloat pickerToCollectionGap = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 6 : 12;
    self.collectionViewTopToPickerConstraint = [NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.viewPicker attribute:NSLayoutAttributeBottom multiplier:1 constant:pickerToCollectionGap];
    // Kiosk: pin to safe area top. Section inset adds 4pt internally,
    // so use 12pt here for a total of 16pt (matching side padding).
    if (@available(iOS 11.0, *)) {
        self.collectionViewTopToViewConstraint = [self.collectionView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12];
    } else {
        self.collectionViewTopToViewConstraint = [self.collectionView.topAnchor
            constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:12];
    }
    // No-picker constraint: pin directly to safe area (tight, no gap)
    if (@available(iOS 11.0, *)) {
        self.collectionViewTopToSafeAreaConstraint = [self.collectionView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:0];
    } else {
        self.collectionViewTopToSafeAreaConstraint = [self.collectionView.topAnchor
            constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:0];
    }

    // Only activate the picker constraint initially; the kiosk constraint
    // stays inactive. Using .active alone (not addConstraint:) avoids an
    // iOS 9 bug where addConstraint: activates the constraint regardless
    // of the .active property, causing a "Unable to simultaneously satisfy
    // constraints" warning at launch.
    self.collectionViewTopToPickerConstraint.active = NO;
    self.collectionViewTopToViewConstraint.active = NO;
    self.collectionViewTopToSafeAreaConstraint.active = YES;

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
}

- (void)updateCollectionViewTopConstraintForPicker:(BOOL)pickerVisible {
    BOOL kiosk = [[HAAuthManager sharedManager] isKioskMode];
    self.collectionViewTopToPickerConstraint.active = NO;
    self.collectionViewTopToViewConstraint.active = NO;
    self.collectionViewTopToSafeAreaConstraint.active = NO;

    if (pickerVisible) {
        // Always position below picker when it's visible (including kiosk mode)
        self.collectionViewTopToPickerConstraint.active = YES;
    } else if (kiosk) {
        // Kiosk mode without picker: use view constraint (has 12pt padding)
        self.collectionViewTopToViewConstraint.active = YES;
    } else {
        // Normal mode without picker: pin to safe area
        self.collectionViewTopToSafeAreaConstraint.active = YES;
    }
}

/// Switch the collection view layout based on whether the view uses HA sections (columns)
- (void)applyLayoutForSectionsView:(BOOL)isSections {
    // Check if the current layout is already the correct type (not just the flag).
    // On first call, the collection view has a plain UICollectionViewFlowLayout from init,
    // so we must replace it even when usesColumnarLayout already matches isSections.
    BOOL alreadyCorrect = (isSections == self.usesColumnarLayout) &&
        (isSections ? [self.collectionView.collectionViewLayout isKindOfClass:[HAColumnarLayout class]]
                    : [self.collectionView.collectionViewLayout isKindOfClass:[HATopAlignedFlowLayout class]]);
    if (alreadyCorrect) return;
    self.usesColumnarLayout = isSections;

    if (isSections) {
        HAColumnarLayout *columnar = [[HAColumnarLayout alloc] init];
        columnar.delegate = self;
        columnar.interColumnSpacing = 6.0;
        columnar.interItemSpacing = 6.0;
        columnar.contentInsets = UIEdgeInsetsMake(4, 8, 8, 8);
        [self.collectionView setCollectionViewLayout:columnar animated:NO];
    } else {
        HATopAlignedFlowLayout *flow = [[HATopAlignedFlowLayout alloc] init];
        flow.minimumInteritemSpacing = 6;
        flow.minimumLineSpacing = 6;
        flow.sectionInset = UIEdgeInsetsMake(4, 8, 8, 8);
        [self.collectionView setCollectionViewLayout:flow animated:NO];
    }
}

/// Switch to masonry layout for classic (non-sections) views
- (void)applyMasonryLayout {
    if ([self.collectionView.collectionViewLayout isKindOfClass:[HAMasonryLayout class]]) return;
    self.usesColumnarLayout = NO;
    HAMasonryLayout *masonry = [[HAMasonryLayout alloc] init];
    masonry.delegate = self;
    [self.collectionView setCollectionViewLayout:masonry animated:NO];
}

/// Switch to panel layout for single-card full-bleed views
- (void)applyPanelLayout {
    if ([self.collectionView.collectionViewLayout isKindOfClass:[HAPanelLayout class]]) return;
    self.usesColumnarLayout = NO;
    HAPanelLayout *panel = [[HAPanelLayout alloc] init];
    panel.delegate = self;
    [self.collectionView setCollectionViewLayout:panel animated:NO];
}

/// Flatten the parser's one-section-per-card model into a single section for masonry.
/// All items from all sections are merged into section 0. Section headers are removed.
- (void)flattenConfigForMasonry {
    if (!self.dashboardConfig || self.dashboardConfig.sections.count <= 1) return;

    NSMutableArray<HADashboardConfigItem *> *allItems = [NSMutableArray array];
    for (HADashboardConfigSection *section in self.dashboardConfig.sections) {
        for (HADashboardConfigItem *item in section.items) {
            // Preserve the section reference for composite cards (entities, badges, graph)
            if (!item.entitiesSection) {
                item.entitiesSection = section;
            }
            [allItems addObject:item];
        }
    }

    // Create a single flat section
    HADashboardConfigSection *flatSection = [[HADashboardConfigSection alloc] init];
    flatSection.items = [allItems copy];
    self.dashboardConfig.sections = @[flatSection];
    self.dashboardConfig.items = [allItems copy];
}

/// Switch to sidebar layout for main + sidebar split views
- (void)applySidebarLayout {
    if ([self.collectionView.collectionViewLayout isKindOfClass:[HASidebarLayout class]]) return;
    self.usesColumnarLayout = NO;
    HASidebarLayout *sidebar = [[HASidebarLayout alloc] init];
    sidebar.delegate = self;
    [self.collectionView setCollectionViewLayout:sidebar animated:NO];
}

/// Split cards into main (section 0) and sidebar (section 1) based on view_layout.position.
/// Cards with viewLayoutPosition == "sidebar" go to section 1, others to section 0.
- (void)splitConfigForSidebar {
    if (!self.dashboardConfig) return;

    NSMutableArray<HADashboardConfigItem *> *mainItems = [NSMutableArray array];
    NSMutableArray<HADashboardConfigItem *> *sidebarItems = [NSMutableArray array];

    for (HADashboardConfigSection *section in self.dashboardConfig.sections) {
        BOOL isSidebarCard = [section.customProperties[@"viewLayoutPosition"] isEqualToString:@"sidebar"];
        for (HADashboardConfigItem *item in section.items) {
            if (!item.entitiesSection) {
                item.entitiesSection = section;
            }
            if (isSidebarCard) {
                [sidebarItems addObject:item];
            } else {
                [mainItems addObject:item];
            }
        }
    }

    HADashboardConfigSection *mainSection = [[HADashboardConfigSection alloc] init];
    mainSection.items = [mainItems copy];

    HADashboardConfigSection *sidebarSection = [[HADashboardConfigSection alloc] init];
    sidebarSection.items = [sidebarItems copy];

    NSMutableArray *allItems = [NSMutableArray arrayWithArray:mainItems];
    [allItems addObjectsFromArray:sidebarItems];

    self.dashboardConfig.sections = @[mainSection, sidebarSection];
    self.dashboardConfig.items = [allItems copy];
}

/// Trim config to only the first item (for panel view: single card full-bleed)
- (void)trimConfigForPanel {
    if (!self.dashboardConfig || self.dashboardConfig.sections.count == 0) return;
    HADashboardConfigSection *section = self.dashboardConfig.sections.firstObject;
    if (section.items.count <= 1) return;

    HADashboardConfigItem *firstItem = section.items.firstObject;
    HADashboardConfigSection *trimmedSection = [[HADashboardConfigSection alloc] init];
    trimmedSection.items = @[firstItem];
    trimmedSection.entityIds = section.entityIds;
    self.dashboardConfig.sections = @[trimmedSection];
    self.dashboardConfig.items = @[firstItem];
}

- (void)setupStatusView {
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    self.statusLabel.textColor = [HATheme secondaryTextColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.statusLabel attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.statusLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterY multiplier:1 constant:-20]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.spinner attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.spinner attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.statusLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:12]];
}

- (void)showLoading:(BOOL)loading message:(NSString *)message {
    self.statusLabel.text = message;
    self.collectionView.hidden = loading;

    BOOL showPicker = !loading && self.lovelaceLoaded && (self.lovelaceDashboard.views.count > 1);
    self.viewPicker.hidden = !showPicker;
    [self updateCollectionViewTopConstraintForPicker:showPicker];

    if (loading) {
        // Show skeleton instead of spinner/label
        self.statusLabel.hidden = YES;
        self.spinner.hidden = YES;
        [self.spinner stopAnimating];

        if (!self.skeletonView) {
            self.skeletonView = [[HASkeletonView alloc] init];
            self.skeletonView.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view insertSubview:self.skeletonView belowSubview:self.connectionBar ?: self.view];
            [NSLayoutConstraint activateConstraints:@[
                [self.skeletonView.leadingAnchor constraintEqualToAnchor:self.collectionView.leadingAnchor],
                [self.skeletonView.trailingAnchor constraintEqualToAnchor:self.collectionView.trailingAnchor],
                [self.skeletonView.topAnchor constraintEqualToAnchor:self.collectionView.topAnchor],
                [self.skeletonView.bottomAnchor constraintEqualToAnchor:self.collectionView.bottomAnchor],
            ]];
        }
        self.skeletonView.hidden = NO;
        self.skeletonView.alpha = 1.0;
        [self.skeletonView startAnimating];
    } else {
        self.statusLabel.hidden = YES;
        [self.spinner stopAnimating];

        // Fade out skeleton
        if (self.skeletonView && !self.skeletonView.hidden) {
            [UIView animateWithDuration:0.3 animations:^{
                self.skeletonView.alpha = 0.0;
            } completion:^(BOOL finished) {
                [self.skeletonView stopAnimating];
                self.skeletonView.hidden = YES;
            }];
        }
    }
}

#pragma mark - Section Helpers

- (HADashboardConfigSection *)sectionAtIndex:(NSInteger)index {
    if (!self.dashboardConfig || index < 0 || index >= (NSInteger)self.dashboardConfig.sections.count) {
        return nil;
    }
    return self.dashboardConfig.sections[index];
}

- (HADashboardConfigItem *)itemAtIndexPath:(NSIndexPath *)indexPath {
    HADashboardConfigSection *section = [self sectionAtIndex:indexPath.section];
    if (!section || indexPath.item < 0 || indexPath.item >= (NSInteger)section.items.count) {
        return nil;
    }
    return section.items[indexPath.item];
}

#pragma mark - Item Height

/// Compute the preferred height for an item given its width (used by both flow and columnar layouts)
/// HA sections layout row unit height (matches web UI ~56px per row unit).
static const CGFloat kRowUnitHeight = 56.0;

- (CGFloat)heightForItemAtIndexPath:(NSIndexPath *)indexPath itemWidth:(CGFloat)itemWidth {
    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    HADashboardConfigSection *section = [self sectionAtIndex:indexPath.section];
    HAEntity *entity = [[HAConnectionManager sharedManager] entityForId:item.entityId];

    // Extra height for items that have a heading above the card
    BOOL hasHeading = (item.customProperties[@"headingIcon"] != nil && item.displayName.length > 0);
    CGFloat headingExtra = hasHeading ? [HABaseEntityCell headingHeight] : 0;

    // Compact button/tile cards (inside horizontal-stack) use a fixed small height
    BOOL isCompact = [item.customProperties[@"compact"] boolValue];
    if (isCompact) {
        return [HATileEntityCell compactHeight] + headingExtra;
    }

    // Compute per-card-type height
    CGFloat height;

    if ([item.cardType isEqualToString:@"heading"]) {
        return 36.0; // match section header height (HASectionHeaderView = 36pt)
    } else if ([item.cardType isEqualToString:@"markdown"]) {
        return [HAMarkdownCardCell preferredHeightForConfigItem:item width:itemWidth];
    } else if ([item.cardType isEqualToString:@"badges"]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        NSDictionary *allEntities = [[HAConnectionManager sharedManager] allEntities];
        return [HABadgeRowCell preferredHeightForSection:entSection entities:allEntities width:itemWidth];
    } else if ([item.cardType isEqualToString:@"glance"]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        return [HAGlanceCardCell preferredHeightForSection:entSection width:itemWidth configItem:item] + headingExtra;
    } else if ([item.cardType isEqualToString:@"entities"]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        if (entSection.entityIds.count > 0 || entSection.customProperties[@"sceneEntityIds"]) {
            NSDictionary *allEntities = [[HAConnectionManager sharedManager] allEntities];
            height = [HAEntitiesCardCell preferredHeightForSection:entSection entities:allEntities] + headingExtra;
        } else {
            height = 100.0 + headingExtra;
        }
    } else if ([item.cardType isEqualToString:@"thermostat"]) {
        height = [HAThermostatGaugeCell preferredHeightForWidth:itemWidth] + headingExtra;
    } else if ([item.cardType isEqualToString:@"gauge"]) {
        height = [HAGaugeCardCell preferredHeightForWidth:itemWidth] + headingExtra;
    } else if ([item.cardType isEqualToString:@"graph"] || [item.cardType isEqualToString:@"mini-graph-card"] ||
               [item.cardType isEqualToString:@"history-graph"]) {
        height = [HAGraphCardCell preferredHeight] + headingExtra;
    } else if ([item.cardType isEqualToString:@"calendar"]) {
        NSString *initialView = item.customProperties[@"initial_view"];
        HACalendarViewMode mode = ([initialView hasPrefix:@"list"]) ? HACalendarViewModeList : HACalendarViewModeMonth;
        height = [HACalendarCardCell preferredHeightForMode:mode] + headingExtra;
    } else if ([item.cardType containsString:@"clock-weather"]) {
        NSNumber *rows = item.customProperties[@"forecast_rows"];
        NSInteger forecastRows = rows ? [rows integerValue] : 5;
        height = [HAClockWeatherCell preferredHeightForForecastRows:forecastRows] + headingExtra;
    } else if ([[entity domain] isEqualToString:HAEntityDomainCamera]) {
        NSNumber *customHeight = item.customProperties[@"height"];
        height = customHeight ? [customHeight floatValue] + headingExtra : itemWidth * 0.75 + headingExtra;
    } else if ([[entity domain] isEqualToString:HAEntityDomainVacuum]) {
        height = 160.0 + headingExtra;
    } else if ([[entity domain] isEqualToString:HAEntityDomainWeather]) {
        height = [HAWeatherEntityCell preferredHeight] + headingExtra;
    } else if ([[entity domain] isEqualToString:HAEntityDomainAlarmControlPanel]) {
        BOOL hasKeypad = ([entity alarmCodeFormat] != nil);
        height = (hasKeypad ? [HAAlarmEntityCell preferredHeightWithKeypad]
                            : [HAAlarmEntityCell preferredHeightWithoutKeypad]) + headingExtra;
    } else if ([[entity domain] isEqualToString:HAEntityDomainMediaPlayer]) {
        height = [HAMediaPlayerEntityCell preferredHeight] + headingExtra;
    } else if ([item.cardType isEqualToString:@"tile"]) {
        BOOL isCompact = [item.customProperties[@"compact"] boolValue];
        height = (isCompact ? [HATileEntityCell compactHeight] : [HATileEntityCell preferredHeightForConfigItem:item]) + headingExtra;
    } else if ([item.cardType isEqualToString:@"logbook"]) {
        NSInteger hours = 24;
        if ([item.customProperties[@"hours_to_show"] isKindOfClass:[NSNumber class]]) {
            hours = [item.customProperties[@"hours_to_show"] integerValue];
        }
        height = [HALogbookCardCell preferredHeightForHours:hours] + headingExtra;
    } else {
        height = 100.0 + headingExtra;
    }

    // If grid_options specifies explicit rows, use as minimum height
    if (item.rowSpan > 0) {
        CGFloat interItemSpacing = 6.0;
        CGFloat rowSpanHeight = (item.rowSpan * kRowUnitHeight) + ((item.rowSpan - 1) * interItemSpacing) + headingExtra;
        height = MAX(height, rowSpanHeight);
    }
    return height;
}

#pragma mark - Data

- (NSInteger)currentColumns {
    CGFloat width = self.view.bounds.size.width;
    static const CGFloat kMinColumnWidth = 280.0;
    NSInteger cols = (NSInteger)floor(width / kMinColumnWidth);
    return MAX(cols, 1);
}

/// Remove items from dashboardConfig whose visibilityConditions aren't met.
/// Also collects all condition entity IDs for change detection in entityDidUpdate:.
- (void)filterConditionalItems:(NSDictionary<NSString *, HAEntity *> *)entities {
    if (!self.dashboardConfig) return;

    // Collect all entity IDs used in conditions (before filtering removes them)
    NSMutableSet<NSString *> *condIds = [NSMutableSet set];
    for (HADashboardConfigSection *section in self.dashboardConfig.sections) {
        for (HADashboardConfigItem *item in section.items) {
            for (NSDictionary *cond in item.visibilityConditions) {
                NSString *eid = cond[@"entity"];
                if (eid) [condIds addObject:eid];
            }
        }
    }
    for (HADashboardConfigItem *item in self.dashboardConfig.items) {
        for (NSDictionary *cond in item.visibilityConditions) {
            NSString *eid = cond[@"entity"];
            if (eid) [condIds addObject:eid];
        }
    }
    self.conditionEntityIds = [condIds copy];

    NSMutableArray<HADashboardConfigSection *> *filteredSections = [NSMutableArray array];
    for (HADashboardConfigSection *section in self.dashboardConfig.sections) {
        NSMutableArray<HADashboardConfigItem *> *filteredItems = [NSMutableArray array];
        for (HADashboardConfigItem *item in section.items) {
            if ([self item:item meetsConditions:entities]) {
                [filteredItems addObject:item];
            }
        }
        // Keep section only if it has items (or has a title — empty titled sections are ok as spacers)
        if (filteredItems.count > 0 || section.title.length > 0) {
            HADashboardConfigSection *filtered = [[HADashboardConfigSection alloc] init];
            filtered.title = section.title;
            filtered.icon = section.icon;
            filtered.cardType = section.cardType;
            filtered.entityIds = section.entityIds;
            filtered.nameOverrides = section.nameOverrides;
            filtered.customProperties = section.customProperties;
            filtered.items = filteredItems;
            [filteredSections addObject:filtered];
        }
    }
    // Also filter top-level items
    NSMutableArray<HADashboardConfigItem *> *filteredItems = [NSMutableArray array];
    for (HADashboardConfigItem *item in self.dashboardConfig.items) {
        if ([self item:item meetsConditions:entities]) {
            [filteredItems addObject:item];
        }
    }
    self.dashboardConfig.sections = filteredSections;
    self.dashboardConfig.items = filteredItems;
}

/// Check if item's visibilityConditions are all met. nil conditions = always visible.
- (BOOL)item:(HADashboardConfigItem *)item meetsConditions:(NSDictionary<NSString *, HAEntity *> *)entities {
    NSArray<NSDictionary *> *conditions = item.visibilityConditions;
    if (!conditions || conditions.count == 0) return YES;

    for (NSDictionary *condition in conditions) {
        NSString *entityId = condition[@"entity"];
        NSString *requiredState = condition[@"state"];
        NSString *requiredStateNot = condition[@"state_not"];
        if (!entityId) continue;

        HAEntity *entity = entities[entityId];
        NSString *currentState = entity.state;

        if (requiredState && ![requiredState isEqualToString:currentState ?: @""]) {
            return NO; // state doesn't match
        }
        if (requiredStateNot && [requiredStateNot isEqualToString:currentState ?: @""]) {
            return NO; // state matches the "not" value
        }
    }
    return YES;
}

/// Check if an entity ID is referenced in any visibility condition.
/// Uses the pre-collected set (built before filtering removes hidden items).
- (BOOL)entityUsedInVisibilityConditions:(NSString *)entityId {
    return entityId && [self.conditionEntityIds containsObject:entityId];
}

- (void)rebuildDashboard {
    if (!self.statesLoaded) {
        // The entity store may already have cached entities from loadCachedStateIfAvailable
        // even though statesLoaded is NO (set only by the REST fetchAllStates completion).
        // If we have entities, promote to statesLoaded so we can render immediately
        // rather than showing a white screen until the REST call completes.
        NSUInteger entityCount = [[HAConnectionManager sharedManager] allEntities].count;
        if (entityCount > 0) {
            HALogI(@"dash", @"rebuildDashboard: promoting statesLoaded (have %lu cached entities)", (unsigned long)entityCount);
            self.statesLoaded = YES;
        } else {
            HALogD(@"dash", @"rebuildDashboard: SKIPPED (statesLoaded=NO, lovelaceFetchDone=%d, entities=0)",
                   self.lovelaceFetchDone);
            return;
        }
    }
    // Don't build until we know whether a Lovelace config exists — otherwise
    // we briefly flash the auto-generated "default" entity dump before the
    // real dashboard arrives.
    if (!self.lovelaceFetchDone) return;
    [[HAPerfMonitor sharedMonitor] markRebuildStart];

    NSDictionary<NSString *, HAEntity *> *entities = [[HAConnectionManager sharedManager] allEntities];

    if (self.lovelaceDashboard && self.lovelaceDashboard.views.count > 0) {
        [self buildLovelaceDashboard:entities];
    } else {
        [self buildDefaultDashboardFromEntities:entities];
    }

    // Filter out items whose visibility conditions aren't met
    [self filterConditionalItems:entities];

    // Build reverse lookup map: entityId -> [NSIndexPath, ...]
    [self buildEntityToIndexPathMap];

    [self showLoading:NO message:nil];
    [self showConnectionBar:NO message:nil];
    [self.refreshControl endRefreshing];
    [self.collectionView reloadData];
    [[HAPerfMonitor sharedMonitor] markRebuildEnd];

    // Screenshot trigger: when /tmp/take_screenshot exists, capture after layout settles
    if (!self.screenshotScheduled) {
        NSString *triggerFile = @"/tmp/take_screenshot";
        NSString *outputFile = @"/tmp/screenshot.png";
        if ([[NSFileManager defaultManager] fileExistsAtPath:triggerFile]) {
            self.screenshotScheduled = YES;
            [[NSFileManager defaultManager] removeItemAtPath:triggerFile error:nil];
            HALogD(@"dash", @"Screenshot trigger found, will capture in 3s");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self captureScreenshotToPath:outputFile];
            });
        }
    }
}

- (void)buildEntityToIndexPathMap {
    NSMutableDictionary<NSString *, NSMutableArray<NSIndexPath *> *> *map = [NSMutableDictionary dictionary];

    for (NSUInteger s = 0; s < self.dashboardConfig.sections.count; s++) {
        HADashboardConfigSection *section = self.dashboardConfig.sections[s];

        for (NSUInteger i = 0; i < section.items.count; i++) {
            HADashboardConfigItem *item = section.items[i];
            NSIndexPath *ip = [NSIndexPath indexPathForItem:i inSection:s];

            // Map the item's own entityId
            if (item.entityId) {
                if (!map[item.entityId]) map[item.entityId] = [NSMutableArray array];
                [map[item.entityId] addObject:ip];
            }

            // Map entity IDs from the item's nested entitiesSection
            // (entities cards, badges, graphs store child IDs here)
            HADashboardConfigSection *entSection = item.entitiesSection;
            if (entSection.entityIds.count > 0) {
                for (NSString *eid in entSection.entityIds) {
                    if (!map[eid]) map[eid] = [NSMutableArray array];
                    if (![map[eid] containsObject:ip]) {
                        [map[eid] addObject:ip];
                    }
                }
            }
        }

        // Also map section-level entityIds (used by some layout paths)
        if (section.entityIds.count > 0) {
            NSIndexPath *compositeIP = [NSIndexPath indexPathForItem:0 inSection:s];
            for (NSString *eid in section.entityIds) {
                if (!map[eid]) map[eid] = [NSMutableArray array];
                if (![map[eid] containsObject:compositeIP]) {
                    [map[eid] addObject:compositeIP];
                }
            }
        }
    }

    // Convert mutable arrays to immutable
    NSMutableDictionary<NSString *, NSArray<NSIndexPath *> *> *immutable = [NSMutableDictionary dictionaryWithCapacity:map.count];
    for (NSString *key in map) {
        immutable[key] = [map[key] copy];
    }
    self.entityToIndexPaths = [immutable copy];
}

- (void)buildLovelaceDashboard:(NSDictionary<NSString *, HAEntity *> *)entities {
    HALovelaceView *view = [self.lovelaceDashboard viewAtIndex:self.selectedViewIndex];
    if (!view) return;

    // Update title button: always show dashboard name (view name is in the segmented control)
    NSString *currentPath = [[HAAuthManager sharedManager] selectedDashboardPath];
    NSString *dashName = [self dashboardNameForPath:currentPath];
    if (!dashName) dashName = self.lovelaceDashboard.title;
    if (!dashName) dashName = @"Dashboard";
    [self updateTitleButtonText:dashName];

    // Route layout based on viewType
    BOOL isSections = [view.viewType isEqualToString:@"sections"];
    BOOL isMasonry = [view.viewType isEqualToString:@"masonry"];
    BOOL isPanel = [view.viewType isEqualToString:@"panel"];
    BOOL isSidebar = [view.viewType isEqualToString:@"sidebar"];
    BOOL isIPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);

    // Clear data source and sync the collection view before switching layouts.
    // UIKit's setCollectionViewLayout: reconciles its cached section/item counts
    // against the data source.  If the previous config had a different section
    // structure (e.g. multi-section "sections" view → single-section masonry),
    // the mismatch causes an NSInternalInconsistencyException.  We must nil the
    // config AND call reloadData so UIKit's internal counts match (both zero).
    self.dashboardConfig = nil;
    [self.collectionView reloadData];

    if (isMasonry) {
        // Masonry view: shortest-column-first layout with HA breakpoints
        [self applyMasonryLayout];
    } else if (isPanel) {
        // Panel view: single card full-bleed
        [self applyPanelLayout];
    } else if (isSidebar) {
        // Sidebar view: main + sidebar split
        [self applySidebarLayout];
    } else {
        // Sections view: existing columnar layout
        BOOL useColumnar = isIPad;
        [self applyLayoutForSectionsView:useColumnar];
        if (useColumnar && [self.collectionView.collectionViewLayout isKindOfClass:[HAColumnarLayout class]]) {
            HAColumnarLayout *columnar = (HAColumnarLayout *)self.collectionView.collectionViewLayout;
            columnar.maxColumns = view.maxColumns; // from HA config (0 = default 4)
        }
    }

    self.dashboardConfig = [HALovelaceParser dashboardConfigFromView:view columns:[self currentColumns]];

    // For classic views, flatten all cards into a single section (section 0).
    // The parser produces one section per card, but masonry/panel need all items in one section.
    if (isMasonry) {
        [self flattenConfigForMasonry];
    } else if (isPanel) {
        // Panel: flatten then trim to first card only
        [self flattenConfigForMasonry];
        [self trimConfigForPanel];
    } else if (isSidebar) {
        // Sidebar: split cards into main (section 0) and sidebar (section 1)
        [self splitConfigForSidebar];
    }
}

- (void)buildDefaultDashboardFromEntities:(NSDictionary<NSString *, HAEntity *> *)entities {
    // Use flow layout for default dashboard
    [self applyLayoutForSectionsView:NO];

    NSArray *showDomains = @[
        HAEntityDomainLight, HAEntityDomainSwitch, HAEntityDomainSensor,
        HAEntityDomainBinarySensor, HAEntityDomainClimate, HAEntityDomainCover,
        HAEntityDomainFan, HAEntityDomainLock, HAEntityDomainInputBoolean,
        HAEntityDomainInputNumber, HAEntityDomainInputSelect,
        HAEntityDomainInputDatetime, HAEntityDomainInputText,
        HAEntityDomainCamera, HAEntityDomainWeather,
        HAEntityDomainMediaPlayer,
        HAEntityDomainScene, HAEntityDomainScript,
        HAEntityDomainNumber, HAEntityDomainSelect,
        HAEntityDomainButton, HAEntityDomainInputButton,
        HAEntityDomainHumidifier, HAEntityDomainVacuum,
        HAEntityDomainAlarmControlPanel, HAEntityDomainTimer,
        HAEntityDomainCounter, HAEntityDomainPerson,
        HAEntityDomainSiren, HAEntityDomainUpdate,
    ];
    NSSet *domainSet = [NSSet setWithArray:showDomains];

    // Domain priority for sorting within area cards (lower = first)
    NSDictionary *domainPriority = @{
        HAEntityDomainLight: @0, HAEntityDomainSwitch: @1, HAEntityDomainFan: @2,
        HAEntityDomainCover: @3, HAEntityDomainClimate: @4, HAEntityDomainLock: @5,
        HAEntityDomainInputBoolean: @6, HAEntityDomainSensor: @10, HAEntityDomainBinarySensor: @11,
        HAEntityDomainCamera: @20, HAEntityDomainMediaPlayer: @21,
    };

    // Filter entities: domain whitelist + registry-based filtering
    NSMutableArray<NSString *> *filteredIds = [NSMutableArray array];
    for (HAEntity *entity in entities.allValues) {
        if ([domainSet containsObject:[entity domain]] && [entity shouldShowInDefaultView]) {
            [filteredIds addObject:entity.entityId];
        }
    }

    HAConnectionManager *conn = [HAConnectionManager sharedManager];

    // If registries aren't loaded yet, fall back to flat grid
    if (!conn.registriesLoaded) {
        [filteredIds sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            HAEntity *ea = entities[a];
            HAEntity *eb = entities[b];
            NSComparisonResult domainCmp = [[ea domain] compare:[eb domain]];
            if (domainCmp != NSOrderedSame) return domainCmp;
            return [[ea friendlyName] caseInsensitiveCompare:[eb friendlyName]];
        }];
        self.dashboardConfig = [HADashboardConfig defaultConfigWithEntityIds:filteredIds columns:[self currentColumns]];
        return;
    }

    // Domains rendered as chips instead of entity rows
    NSSet *chipDomains = [NSSet setWithObjects:HAEntityDomainScene, HAEntityDomainScript, nil];

    // Group entities by area, separating scene/script into chip lists
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *areaGroups = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *areaScenes = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *noAreaIds = [NSMutableArray array];

    for (NSString *entityId in filteredIds) {
        HAEntity *entity = entities[entityId];
        NSString *areaName = [conn areaNameForEntityId:entityId];
        BOOL isChip = [chipDomains containsObject:[entity domain]];

        if (areaName) {
            NSMutableDictionary *target = isChip ? areaScenes : areaGroups;
            if (!target[areaName]) {
                target[areaName] = [NSMutableArray array];
            }
            [target[areaName] addObject:entityId];
        } else if (!isChip) {
            [noAreaIds addObject:entityId];
        }
    }

    // Sort entities within each group by domain priority then name
    // Sort entities by friendly name within each area (matching HA overview behavior)
    NSComparator entitySorter = ^NSComparisonResult(NSString *a, NSString *b) {
        HAEntity *ea = entities[a];
        HAEntity *eb = entities[b];
        return [[ea friendlyName] caseInsensitiveCompare:[eb friendlyName]];
    };

    // Build all area cards as items in a single section for flow layout multi-column
    NSMutableArray<HADashboardConfigItem *> *allItems = [NSMutableArray array];

    // Also collect area names that only have scenes (no entity rows) — still need cards for them
    NSMutableSet *allAreaNames = [NSMutableSet setWithArray:[areaGroups allKeys]];
    [allAreaNames addObjectsFromArray:[areaScenes allKeys]];
    NSArray<NSString *> *sortedAreaNames = [[allAreaNames allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];

    for (NSString *areaName in sortedAreaNames) {
        NSMutableArray<NSString *> *ids = areaGroups[areaName] ?: [NSMutableArray array];
        [ids sortUsingComparator:entitySorter];

        // Skip areas with no entity rows and no scenes
        NSArray<NSString *> *sceneIds = areaScenes[areaName];
        if (ids.count == 0 && sceneIds.count == 0) continue;

        HADashboardConfigSection *areaSection = [[HADashboardConfigSection alloc] init];
        areaSection.title = areaName;
        areaSection.entityIds = [ids copy];
        areaSection.cardType = @"entities";
        if (sceneIds.count > 0) {
            NSMutableDictionary *props = [NSMutableDictionary dictionary];
            props[@"sceneEntityIds"] = sceneIds;
            // Pre-compute display names with area prefix stripped
            NSMutableDictionary *chipNames = [NSMutableDictionary dictionaryWithCapacity:sceneIds.count];
            for (NSString *sid in sceneIds) {
                HAEntity *scene = entities[sid];
                NSString *name = [scene friendlyName];
                if (areaName.length > 0 && name.length >= areaName.length) {
                    NSString *namePrefix = [name substringToIndex:areaName.length];
                    if ([namePrefix localizedCaseInsensitiveCompare:areaName] == NSOrderedSame) {
                        NSString *stripped = [[name substringFromIndex:areaName.length]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        if (stripped.length > 0) name = stripped;
                    }
                }
                chipNames[sid] = name;
            }
            props[@"sceneChipNames"] = chipNames;
            areaSection.customProperties = [props copy];
        }

        HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
        item.entityId = ids.firstObject ?: sceneIds.firstObject;
        item.cardType = @"entities";
        item.columnSpan = 1;
        item.entitiesSection = areaSection;
        [allItems addObject:item];
    }

    // "Other" group for entities without area assignment
    if (noAreaIds.count > 0) {
        [noAreaIds sortUsingComparator:entitySorter];

        HADashboardConfigSection *otherSection = [[HADashboardConfigSection alloc] init];
        otherSection.title = @"Other";
        otherSection.entityIds = [noAreaIds copy];
        otherSection.cardType = @"entities";

        HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
        item.entityId = noAreaIds.firstObject;
        item.cardType = @"entities";
        item.columnSpan = 1;
        item.entitiesSection = otherSection;
        [allItems addObject:item];
    }

    // Wrap all items in a single section so flow layout arranges them in columns
    HADashboardConfigSection *wrapperSection = [[HADashboardConfigSection alloc] init];
    wrapperSection.items = [allItems copy];

    HADashboardConfig *config = [[HADashboardConfig alloc] init];
    config.title = @"Dashboard";
    config.columns = [self currentColumns];
    config.sections = @[wrapperSection];
    config.items = [allItems copy];

    self.dashboardConfig = config;
}

- (void)populateViewPicker {
    [self.viewPicker removeAllSegments];

    if (!self.lovelaceDashboard || self.lovelaceDashboard.views.count <= 1) {
        self.viewPicker.hidden = YES;
        return;
    }

    for (NSUInteger i = 0; i < self.lovelaceDashboard.views.count; i++) {
        HALovelaceView *view = self.lovelaceDashboard.views[i];
        [self.viewPicker insertSegmentWithTitle:view.title atIndex:i animated:NO];
    }

    self.viewPicker.selectedSegmentIndex = (NSInteger)self.selectedViewIndex;
    self.viewPicker.hidden = NO;
}

#pragma mark - Kiosk Mode

- (void)applyKioskMode {
    BOOL kiosk = [[HAAuthManager sharedManager] isKioskMode];
    BOOL wakeOnTouch = kiosk && [[HAAuthManager sharedManager] proximityWakeEnabled];

    if (wakeOnTouch) {
        if (!self.proximityWakeController && self.view.window) {
            self.proximityWakeController = [[HAProximityWakeController alloc]
                initWithWindow:self.view.window];
            [self.proximityWakeController start];
        }
    } else {
        [self.proximityWakeController stop];
        self.proximityWakeController = nil;
    }
#if !TARGET_OS_MACCATALYST
    [UIApplication sharedApplication].idleTimerDisabled = kiosk;
#endif
    [self.navigationController setNavigationBarHidden:kiosk animated:YES];
    [self setNeedsStatusBarAppearanceUpdate];
    // Also use UIApplication method for iOS 9 compatibility where
    // childViewControllerForStatusBarHidden may not be respected.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[UIApplication sharedApplication] setStatusBarHidden:kiosk withAnimation:UIStatusBarAnimationSlide];
#pragma clang diagnostic pop
    BOOL showPicker = !kiosk && self.lovelaceLoaded && (self.lovelaceDashboard.views.count > 1);
    self.viewPicker.hidden = !showPicker;
    [self updateCollectionViewTopConstraintForPicker:showPicker];
    [self.view layoutIfNeeded];

    if (kiosk) {
        // Delay slightly so the view hierarchy is fully laid out before
        // computing safe-area insets and animating. Fixes the toast not
        // appearing on iOS 9 devices where viewWillAppear fires before
        // the view has a final frame.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showKioskToast];
        });
    } else {
        [self dismissKioskToast];
    }
}

- (void)showKioskToast {
    if (self.kioskToast && self.kioskToast.superview) return;
    __weak typeof(self) weakSelf = self;
    self.kioskToast = [HAToastView showInView:self.view
        message:@"Kiosk mode is on. Triple-tap the top of the screen to exit."
        subtitle:@"Tap to open Settings"
        duration:5.0
        tapAction:^{
            [weakSelf.navigationController setNavigationBarHidden:NO animated:NO];
            [weakSelf settingsTapped];
        }];
}

- (void)dismissKioskToast {
    [self.kioskToast dismiss];
    self.kioskToast = nil;
}

- (void)kioskExitTapped {
    if (![[HAAuthManager sharedManager] isKioskMode]) return;
    // Temporarily show nav bar and restore normal layout
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    BOOL showPicker = self.lovelaceLoaded && (self.lovelaceDashboard.views.count > 1);
    [self updateCollectionViewTopConstraintForPicker:showPicker];
    [UIView animateWithDuration:0.3 animations:^{
        [self.view layoutIfNeeded];
    }];
    [self.kioskHideTimer invalidate];
    self.kioskHideTimer = [NSTimer scheduledTimerWithTimeInterval:8.0
                                                          target:self
                                                        selector:@selector(kioskHideTimerFired)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)kioskHideTimerFired {
    if ([[HAAuthManager sharedManager] isKioskMode]) {
        [self.navigationController setNavigationBarHidden:YES animated:YES];
        self.collectionViewTopToPickerConstraint.active = NO;
        self.collectionViewTopToViewConstraint.active = YES;
        [UIView animateWithDuration:0.3 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
}

- (void)authDidUpdate:(NSNotification *)notification {
    [self applyKioskMode];
}

/// Renders an MDI glyph as a template UIImage suitable for UIBarButtonItem.
- (UIImage *)renderMDIIcon:(NSString *)name size:(CGFloat)size {
    NSString *glyph = [HAIconMapper glyphForIconName:name];
    if (!glyph) return nil;
    UIFont *font = [HAIconMapper mdiFontOfSize:size];
    NSDictionary *attrs = @{NSFontAttributeName: font,
                            NSForegroundColorAttributeName: [UIColor blackColor]};
    CGSize textSize = [glyph sizeWithAttributes:attrs];
    UIGraphicsBeginImageContextWithOptions(textSize, NO, 0);
    [glyph drawAtPoint:CGPointZero withAttributes:attrs];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - Actions

- (void)settingsTapped {
    HASettingsViewController *settings = [[HASettingsViewController alloc] init];
    [self.navigationController pushViewController:settings animated:YES];
}

#pragma mark - Title Dashboard Switcher

- (void)updateTitleButtonText:(NSString *)name {
    NSString *display = (name.length > 0) ? name : @"Dashboard";
    [self.titleButton setTitle:[NSString stringWithFormat:@"%@ \u25BE", display] forState:UIControlStateNormal];
    [self.titleButton sizeToFit];
}

- (NSString *)dashboardNameForPath:(NSString *)path {
    for (NSDictionary *d in self.availableDashboards) {
        NSString *urlPath = d[@"url_path"];
        if ([urlPath isEqualToString:path] || (urlPath == nil && path == nil)) {
            return d[@"title"] ?: @"Dashboard";
        }
    }
    return nil;
}

- (void)titleTapped:(UIButton *)sender {
    if (!self.availableDashboards || self.availableDashboards.count <= 1) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *currentPath = [[HAAuthManager sharedManager] selectedDashboardPath];

    for (NSDictionary *dashboard in self.availableDashboards) {
        NSString *title = dashboard[@"title"] ?: @"Untitled";
        NSString *urlPath = dashboard[@"url_path"];

        BOOL isSelected = [urlPath isEqualToString:currentPath] ||
                          (urlPath == nil && currentPath == nil);
        NSString *displayTitle = isSelected ? [NSString stringWithFormat:@"\u2713 %@", title] : title;

        UIAlertAction *action = [UIAlertAction actionWithTitle:displayTitle
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *a) {
            [self switchToDashboard:urlPath title:title];
        }];
        [alert addAction:action];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // iPad: present as popover from title button
    alert.popoverPresentationController.sourceView = self.titleButton;
    alert.popoverPresentationController.sourceRect = self.titleButton.bounds;

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)switchToDashboard:(NSString *)urlPath title:(NSString *)title {
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:urlPath];
    [self updateTitleButtonText:title];

    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    if (conn.isConnected) {
        [self showLoading:YES message:@"Loading dashboard..."];
        [conn fetchLovelaceConfig:urlPath];
    }
}

- (void)dashboardListReceived:(NSNotification *)notification {
    NSArray *dashboards = notification.userInfo[@"dashboards"];
    if (dashboards) {
        self.availableDashboards = dashboards;
        // Update title to match current selection name
        NSString *currentPath = [[HAAuthManager sharedManager] selectedDashboardPath];
        NSString *name = [self dashboardNameForPath:currentPath];
        if (name) {
            [self updateTitleButtonText:name];
        }
    }
}

- (void)pullToRefresh:(UIRefreshControl *)sender {
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    if (conn.isConnected) {
        [conn fetchAllStates];
        // Preserve the user's selected dashboard — passing nil resets to default
        NSString *currentDashboard = [[HAAuthManager sharedManager] selectedDashboardPath];
        [conn fetchLovelaceConfig:currentDashboard];
    } else {
        [conn connect];
    }
}

- (void)viewPickerChanged:(UISegmentedControl *)sender {
    [HAHaptics selectionChanged];
    self.selectedViewIndex = (NSUInteger)sender.selectedSegmentIndex;
    [self rebuildDashboard];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.dashboardConfig ? (NSInteger)self.dashboardConfig.sections.count : 0;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    HADashboardConfigSection *configSection = [self sectionAtIndex:section];
    return configSection ? (NSInteger)configSection.items.count : 0;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
    cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    HADashboardConfigSection *section = [self sectionAtIndex:indexPath.section];
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    HAEntity *entity = [conn entityForId:item.entityId];
    NSDictionary *allEntities = [conn allEntities];

    NSString *reuseId = [HAEntityCellFactory reuseIdentifierForEntity:entity cardType:item.cardType];
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseId forIndexPath:indexPath];
    [[HAPerfMonitor sharedMonitor] markCellStart:reuseId];

    if ([cell isKindOfClass:[HAGaugeCardCell class]]) {
        [(HAGaugeCardCell *)cell configureWithEntity:entity configItem:item];
    } else if ([cell isKindOfClass:[HAHeadingCell class]]) {
        [(HAHeadingCell *)cell configureWithItem:item];
    } else if ([cell isKindOfClass:[HAMarkdownCardCell class]]) {
        [(HAMarkdownCardCell *)cell configureWithConfigItem:item];
    } else if ([cell isKindOfClass:[HABadgeRowCell class]]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        [(HABadgeRowCell *)cell configureWithSection:entSection entities:allEntities];
        __weak typeof(self) weakSelf = self;
        ((HABadgeRowCell *)cell).entityTapBlock = ^(HAEntity *tappedEntity) {
            // Badges default to more-info (no per-badge action config yet)
            [weakSelf executeActionType:@"tap_action" forEntity:tappedEntity configProperties:item.customProperties];
        };
    } else if ([cell isKindOfClass:[HAGlanceCardCell class]]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        [(HAGlanceCardCell *)cell configureWithSection:entSection entities:allEntities configItem:item];
        __weak typeof(self) weakSelf = self;
        ((HAGlanceCardCell *)cell).entityTapBlock = ^(HAEntity *tappedEntity, NSDictionary *actionConfig) {
            // Use per-entity action config if available, fall back to card-level
            NSDictionary *props = actionConfig ?: item.customProperties;
            [weakSelf executeActionType:@"tap_action" forEntity:tappedEntity configProperties:props];
        };
    } else if ([cell isKindOfClass:[HAGraphCardCell class]]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        if (entSection.entityIds.count > 0) {
            [(HAGraphCardCell *)cell configureWithSection:entSection entities:allEntities];
        } else {
            [(HAGraphCardCell *)cell configureWithEntity:entity item:item];
        }
    } else if ([cell isKindOfClass:[HAEntitiesCardCell class]]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        [(HAEntitiesCardCell *)cell configureWithSection:entSection entities:allEntities configItem:item];
        __weak typeof(self) weakSelf = self;
        ((HAEntitiesCardCell *)cell).entityTapBlock = ^(HAEntity *tappedEntity) {
            [weakSelf presentEntityDetail:tappedEntity];
        };
    } else if ([cell isKindOfClass:[HACalendarCardCell class]]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: section;
        NSArray *calEntityIds = entSection.entityIds.count > 0 ? entSection.entityIds : (item.entityId ? @[item.entityId] : @[]);
        [(HACalendarCardCell *)cell configureWithEntityIds:calEntityIds configItem:item];
    } else if ([cell isKindOfClass:[HABaseEntityCell class]]) {
        [(HABaseEntityCell *)cell configureWithEntity:entity configItem:item];
    }

    // Apply blur background here for iOS 9 compatibility.
    // On iOS 9, willDisplayCell may not fire for initially visible cells.
    [self applyBlurBackgroundToCell:cell];

    [[HAPerfMonitor sharedMonitor] markCellEnd];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {

    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        HASectionHeaderView *header = (HASectionHeaderView *)[collectionView
            dequeueReusableSupplementaryViewOfKind:kind
                              withReuseIdentifier:kSectionHeaderReuseId
                                     forIndexPath:indexPath];

        HADashboardConfigSection *configSection = [self sectionAtIndex:indexPath.section];
        [header configureWithSection:configSection];

        return header;
    }

    return [[UICollectionReusableView alloc] init];
}

#pragma mark - Visibility-Based Loading

- (void)applyBlurBackgroundToCell:(UICollectionViewCell *)cell {
    BOOL isCard = (cell.contentView.layer.cornerRadius > 0);
    if (!isCard) {
        if (cell.backgroundView) cell.backgroundView = nil;
        return;
    }

    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.contentView.opaque = NO;

    // Update existing backgroundView in-place when possible (avoids alloc on A5).
    // Only allocate a new view when the type doesn't match the current blur mode.
    [HATheme updateFrostedBackgroundForCell:cell];

    if ([cell.backgroundView isKindOfClass:[UIImageView class]]) {
        CGSize viewSize = self.view.bounds.size;
        if (viewSize.width > 0 && viewSize.height > 0) {
            CGRect cellFrame = [cell.superview convertRect:cell.frame toView:self.view];
            ((UIImageView *)cell.backgroundView).layer.contentsRect = CGRectMake(
                cellFrame.origin.x / viewSize.width,
                cellFrame.origin.y / viewSize.height,
                cellFrame.size.width / viewSize.width,
                cellFrame.size.height / viewSize.height);
        }
    }
}

- (void)collectionView:(UICollectionView *)collectionView
       willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {
    // Trigger deferred network fetches when cell becomes visible
    if ([cell isKindOfClass:[HAGraphCardCell class]]) {
        [(HAGraphCardCell *)cell beginLoading];
    } else if ([cell isKindOfClass:[HACameraEntityCell class]]) {
        [(HACameraEntityCell *)cell beginLoading];
    } else if ([cell isKindOfClass:[HACalendarCardCell class]]) {
        [(HACalendarCardCell *)cell beginLoading];
    } else if ([cell isKindOfClass:[HALogbookCardCell class]]) {
        [(HALogbookCardCell *)cell beginLoading];
    }

    // Apply blur background (idempotent — safe to call from both cellForItem and willDisplay)
    [self applyBlurBackgroundToCell:cell];

    // Rasterize static cells for faster scrolling (caches rendered bitmap).
    // Skip camera cells (content updates frequently) and blur cells
    // (shouldRasterize bakes the blur into a static bitmap, breaking compositing).
    BOOL isCamera = [cell isKindOfClass:[HACameraEntityCell class]];
    BOOL isBadge = [cell isKindOfClass:[HABadgeRowCell class]];
    BOOL isCard = (cell.contentView.layer.cornerRadius > 0);
    cell.layer.shouldRasterize = !isCamera && !isCard && !isBadge;
    cell.layer.rasterizationScale = [UIScreen mainScreen].scale;
}

- (void)collectionView:(UICollectionView *)collectionView
  didEndDisplayingCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {
    // Cancel pending network requests when cell scrolls off screen
    if ([cell isKindOfClass:[HAGraphCardCell class]]) {
        [(HAGraphCardCell *)cell cancelLoading];
    } else if ([cell isKindOfClass:[HACameraEntityCell class]]) {
        [(HACameraEntityCell *)cell cancelLoading];
    } else if ([cell isKindOfClass:[HACalendarCardCell class]]) {
        [(HACalendarCardCell *)cell cancelLoading];
    }
}

#pragma mark - HAColumnarLayoutDelegate

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath
                itemWidth:(CGFloat)itemWidth {
    return [self heightForItemAtIndexPath:indexPath itemWidth:itemWidth];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)layout
  gridColumnsForItemAtIndexPath:(NSIndexPath *)indexPath {
    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    return item ? item.columnSpan : 12;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
heightForHeaderInSection:(NSInteger)section {
    HADashboardConfigSection *configSection = [self sectionAtIndex:section];
    return (configSection.title.length > 0) ? 36.0 : 0.0;
}

- (BOOL)collectionView:(UICollectionView *)collectionView
                 layout:(UICollectionViewLayout *)layout
  isHeadingItemAtIndexPath:(NSIndexPath *)indexPath {
    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    return [item.cardType isEqualToString:@"heading"];
}

#pragma mark - HAMasonryLayoutDelegate

- (NSString *)collectionView:(UICollectionView *)collectionView
                      layout:(UICollectionViewLayout *)layout
     cardTypeForItemAtIndexPath:(NSIndexPath *)indexPath {
    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    return item.cardType;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)layout
  entityCountForItemAtIndexPath:(NSIndexPath *)indexPath {
    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    HADashboardConfigSection *section = item.entitiesSection ?: [self sectionAtIndex:indexPath.section];
    return (NSInteger)section.entityIds.count;
}

#pragma mark - UICollectionViewDelegateFlowLayout (for non-sections views)

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {

    if (![collectionViewLayout isKindOfClass:[UICollectionViewFlowLayout class]]) {
        return CGSizeMake(100, 100); // Shouldn't reach here for columnar
    }

    UICollectionViewFlowLayout *flow = (UICollectionViewFlowLayout *)collectionViewLayout;
    CGFloat totalWidth = collectionView.bounds.size.width - flow.sectionInset.left - flow.sectionInset.right;
    CGFloat interitemSpacing = flow.minimumInteritemSpacing;

    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    HADashboardConfigSection *section = [self sectionAtIndex:indexPath.section];

    // Use 12-column sub-grid system (matching columnar layout).
    // Calculate cell width proportionally: each column = (totalWidth - 11*spacing) / 12,
    // then an item spanning N columns = N * colWidth + (N-1) * spacing.
    // This handles mixed spans (e.g. 9+3 side-by-side) correctly.
    NSInteger gridSpan = item.columnSpan;
    if (gridSpan <= 0 || gridSpan > 12) gridSpan = 12;

    CGFloat cellWidth;
    if (gridSpan >= 12) {
        cellWidth = totalWidth;
    } else {
        CGFloat colWidth = (totalWidth - 11.0 * interitemSpacing) / 12.0;
        cellWidth = floor(gridSpan * colWidth + (gridSpan - 1) * interitemSpacing);
    }

    CGFloat cellHeight = [self heightForItemAtIndexPath:indexPath itemWidth:cellWidth];
    return CGSizeMake(cellWidth, cellHeight);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout
    referenceSizeForHeaderInSection:(NSInteger)section {

    HADashboardConfigSection *configSection = [self sectionAtIndex:section];
    if (configSection.title.length > 0) {
        return CGSizeMake(collectionView.bounds.size.width, 40);
    }
    return CGSizeZero;
}

#pragma mark - UICollectionViewDelegate

- (void)trackTapPoint:(UITapGestureRecognizer *)gesture {
    self.lastTapPoint = [gesture locationInView:self.collectionView];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    if (!item) return;

    NSString *ct = item.cardType;

    // Entities card: resolve which entity row was tapped
    if ([ct isEqualToString:@"entities"]) {
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        if ([cell isKindOfClass:[HAEntitiesCardCell class]]) {
            HAEntitiesCardCell *entCell = (HAEntitiesCardCell *)cell;
            CGPoint cellPoint = [collectionView convertPoint:self.lastTapPoint toView:entCell];
            for (HAEntityRowView *row in entCell.rowViews) {
                if (CGRectContainsPoint(row.frame, [entCell.stackView convertPoint:cellPoint fromView:entCell])) {
                    if (row.entity) {
                        [self executeActionType:@"tap_action" forEntity:row.entity configProperties:row.actionConfig ?: item.customProperties];
                        return;
                    }
                }
            }
        }
        return;
    }

    // Badges: handled by HABadgeRowCell's own tap gestures
    if ([ct isEqualToString:@"badges"]) return;

    // Glance: handled by HAGlanceCardCell's own tap gestures
    if ([ct isEqualToString:@"glance"]) return;

    // Graph cards: resolve primary entity from section
    if ([ct isEqualToString:@"graph"]) return;

    // Calendar card: interactions handled internally
    if ([ct isEqualToString:@"calendar"]) return;

    HAEntity *entity = [[HAConnectionManager sharedManager] entityForId:item.entityId];
    if (!entity) return;

    [self executeActionType:@"tap_action" forEntity:entity configProperties:item.customProperties];
}

/// Resolve and execute an action (tap_action, hold_action, double_tap_action) for an entity.
/// Falls back to domain-default behavior when no action is configured.
- (void)executeActionType:(NSString *)actionType
                forEntity:(HAEntity *)entity
         configProperties:(NSDictionary *)props {
    // Check for configured action
    NSDictionary *actionDict = props[actionType];
    HAAction *action = [HAAction actionFromDictionary:actionDict];

    // No configured action: apply defaults matching previous hardcoded behavior
    if (!action) {
        if ([actionType isEqualToString:@"tap_action"]) {
            action = [HAAction defaultTapActionForEntity:entity];
        } else if ([actionType isEqualToString:@"hold_action"]) {
            action = [HAAction defaultHoldAction];
        } else {
            // double_tap: no default (no-op)
            return;
        }
    }

    [[HAActionDispatcher sharedDispatcher] executeAction:action
                                              forEntity:entity
                                     fromViewController:self];
}

- (void)presentEntityDetail:(HAEntity *)entity {
    HAEntityDetailViewController *detail = [[HAEntityDetailViewController alloc] init];
    detail.entity = entity;
    detail.delegate = self;
    [self presentGraphDetail:detail];
}

- (void)presentGraphDetail:(HAEntityDetailViewController *)detail {
    if (@available(iOS 15.0, *)) {
        detail.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sheet = detail.sheetPresentationController;
        sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    } else {
        detail.modalPresentationStyle = UIModalPresentationCustom;
        detail.transitioningDelegate = self.bottomSheetDelegate;
    }

    [HAHaptics lightImpact];
    [self presentViewController:detail animated:YES completion:nil];
}

#pragma mark - Action Notification Handlers

- (void)actionMoreInfoRequested:(NSNotification *)note {
    HAEntity *entity = note.userInfo[@"entity"];
    if (entity) {
        [self presentEntityDetail:entity];
    }
}

- (void)actionNavigateRequested:(NSNotification *)note {
    NSString *path = note.userInfo[@"path"];
    if (!path) return;

    // Navigate to a view within the current dashboard.
    // Path format: "/lovelace/view-path" or just "view-path"
    // Strip leading dashboard path to get view path/index.
    NSString *viewPath = [path lastPathComponent];

    HALovelaceDashboard *dashboard = [HAConnectionManager sharedManager].lovelaceDashboard;
    if (!dashboard) return;

    // Try to find view by path
    for (NSUInteger i = 0; i < dashboard.views.count; i++) {
        HALovelaceView *view = dashboard.views[i];
        if ([view.path isEqualToString:viewPath] ||
            [view.title.lowercaseString isEqualToString:viewPath.lowercaseString]) {
            self.selectedViewIndex = i;
            self.viewPicker.selectedSegmentIndex = (NSInteger)i;
            [self rebuildDashboard];
            return;
        }
    }

    // Try as numeric index
    NSInteger idx = [viewPath integerValue];
    if (idx > 0 && (NSUInteger)idx < dashboard.views.count) {
        self.selectedViewIndex = (NSUInteger)idx;
        self.viewPicker.selectedSegmentIndex = (NSInteger)idx;
        [self rebuildDashboard];
    }
}

#pragma mark - Double Tap

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
    if (!indexPath) return;

    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    if (!item) return;

    // Only fire if double_tap_action is actually configured
    NSDictionary *doubleTapConfig = item.customProperties[@"double_tap_action"];
    if (!doubleTapConfig) return;

    HAEntity *entity = [[HAConnectionManager sharedManager] entityForId:item.entityId];
    [self executeActionType:@"double_tap_action" forEntity:entity configProperties:item.customProperties];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.doubleTapGesture) return YES;

    // Only allow the double-tap gesture to begin if the tapped cell has
    // double_tap_action configured. Otherwise fail immediately so the
    // single-tap fires without any delay.
    CGPoint point = [gestureRecognizer locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
    if (!indexPath) return NO;

    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    if (!item) return NO;

    return item.customProperties[@"double_tap_action"] != nil;
}

#pragma mark - Long Press (Quick Toggle)

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    CGPoint point = [gesture locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
    if (!indexPath) return;

    HADashboardConfigItem *item = [self itemAtIndexPath:indexPath];
    if (!item) return;

    // Graph cards: resolve entities from section and pass multi-entity info
    NSString *ct = item.cardType;
    if ([ct isEqualToString:@"graph"] || [ct isEqualToString:@"history-graph"] || [ct isEqualToString:@"mini-graph-card"]) {
        HADashboardConfigSection *entSection = item.entitiesSection ?: (HADashboardConfigSection *)item;
        NSArray *entityIds = entSection.entityIds;
        if (!entityIds.count) {
            if (item.entityId) entityIds = @[item.entityId];
            else return;
        }
        NSDictionary *allEntities = [[HAConnectionManager sharedManager] allEntities];
        NSArray *entityConfigs = entSection.customProperties[@"entityConfigs"];

        // Same color palette as HAGraphCardCell
        static NSArray<UIColor *> *palette;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            palette = @[
                [UIColor colorWithRed:0.30 green:0.60 blue:1.00 alpha:1.0], // Blue
                [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0], // Red
                [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0], // Green
                [UIColor colorWithRed:1.00 green:0.60 blue:0.00 alpha:1.0], // Orange
                [UIColor colorWithRed:0.60 green:0.30 blue:0.90 alpha:1.0], // Purple
                [UIColor colorWithRed:0.00 green:0.80 blue:0.70 alpha:1.0], // Teal
                [UIColor colorWithRed:0.90 green:0.40 blue:0.70 alpha:1.0], // Pink
                [UIColor colorWithRed:1.00 green:0.85 blue:0.00 alpha:1.0], // Yellow
            ];
        });

        // Filter entities by show_graph config (matches HAGraphCardCell logic)
        NSMutableArray *graphEntities = [NSMutableArray array];
        for (NSUInteger i = 0; i < entityIds.count; i++) {
            NSString *eid = entityIds[i];
            NSDictionary *cfg = (i < entityConfigs.count && [entityConfigs[i] isKindOfClass:[NSDictionary class]]) ? entityConfigs[i] : nil;

            BOOL showGraph = YES;
            if (cfg[@"show_graph"]) showGraph = [cfg[@"show_graph"] boolValue];
            if (!showGraph) continue;

            HAEntity *entity = allEntities[eid];
            if (!entity) continue;

            // Color: per-entity override or auto-assign from palette
            UIColor *color = nil;
            if (cfg[@"color"]) {
                if ([cfg[@"color"] isKindOfClass:[UIColor class]]) color = cfg[@"color"];
                else if ([cfg[@"color"] isKindOfClass:[NSString class]]) color = [HATheme colorFromString:cfg[@"color"]];
            }
            if (!color) color = palette[graphEntities.count % palette.count];

            NSString *label = [cfg[@"name"] isKindOfClass:[NSString class]] ? cfg[@"name"] : (entSection.nameOverrides[eid] ?: entity.friendlyName ?: eid);
            NSString *unit = entity.unitOfMeasurement ?: @"";

            [graphEntities addObject:@{
                @"entityId": eid,
                @"color": color,
                @"label": label,
                @"unit": unit,
            }];
        }

        // Fallback: if no entities pass filter, use first
        if (graphEntities.count == 0 && entityIds.count > 0) {
            HAEntity *entity = allEntities[entityIds.firstObject];
            if (entity) {
                [graphEntities addObject:@{
                    @"entityId": entityIds.firstObject,
                    @"color": palette[0],
                    @"label": entity.friendlyName ?: entityIds.firstObject,
                    @"unit": entity.unitOfMeasurement ?: @"",
                }];
            }
        }

        HAEntity *primaryEntity = allEntities[((NSDictionary *)graphEntities.firstObject)[@"entityId"]];
        if (!primaryEntity) return;

        [HAHaptics mediumImpact];

        HAEntityDetailViewController *detail = [[HAEntityDetailViewController alloc] init];
        detail.entity = primaryEntity;
        detail.delegate = self;

        if (graphEntities.count > 1) {
            detail.graphEntities = graphEntities;
            detail.graphTitle = entSection.title ?: primaryEntity.friendlyName;
        }

        // Pass hours_to_show from card config
        NSNumber *hoursToShow = entSection.customProperties[@"hours_to_show"];
        if ([hoursToShow isKindOfClass:[NSNumber class]]) {
            detail.hoursToShow = [hoursToShow integerValue];
        }

        [self presentGraphDetail:detail];
        return;
    }

    // Entities card: resolve which entity row was long-pressed
    if ([ct isEqualToString:@"entities"]) {
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        if ([cell isKindOfClass:[HAEntitiesCardCell class]]) {
            HAEntitiesCardCell *entCell = (HAEntitiesCardCell *)cell;
            CGPoint cellPoint = [self.collectionView convertPoint:point toView:entCell];
            for (HAEntityRowView *row in entCell.rowViews) {
                if (CGRectContainsPoint(row.frame, [entCell.stackView convertPoint:cellPoint fromView:entCell])) {
                    if (row.entity) {
                        [self executeActionType:@"hold_action" forEntity:row.entity configProperties:row.actionConfig ?: item.customProperties];
                        return;
                    }
                }
            }
        }
        return;
    }

    // Badges card: handled by HABadgeRowCell's own gesture recognizers
    if ([ct isEqualToString:@"badges"]) return;

    // Glance card: handled by HAGlanceCardCell's own gesture recognizers
    if ([ct isEqualToString:@"glance"]) return;

    // Calendar card: no entity detail for calendar entities
    if ([ct isEqualToString:@"calendar"]) return;

    HAEntity *entity = [[HAConnectionManager sharedManager] entityForId:item.entityId];
    if (!entity) return;

    [self executeActionType:@"hold_action" forEntity:entity configProperties:item.customProperties];
}

#pragma mark - HAEntityDetailDelegate

- (void)entityDetail:(HAEntityDetailViewController *)detail
      didCallService:(NSString *)service
            inDomain:(NSString *)domain
            withData:(NSDictionary *)data
            entityId:(NSString *)entityId {
    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:domain
                                            withData:data
                                            entityId:entityId];
}

- (void)entityDetailDidRequestDismiss:(HAEntityDetailViewController *)detail {
    [detail dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Rotation

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (self.dashboardConfig) {
            BOOL isLandscape = (size.width > size.height);
            BOOL isIPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
            if (isIPad) {
                self.dashboardConfig.columns = 2;
            } else {
                self.dashboardConfig.columns = isLandscape ? 2 : 1;
            }
        }
        [self.collectionView.collectionViewLayout invalidateLayout];
    } completion:nil];
}

#pragma mark - Notification

- (void)registriesDidLoad:(NSNotification *)notification {
    // Rebuild when registries load — needed for:
    // - Default dashboard (no lovelace config): needs area grouping
    // - Strategy dashboard: connection manager re-resolves with area data and sends
    //   updated lovelaceDashboard, so we rebuild to pick it up
    if (self.statesLoaded) {
        [self rebuildDashboard];
    }
}

- (void)entityDidUpdate:(NSNotification *)notification {
    HAEntity *entity = notification.userInfo[@"entity"];
    if (!entity || !self.dashboardConfig) return;

    // Camera cells manage their own 5s refresh timer. Reloading them via the
    // standard path recycles the cell, killing the timer and causing black flashes
    // while the next HTTP image fetch completes.
    if ([[entity domain] isEqualToString:HAEntityDomainCamera]) return;

    // If this entity is used in a visibility condition, the update may add/remove
    // items from the collection view — trigger a full rebuild instead of cell reload.
    if ([self entityUsedInVisibilityConditions:entity.entityId]) {
        [self rebuildDashboard];
        return;
    }

    NSArray<NSIndexPath *> *indexPaths = self.entityToIndexPaths[entity.entityId];
    if (indexPaths.count > 0) {
        [self scheduleReloadForIndexPaths:indexPaths];
        return;
    }

    // Fallback: linear scan for entities not in the reverse map
    // (e.g. entities added after initial dashboard build)
    NSMutableArray<NSIndexPath *> *found = [NSMutableArray array];
    for (NSUInteger s = 0; s < self.dashboardConfig.sections.count; s++) {
        HADashboardConfigSection *section = self.dashboardConfig.sections[s];
        for (NSUInteger i = 0; i < section.items.count; i++) {
            if ([section.items[i].entityId isEqualToString:entity.entityId]) {
                [found addObject:[NSIndexPath indexPathForItem:i inSection:s]];
            }
        }
        if ([section.entityIds containsObject:entity.entityId]) {
            NSIndexPath *ip = [NSIndexPath indexPathForItem:0 inSection:s];
            if (![found containsObject:ip]) [found addObject:ip];
        }
    }
    if (found.count > 0) {
        [self scheduleReloadForIndexPaths:found];
    }
}

/// Coalesce multiple entity updates into a single batch reload
- (void)scheduleReloadForIndexPaths:(NSArray<NSIndexPath *> *)paths {
    if (!self.pendingReloadPaths) {
        self.pendingReloadPaths = [NSMutableSet set];
    }
    [self.pendingReloadPaths addObjectsFromArray:paths];

    // Coalesce: batch rapid-fire entity updates into a single reload pass.
    // 300ms batches more updates together (reduces flush frequency on A5 devices)
    // while still feeling responsive for user-triggered changes.
    [self.reloadCoalesceTimer invalidate];
    self.reloadCoalesceTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                               target:self
                                                             selector:@selector(flushPendingReloads)
                                                             userInfo:nil
                                                              repeats:NO];
}

- (void)flushPendingReloads {
    if (self.pendingReloadPaths.count == 0) return;

    // Take a snapshot and clear before iterating
    NSSet<NSIndexPath *> *pending = [self.pendingReloadPaths copy];
    [self.pendingReloadPaths removeAllObjects];

    // Early exit: check if ANY pending path intersects with visible cells.
    // On iPad 2, this saves ~40ms when many entities update but none are visible.
    NSSet<NSIndexPath *> *visible = [NSSet setWithArray:self.collectionView.indexPathsForVisibleItems];
    NSMutableSet *intersection = [pending mutableCopy];
    [intersection intersectSet:visible];
    if (intersection.count == 0) return;

    [[HAPerfMonitor sharedMonitor] markRebuildStart];
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    NSDictionary *allEntities = [conn allEntities];
    for (NSIndexPath *ip in intersection) {

        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:ip];
        if (!cell) continue;

        HADashboardConfigItem *item = [self itemAtIndexPath:ip];
        if (!item) continue;

        HADashboardConfigSection *section = [self sectionAtIndex:ip.section];

        if ([cell isKindOfClass:[HABadgeRowCell class]]) {
            HADashboardConfigSection *entSection = item.entitiesSection ?: section;
            [(HABadgeRowCell *)cell configureWithSection:entSection entities:allEntities];
        } else if ([cell isKindOfClass:[HAGraphCardCell class]]) {
            HADashboardConfigSection *entSection = item.entitiesSection ?: section;
            HAEntity *entity = [conn entityForId:item.entityId];
            if (entSection.entityIds.count > 0) {
                [(HAGraphCardCell *)cell configureWithSection:entSection entities:allEntities];
            } else {
                [(HAGraphCardCell *)cell configureWithEntity:entity item:item];
            }
        } else if ([cell isKindOfClass:[HAEntitiesCardCell class]]) {
            HADashboardConfigSection *entSection = item.entitiesSection ?: section;
            [(HAEntitiesCardCell *)cell configureWithSection:entSection entities:allEntities configItem:item];
        } else if ([cell isKindOfClass:[HAGaugeCardCell class]]) {
            HAEntity *entity = [conn entityForId:item.entityId];
            [(HAGaugeCardCell *)cell configureWithEntity:entity configItem:item];
        } else if ([cell isKindOfClass:[HABaseEntityCell class]]) {
            HAEntity *entity = [conn entityForId:item.entityId];
            [(HABaseEntityCell *)cell configureWithEntity:entity configItem:item];
        }
    }
    [[HAPerfMonitor sharedMonitor] markRebuildEnd];
}

#pragma mark - HAConnectionManagerDelegate

- (void)connectionManagerDidConnect:(HAConnectionManager *)manager {
    [self showConnectionBar:NO message:nil];
    // If we're already showing cached data, don't show loading spinner —
    // live data will seamlessly replace cached data in the background
    if (!manager.showingCachedData && !self.statesLoaded) {
        [self showLoading:YES message:@"Loading dashboard..."];
    }
    // Fetch available dashboards for the title switcher
    [manager fetchDashboardList];
}

- (void)connectionManager:(HAConnectionManager *)manager didDisconnectWithError:(NSError *)error {
    NSString *msg = error ? [NSString stringWithFormat:@"Disconnected — reconnecting..."] : @"Disconnected";
    [self showConnectionBar:YES message:msg];

    if (!self.statesLoaded) {
        // Hide skeleton and show error text
        [self.skeletonView stopAnimating];
        self.skeletonView.hidden = YES;
        self.statusLabel.text = error ? error.localizedDescription : @"Disconnected";
        self.statusLabel.textColor = [UIColor redColor];
        self.statusLabel.hidden = NO;
    }
}

- (void)connectionManager:(HAConnectionManager *)manager didReceiveAllStates:(NSDictionary<NSString *, HAEntity *> *)entities {
    self.statesLoaded = YES;
    [[HASunBasedTheme sharedInstance] start];
    [self rebuildDashboard];
}

- (void)connectionManager:(HAConnectionManager *)manager didReceiveLovelaceDashboard:(HALovelaceDashboard *)dashboard {
    // Preserve the user's current view selection when the same dashboard is
    // re-delivered (e.g. after a websocket reconnect while in Settings).
    // Only reset to view 0 on the very first load or when the dashboard changes.
    BOOL wasLoaded = self.lovelaceLoaded;
    BOOL isRefresh = (wasLoaded && self.selectedViewIndex < dashboard.views.count);

    self.lovelaceDashboard = dashboard;
    self.lovelaceLoaded = YES;
    self.lovelaceFetchDone = YES;

    // -HAViewIndex N — override the initial view index (for test harness capture)
    NSInteger bootViewIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"HAViewIndex"];
    if (bootViewIndex > 0 && (NSUInteger)bootViewIndex < dashboard.views.count) {
        self.selectedViewIndex = (NSUInteger)bootViewIndex;
    } else if (!isRefresh) {
        self.selectedViewIndex = 0;
    }

    HALogI(@"dash", @"Received Lovelace config: %lu views", (unsigned long)dashboard.views.count);
    for (NSUInteger i = 0; i < dashboard.views.count; i++) {
        HALovelaceView *view = dashboard.views[i];
        HALogD(@"dash", @"  View %lu: %@ (%lu cards)", (unsigned long)i, view.title, (unsigned long)view.rawCards.count);
    }

    [self populateViewPicker];
    [self rebuildDashboard];
}

- (void)connectionManagerDidFailToLoadLovelaceDashboard:(HAConnectionManager *)manager {
    HALogW(@"dash", @"Lovelace fetch failed, falling back to default entity dashboard");
    self.lovelaceFetchDone = YES;
    [self rebuildDashboard];
}

- (void)connectionManager:(HAConnectionManager *)manager didUpdateEntity:(HAEntity *)entity {
    // Handled via notification
}

#pragma mark - Screenshot Capture

- (void)captureScreenshotToPath:(NSString *)path {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        HALogW(@"dash", @"Screenshot: No key window");
        return;
    }

    UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, window.screen.scale);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (!image) {
        HALogE(@"dash", @"Screenshot capture failed");
        return;
    }

    NSData *pngData = UIImagePNGRepresentation(image);
    BOOL ok = [pngData writeToFile:path atomically:YES];
    HALogI(@"dash", @"Screenshot %@ -> %@ (%lu bytes)", ok ? @"Saved" : @"FAILED", path, (unsigned long)pngData.length);
}

@end
