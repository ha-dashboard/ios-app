#import "HABLEIdentityViewController.h"
#import "HABLEIdentityResolver.h"
#import "HABLEProxyManager.h"

@interface HABLEIdentityViewController ()
@property (nonatomic, copy) NSDictionary *observation;
@property (nonatomic, strong) HABLEIdentityResolver *resolver;
@property (nonatomic, copy) NSArray<NSDictionary *> *candidates;
@property (nonatomic, assign) BOOL identifying;
@end
@implementation HABLEIdentityViewController
- (instancetype)initWithObservation:(NSDictionary *)observation {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) { _observation = [observation copy]; _resolver = [[HABLEIdentityResolver alloc] init]; _candidates = @[]; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Bluetooth identity";
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 70;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(modelChanged:) name:HABLEProxyDidChangeNotification object:nil];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh:)]; [self refresh:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [self.resolver cancel]; }
- (void)modelChanged:(NSNotification *)note {
    for (NSDictionary *device in [HABLEProxyManager sharedManager].devices) if ([device[@"identifier"] isEqual:self.observation[@"identifier"]]) { self.observation = device; break; }
    self.candidates = [[HABLEProxyManager sharedManager] identityCandidatesForObservation:self.observation];
    [self.tableView reloadData];
}
- (void)refresh:(id)sender {
    [[HABLEProxyManager sharedManager] refreshIdentityInformation];
    [self modelChanged:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : self.candidates.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? self.observation[@"name"] : @"Observed and registered devices"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"HA identities and peer observations synchronize automatically." : @"HA identities, confirmed associations and fresh peer evidence synchronize automatically. Identical readings, names and services can belong to multiple devices. Ambiguous matches stay pending; confirm the physical device before creating an association.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.textLabel.numberOfLines = cell.detailTextLabel.numberOfLines = 0;
    if (path.section == 0 && path.row == 0) {
        cell.textLabel.text = self.observation[@"address"];
        NSMutableArray *lines = [NSMutableArray arrayWithObject:@"Current address used by this proxy"];
        for (NSString *field in @[@"serial_number", @"system_id", @"manufacturer_name", @"model_number"]) if ([self.observation[field] length]) [lines addObject:[NSString stringWithFormat:@"%@: %@", [field stringByReplacingOccurrencesOfString:@"_" withString:@" "], self.observation[field]]];
        if (self.observation[@"gatt_characteristic_uuids"]) [lines addObject:[NSString stringWithFormat:@"%lu GATT characteristics discovered", (unsigned long)[self.observation[@"gatt_characteristic_uuids"] count]]];
        cell.detailTextLabel.text = [lines componentsJoinedByString:@"\n"];
    }
    else if (path.section == 0 && path.row == 1) { cell.textLabel.text = @"Enter an address manually"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    else if (path.section == 0) { cell.textLabel.text = self.identifying ? @"Reading identification…" : @"Read identifying characteristics"; cell.detailTextLabel.text = @"Reads available identity fields and bounded read-only fingerprints. No device control commands are sent."; cell.userInteractionEnabled = !self.identifying; }
    else { NSDictionary *candidate = self.candidates[path.row]; cell.textLabel.text = candidate[@"label"]; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ %@\n%@", candidate[@"address"], candidate[@"manufacturer"] ?: @"", candidate[@"model"] ?: @"", candidate[@"evidence"]]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    return cell;
}
- (void)applyAddress:(NSString *)address {
    NSError *error;
    if ([[HABLEProxyManager sharedManager] setRealAddress:address forIdentifier:self.observation[@"identifier"] error:&error]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Could not link device" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; __weak typeof(self) weakSelf = self;
    if (path.section == 0 && path.row == 1) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hardware address" message:@"Enter a verified address as AA:BB:CC:DD:EE:FF. Leave blank to remove a manual association." preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"AA:BB:CC:DD:EE:FF"; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf applyAddress:[alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (path.section == 0 && path.row == 2) {
        self.identifying = YES; [self.tableView reloadData];
        [[HABLEProxyManager sharedManager] inspectIdentifier:self.observation[@"identifier"] completion:^(NSDictionary *identity, NSError *error) {
            HABLEIdentityViewController *self = weakSelf; if (!self) return;
            self.identifying = NO;
            if (identity) { NSMutableDictionary *updated = [self.observation mutableCopy]; [updated addEntriesFromDictionary:identity]; self.observation = updated; self.candidates = [[HABLEProxyManager sharedManager] identityCandidatesForObservation:updated]; }
            [self.tableView reloadData];
            if (error) { UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Identification unavailable" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; }
        }];
    } else if (path.section == 1) {
        NSDictionary *candidate = self.candidates[path.row];
        if (![candidate[@"address"] length]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Bluetooth address unavailable" message:@"Home Assistant knows this device's identity but has no independent Bluetooth address for it yet. Leave another scanner online and refresh, or enter its verified address manually." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil]; return;
        }
        NSString *message = [NSString stringWithFormat:@"Link this Bluetooth device to %@ (%@)?\n\n%@\n\nOnly confirm if these are the same physical device.", candidate[@"label"], candidate[@"address"], candidate[@"evidence"]];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm device identity" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Link device" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf applyAddress:candidate[@"address"]]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
