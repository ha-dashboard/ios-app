#import "HAAutoLayout.h"
#import "HAMapCardCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"

@interface HAMapCardCell ()
@property (nonatomic, strong) MKMapView *mapView;
@end

@implementation HAMapCardCell

- (void)setupSubviews {
    [super setupSubviews];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    self.mapView = [[MKMapView alloc] init];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.layer.cornerRadius = 12;
    self.mapView.clipsToBounds = YES;
    self.mapView.userInteractionEnabled = NO; // static map in card view
    [self.contentView addSubview:self.mapView];

    HAPinEdgesFlush(self.mapView, self.contentView);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        self.mapView.frame = self.contentView.bounds;
    }
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary<NSString *, HAEntity *> *)entities
                  configItem:(HADashboardConfigItem *)configItem {
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    [self.mapView removeAnnotations:self.mapView.annotations];

    NSDictionary *props = section.customProperties;
    NSNumber *defaultZoom = props[@"default_zoom"];
    BOOL darkMode = [props[@"dark_mode"] boolValue];

    // Dark mode map appearance (iOS 13+)
    if (@available(iOS 13.0, *)) {
        self.mapView.overrideUserInterfaceStyle = darkMode ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
    }

    // Add entity locations as annotations
    CLLocationCoordinate2D sumCoord = {0, 0};
    NSInteger count = 0;

    for (NSString *eid in section.entityIds) {
        HAEntity *entity = entities[eid];
        if (!entity) continue;

        NSNumber *lat = entity.attributes[@"latitude"];
        NSNumber *lon = entity.attributes[@"longitude"];
        if (![lat isKindOfClass:[NSNumber class]] || ![lon isKindOfClass:[NSNumber class]]) continue;

        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake([lat doubleValue], [lon doubleValue]);
        MKPointAnnotation *pin = [[MKPointAnnotation alloc] init];
        pin.coordinate = coord;
        pin.title = entity.attributes[@"friendly_name"] ?: eid;
        [self.mapView addAnnotation:pin];

        sumCoord.latitude += coord.latitude;
        sumCoord.longitude += coord.longitude;
        count++;
    }

    // Center map on entities
    if (count > 0) {
        CLLocationCoordinate2D center = CLLocationCoordinate2DMake(sumCoord.latitude / count,
                                                                    sumCoord.longitude / count);
        double zoom = defaultZoom ? [defaultZoom doubleValue] : 14.0;
        // Convert zoom level to region span (approximate)
        double span = 360.0 / pow(2.0, zoom);
        MKCoordinateRegion region = MKCoordinateRegionMake(center, MKCoordinateSpanMake(span, span));
        [self.mapView setRegion:region animated:NO];
    }

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.mapView removeAnnotations:self.mapView.annotations];
}

@end
