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
        return;
    }
    self.devices = manager.devices; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : section == 1 ? 3 : self.devices.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"Bluetooth Proxy", @"Home Assistant setup", @"Nearby devices"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Share nearby Bluetooth LE devices with Home Assistant while HA Dashboard is open. The connection is encrypted. Locking the screen or leaving the app pauses the proxy. This prototype uses Apple's public Bluetooth APIs.";
    if (section == 1) return @"Add an ESPHome integration in Home Assistant using this address and port 6053, then enter the encryption key. Home Assistant must be able to reach this device on the local network.";
    return @"Addresses published in supported SwitchBot advertisements are recognised automatically. Other devices use local aliases because Apple does not expose their hardware addresses. Tap a device to associate a verified address. Aliases do not match other proxies and cannot decrypt address-dependent sensor messages. Refresh to update this device list.";
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
    else { NSDictionary *device = self.devices[path.row]; cell.textLabel.text = device[@"name"]; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ dBm\n%@", device[@"address"], device[@"rssi"], [device[@"identity"] isEqual:@"local_alias"] ? @"Local alias" : [device[@"identity"] isEqual:@"switchbot_advertised_mac"] ? @"Address published by SwitchBot" : @"Associated hardware address"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:key ? @"Encryption key copied" : @"Key unavailable" message:key ? @"Paste it into the ESPHome integration's encryption key field. The clipboard copy expires after one minute." : @"Unlock this device and try again." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    } else if (path.section == 1 && path.row == 2) {
        [manager registerWithHomeAssistant];
    } else if (path.section == 2) {
        [self.navigationController pushViewController:[[HABLEIdentityViewController alloc] initWithObservation:self.devices[path.row]] animated:YES];
    }
}
@end
