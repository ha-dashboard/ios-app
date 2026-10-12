#import "HABaseSnapshotTestCase.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HABaseEntityCell.h"
#import "HAEntitiesCardCell.h"
#import "HABadgeRowCell.h"
#import "HAGlanceCardCell.h"
#import "HATheme.h"

/// FBSnapshotTestCase's own key-window lookup (Vendor UIApplication+KeyWindow),
/// so the warm-up renders in the same window the snapshots are drawn in.
@interface UIApplication (HASnapshotKeyWindow)
- (UIWindow *)ub_keyWindow;
@end

@implementation HABaseSnapshotTestCase

+ (void)setUp {
    [super setUp];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self warmUpRoundedBlurRendering];
    });
}

/// Render one corner-clipped frosted background, exactly the way
/// FBSnapshotTestCase renders a snapshot, before any test runs.
///
/// The first time a test process draws a UIVisualEffectView whose layer is
/// clipped to a corner radius (drawViewHierarchyInRect:afterScreenUpdates:YES
/// from a view in the key window), the render server antialiases the rounded
/// edge differently — 2/255 on the pill's outermost pixel at its vertical
/// centre — from every later render. So a blurred pill (badge row, view
/// badges) snapshot depended on whether another rounded blur had already
/// been drawn: it failed when its class or test ran alone and passed in the
/// full suite. One warm-up with any radius, size or blur style is enough
/// (a rounded plain view, or an unclipped blur, is not), so do it once per
/// process here rather than in individual tests.
+ (void)warmUpRoundedBlurRendering {
    CGRect frame = CGRectMake(0, 0, 72, 36);
    UIView *pill = [HATheme frostedBackgroundViewWithCornerRadius:frame.size.height / 2.0];
    pill.frame = frame;
    pill.clipsToBounds = YES;
    UIWindow *window = [[UIApplication sharedApplication] ub_keyWindow];
    if (!window) return;
    [window addSubview:pill];
    UIGraphicsBeginImageContextWithOptions(frame.size, NO, 0);
    [pill drawViewHierarchyInRect:pill.bounds afterScreenUpdates:YES];
    UIGraphicsEndImageContext();
    [pill removeFromSuperview];
}

- (void)setUp {
    [super setUp];
    // Record mode controlled by GCC_PREPROCESSOR_DEFINITIONS:
    // xcodebuild test ... GCC_PREPROCESSOR_DEFINITIONS='RECORD_SNAPSHOTS=1'
#ifdef RECORD_SNAPSHOTS
    self.recordMode = YES;
#else
    self.recordMode = NO;
#endif
    self.usesDrawViewHierarchyInRect = YES;
}

#pragma mark - Reference / Failure Image Directories

/// Override to point at our source tree ReferenceImages directory.
///
/// Reference images are deterministic only when recorded and compared on
/// the same simulator runtime (rendering/font metrics differ across iOS
/// versions). Set HA_SNAPSHOT_RUNTIME_SUFFIX (e.g. "_ios18") via
/// scripts/test-snapshots.sh to record or compare against a separate,
/// OS-tagged directory without touching the existing "ReferenceImages_64"
/// set recorded on iOS 17.4 — left unset, behavior is unchanged. This is a
/// compile-time define (GCC_PREPROCESSOR_DEFINITIONS, same mechanism as
/// RECORD_SNAPSHOTS below) rather than a runtime environment variable,
/// because the simulator-hosted test process does not inherit the
/// invoking shell's environment. See CLAUDE.md Testing section for the
/// pinned runtime and the re-record procedure.
- (NSString *)getReferenceImageDirectoryWithDefault:(NSString *)dir {
    NSString *thisFile = @__FILE__;
    NSString *testDir = [thisFile stringByDeletingLastPathComponent];
#ifdef HA_SNAPSHOT_RUNTIME_SUFFIX
    NSString *runtimeSuffix = @HA_SNAPSHOT_RUNTIME_SUFFIX;
#else
    NSString *runtimeSuffix = @"";
#endif
    NSString *folderName = [@"ReferenceImages" stringByAppendingString:runtimeSuffix];
    return [testDir stringByAppendingPathComponent:folderName];
}

