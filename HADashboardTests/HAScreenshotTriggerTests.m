#import <XCTest/XCTest.h>
#import "HADashboardViewController.h"

// -----------------------------------------------------------------------
// Expose private trigger-check API for testing.
// -----------------------------------------------------------------------

@interface HADashboardViewController (ScreenshotTestAccess)
@property (nonatomic, assign) BOOL screenshotScheduled;
+ (NSArray<NSString *> *)screenshotCandidateDirectories;
- (void)checkScreenshotTrigger;
@end

// -----------------------------------------------------------------------
// HAScreenshotTriggerTests
//
// Regression coverage for the physical-iPad screenshot trigger
// (CLAUDE.md "Physical iPad Screenshots"). The trigger used to be checked
// only from inside -rebuildDashboard, which (a) can return early before
// reaching the check, and (b) is only invoked when entity/Lovelace data
// changes — so on an idle dashboard, touching /tmp/take_screenshot could
// go unnoticed indefinitely. -checkScreenshotTrigger is now a standalone,
// idempotent, periodically-polled method; these tests exercise it
// directly without needing a live rebuild cycle.
// -----------------------------------------------------------------------

@interface HAScreenshotTriggerTests : XCTestCase
@property (nonatomic, strong) HADashboardViewController *dashVC;
@property (nonatomic, strong) NSString *triggerPath;
@property (nonatomic, strong) NSString *outputPath;
@end

@implementation HAScreenshotTriggerTests

- (void)setUp {
    [super setUp];
    self.dashVC = [[HADashboardViewController alloc] init];
    [self.dashVC loadViewIfNeeded];

    NSString *dir = [HADashboardViewController screenshotCandidateDirectories].firstObject;
    self.triggerPath = [dir stringByAppendingPathComponent:@"take_screenshot"];
    self.outputPath = [dir stringByAppendingPathComponent:@"screenshot.png"];
    [[NSFileManager defaultManager] removeItemAtPath:self.triggerPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:self.outputPath error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.triggerPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:self.outputPath error:nil];
    self.dashVC = nil;
    [super tearDown];
}

/// Candidate directories must never be empty, or the trigger could never be found.
- (void)testCandidateDirectoriesNonEmpty {
    NSArray<NSString *> *dirs = [HADashboardViewController screenshotCandidateDirectories];
    XCTAssertGreaterThan(dirs.count, 0u);
}

/// The legacy, documented /tmp path must always remain a candidate so the
/// existing SSH-driven workflow for iPad 2/3/4 keeps working unchanged.
- (void)testCandidateDirectoriesIncludesLegacyTmpPath {
    NSArray<NSString *> *dirs = [HADashboardViewController screenshotCandidateDirectories];
    BOOL hasLegacyTmp = NO;
    for (NSString *dir in dirs) {
        if ([dir isEqualToString:@"/tmp/"] || [dir isEqualToString:@"/tmp"]) {
            hasLegacyTmp = YES;
            break;
        }
    }
    XCTAssertTrue(hasLegacyTmp, @"screenshotCandidateDirectories must include /tmp/ for backward compatibility");
}

/// With no trigger file present, checking must be a harmless no-op.
- (void)testCheckScreenshotTriggerDoesNothingWithoutTriggerFile {
    self.dashVC.screenshotScheduled = NO;
    [self.dashVC checkScreenshotTrigger];
    XCTAssertFalse(self.dashVC.screenshotScheduled);
}

/// Dropping the trigger file must be picked up by a standalone call to
/// -checkScreenshotTrigger — the regression this test guards against is the
/// trigger only ever being noticed from inside -rebuildDashboard.
- (void)testCheckScreenshotTriggerConsumesTriggerFile {
    [@"" writeToFile:self.triggerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:self.triggerPath]);

    self.dashVC.screenshotScheduled = NO;
    [self.dashVC checkScreenshotTrigger];

    XCTAssertTrue(self.dashVC.screenshotScheduled, @"Trigger must be consumed without any rebuildDashboard call");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:self.triggerPath],
                    @"Trigger file must be removed once consumed, so it fires only once");
}

/// Once scheduled, a repeat call (e.g. from the periodic poll firing again
/// a moment later) must not re-arm or re-schedule a second capture.
- (void)testCheckScreenshotTriggerIsIdempotentOncePerLaunch {
    [@"" writeToFile:self.triggerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    self.dashVC.screenshotScheduled = NO;
    [self.dashVC checkScreenshotTrigger];
    XCTAssertTrue(self.dashVC.screenshotScheduled);

    // Re-create the trigger file as if something touched it again; a second
    // check must still be a no-op because capture is already scheduled.
    [@"" writeToFile:self.triggerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self.dashVC checkScreenshotTrigger];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:self.triggerPath],
                   @"A second trigger file must be left alone once a capture is already scheduled this launch");
}

@end
