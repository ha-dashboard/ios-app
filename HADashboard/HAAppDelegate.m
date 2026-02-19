#import "HAAppDelegate.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HADashboardViewController.h"
#import "HASettingsViewController.h"
#import "HALoginViewController.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAPerfMonitor.h"

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
    // Preload fonts before any UI is created — shifts ~350ms of first-cell
    // font loading cost out of the render path on iPad 2.
    [HAIconMapper warmFonts];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];

    // Bootstrap credentials from launch arguments (for simulator/testing):
    //   -HAServerURL http://... -HAAccessToken eyJ... -HADashboard office
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *bootURL = [defaults stringForKey:@"HAServerURL"];
    NSString *bootToken = [defaults stringForKey:@"HAAccessToken"];
    if (bootURL.length > 0 && bootToken.length > 0) {
        [[HAAuthManager sharedManager] saveServerURL:bootURL token:bootToken];
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
    // -HAThemeMode 0-3 — override theme (0=auto, 1=gradient, 2=dark, 3=light)
    if ([defaults objectForKey:@"HAThemeMode"]) {
        [HATheme setCurrentMode:(HAThemeMode)[defaults integerForKey:@"HAThemeMode"]];
    }
    // -HADemoMode YES/NO — override demo mode from launch arguments
    if ([defaults objectForKey:@"HADemoMode"]) {
        [[HAAuthManager sharedManager] setDemoMode:[defaults boolForKey:@"HADemoMode"]];
    }

    UIViewController *rootVC;
    if ([[HAAuthManager sharedManager] isConfigured]) {
        rootVC = [[HADashboardViewController alloc] init];
    } else {
        rootVC = [[HALoginViewController alloc] init];
    }

    HAStatusBarNavigationController *navController = [[HAStatusBarNavigationController alloc] initWithRootViewController:rootVC];
    self.window.rootViewController = navController;
    [self.window makeKeyAndVisible];

    [[HAPerfMonitor sharedMonitor] start];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if ([[HAAuthManager sharedManager] isConfigured]) {
        [[HAConnectionManager sharedManager] connect];
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
                    NSLog(@"[HAApp] Guided Access enabled for kiosk mode");
                }
            });
        }
    }
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [[HAPerfMonitor sharedMonitor] stop];
    [[HAConnectionManager sharedManager] disconnect];

    // Exit Guided Access when app goes to background (if we initiated it)
    if (@available(iOS 12.2, *)) {
        if (UIAccessibilityIsGuidedAccessEnabled()) {
            UIAccessibilityRequestGuidedAccessSession(NO, ^(BOOL didSucceed) {
                if (didSucceed) {
                    NSLog(@"[HAApp] Guided Access disabled");
                }
            });
        }
    }
}

@end
