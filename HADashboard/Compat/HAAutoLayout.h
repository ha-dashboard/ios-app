#import <UIKit/UIKit.h>

/// iOS 5-safe UICollectionElementKindSectionHeader/Footer.
/// The extern NSString *const doesn't exist in iOS 5's UIKit — referencing it
/// causes a dyld lazy binding crash. Use the raw string instead (matches
/// PSTCollectionView's internal value and UIKit's actual string on iOS 6+).
static inline NSString *HACollectionElementKindSectionHeader(void) {
    return @"UICollectionElementKindSectionHeader";
}

static inline NSString *HACollectionElementKindSectionFooter(void) {
    return @"UICollectionElementKindSectionFooter";
}

/// iOS 5-safe system major version check.
/// NSProcessInfo.operatingSystemVersion is iOS 8+.  On older systems
/// parse [[UIDevice currentDevice] systemVersion] instead.
static inline NSInteger HASystemMajorVersion(void) {
    static NSInteger ver = -1;
    if (ver < 0) {
        if ([[NSProcessInfo processInfo] respondsToSelector:@selector(operatingSystemVersion)]) {
            ver = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
        } else {
            ver = [[[UIDevice currentDevice] systemVersion] integerValue];
        }
    }
    return ver;
}

/// Force-disable Auto Layout for testing iOS 5 layout fallbacks on modern devices.
/// Set via developer settings toggle.  Defaults to NO.
static inline BOOL HAForceDisableAutoLayout(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HAForceDisableAutoLayout"];
}

/// Returns YES if Auto Layout (NSLayoutConstraint) is available at runtime
/// AND the developer hasn't force-disabled it for testing.
/// On iOS 5.x this returns NO.  On iOS 6+ this returns YES (unless overridden).
static inline BOOL HAAutoLayoutAvailable(void) {
    if (HAForceDisableAutoLayout()) return NO;
    static BOOL checked = NO, available = NO;
    if (!checked) {
        available = (NSClassFromString(@"NSLayoutConstraint") != nil);
        checked = YES;
    }
    return available;
}

#pragma mark - Nil-safe constraint helpers

/// Sentinel for nil constraints in @[] literals. On iOS 5, anchor methods
/// return a dummy whose constraintEqualToAnchor: returns nil — but @[nil]
/// crashes. Wrap each constraint expression in HACon() to substitute NSNull
/// for nil, then HAActivateConstraints filters them out.
///
/// Usage:
///   HAActivateConstraints(@[
///       HACon([v.topAnchor constraintEqualToAnchor:sv.topAnchor]),
///       HACon([v.leadingAnchor constraintEqualToAnchor:sv.leadingAnchor]),
///   ]);
#define HACon(expr) ((id)(expr) ?: (id)[NSNull null])

/// Activate an array of constraints, filtering out NSNull sentinels.
/// No-op when Auto Layout is unavailable (iOS 5 / developer toggle).
///
/// Replaces:
///   if (HAAutoLayoutAvailable()) {
///       [NSLayoutConstraint activateConstraints:@[...]];
///   }
static inline void HAActivateConstraints(NSArray *constraints) {
    if (!HAAutoLayoutAvailable()) return;
    NSMutableArray *valid = nil;
    for (id c in constraints) {
        if (c && c != (id)[NSNull null]) {
            if (!valid) valid = [NSMutableArray arrayWithCapacity:constraints.count];
            [valid addObject:c];
        }
    }
    if (valid) [NSLayoutConstraint activateConstraints:valid];
}

/// Set .active on a constraint, guarded by HAAutoLayoutAvailable().
/// No-op when the constraint is nil or Auto Layout is unavailable.
///
/// Replaces:
///   if (HAAutoLayoutAvailable()) { constraint.active = YES; }
static inline void HASetConstraintActive(NSLayoutConstraint *constraint, BOOL active) {
    if (!HAAutoLayoutAvailable() || !constraint) return;
    constraint.active = active;
}

/// Create and return a constraint without activating it.
/// Returns nil when Auto Layout is unavailable.
///
/// Usage:
///   self.bottomConstraint = HAMakeConstraint(
///       [slider.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-p]);
#define HAMakeConstraint(expr) (HAAutoLayoutAvailable() ? (expr) : nil)

#pragma mark - High-level layout helpers

/// Pin all four edges of `view` to `container` with the given insets.
/// No-op when Auto Layout is unavailable.
static inline void HAPinEdges(UIView *view, UIView *container, UIEdgeInsets insets) {
    HAActivateConstraints(@[
        HACon([view.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top]),
        HACon([view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left]),
        HACon([view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom]),
        HACon([view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right]),
    ]);
}

/// Pin all four edges with zero insets.
static inline void HAPinEdgesFlush(UIView *view, UIView *container) {
    HAPinEdges(view, container, UIEdgeInsetsZero);
}

/// Center `view` within `container` on one or both axes.
/// Pass YES for each axis you want centered.
static inline void HACenterIn(UIView *view, UIView *container, BOOL x, BOOL y) {
    NSMutableArray *constraints = [NSMutableArray arrayWithCapacity:2];
    if (x) [constraints addObject:HACon([view.centerXAnchor constraintEqualToAnchor:container.centerXAnchor])];
    if (y) [constraints addObject:HACon([view.centerYAnchor constraintEqualToAnchor:container.centerYAnchor])];
    HAActivateConstraints(constraints);
}

/// Set a fixed width and/or height on a view. Pass 0 to skip an axis.
static inline void HASetFixedSize(UIView *view, CGFloat width, CGFloat height) {
    NSMutableArray *constraints = [NSMutableArray arrayWithCapacity:2];
    if (width > 0)  [constraints addObject:HACon([view.widthAnchor constraintEqualToConstant:width])];
    if (height > 0) [constraints addObject:HACon([view.heightAnchor constraintEqualToConstant:height])];
    HAActivateConstraints(constraints);
}
