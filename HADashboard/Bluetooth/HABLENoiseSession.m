#import "HABLENoiseSession.h"
#import "monocypher.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>

static void HABLEHash(const void *bytes, size_t length, uint8_t out[32]) { CC_SHA256(bytes, (CC_LONG)length, out); }
static void HABLEMixHash(uint8_t hash[32], const void *bytes, size_t length) {
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); CC_SHA256_Update(&ctx, hash, 32);
    CC_SHA256_Update(&ctx, bytes, (CC_LONG)length); CC_SHA256_Final(hash, &ctx);
}
static void HABLEHKDF(uint8_t chain[32], const void *input, size_t length, uint8_t second[32], uint8_t *third) {
    uint8_t temp[32], one[32], message[33], two[32];
    CCHmac(kCCHmacAlgSHA256, chain, 32, input, length, temp);
    message[0] = 1; CCHmac(kCCHmacAlgSHA256, temp, 32, message, 1, one);
    memcpy(message, one, 32); message[32] = 2;
    CCHmac(kCCHmacAlgSHA256, temp, 32, message, 33, two);
    if (third) { memcpy(message, two, 32); message[32] = 3; CCHmac(kCCHmacAlgSHA256, temp, 32, message, 33, third); }
    memcpy(chain, one, 32); memcpy(second, two, 32);
    crypto_wipe(temp, 32); crypto_wipe(one, 32); crypto_wipe(two, 32); crypto_wipe(message, 33);
}
static NSData *HABLEAEAD(NSData *input, uint8_t key[32], uint64_t nonce, const uint8_t *ad, size_t adLength, BOOL encrypt) {
    if (!encrypt && input.length < 16) return nil;
    uint8_t iv[12] = {0};
    for (NSUInteger i = 0; i < 8; i++) iv[i + 4] = (uint8_t)(nonce >> (8 * i));
    crypto_aead_ctx ctx; crypto_aead_init_ietf(&ctx, key, iv);
    NSUInteger size = encrypt ? input.length : input.length - 16;
    NSMutableData *result = [NSMutableData dataWithLength:size + (encrypt ? 16 : 0)];
    // A real one-byte allocation also gives C a non-null pointer for empty messages.
    uint8_t dummy = 0;
    uint8_t *out = result.length ? result.mutableBytes : &dummy;
    const uint8_t *bytes = input.length ? input.bytes : &dummy;
    if (encrypt) crypto_aead_write(&ctx, out, out + size, ad, adLength, bytes, size);
    else if (crypto_aead_read(&ctx, out, bytes + size, ad, adLength, bytes, size)) { crypto_wipe(&ctx, sizeof(ctx)); return nil; }
    crypto_wipe(&ctx, sizeof(ctx));
    return result;
}

@implementation HABLENoiseSession {
    uint8_t _psk[32], _receiveKey[32], _sendKey[32];
    uint64_t _receiveNonce, _sendNonce;
    BOOL _ready, _attempted;
}
- (instancetype)initWithKey:(NSData *)key {
    if (key.length != 32) return nil;
    if ((self = [super init])) memcpy(_psk, key.bytes, 32);
    return self;
}
- (void)dealloc {
    crypto_wipe(_psk, 32); crypto_wipe(_receiveKey, 32); crypto_wipe(_sendKey, 32);
}
- (NSData *)respondToHandshake:(NSData *)message {
    if (_attempted || message.length != 48) return nil;
    _attempted = YES;
    uint8_t hash[32], chain[32], key[32], temporary[32], secret[32], publicKey[32], dh[32];
    const char *name = "Noise_NNpsk0_25519_ChaChaPoly_SHA256";
    HABLEHash(name, strlen(name), hash); memcpy(chain, hash, 32);
    static const uint8_t prologue[] = "NoiseAPIInit\0\0";
    HABLEMixHash(hash, prologue, sizeof(prologue) - 1);
    HABLEHKDF(chain, _psk, 32, temporary, key); HABLEMixHash(hash, temporary, 32);
    const uint8_t *remote = message.bytes;
    HABLEMixHash(hash, remote, 32); HABLEHKDF(chain, remote, 32, key, NULL);
    NSData *payload = [message subdataWithRange:NSMakeRange(32, 16)];
    BOOL ok = HABLEAEAD(payload, key, 0, hash, 32, NO) != nil;
    NSMutableData *response = nil;
    if (ok && SecRandomCopyBytes(kSecRandomDefault, 32, secret) == errSecSuccess) {
        HABLEMixHash(hash, payload.bytes, payload.length);
        crypto_x25519_public_key(publicKey, secret);
        HABLEMixHash(hash, publicKey, 32); HABLEHKDF(chain, publicKey, 32, key, NULL);
        crypto_x25519(dh, secret, remote);
        uint8_t aggregate = 0; for (NSUInteger i = 0; i < 32; i++) aggregate |= dh[i];
        if (aggregate) {
            HABLEHKDF(chain, dh, 32, key, NULL);
            NSData *tag = HABLEAEAD([NSData data], key, 0, hash, 32, YES);
            response = [NSMutableData dataWithBytes:publicKey length:32]; [response appendData:tag];
            HABLEMixHash(hash, tag.bytes, tag.length);
            HABLEHKDF(chain, NULL, 0, _sendKey, NULL); memcpy(_receiveKey, chain, 32);
            _ready = YES;
        }
    }
    crypto_wipe(_psk, 32); crypto_wipe(hash, 32); crypto_wipe(chain, 32); crypto_wipe(key, 32);
    crypto_wipe(temporary, 32); crypto_wipe(secret, 32); crypto_wipe(publicKey, 32); crypto_wipe(dh, 32);
    return response;
}
- (NSData *)encrypt:(NSData *)plaintext {
    if (!_ready || _sendNonce == UINT64_MAX || plaintext.length > 16388) return nil;
    return HABLEAEAD(plaintext, _sendKey, _sendNonce++, NULL, 0, YES);
}
- (NSData *)decrypt:(NSData *)ciphertext {
    if (!_ready || _receiveNonce == UINT64_MAX || ciphertext.length > 16404) return nil;
    NSData *result = HABLEAEAD(ciphertext, _receiveKey, _receiveNonce++, NULL, 0, NO);
    if (!result) _ready = NO;
    return result;
}
@end
