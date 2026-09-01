#import "HARTSPCredentialManager.h"

#import <Security/Security.h>

NSString *const HARTSPCredentialErrorDomain = @"HARTSPCredentialErrorDomain";
NSString *const HARTSPCredentialUsername = @"hadashboard";

static NSUInteger const HARTSPPasswordRandomByteCount = 24;
static NSUInteger const HARTSPRevisionRandomByteCount = 16;
static NSString *const HARTSPDefaultServiceSuffix = @".rtsp-stream-credentials";

@interface HARTSPCredentials ()

- (instancetype)initWithPassword:(NSString *)password revision:(NSString *)revision;

@end

@implementation HARTSPCredentials

- (instancetype)initWithPassword:(NSString *)password revision:(NSString *)revision {
    self = [super init];
    if (self) {
        _username = [HARTSPCredentialUsername copy];
        _password = [password copy];
        _revision = [revision copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p; username=%@; revision=%@; password=<redacted>>",
            NSStringFromClass([self class]), self, self.username, self.revision];
}

- (NSString *)debugDescription {
    return self.description;
}

@end

@interface HARTSPCredentialManager ()

@property (nonatomic, copy) NSString *serviceIdentifier;

@end

@implementation HARTSPCredentialManager

+ (HARTSPCredentialManager *)sharedManager {
    static HARTSPCredentialManager *manager = nil;
    @synchronized(self) {
        if (!manager) {
            manager = [[self alloc] init];
        }
    }
    return manager;
}

- (instancetype)init {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    if (bundleIdentifier.length == 0) {
        bundleIdentifier = @"com.hadashboard.app";
    }
    return [self initWithServiceIdentifier:
            [bundleIdentifier stringByAppendingString:HARTSPDefaultServiceSuffix]];
}

- (instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier {
    if (serviceIdentifier.length == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _serviceIdentifier = [serviceIdentifier copy];
    }
    return self;
}

- (NSString *)username {
    return HARTSPCredentialUsername;
}

- (HARTSPCredentials *)credentialsWithError:(NSError **)error {
    if (error) {
        *error = nil;
    }

    // Serialize in-process access across instances as well as the singleton.
    // SecItemAdd's duplicate handling below also closes the lazy-create race.
    @synchronized([HARTSPCredentialManager class]) {
        OSStatus readStatus = errSecSuccess;
        NSError *readError = nil;
        HARTSPCredentials *stored = [self storedCredentialsWithStatus:&readStatus error:&readError];
        if (stored) {
            return stored;
        }

        // A malformed record cannot authenticate any legitimate client. Replace
        // it atomically with a fresh credential so a damaged or pre-release
        // Keychain item does not permanently strand the feature. Other Keychain
        // failures remain fail-closed and are surfaced without modifying data.
        if (readStatus == errSecSuccess &&
            [readError.domain isEqualToString:HARTSPCredentialErrorDomain] &&
            readError.code == HARTSPCredentialErrorInvalidStoredCredential) {
            HARTSPCredentials *replacement = [self generateCredentialsWithError:error];
            if (!replacement) {
                return nil;
            }
            OSStatus replacementStatus = SecItemUpdate(
                (__bridge CFDictionaryRef)[self baseQuery],
                (__bridge CFDictionaryRef)[self valuesForCredentials:replacement
                                                  includeAccessibility:YES]);
            if (replacementStatus == errSecSuccess) {
                return replacement;
            }
            [self assignError:error
                          code:HARTSPCredentialErrorKeychainFailure
                        status:replacementStatus
                   description:@"The invalid RTSP access credential could not be replaced."];
            return nil;
        }
        if (readStatus != errSecItemNotFound) {
            if (error) {
                *error = readError;
            }
            return nil;
        }

        HARTSPCredentials *generated = [self generateCredentialsWithError:error];
        if (!generated) {
            return nil;
        }

        OSStatus addStatus = [self addCredentials:generated];
        if (addStatus == errSecSuccess) {
            return generated;
        }

        // Another manager may have created the same service between the read
        // and add. Prefer that stored value rather than rotating it.
        if (addStatus == errSecDuplicateItem) {
            OSStatus retryStatus = errSecSuccess;
            NSError *retryError = nil;
            HARTSPCredentials *retry = [self storedCredentialsWithStatus:&retryStatus
                                                                    error:&retryError];
            if (retry) {
                return retry;
            }
            if (retryStatus != errSecItemNotFound && retryError) {
                if (error) {
                    *error = retryError;
                }
                return nil;
            }
            [self assignError:error
                          code:HARTSPCredentialErrorKeychainFailure
                        status:retryStatus
                   description:@"The RTSP access credential changed while it was being saved."];
            return nil;
        }

        [self assignError:error
                      code:HARTSPCredentialErrorKeychainFailure
                    status:addStatus
               description:@"The RTSP access credential could not be saved."];
        return nil;
    }
}

- (HARTSPCredentials *)rotateCredentialsWithError:(NSError **)error {
    if (error) {
        *error = nil;
    }

    @synchronized([HARTSPCredentialManager class]) {
        HARTSPCredentials *generated = [self generateCredentialsWithError:error];
        if (!generated) {
            return nil;
        }

        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)[self baseQuery],
                                        (__bridge CFDictionaryRef)[self valuesForCredentials:generated
                                                                         includeAccessibility:YES]);
        if (status == errSecItemNotFound) {
            status = [self addCredentials:generated];
        }

        if (status != errSecSuccess) {
            [self assignError:error
                          code:HARTSPCredentialErrorKeychainFailure
                        status:status
                   description:@"The RTSP access credential could not be rotated."];
            return nil;
        }
        return generated;
    }
}

