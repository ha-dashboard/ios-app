#import <Foundation/Foundation.h>

@class HABLEAPIServer;
@interface HABLEAPIConnection : NSObject
@property (nonatomic, assign) BOOL advertisements;
@property (nonatomic, assign) BOOL logs;
@property (nonatomic, assign) BOOL connectionSlots;
@property (nonatomic, readonly) BOOL authenticated;
@end

@protocol HABLEAPIServerDelegate <NSObject>
- (void)bleServer:(HABLEAPIServer *)server receivedType:(NSUInteger)type data:(NSData *)data connection:(HABLEAPIConnection *)connection;
- (void)bleServer:(HABLEAPIServer *)server closedConnection:(HABLEAPIConnection *)connection;
@end

// Main-run-loop transport, encrypted only. Does not implement Bluetooth semantics.
@interface HABLEAPIServer : NSObject
@property (nonatomic, weak) id<HABLEAPIServerDelegate> delegate;
@property (nonatomic, readonly) NSUInteger authenticatedClients;
- (instancetype)initWithName:(NSString *)name address:(NSString *)address key:(NSData *)key;
- (BOOL)startWithHost:(NSString *)host port:(uint16_t)port error:(NSError **)error;
- (void)stop;
- (void)sendType:(NSUInteger)type data:(NSData *)data to:(HABLEAPIConnection *)connection;
- (BOOL)broadcastAdvertisement:(NSData *)data;
- (void)broadcastSlots:(NSData *)data;
- (void)broadcastLog:(NSString *)message;
@end
