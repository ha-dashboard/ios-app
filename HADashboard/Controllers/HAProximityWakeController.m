#import "HAProximityWakeController.h"

NSString *const HAWindowUserDidInteractNotification = @"HAWindowUserDidInteractNotification";

/// Seconds of inactivity before the screen dims.
static const NSTimeInterval kDimDelay = 60.0;
/// Duration of the dim-to-black animation.
static const NSTimeInterval kDimDuration = 4.0;
/// Duration of the wake (overlay fade-out) animation.
static const NSTimeInterval kWakeDuration = 0.35;

@interface HAProximityWakeController ()
@property (nonatomic, weak)   UIWindow *window;
@property (nonatomic, strong) NSTimer  *idleTimer;
@property (nonatomic, strong) UIView   *sleepOverlay;
@property (nonatomic, assign) CGFloat   savedBrightness;
@property (nonatomic, assign) BOOL      sleeping;
@end

@implementation HAProximityWakeController

- (instancetype)initWithWindow:(UIWindow *)window {
    self = [super init];
    if (self) {
        _window = window;
    }
    return self;
}

#pragma mark - Public

- (void)start {
    [self scheduleIdleTimer];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(userDidInteract)
               name:HAWindowUserDidInteractNotification object:nil];
    [nc addObserver:self selector:@selector(appWillResignActive)
               name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appDidBecomeActive)
               name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)stop {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.idleTimer invalidate];
    self.idleTimer = nil;
    [self wakeImmediately];
}

#pragma mark - Idle timer

- (void)scheduleIdleTimer {
    [self.idleTimer invalidate];
    self.idleTimer = [NSTimer scheduledTimerWithTimeInterval:kDimDelay
                                                      target:self
                                                    selector:@selector(idleTimerFired)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)idleTimerFired {
    self.idleTimer = nil;
    [self dim];
}

#pragma mark - Touch handling

- (void)userDidInteract {
    if (self.sleeping) {
        [self wake];
    } else {
        [self scheduleIdleTimer];
    }
}

#pragma mark - Dim / wake

- (void)dim {
    if (self.sleeping) return;
    self.sleeping = YES;

    UIWindow *window = self.window;
    if (!window) return;

    self.savedBrightness = [UIScreen mainScreen].brightness;

    UIView *overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.backgroundColor = [UIColor blackColor];
    overlay.alpha = 0.0;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // userInteractionEnabled YES so it absorbs touches (sendEvent: still fires for wake)
    overlay.userInteractionEnabled = YES;
    self.sleepOverlay = overlay;
    [window addSubview:overlay];

    [UIView animateWithDuration:kDimDuration delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        overlay.alpha = 1.0;
        [UIScreen mainScreen].brightness = 0.0;
    } completion:nil];
}

- (void)wake {
    if (!self.sleeping) return;
    self.sleeping = NO;

    // Restore brightness immediately so the first thing the user sees is the
    // screen coming back on, not a black frame while the overlay fades.
    [UIScreen mainScreen].brightness = self.savedBrightness;

    UIView *overlay = self.sleepOverlay;
    self.sleepOverlay = nil;

    [overlay.layer removeAllAnimations]; // cancel any in-progress dim
    [UIView animateWithDuration:kWakeDuration animations:^{
        overlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
    }];

    [self scheduleIdleTimer];
}

/// Instant restore with no animation, used when the feature is disabled.
- (void)wakeImmediately {
    if (!self.sleeping) return;
    self.sleeping = NO;
    [UIScreen mainScreen].brightness = self.savedBrightness;
    [self.sleepOverlay.layer removeAllAnimations];
    [self.sleepOverlay removeFromSuperview];
    self.sleepOverlay = nil;
}

#pragma mark - App lifecycle

- (void)appWillResignActive {
    // Pause idle timer when app is not active (control center, incoming call, etc.)
    // Don't dim — the OS will dim/lock on its own.
    [self.idleTimer invalidate];
    self.idleTimer = nil;
}

- (void)appDidBecomeActive {
    if (!self.sleeping) {
        [self scheduleIdleTimer];
    }
    // If we were sleeping when resigned, stay sleeping — user will touch to wake.
}

@end
