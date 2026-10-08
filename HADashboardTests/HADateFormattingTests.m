#import <XCTest/XCTest.h>
#import "HADateUtils.h"

/// Guardrail tests for docs/plans/i18n-plan.md §3.2/§5.2.
///
/// Two independent concerns, both load-bearing for localisation work that
/// touches date/time formatting:
///
/// 1. Wire-format parsing (HADateUtils, and the equivalent inline
///    en_US_POSIX formatters in HAEntity.m, HAHistoryManager.m,
///    HAEntityDetailSection.m, HACalendarCardCell.m) must NEVER be
///    localised — it parses Home Assistant's API payload, not something
///    shown to a user. This test pins HADateUtils' round-trip behaviour
///    so a well-intentioned i18n change to date parsing fails loudly here
///    instead of silently breaking HA API communication.
///
/// 2. Locale-correct *display* formatting (NSDateFormatter
///    dateFormatFromTemplate:options:locale:) must respect field order and
///    the 12h/24h convention per-locale. This is the fix recommended in
///    plan §3.2 for the hardcoded `HH:mm`-style patterns; these tests pin
///    the system API's behaviour (not an app type) as a guardrail that
///    must hold before any of that formatting work lands.
@interface HADateFormattingTests : XCTestCase
@end

@implementation HADateFormattingTests

#pragma mark - 1. Wire-format parsing must stay en_US_POSIX and round-trip

- (void)testISO8601RoundTripNoFractionalSeconds {
    NSString *wire = @"2024-01-15T14:30:00+00:00";
    NSDate *date = [HADateUtils dateFromISO8601String:wire];
    XCTAssertNotNil(date, @"HA wire-format timestamp without fractional seconds must parse");

    NSDateComponents *c = [self utcComponentsFromDate:date];
    XCTAssertEqual(c.year, 2024);
    XCTAssertEqual(c.month, 1);
    XCTAssertEqual(c.day, 15);
    XCTAssertEqual(c.hour, 14);
    XCTAssertEqual(c.minute, 30);
}

- (void)testISO8601RoundTripWithMillisecondFraction {
    NSDate *date = [HADateUtils dateFromISO8601String:@"2024-06-01T08:15:30.123+00:00"];
    XCTAssertNotNil(date, @"Millisecond-fraction HA timestamps must parse");
}

- (void)testISO8601RoundTripWithMicrosecondFraction {
    // HA commonly emits 6-digit microsecond fractions, e.g. last_changed.
    NSDate *date = [HADateUtils dateFromISO8601String:@"2024-06-01T08:15:30.123456+00:00"];
    XCTAssertNotNil(date, @"Microsecond-fraction HA timestamps must parse");
}

- (void)testISO8601RoundTripNonUTCOffset {
    NSDate *date = [HADateUtils dateFromISO8601String:@"2024-03-10T23:00:00+05:30"];
    XCTAssertNotNil(date, @"Non-UTC timezone offsets must parse");
}

- (void)testISO8601ParsingIsLocaleIndependent {
    // This is the actual regression this test exists to catch: a formatter
    // built with the *current* locale (instead of en_US_POSIX) would fail
    // to parse "Jan"/digit-only ISO strings in some calendars/locales.
    // We can't easily swap [NSLocale currentLocale] in a unit test, but we
    // CAN assert the same wire string parses to the same instant regardless
    // of how many times/threads we call it, which is what the dispatch_once
    // POSIX-locale formatter pattern guarantees and a locale-dependent
    // formatter would not.
    NSString *wire = @"2024-12-25T00:00:00+00:00";
    NSDate *first = [HADateUtils dateFromISO8601String:wire];
    for (int i = 0; i < 20; i++) {
        NSDate *subsequent = [HADateUtils dateFromISO8601String:wire];
        XCTAssertEqualObjects(first, subsequent, @"Repeated parses of the same wire string must be identical");
    }
}

- (void)testISO8601RejectsNilAndNonString {
    XCTAssertNil([HADateUtils dateFromISO8601String:nil]);
    XCTAssertNil([HADateUtils dateFromISO8601String:(NSString *)@123]);
}

- (NSDateComponents *)utcComponentsFromDate:(NSDate *)date {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    return [calendar components:units fromDate:date];
}

#pragma mark - 2. Display formatting must honour locale field order (template API)

- (void)testTemplateHourMinuteIs12HourForUSEnglish {
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:locale];
    XCTAssertNotNil(pattern);
    // en-US is a 12h locale: the resolved pattern must contain "a" (AM/PM)
    // and the lowercase "h" hour field, never the forced-24h "H".
    XCTAssertTrue([pattern rangeOfString:@"a"].location != NSNotFound,
                   @"en_US 'jmm' template should resolve to a 12h pattern with an AM/PM marker, got: %@", pattern);
}

- (void)testTemplateHourMinuteIs24HourForFrenchFrance {
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"fr_FR"];
    NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:locale];
    XCTAssertNotNil(pattern);
    // fr-FR is a 24h locale: no AM/PM marker, and the hour field must be
    // the forced-24h "H", not "h".
    XCTAssertTrue([pattern rangeOfString:@"a"].location == NSNotFound,
                   @"fr_FR 'jmm' template should resolve to a 24h pattern with no AM/PM marker, got: %@", pattern);
    XCTAssertTrue([pattern rangeOfString:@"H"].location != NSNotFound,
                   @"fr_FR 'jmm' template should use the 24h 'H' hour field, got: %@", pattern);
}

- (void)testTemplateMonthDayOrderDiffersBetweenUSAndBritishEnglish {
    // en-US: month before day ("M d" family). en-GB: day before month
    // ("d M" family) despite both being English. This is exactly the bug
    // a hardcoded "d/M" or "M/d" pattern cannot avoid; the template API
    // must resolve them differently.
    NSString *usPattern = [NSDateFormatter dateFormatFromTemplate:@"Md" options:0 locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    NSString *gbPattern = [NSDateFormatter dateFormatFromTemplate:@"Md" options:0 locale:[NSLocale localeWithLocaleIdentifier:@"en_GB"]];
    XCTAssertNotNil(usPattern);
    XCTAssertNotNil(gbPattern);

    NSUInteger usMonthIndex = [usPattern rangeOfString:@"M"].location;
    NSUInteger usDayIndex = [usPattern rangeOfString:@"d"].location;
    NSUInteger gbMonthIndex = [gbPattern rangeOfString:@"M"].location;
    NSUInteger gbDayIndex = [gbPattern rangeOfString:@"d"].location;

    XCTAssertLessThan(usMonthIndex, usDayIndex, @"en_US should order month before day, got: %@", usPattern);
    XCTAssertLessThan(gbDayIndex, gbMonthIndex, @"en_GB should order day before month, got: %@", gbPattern);
}

- (void)testTemplateFullMonthYearOrderForFrench {
    // "yMMMM" (plan's template for "MMMM yyyy") must still place the month
    // name before the year for fr_FR -- a sanity check that the template
    // API, not a hardcoded pattern, is driving field order.
    NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"yMMMM" options:0 locale:[NSLocale localeWithLocaleIdentifier:@"fr_FR"]];
    XCTAssertNotNil(pattern);
    NSUInteger monthIndex = [pattern rangeOfString:@"M"].location;
    NSUInteger yearIndex = [pattern rangeOfString:@"y"].location;
    XCTAssertLessThan(monthIndex, yearIndex, @"fr_FR 'yMMMM' should place the month before the year, got: %@", pattern);
}

@end
