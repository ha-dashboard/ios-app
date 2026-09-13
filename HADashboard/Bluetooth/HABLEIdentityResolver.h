#import <Foundation/Foundation.h>

@interface HABLEIdentityResolver : NSObject
@property (nonatomic, readonly) NSArray<NSDictionary *> *knownDevices;
@property (nonatomic, readonly) NSString *status;
- (void)refreshExcludingSource:(NSString *)source completion:(void (^)(NSError *error))completion;
- (NSArray<NSDictionary *> *)candidatesForObservation:(NSDictionary *)observation;
/// Returns only an unambiguous address backed by a device-specific identifier.
- (NSDictionary *)automaticMatchForObservation:(NSDictionary *)observation;
- (void)rememberAutomaticMatch:(NSDictionary *)match;
- (void)cancel;
@end
