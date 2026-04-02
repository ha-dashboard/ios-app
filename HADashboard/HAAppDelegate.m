#import "HAAppDelegate.h"
#import "HAAuthManager.h"
#import "HAProximityWakeController.h"
#import "HAPerfMonitor.h"
#import "HAConnectionManager.h"
#import "HADashboardViewController.h"
#import "HASettingsViewController.h"
#import "HALoginViewController.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAPerfMonitor.h"
#import "HALog.h"
#import "HAEntityStateCache.h"
#import "HADeviceIntegrationManager.h"
#import "HADeviceRegistration.h"

/// Window subclass that detects system appearance changes (iOS 13+) and posts
/// HAThemeDidChangeNotification so every view/VC refreshes — not just the
/// dashboard.  Also catches background→foreground appearance flips that
/// traitCollectionDidChange on individual VCs can miss.
@interface HAThemeAwareWindow : UIWindow
@end

@implementation HAThemeAwareWindow

- (void)sendEvent:(UIEvent *)event {
    [super sendEvent:event];
    // Notify HAProximityWakeController of user interaction so it can reset
    // the idle timer or wake the screen. We only care about touch-began so
    // rapid move/end events don't flood the notification center.
    if (event.type == UIEventTypeTouches) {
        for (UITouch *touch in [event allTouches]) {
            if (touch.phase == UITouchPhaseBegan) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:HAWindowUserDidInteractNotification object:nil];
                break;
            }
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([previousTraitCollection hasDifferentColorAppearanceComparedToTraitCollection:self.traitCollection]) {
            if ([HATheme currentMode] == HAThemeModeAuto) {
                [[NSNotificationCenter defaultCenter] postNotificationName:HAThemeDidChangeNotification object:nil];
            }
        }
    }
}
@end

/// Nav controller that defers status bar appearance to the visible child VC.
/// Required because UINavigationController controls the status bar by default,
/// ignoring the child's prefersStatusBarHidden on iOS 9+.
@interface HAStatusBarNavigationController : UINavigationController
@end

@implementation HAStatusBarNavigationController
- (UIViewController *)childViewControllerForStatusBarHidden {
    return self.topViewController;
}
- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.topViewController;
}
@end

@interface HAAppDelegate ()
@end

