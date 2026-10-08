#import "HABaseSnapshotTestCase.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HABaseEntityCell.h"
#import "HAEntitiesCardCell.h"
#import "HABadgeRowCell.h"
#import "HAGlanceCardCell.h"
#import "HATheme.h"

@implementation HABaseSnapshotTestCase

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
