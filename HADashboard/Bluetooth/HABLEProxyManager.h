#import <Foundation/Foundation.h>

extern NSString *const HABLEProxyDidChangeNotification;
typedef NS_ENUM(NSUInteger, HABLEScanMode) {
    HABLEScanModeAutomatic = 0,
    HABLEScanModeBroad = 1,
    HABLEScanModeServices = 2,
};
@interface HABLEProxyManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) NSString *status;
@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) NSString *nodeName;
@property (nonatomic, readonly) NSString *adapterAddress;
@property (nonatomic, readonly) NSUInteger advertisementCount;
@property (nonatomic, readonly) NSUInteger forwardedCount;
@property (nonatomic, readonly) NSArray<NSDictionary *> *devices;
@property (nonatomic, readonly) NSString *registrationStatus;
@property (nonatomic, assign) HABLEScanMode scanMode;
@property (nonatomic, readonly) BOOL usingServiceFilters;
@property (nonatomic, readonly) NSArray<NSString *> *scanServiceUUIDs;
@property (nonatomic, readonly) NSArray<NSString *> *additionalScanServiceUUIDs;
@property (nonatomic, readonly) NSString *scanServiceStatus;
- (BOOL)setAdditionalScanServiceUUIDs:(NSArray<NSString *> *)values error:(NSError **)error;
- (void)refreshScanServices;
- (void)registerWithHomeAssistant;
- (void)refreshIdentityInformation;
- (NSArray<NSDictionary *> *)identityCandidatesForObservation:(NSDictionary *)observation;
- (NSString *)encryptionKey;
- (void)resume;
- (void)suspend;
- (void)reset;
- (BOOL)setRealAddress:(NSString *)address forIdentifier:(NSString *)identifier error:(NSError **)error;
- (NSDictionary *)diagnostics;
- (void)inspectIdentifier:(NSString *)identifier completion:(void (^)(NSDictionary *identity, NSError *error))completion;
@end
