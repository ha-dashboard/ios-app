#import "HABLEProxyViewController.h"
#import "HABLEProxyManager.h"
#import "HABLEIdentityViewController.h"
#import "HATheme.h"

@interface HABLEProxyViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *devices;
@end
@implementation HABLEProxyViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Bluetooth Proxy";
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 62;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshScan:)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:HABLEProxyDidChangeNotification object:nil];
    [self refresh:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh:nil]; }
- (void)refreshScan:(id)sender { [self refresh:nil]; }
- (void)refresh:(NSNotification *)notification {
    HABLEProxyManager *manager = [HABLEProxyManager sharedManager];
    if (notification) {
        // Keep scan rows stable while the user selects a device. Replacing and
        // reordering every second could associate a MAC with the wrong row.
        UITableViewCell *status = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        status.textLabel.text = manager.status;
        status.detailTextLabel.text = [NSString stringWithFormat:@"%lu advertisements received · %lu forwarded", (unsigned long)manager.advertisementCount, (unsigned long)manager.forwardedCount];
        UITableViewCell *host = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
        host.textLabel.text = manager.host ? [manager.host stringByAppendingString:@":6053"] : @"Proxy is not listening";
        UITableViewCell *registration = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:1]];
        registration.detailTextLabel.text = manager.registrationStatus;
        UITableViewCell *scan = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        scan.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu known services", manager.usingServiceFilters ? @"Using service filters" : @"Broad discovery", (unsigned long)manager.scanServiceUUIDs.count];
        UITableViewCell *import = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
        import.detailTextLabel.text = manager.scanServiceStatus;
        return;
    }
    self.devices = manager.devices; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : section <= 2 ? 3 : self.devices.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"Bluetooth Proxy", @"Home Assistant setup", @"Discovery", @"Nearby devices"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Share nearby Bluetooth LE devices with Home Assistant while HA Dashboard is open. The connection is encrypted. Locking the screen or leaving the iOS app pauses the proxy. Uses Apple's public Bluetooth APIs.";
    if (section == 1) return @"Register with Home Assistant automatically enables and registers the proxy unless you have switched it off here. Administrator access is required. You can also tap Add to Home Assistant, or add ESPHome manually using this address, port 6053 and the encryption key. HA must reach this device on the local network. Use HTTPS or a trusted local network.";
    if (section == 2) return @"Automatic starts with broad discovery. If no devices are discovered, it imports advertised service UUIDs from HA and tries service filters. Filtered scans can miss devices that do not advertise a known service. Additional UUIDs are combined with HA's services.";
    return @"Identities are learned automatically from Home Assistant, standard identifiers and synchronized observations. Ambiguous devices remain pending. Tap a device to inspect the evidence or confirm an association. Local aliases are not hardware addresses.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    HABLEProxyManager *manager = [HABLEProxyManager sharedManager];
    if (path.section == 0 && path.row == 0) {
        cell.textLabel.text = @"Enable Bluetooth Proxy"; UISwitch *toggle = [[UISwitch alloc] init]; toggle.on = manager.enabled;
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else if (path.section == 0) { cell.textLabel.text = manager.status; cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu advertisements received · %lu forwarded", (unsigned long)manager.advertisementCount, (unsigned long)manager.forwardedCount]; }
    else if (path.section == 1 && path.row == 0) { cell.textLabel.text = manager.host ? [manager.host stringByAppendingString:@":6053"] : @"Proxy is not listening"; cell.detailTextLabel.text = manager.nodeName; }
    else if (path.section == 1 && path.row == 1) { cell.textLabel.text = @"Copy encryption key"; cell.textLabel.textColor = self.view.tintColor; cell.detailTextLabel.text = @"Only share this key with your Home Assistant server."; cell.isAccessibilityElement = YES; cell.accessibilityLabel = @"Copy encryption key"; cell.accessibilityTraits = UIAccessibilityTraitButton; }
    else if (path.section == 1) { cell.textLabel.text = @"Add to Home Assistant"; cell.detailTextLabel.text = manager.registrationStatus; cell.isAccessibilityElement = YES; cell.accessibilityLabel = @"Add to Home Assistant"; cell.accessibilityTraits = UIAccessibilityTraitButton; }
    else if (path.section == 2) {
        if (path.row == 0) {
            cell.textLabel.text = [@"Scan mode: " stringByAppendingString:@[@"Automatic", @"Broad discovery", @"Known services"][manager.scanMode]];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu known services", manager.usingServiceFilters ? @"Using service filters" : @"Broad discovery", (unsigned long)manager.scanServiceUUIDs.count];
        } else if (path.row == 1) { cell.textLabel.text = @"Import services from HA"; cell.detailTextLabel.text = manager.scanServiceStatus; }
        else { cell.textLabel.text = @"Additional service UUIDs"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu manually added", (unsigned long)manager.additionalScanServiceUUIDs.count]; }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    else { NSDictionary *device = self.devices[path.row]; cell.textLabel.text = device[@"ha_name"] ?: device[@"name"]; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ dBm\n%@", device[@"address"], device[@"rssi"], [device[@"identity_pending"] boolValue] ? @"Waiting for identity evidence" : [device[@"identity"] isEqual:@"local_alias"] ? @"Local alias" : [device[@"identity"] isEqual:@"ha_matched_mac"] ? @"Matched with Home Assistant" : [device[@"identity"] isEqual:@"shared_observed_address"] ? @"Shared Bluetooth identity" : [device[@"identity"] isEqual:@"shared_alias"] ? @"Shared synthetic identity" : @"Associated hardware address"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    return cell;
}
- (void)toggled:(UISwitch *)toggle { [HABLEProxyManager sharedManager].enabled = toggle.on; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; HABLEProxyManager *manager = [HABLEProxyManager sharedManager];
    if (path.section == 1 && path.row == 1) {
        NSString *key = [manager encryptionKey];
        if (key) {
            if (@available(iOS 10.0, *)) [[UIPasteboard generalPasteboard] setItems:@[@{@"public.utf8-plain-text":key}] options:@{UIPasteboardOptionLocalOnly:@YES, UIPasteboardOptionExpirationDate:[[NSDate date] dateByAddingTimeInterval:60]}];
            else {
                [UIPasteboard generalPasteboard].string = key; NSInteger change = [UIPasteboard generalPasteboard].changeCount;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if ([UIPasteboard generalPasteboard].changeCount == change) [UIPasteboard generalPasteboard].items = @[]; });
            }
        }
        NSString *copyMessage = @"Paste it into the ESPHome integration's encryption key field. Clear the clipboard after setup; this iOS version can only expire it while the app can run.";
        if (@available(iOS 10.0, *)) copyMessage = @"Paste it into the ESPHome integration's encryption key field. The clipboard copy expires after one minute.";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:key ? @"Encryption key copied" : @"Key unavailable" message:key ? copyMessage : @"Unlock this device and try again." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    } else if (path.section == 1 && path.row == 2) {
        [manager registerWithHomeAssistant];
    } else if (path.section == 2 && path.row == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Discovery mode" message:@"Automatic adapts when broad scanning returns no discoveries." preferredStyle:UIAlertControllerStyleAlert];
        NSArray *names = @[@"Automatic", @"Broad discovery", @"Known services"];
        for (NSUInteger index = 0; index < names.count; index++) [alert addAction:[UIAlertAction actionWithTitle:names[index] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { manager.scanMode = index; [self refresh:nil]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (path.section == 2 && path.row == 1) {
        [manager refreshScanServices];
    } else if (path.section == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Additional service UUIDs" message:@"Enter advertised service UUIDs separated by commas. These are combined with services imported from HA." preferredStyle:UIAlertControllerStyleAlert];
        __weak UIAlertController *weakAlert = alert;
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = [manager.additionalScanServiceUUIDs componentsJoinedByString:@", "]; field.placeholder = @"For example: FCD2"; field.autocorrectionType = UITextAutocorrectionTypeNo; field.keyboardType = UIKeyboardTypeASCIICapable; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSArray *values = [weakAlert.textFields.firstObject.text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",; \n"]]; NSError *error;
            if ([manager setAdditionalScanServiceUUIDs:values error:&error]) [self refresh:nil];
            else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 3), dispatch_get_main_queue(), ^{
                UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"Invalid service UUID" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [failure addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:failure animated:YES completion:nil];
            });
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    } else if (path.section == 3) {
        [self.navigationController pushViewController:[[HABLEIdentityViewController alloc] initWithObservation:self.devices[path.row]] animated:YES];
    }
}
@end
