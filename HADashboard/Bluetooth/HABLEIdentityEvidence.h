#import <Foundation/Foundation.h>

/// Brand-independent, bounded correlation of actual observed BLE payloads.
@interface HABLEIdentityEvidence : NSObject
+ (NSDictionary *)fingerprintsForValue:(NSData *)data path:(NSString *)path;
+ (BOOL)isIdentifierFingerprint:(NSDictionary *)fingerprint path:(NSString *)path;
+ (BOOL)identifierFingerprints:(NSDictionary *)a conflictWith:(NSDictionary *)b;
+ (NSDictionary *)mergeFingerprintReads:(NSDictionary *)reads previous:(NSDictionary *)previous session:(NSString *)session atTime:(NSTimeInterval)time;
+ (NSArray<NSString *> *)tokensForObservation:(NSDictionary *)observation;
+ (NSArray<NSString *> *)tokensForRawAdvertisement:(NSData *)raw;
+ (BOOL)tokens:(NSArray<NSString *> *)local agreeWith:(NSArray<NSString *> *)remote;
+ (BOOL)tokens:(NSArray<NSString *> *)local corroborateAddress:(NSString *)address withTokens:(NSArray<NSString *> *)remote;
+ (NSArray<NSString *> *)canonicalServices:(NSArray *)values;
+ (BOOL)observation:(NSDictionary *)observation containsUUID:(NSString *)uuid;
+ (BOOL)observation:(NSDictionary *)observation containsAddress:(NSString *)address;
- (void)recordLocal:(NSDictionary *)observation identifier:(NSString *)identifier atTime:(NSTimeInterval)time;
- (void)recordRemoteTokens:(NSArray<NSString *> *)tokens address:(NSString *)address source:(NSString *)source atTime:(NSTimeInterval)time;
- (void)recordRemoteTokens:(NSArray<NSString *> *)tokens address:(NSString *)address source:(NSString *)source atTime:(NSTimeInterval)time lastSeen:(NSTimeInterval)lastSeen;
- (NSDictionary *)correlationForIdentifier:(NSString *)identifier address:(NSString *)address now:(NSTimeInterval)now;
- (BOOL)hasCompetingLocalIdentifier:(NSString *)identifier address:(NSString *)address now:(NSTimeInterval)now;
- (NSArray<NSDictionary *> *)recentLocalEventsForIdentifier:(NSString *)identifier now:(NSTimeInterval)now;
- (void)removeIdentifier:(NSString *)identifier;
- (void)reset;
@end
