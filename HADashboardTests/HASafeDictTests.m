#import <XCTest/XCTest.h>
#import "HASafeDict.h"

@interface HASafeDictTests : XCTestCase
@end

@implementation HASafeDictTests

#pragma mark - HASafeDictString

- (void)testStringWithStringReturnsValue {
    NSDictionary *d = @{@"key": @"hello"};
    XCTAssertEqualObjects(HASafeDictString(d, @"key", @"fallback"), @"hello");
}

- (void)testStringWithNumberReturnsFallback {
    NSDictionary *d = @{@"key": @42};
    XCTAssertEqualObjects(HASafeDictString(d, @"key", @"fallback"), @"fallback");
}

- (void)testStringWithNSNullReturnsFallback {
    NSDictionary *d = @{@"key": [NSNull null]};
    XCTAssertEqualObjects(HASafeDictString(d, @"key", @"fallback"), @"fallback");
}

- (void)testStringWithMissingKeyReturnsFallback {
    NSDictionary *d = @{};
    XCTAssertEqualObjects(HASafeDictString(d, @"key", @"fallback"), @"fallback");
}

- (void)testStringWithArrayReturnsFallback {
    NSDictionary *d = @{@"key": @[@"a", @"b"]};
    XCTAssertEqualObjects(HASafeDictString(d, @"key", @"fallback"), @"fallback");
}

- (void)testStringWithBoolReturnsFallback {
    NSDictionary *d = @{@"key": @YES};
    XCTAssertEqualObjects(HASafeDictString(d, @"key", @"fallback"), @"fallback");
}

#pragma mark - HASafeDictStringOrNil

- (void)testStringOrNilWithStringReturnsValue {
    NSDictionary *d = @{@"key": @"hello"};
    XCTAssertEqualObjects(HASafeDictStringOrNil(d, @"key"), @"hello");
}

- (void)testStringOrNilWithNumberReturnsNil {
    NSDictionary *d = @{@"key": @42};
    XCTAssertNil(HASafeDictStringOrNil(d, @"key"));
}

- (void)testStringOrNilWithMissingKeyReturnsNil {
    NSDictionary *d = @{};
    XCTAssertNil(HASafeDictStringOrNil(d, @"key"));
}

- (void)testStringOrNilWithNSNullReturnsNil {
    NSDictionary *d = @{@"key": [NSNull null]};
    XCTAssertNil(HASafeDictStringOrNil(d, @"key"));
}

#pragma mark - HASafeDictInteger

- (void)testIntegerWithNumberReturnsValue {
    NSDictionary *d = @{@"key": @42};
    XCTAssertEqual(HASafeDictInteger(d, @"key", -1), 42);
}

- (void)testIntegerWithStringReturnsFallback {
    NSDictionary *d = @{@"key": @"not a number"};
    XCTAssertEqual(HASafeDictInteger(d, @"key", -1), -1);
}

- (void)testIntegerWithNSNullReturnsFallback {
    NSDictionary *d = @{@"key": [NSNull null]};
    XCTAssertEqual(HASafeDictInteger(d, @"key", -1), -1);
}

- (void)testIntegerWithMissingKeyReturnsFallback {
    NSDictionary *d = @{};
    XCTAssertEqual(HASafeDictInteger(d, @"key", -1), -1);
}

- (void)testIntegerWithBoolReturnsValue {
    // NSNumber wraps BOOL — @YES is NSNumber(1)
    NSDictionary *d = @{@"key": @YES};
    XCTAssertEqual(HASafeDictInteger(d, @"key", -1), 1);
}

- (void)testIntegerWithFloatTruncates {
    NSDictionary *d = @{@"key": @3.7};
    XCTAssertEqual(HASafeDictInteger(d, @"key", -1), 3);
}

#pragma mark - HASafeDictNumberOrNil

- (void)testNumberOrNilWithNumberReturnsValue {
    NSDictionary *d = @{@"key": @3.14};
    XCTAssertEqualObjects(HASafeDictNumberOrNil(d, @"key"), @3.14);
}

