#import "NSMutableURLRequest+HAHelpers.h"

@implementation NSMutableURLRequest (HAHelpers)

- (void)ha_setAuthHeaders:(NSString *)token {
    [self setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [self setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
}

+ (NSURLSessionConfiguration *)ha_defaultSessionConfiguration {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 15.0;
    config.timeoutIntervalForResource = 30.0;
    return config;
}

@end