@implementation HAAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [HALog logStartup:@"didFinishLaunching START"];

    // Log app version and build number for diagnostics
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *buildNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    HALogI(@"startup", @"App version: %@ (%@)", appVersion, buildNumber);

    // Performance monitor — opt-in via developer settings toggle or launch arg.
    // Default OFF to avoid CADisplayLink + timer overhead on production devices.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"HAPerfMonitorEnabled"] ||
        [[[NSProcessInfo processInfo] arguments] containsObject:@"-HAEnablePerfMonitor"]) {
        [[HAPerfMonitor sharedMonitor] start];
    }

    // Preload fonts before any UI is created — shifts ~350ms of first-cell
    // font loading cost out of the render path on iPad 2.
    [HALog logStartup:@"warmFonts BEGIN"];
    [HAIconMapper warmFonts];
    [HALog logStartup:@"warmFonts END"];

    [HALog logStartup:@"UIWindow alloc BEGIN"];
    self.window = [[HAThemeAwareWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    [HALog logStartup:@"UIWindow alloc END"];

    // Bootstrap credentials from launch arguments (for simulator/testing):
    //   -HAServerURL http://... -HAAccessToken eyJ... -HADashboard office
    //   -HAClearCredentials YES — wipe keychain + prefs (force login screen)
    [HALog logStartup:@"NSUserDefaults read BEGIN"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults boolForKey:@"HAClearCredentials"]) {
        [HALog logStartup:@"HAClearCredentials=YES — wiping keychain"];
        [[HAAuthManager sharedManager] clearCredentials];
    }

    NSString *bootURL = [defaults stringForKey:@"HAServerURL"];
    NSString *bootToken = [defaults stringForKey:@"HAAccessToken"];
    HALogI(@"startup", @"NSUserDefaults read END (url=%@, token=%@)",
        bootURL.length > 0 ? @"YES" : @"NO",
        bootToken.length > 0 ? @"YES" : @"NO");

    if (bootURL.length > 0 && bootToken.length > 0) {
        [HALog logStartup:@"saveServerURL BEGIN"];
        [[HAAuthManager sharedManager] saveServerURL:bootURL token:bootToken];
        [HALog logStartup:@"saveServerURL END"];
    }
    NSString *bootDashboard = [defaults stringForKey:@"HADashboard"];
    if (bootDashboard) {
        // Empty string clears selection (default dashboard), non-empty sets it
        [[HAAuthManager sharedManager] saveSelectedDashboardPath:bootDashboard.length > 0 ? bootDashboard : nil];
    }
    // -HAKioskMode YES/NO — override kiosk mode from launch arguments
    if ([defaults objectForKey:@"HAKioskMode"]) {
        [[HAAuthManager sharedManager] setKioskMode:[defaults boolForKey:@"HAKioskMode"]];
    }
    // -HAThemeMode 0-2 — override theme (0=auto, 1=dark, 2=light)
    if ([defaults objectForKey:@"HAThemeMode"]) {
        [HATheme setCurrentMode:(HAThemeMode)[defaults integerForKey:@"HAThemeMode"]];
    }
    // -HAGradientEnabled YES/NO — override gradient background
    if ([defaults objectForKey:@"HAGradientEnabled"]) {
        [HATheme setGradientEnabled:[defaults boolForKey:@"HAGradientEnabled"]];
    }
    // -HADemoMode YES/NO — override demo mode from launch arguments
    if ([defaults objectForKey:@"HADemoMode"]) {
        [[HAAuthManager sharedManager] setDemoMode:[defaults boolForKey:@"HADemoMode"]];
    }
    // -HAAutoRegister YES — auto-register device integration on launch (testing only)
    if ([defaults boolForKey:@"HAAutoRegister"]) {
        [HADeviceIntegrationManager sharedManager].enabled = YES;
        if (![[HADeviceRegistration sharedManager] isRegistered]) {
            HALogI(@"startup", @"HAAutoRegister: triggering device registration");
            [[HADeviceRegistration sharedManager] registerWithCompletion:^(BOOL success, NSError *error) {
                if (success) {
                    HALogI(@"startup", @"HAAutoRegister: registration succeeded");
                } else {
                    HALogE(@"startup", @"HAAutoRegister: registration failed: %@", error.localizedDescription);
                }
            }];
        } else {
            HALogI(@"startup", @"HAAutoRegister: already registered");
        }
    }

    [HALog logStartup:@"isConfigured check BEGIN"];
    BOOL configured = [[HAAuthManager sharedManager] isConfigured];
    HALogI(@"startup", @"isConfigured=%@", configured ? @"YES" : @"NO");

    UIViewController *rootVC;
    if (configured) {
        [HALog logStartup:@"Creating HADashboardViewController"];
        rootVC = [[HADashboardViewController alloc] init];
    } else {
        [HALog logStartup:@"Creating HALoginViewController"];
        rootVC = [[HALoginViewController alloc] init];
    }
    [HALog logStartup:@"Root VC created"];

    [HALog logStartup:@"NavController + setRoot BEGIN"];
    HAStatusBarNavigationController *navController = [[HAStatusBarNavigationController alloc] initWithRootViewController:rootVC];
    self.window.rootViewController = navController;
    [HALog logStartup:@"makeKeyAndVisible BEGIN"];
    [self.window makeKeyAndVisible];
    [HALog logStartup:@"makeKeyAndVisible END"];

    // Apply the saved theme's interface style to the window so the nav bar,
    // status bar, and all dynamic colors match the selected theme from launch.
    [HATheme applyInterfaceStyle];

    [[HAPerfMonitor sharedMonitor] start];

    [HALog logStartup:@"didFinishLaunching END"];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if ([[HAAuthManager sharedManager] isConfigured]) {
        [[HAConnectionManager sharedManager] connect];
        [[HADeviceIntegrationManager sharedManager] start];
    }

    // Request Guided Access if kiosk mode is on and not already in Guided Access.
    // Guard entire block to iOS 12.2+: both UIAccessibilityIsGuidedAccessEnabled()
    // and UIAccessibilityRequestGuidedAccessSession() can block the main thread on
    // jailbroken iOS 9 devices, causing a watchdog kill (0x8badf00d). Kiosk features
    // (hidden nav bar, disabled idle timer) still work without Guided Access.
    if (@available(iOS 12.2, *)) {
        if ([[HAAuthManager sharedManager] isKioskMode] && !UIAccessibilityIsGuidedAccessEnabled()) {
            UIAccessibilityRequestGuidedAccessSession(YES, ^(BOOL didSucceed) {
                if (didSucceed) {
                    HALogI(@"startup", @"Guided Access enabled for kiosk mode");
                }
            });
        }
    }
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [[HAPerfMonitor sharedMonitor] stop];
    // Flush entity state cache to disk synchronously before disconnect
    [[HADeviceIntegrationManager sharedManager] stop];
    [[HAEntityStateCache sharedCache] flushToDisk];
    [[HAConnectionManager sharedManager] disconnect];

    // Exit Guided Access when app goes to background (if we initiated it)
    if (@available(iOS 12.2, *)) {
        if (UIAccessibilityIsGuidedAccessEnabled()) {
            UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didSucceed) {
                if (didSucceed) {
                    HALogI(@"startup", @"Guided Access disabled");
                }
            });
        }
    }
}

@end