- (void)testNumberOrNilWithStringReturnsNil {
    NSDictionary *d = @{@"key": @"not a number"};
    XCTAssertNil(HASafeDictNumberOrNil(d, @"key"));
}

- (void)testNumberOrNilWithNSNullReturnsNil {
    NSDictionary *d = @{@"key": [NSNull null]};
    XCTAssertNil(HASafeDictNumberOrNil(d, @"key"));
}

#pragma mark - HASafeDictBool

- (void)testBoolWithYESReturnsYES {
    NSDictionary *d = @{@"key": @YES};
    XCTAssertTrue(HASafeDictBool(d, @"key", NO));
}

- (void)testBoolWithNOReturnsNO {
    NSDictionary *d = @{@"key": @NO};
    XCTAssertFalse(HASafeDictBool(d, @"key", YES));
}

- (void)testBoolWithStringReturnsFallback {
    NSDictionary *d = @{@"key": @"true"};
    XCTAssertFalse(HASafeDictBool(d, @"key", NO), @"String 'true' should not be treated as BOOL");
}

- (void)testBoolWithNSNullReturnsFallback {
    NSDictionary *d = @{@"key": [NSNull null]};
    XCTAssertTrue(HASafeDictBool(d, @"key", YES));
}

- (void)testBoolWithMissingKeyReturnsFallback {
    NSDictionary *d = @{};
    XCTAssertTrue(HASafeDictBool(d, @"key", YES));
    XCTAssertFalse(HASafeDictBool(d, @"key", NO));
}

#pragma mark - HASafeDictArrayOrNil

- (void)testArrayOrNilWithArrayReturnsValue {
    NSDictionary *d = @{@"key": @[@"a", @"b"]};
    NSArray *result = HASafeDictArrayOrNil(d, @"key");
    XCTAssertNotNil(result);
    XCTAssertEqual(result.count, 2);
}

- (void)testArrayOrNilWithStringReturnsNil {
    NSDictionary *d = @{@"key": @"not an array"};
    XCTAssertNil(HASafeDictArrayOrNil(d, @"key"));
}

- (void)testArrayOrNilWithNSNullReturnsNil {
    NSDictionary *d = @{@"key": [NSNull null]};
    XCTAssertNil(HASafeDictArrayOrNil(d, @"key"));
}

- (void)testArrayOrNilWithDictReturnsNil {
    NSDictionary *d = @{@"key": @{@"nested": @YES}};
    XCTAssertNil(HASafeDictArrayOrNil(d, @"key"));
}

- (void)testArrayOrNilWithMissingKeyReturnsNil {
    NSDictionary *d = @{};
    XCTAssertNil(HASafeDictArrayOrNil(d, @"key"));
}

#pragma mark - HASafeDictDictOrNil

- (void)testDictOrNilWithDictReturnsValue {
    NSDictionary *d = @{@"key": @{@"nested": @YES}};
    NSDictionary *result = HASafeDictDictOrNil(d, @"key");
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"nested"], @YES);
}

- (void)testDictOrNilWithStringReturnsNil {
    NSDictionary *d = @{@"key": @"not a dict"};
    XCTAssertNil(HASafeDictDictOrNil(d, @"key"));
}

- (void)testDictOrNilWithArrayReturnsNil {
    NSDictionary *d = @{@"key": @[@"a"]};
    XCTAssertNil(HASafeDictDictOrNil(d, @"key"));
}

- (void)testDictOrNilWithNSNullReturnsNil {
    NSDictionary *d = @{@"key": [NSNull null]};
    XCTAssertNil(HASafeDictDictOrNil(d, @"key"));
}

- (void)testDictOrNilWithMissingKeyReturnsNil {
    NSDictionary *d = @{};
    XCTAssertNil(HASafeDictDictOrNil(d, @"key"));
}

@end