- (BOOL)deleteCredentialsWithError:(NSError **)error {
    if (error) {
        *error = nil;
    }

    @synchronized([HARTSPCredentialManager class]) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self baseQuery]);
        if (status == errSecSuccess || status == errSecItemNotFound) {
            return YES;
        }

        [self assignError:error
                      code:HARTSPCredentialErrorKeychainFailure
                    status:status
               description:@"The RTSP access credential could not be deleted."];
        return NO;
    }
}

#pragma mark - Keychain

- (NSDictionary *)baseQuery {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: self.serviceIdentifier,
        (__bridge id)kSecAttrAccount: HARTSPCredentialUsername,
    };
}

- (NSDictionary *)valuesForCredentials:(HARTSPCredentials *)credentials
                   includeAccessibility:(BOOL)includeAccessibility {
    NSMutableDictionary *values = [@{
        (__bridge id)kSecValueData: [credentials.password dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrGeneric: [credentials.revision dataUsingEncoding:NSUTF8StringEncoding],
    } mutableCopy];
    if (includeAccessibility) {
        values[(__bridge id)kSecAttrAccessible] =
            (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    }
    return values;
}

- (OSStatus)addCredentials:(HARTSPCredentials *)credentials {
    NSMutableDictionary *item = [[self baseQuery] mutableCopy];
    [item addEntriesFromDictionary:[self valuesForCredentials:credentials includeAccessibility:YES]];
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

- (HARTSPCredentials *)storedCredentialsWithStatus:(OSStatus *)statusOut
                                              error:(NSError **)error {
    NSMutableDictionary *query = [[self baseQuery] mutableCopy];
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef rawResult = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &rawResult);
    if (statusOut) {
        *statusOut = status;
    }
    if (status == errSecItemNotFound) {
        return nil;
    }
    if (status != errSecSuccess) {
        [self assignError:error
                      code:HARTSPCredentialErrorKeychainFailure
                    status:status
               description:@"The RTSP access credential could not be read."];
        if (rawResult) {
            CFRelease(rawResult);
        }
        return nil;
    }

    id result = CFBridgingRelease(rawResult);
    if (![result isKindOfClass:[NSDictionary class]]) {
        [self assignError:error
                      code:HARTSPCredentialErrorInvalidStoredCredential
                    status:errSecSuccess
               description:@"The stored RTSP access credential has an invalid format."];
        return nil;
    }

    NSDictionary *attributes = result;
    NSData *passwordData = attributes[(__bridge id)kSecValueData];
    NSData *revisionData = attributes[(__bridge id)kSecAttrGeneric];
    NSString *password = [[NSString alloc] initWithData:passwordData
                                               encoding:NSUTF8StringEncoding];
    NSString *revision = [[NSString alloc] initWithData:revisionData
                                               encoding:NSUTF8StringEncoding];

    if (![self token:password representsByteCount:HARTSPPasswordRandomByteCount]) {
        [self assignError:error
                      code:HARTSPCredentialErrorInvalidStoredCredential
                    status:errSecSuccess
               description:@"The stored RTSP access credential has an invalid format."];
        return nil;
    }

    if (revision.length == 0) {
        // Preserve an otherwise valid password if a pre-revision build created
        // it. Adding only a non-secret revision avoids silently breaking HA.
        revision = [self randomURLSafeTokenWithByteCount:HARTSPRevisionRandomByteCount error:error];
        if (!revision) {
            return nil;
        }
        OSStatus updateStatus = SecItemUpdate((__bridge CFDictionaryRef)[self baseQuery],
                                              (__bridge CFDictionaryRef)@{
                                                  (__bridge id)kSecAttrGeneric:
                                                      [revision dataUsingEncoding:NSUTF8StringEncoding],
                                                  (__bridge id)kSecAttrAccessible:
                                                      (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                              });
        if (updateStatus != errSecSuccess) {
            [self assignError:error
                          code:HARTSPCredentialErrorKeychainFailure
                        status:updateStatus
                   description:@"The RTSP credential revision could not be saved."];
            return nil;
        }
    } else if (![self token:revision representsByteCount:HARTSPRevisionRandomByteCount]) {
        [self assignError:error
                      code:HARTSPCredentialErrorInvalidStoredCredential
                    status:errSecSuccess
               description:@"The stored RTSP credential revision has an invalid format."];
        return nil;
    }

    return [[HARTSPCredentials alloc] initWithPassword:password revision:revision];
}

#pragma mark - Generation and validation

- (HARTSPCredentials *)generateCredentialsWithError:(NSError **)error {
    NSString *password = [self randomURLSafeTokenWithByteCount:HARTSPPasswordRandomByteCount
                                                          error:error];
    if (!password) {
        return nil;
    }
    NSString *revision = [self randomURLSafeTokenWithByteCount:HARTSPRevisionRandomByteCount
                                                          error:error];
    if (!revision) {
        return nil;
    }
    return [[HARTSPCredentials alloc] initWithPassword:password revision:revision];
}

- (NSString *)randomURLSafeTokenWithByteCount:(NSUInteger)byteCount error:(NSError **)error {
    NSMutableData *randomData = [NSMutableData dataWithLength:byteCount];
    OSStatus status = SecRandomCopyBytes(kSecRandomDefault, byteCount, randomData.mutableBytes);
    if (status != errSecSuccess) {
        [self assignError:error
                      code:HARTSPCredentialErrorRandomGenerationFailed
                    status:status
               description:@"A secure RTSP access credential could not be generated."];
        return nil;
    }

    NSString *token = [randomData base64EncodedStringWithOptions:0];
    token = [token stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    token = [token stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    token = [token stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return token;
}

- (BOOL)token:(NSString *)token representsByteCount:(NSUInteger)byteCount {
    if (token.length == 0) {
        return NO;
    }

    NSCharacterSet *invalidCharacters =
        [[NSCharacterSet characterSetWithCharactersInString:
          @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet];
    if ([token rangeOfCharacterFromSet:invalidCharacters].location != NSNotFound) {
        return NO;
    }

    NSString *base64 = [token stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSUInteger remainder = base64.length % 4;
    if (remainder != 0) {
        base64 = [base64 stringByPaddingToLength:base64.length + (4 - remainder)
                                      withString:@"="
                                 startingAtIndex:0];
    }
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    return decoded.length == byteCount;
}

#pragma mark - Errors

- (BOOL)assignError:(NSError **)error
                code:(HARTSPCredentialErrorCode)code
              status:(OSStatus)status
         description:(NSString *)description {
    if (!error) {
        return NO;
    }

    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey: description} mutableCopy];
    if (status != errSecSuccess) {
        userInfo[NSUnderlyingErrorKey] = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                             code:status
                                                         userInfo:nil];
    }
    *error = [NSError errorWithDomain:HARTSPCredentialErrorDomain code:code userInfo:userInfo];
    return NO;
}

@end
