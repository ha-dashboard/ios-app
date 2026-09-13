#import <Foundation/Foundation.h>

extern NSString *const HABLEProxyDidChangeNotification;
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
- (void)registerWithHomeAssistant;
- (NSString *)encryptionKey;
- (void)resume;
- (void)suspend;
- (void)reset;
- (BOOL)setRealAddress:(NSString *)address forIdentifier:(NSString *)identifier error:(NSError **)error;
- (NSDictionary *)diagnostics;
- (void)inspectIdentifier:(NSString *)identifier completion:(void (^)(NSDictionary *identity, NSError *error))completion;
@end
