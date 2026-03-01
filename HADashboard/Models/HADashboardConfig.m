#import "HADashboardConfig.h"

#pragma mark - HADashboardConfigItem

@implementation HADashboardConfigItem

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _entityId    = [dict[@"entity_id"] isKindOfClass:[NSString class]] ? dict[@"entity_id"] : @"";
        _displayName = dict[@"display_name"];
        _column      = [dict[@"column"] integerValue];
        _row         = [dict[@"row"] integerValue];
        _columnSpan  = dict[@"column_span"] ? [dict[@"column_span"] integerValue] : 1;
        _rowSpan     = dict[@"row_span"] ? [dict[@"row_span"] integerValue] : 1;
    }
    return self;
}

@end


#pragma mark - HADashboardConfigSection

@implementation HADashboardConfigSection
@end


#pragma mark - HADashboardConfig

@implementation HADashboardConfig

+ (instancetype)configFromJSONData:(NSData *)data error:(NSError **)error {
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"HADashboardConfig"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"No data provided"}];
        }
        return nil;
    }

    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    HADashboardConfig *config = [[HADashboardConfig alloc] init];
    config.title   = [dict[@"title"] isKindOfClass:[NSString class]] ? dict[@"title"] : @"Dashboard";
    config.columns = dict[@"columns"] ? [dict[@"columns"] integerValue] : 3;

    NSArray *itemDicts = dict[@"items"];
    if ([itemDicts isKindOfClass:[NSArray class]]) {
        NSMutableArray *items = [NSMutableArray arrayWithCapacity:itemDicts.count];
        for (NSDictionary *itemDict in itemDicts) {
            if ([itemDict isKindOfClass:[NSDictionary class]]) {
                [items addObject:[[HADashboardConfigItem alloc] initWithDictionary:itemDict]];
            }
        }
        config.items = [items copy];
    } else {
        config.items = @[];
    }

    // Wrap items into a single section for backward compatibility
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.title = nil;
    section.items = config.items;
    config.sections = @[section];

    return config;
}

+ (instancetype)configFromFileAtPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    return [self configFromJSONData:data error:error];
}

+ (instancetype)defaultConfigWithEntityIds:(NSArray<NSString *> *)entityIds columns:(NSInteger)columns {
    HADashboardConfig *config = [[HADashboardConfig alloc] init];
    config.title = @"Dashboard";
    config.columns = columns > 0 ? columns : 3;

    NSMutableArray *items = [NSMutableArray arrayWithCapacity:entityIds.count];
    for (NSUInteger i = 0; i < entityIds.count; i++) {
        HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
        item.entityId   = entityIds[i];
        item.column     = (NSInteger)(i % config.columns);
        item.row        = (NSInteger)(i / config.columns);
        item.columnSpan = 1;
        item.rowSpan    = 1;
        [items addObject:item];
    }
    config.items = [items copy];

    // Single section for backward compatibility
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.title = nil;
    section.items = config.items;
    config.sections = @[section];

    return config;
}

- (NSArray<NSString *> *)allEntityIds {
    NSMutableArray *ids = [NSMutableArray array];
    for (HADashboardConfigSection *section in self.sections) {
        for (HADashboardConfigItem *item in section.items) {
            if (item.entityId.length > 0) {
                [ids addObject:item.entityId];
            }
        }
    }
    return [ids copy];
}

@end
