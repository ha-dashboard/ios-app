#import <Foundation/Foundation.h>
@interface HABLEProxyRegistration : NSObject
+ (BOOL)isSetupURLAllowed:(NSURL *)URL;
+ (BOOL)isSuccessfulExistingEntryReason:(NSString *)reason;
@property (nonatomic, readonly) BOOL registering;
@property (nonatomic, readonly) NSString *status;
@property (nonatomic, readonly) NSString *entryID;
- (void)registerHost:(NSString *)host key:(NSString *)key completion:(void (^)(BOOL success))completion;
- (void)cancel;
@end
