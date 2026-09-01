#import <XCTest/XCTest.h>
#import <Security/Security.h>

#import "HARTSPCredentialManager.h"

@interface HARTSPCredentialManagerTests : XCTestCase

@property (nonatomic, copy) NSString *serviceIdentifier;
@property (nonatomic, strong) HARTSPCredentialManager *manager;

@end

@implementation HARTSPCredentialManagerTests

- (void)setUp {
    [super setUp];
    self.serviceIdentifier = [@"com.hadashboard.app.tests.rtsp-credentials."
                              stringByAppendingString:[NSUUID UUID].UUIDString];
    self.manager = [[HARTSPCredentialManager alloc]
                    initWithServiceIdentifier:self.serviceIdentifier];

    NSDictionary *probe = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.serviceIdentifier,
        (__bridge id)kSecAttrAccount: @"entitlement-probe",
        (__bridge id)kSecValueData: [@"probe" dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:
            (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
    OSStatus probeStatus = SecItemAdd((__bridge CFDictionaryRef)probe, NULL);
    if (probeStatus == errSecSuccess) {
        SecItemDelete((__bridge CFDictionaryRef)probe);
    }
    XCTSkipIf(probeStatus == errSecMissingEntitlement,
              @"The unsigned CI Catalyst host has no Keychain access group; signed local/device runs execute this suite.");
    XCTAssertEqual(probeStatus, errSecSuccess);
}

- (void)tearDown {
    [self.manager deleteCredentialsWithError:nil];
    self.manager = nil;
    self.serviceIdentifier = nil;
    [super tearDown];
}

- (void)testGeneratedCredentialHasExpectedEntropyAndPersists {
    NSError *error = nil;
    HARTSPCredentials *first = [self.manager credentialsWithError:&error];
    XCTAssertNotNil(first);
    XCTAssertNil(error);
    XCTAssertEqualObjects(first.username, @"hadashboard");
    XCTAssertEqual([self decodedByteCountForURLSafeToken:first.password], (NSUInteger)24);
    XCTAssertEqual(first.password.length, (NSUInteger)32);
    XCTAssertEqual([self decodedByteCountForURLSafeToken:first.revision], (NSUInteger)16);

    HARTSPCredentialManager *secondManager = [[HARTSPCredentialManager alloc]
                                              initWithServiceIdentifier:self.serviceIdentifier];
    HARTSPCredentials *second = [secondManager credentialsWithError:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(second.password, first.password);
    XCTAssertEqualObjects(second.revision, first.revision);
    XCTAssertFalse([[first description] containsString:first.password]);
    XCTAssertFalse([[first debugDescription] containsString:first.password]);
}

- (void)testCredentialUsesDeviceOnlyWhenUnlockedAccessibility {
    NSError *error = nil;
    XCTAssertNotNil([self.manager credentialsWithError:&error]);
    XCTAssertNil(error);

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.serviceIdentifier,
        (__bridge id)kSecAttrAccount: HARTSPCredentialUsername,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef rawResult = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &rawResult);
    XCTAssertEqual(status, errSecSuccess);

    NSDictionary *attributes = CFBridgingRelease(rawResult);
    XCTAssertEqualObjects(attributes[(__bridge id)kSecAttrAccessible],
                          (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly);
}

- (void)testRotationChangesPasswordAndNonSecretRevision {
    NSError *error = nil;
    HARTSPCredentials *before = [self.manager credentialsWithError:&error];
    HARTSPCredentials *after = [self.manager rotateCredentialsWithError:&error];
    XCTAssertNil(error);
    XCTAssertNotEqualObjects(after.password, before.password);
    XCTAssertNotEqualObjects(after.revision, before.revision);
    XCTAssertEqualObjects(after.username, before.username);

    HARTSPCredentials *stored = [self.manager credentialsWithError:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(stored.password, after.password);
    XCTAssertEqualObjects(stored.revision, after.revision);
}

- (void)testDeleteIsIdempotentAndNextAccessGeneratesFreshValues {
    NSError *error = nil;
    HARTSPCredentials *before = [self.manager credentialsWithError:&error];
    XCTAssertTrue([self.manager deleteCredentialsWithError:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([self.manager deleteCredentialsWithError:&error]);
    XCTAssertNil(error);

    HARTSPCredentials *after = [self.manager credentialsWithError:&error];
    XCTAssertNil(error);
    XCTAssertNotEqualObjects(after.password, before.password);
    XCTAssertNotEqualObjects(after.revision, before.revision);
}

- (void)testMalformedStoredCredentialIsAtomicallyReplaced {
    [self.manager deleteCredentialsWithError:nil];
    NSDictionary *item = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.serviceIdentifier,
        (__bridge id)kSecAttrAccount: HARTSPCredentialUsername,
        (__bridge id)kSecValueData: [@"invalid" dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrGeneric: [@"invalid" dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:
            (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
    XCTAssertEqual(SecItemAdd((__bridge CFDictionaryRef)item, NULL), errSecSuccess);

    NSError *error = nil;
    HARTSPCredentials *repaired = [self.manager credentialsWithError:&error];
    XCTAssertNotNil(repaired);
    XCTAssertNil(error);
    XCTAssertEqual([self decodedByteCountForURLSafeToken:repaired.password], (NSUInteger)24);
    XCTAssertEqual([self decodedByteCountForURLSafeToken:repaired.revision], (NSUInteger)16);

    HARTSPCredentials *reread = [self.manager credentialsWithError:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(reread.password, repaired.password);
    XCTAssertEqualObjects(reread.revision, repaired.revision);
}

- (void)testMissingRevisionMigrationPreservesPassword {
    NSError *error = nil;
    HARTSPCredentials *before = [self.manager credentialsWithError:&error];
    XCTAssertNotNil(before);
    XCTAssertNil(error);

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.serviceIdentifier,
        (__bridge id)kSecAttrAccount: HARTSPCredentialUsername,
    };
    NSDictionary *emptyRevision = @{
        (__bridge id)kSecAttrGeneric: [NSData data],
    };
    XCTAssertEqual(SecItemUpdate((__bridge CFDictionaryRef)query,
                                 (__bridge CFDictionaryRef)emptyRevision), errSecSuccess);

    HARTSPCredentials *migrated = [self.manager credentialsWithError:&error];
    XCTAssertNotNil(migrated);
    XCTAssertNil(error);
    XCTAssertEqualObjects(migrated.password, before.password);
    XCTAssertEqual([self decodedByteCountForURLSafeToken:migrated.revision], (NSUInteger)16);
}

- (void)testRotationCreatesCredentialWhenNoneExists {
    XCTAssertTrue([self.manager deleteCredentialsWithError:nil]);
    NSError *error = nil;
    HARTSPCredentials *rotated = [self.manager rotateCredentialsWithError:&error];
    XCTAssertNotNil(rotated);
    XCTAssertNil(error);

    HARTSPCredentials *stored = [self.manager credentialsWithError:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(stored.password, rotated.password);
    XCTAssertEqualObjects(stored.revision, rotated.revision);
}

- (NSUInteger)decodedByteCountForURLSafeToken:(NSString *)token {
    NSCharacterSet *invalidCharacters =
        [[NSCharacterSet characterSetWithCharactersInString:
          @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet];
    XCTAssertEqual([token rangeOfCharacterFromSet:invalidCharacters].location, NSNotFound);

    NSString *base64 = [token stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (base64.length % 4 != 0) {
        base64 = [base64 stringByAppendingString:@"="];
    }
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    XCTAssertNotNil(decoded);
    return decoded.length;
}

@end
