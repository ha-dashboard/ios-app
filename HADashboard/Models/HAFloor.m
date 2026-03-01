#import "HAFloor.h"

@implementation HAFloor

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _floorId = dict[@"floor_id"];
        _name = [dict[@"name"] isKindOfClass:[NSString class]] ? dict[@"name"] : _floorId;

        id level = dict[@"level"];
        if ([level isKindOfClass:[NSNumber class]]) {
            _level = [level integerValue];
        } else {
            _level = 0;
        }

        // Area IDs can be in "areas" key as an array of area_id strings
        NSArray *areas = dict[@"areas"];
        if ([areas isKindOfClass:[NSArray class]]) {
            NSMutableArray *areaIds = [NSMutableArray arrayWithCapacity:areas.count];
            for (id areaEntry in areas) {
                if ([areaEntry isKindOfClass:[NSString class]]) {
                    [areaIds addObject:areaEntry];
                }
            }
            _areaIds = [areaIds copy];
        } else {
            _areaIds = @[];
        }
    }
    return self;
}

@end