/// Override to point at our source tree FailureDiffs directory.
- (NSString *)getImageDiffDirectoryWithDefault:(NSString *)dir {
    NSString *thisFile = @__FILE__;
    NSString *testDir = [thisFile stringByDeletingLastPathComponent];
    return [testDir stringByAppendingPathComponent:@"FailureDiffs"];
}

#pragma mark - Cell Creation Helpers

- (UIView *)cellForEntity:(HAEntity *)entity
                 cellClass:(Class)cellClass
                      size:(CGSize)size
                configItem:(HADashboardConfigItem *)configItem {
    HABaseEntityCell *cell = [[cellClass alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    [cell configureWithEntity:entity configItem:configItem];
    [cell layoutIfNeeded];
    return cell;
}

- (UIView *)compositeCell:(Class)cellClass
                     size:(CGSize)size
                  section:(HADashboardConfigSection *)section
                 entities:(NSDictionary<NSString *, HAEntity *> *)entities
               configItem:(HADashboardConfigItem *)configItem {
    UICollectionViewCell *cell = [[cellClass alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];

    if ([cell isKindOfClass:[HAEntitiesCardCell class]]) {
        [(HAEntitiesCardCell *)cell configureWithSection:section entities:entities configItem:configItem];
    } else if ([cell isKindOfClass:[HABadgeRowCell class]]) {
        [(HABadgeRowCell *)cell configureWithSection:section entities:entities];
    } else if ([cell isKindOfClass:[HAGlanceCardCell class]]) {
        [(HAGlanceCardCell *)cell configureWithSection:section entities:entities configItem:configItem];
    }

    [cell layoutIfNeeded];
    return cell;
}

#pragma mark - Theme Verification

- (void)verifyView:(UIView *)view identifier:(NSString *)identifier inTheme:(NSInteger)mode {
    [self verifyView:view identifier:identifier inTheme:mode gradient:NO];
}

- (void)verifyView:(UIView *)view identifier:(NSString *)identifier inTheme:(NSInteger)mode gradient:(BOOL)gradient {
    [self verifyView:view identifier:identifier inTheme:mode gradient:gradient perPixelTolerance:0 overallTolerance:0];
}

- (void)verifyView:(UIView *)view identifier:(NSString *)identifier inTheme:(NSInteger)mode gradient:(BOOL)gradient
 perPixelTolerance:(CGFloat)perPixelTolerance overallTolerance:(CGFloat)overallTolerance {
    HAThemeMode originalMode = [HATheme currentMode];
    BOOL originalGradient = [HATheme isGradientEnabled];

    [HATheme setCurrentMode:(HAThemeMode)mode];
    [HATheme setGradientEnabled:gradient];
    [view setNeedsLayout];
    [view layoutIfNeeded];

    NSString *themeSuffix;
    switch ((HAThemeMode)mode) {
        case HAThemeModeLight:
            themeSuffix = gradient ? @"_light_gradient" : @"_light";
            break;
        case HAThemeModeDark:
            themeSuffix = gradient ? @"_dark_gradient" : @"_dark";
            break;
        default:
            themeSuffix = gradient ? @"_auto_gradient" : @"_auto";
            break;
    }

    NSString *suffixedIdentifier;
    if (identifier.length > 0) {
        suffixedIdentifier = [identifier stringByAppendingString:themeSuffix];
    } else {
        suffixedIdentifier = themeSuffix;
    }

    if (perPixelTolerance > 0 || overallTolerance > 0) {
        FBSnapshotVerifyViewWithPixelOptions(view, suffixedIdentifier, FBSnapshotTestCaseDefaultSuffixes(), perPixelTolerance, overallTolerance);
    } else {
        FBSnapshotVerifyView(view, suffixedIdentifier);
    }

    [HATheme setCurrentMode:originalMode];
    [HATheme setGradientEnabled:originalGradient];
}

- (void)verifyView:(UIView *)view identifier:(NSString *)identifier {
    [self verifyView:view identifier:identifier inTheme:HAThemeModeDark gradient:YES];
    [self verifyView:view identifier:identifier inTheme:HAThemeModeLight];
}

@end
