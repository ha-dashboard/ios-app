#import <Foundation/Foundation.h>

// ESPHome's documented Noise_NNpsk0_25519_ChaChaPoly_SHA256 responder.
// Cryptographic primitives are Monocypher 4.0.2 and CommonCrypto SHA256/HMAC.
@interface HABLENoiseSession : NSObject
- (instancetype)initWithKey:(NSData *)key;
- (NSData *)respondToHandshake:(NSData *)message;
- (NSData *)encrypt:(NSData *)plaintext;
- (NSData *)decrypt:(NSData *)ciphertext;
@end
