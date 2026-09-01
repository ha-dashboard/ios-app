#import "HAAppSceneDelegate.h"
#import "HAAppDelegate.h"

@implementation HAAppSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
     options:(UISceneConnectionOptions *)connectionOptions {
    (void)session;
    (void)connectionOptions;
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    if (!self.window) {
        self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    }
    HAAppDelegate *appDelegate = (HAAppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate configureInitialInterfaceInWindow:self.window];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    (void)scene;
    // UIKit delivers this callback while applicationState may still be
    // Inactive. Defer one main-loop turn so the foreground-only stream can
    // arm itself without treating a normal launch as an invalid request.
    dispatch_async(dispatch_get_main_queue(), ^{
        HAAppDelegate *appDelegate = (HAAppDelegate *)[UIApplication sharedApplication].delegate;
        [appDelegate resumeForegroundServices];
    });
}

- (void)sceneWillResignActive:(UIScene *)scene {
    (void)scene;
    HAAppDelegate *appDelegate = (HAAppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate suspendForegroundServices];
}

@end
