#import <Foundation/Foundation.h>

@interface HABLEIdentityResolver : NSObject
@property (nonatomic, readonly) NSArray<NSDictionary *> *knownDevices;
@property (nonatomic, readonly) NSString *status;
@property (nonatomic, readonly) BOOL needsRegistryRefresh;
- (void)refreshExcludingSource:(NSString *)source completion:(void (^)(NSError *error))completion;
- (void)recordObservation:(NSDictionary *)observation identifier:(NSString *)identifier;
- (void)removeIdentifier:(NSString *)identifier;
- (NSArray<NSDictionary *> *)candidatesForObservation:(NSDictionary *)observation;
- (NSDictionary *)automaticMatchForObservation:(NSDictionary *)observation;
- (BOOL)hasKnownIdentityForObservation:(NSDictionary *)observation;
- (void)rememberAutomaticMatch:(NSDictionary *)match;
- (void)rememberConfirmedAddress:(NSString *)address observation:(NSDictionary *)observation;
- (void)maintainSynchronization;
- (void)cancel;
@end
