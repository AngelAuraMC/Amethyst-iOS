#import "LauncherPrefJITViewController.h"
#import "LauncherPreferences.h"
#import "jit/BuiltinJIT.h"
#import "utils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation LauncherPrefJITViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"preference.title.jit_setup", nil);
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateStatus:) name:BuiltinJITStatusDidChangeNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)updateStatus:(NSNotification *)notification { [self.tableView reloadData]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : 7;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return localize(section == 0 ? @"jit.method.title" : @"jit.method.builtin", nil);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return localize(@"jit.method.detail", nil);
    NSString *reason = BuiltinJIT.unavailableReason;
    return reason ?: localize(@"jit.setup.instructions", nil);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = cell.detailTextLabel.numberOfLines = 0;
    BuiltinJIT *jit = BuiltinJIT.shared;
    BOOL available = BuiltinJIT.unavailableReason == nil;
    if (indexPath.section == 0) {
        NSString *method = @[@"external", @"builtin", @"wait"][indexPath.row];
        cell.textLabel.text = localize([@"jit.method." stringByAppendingString:method], nil);
        cell.accessoryType = [getPrefObject(@"jit.method") isEqual:method] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.userInteractionEnabled = !jit.busy && (indexPath.row != 1 || available);
    } else {
        NSArray *titles = @[@"jit.status.title", @"jit.pairing.import", @"jit.prepare", @"jit.txm.title", @"jit.force_script", @"jit.reset_ddi", @"jit.pairing.remove"];
        cell.textLabel.text = localize(titles[indexPath.row], nil);
        cell.userInteractionEnabled = available && !jit.busy;
        switch (indexPath.row) {
            case 0:
                cell.detailTextLabel.text = jit.status;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.userInteractionEnabled = NO;
                break;
            case 1:
                cell.detailTextLabel.text = jit.pairingFileName ?: localize(@"jit.pairing.missing", nil);
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 2:
                cell.userInteractionEnabled &= jit.hasPairingFile;
                break;
            case 3:
                cell.detailTextLabel.text = localize(jit.txmPresent ? (jit.txmPresent.boolValue ? @"jit.txm.present" : @"jit.txm.absent") : @"jit.txm.unknown", nil);
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.userInteractionEnabled = NO;
                break;
            case 4: {
                UISwitch *toggle = [UISwitch new];
                toggle.on = getPrefBool(@"jit.force_script");
                toggle.enabled = cell.userInteractionEnabled;
                [toggle addTarget:self action:@selector(changeForceScript:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                cell.detailTextLabel.text = localize(@"jit.force_script.detail", nil);
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            }
            case 6:
                cell.textLabel.textColor = UIColor.systemRedColor;
                cell.userInteractionEnabled &= jit.hasPairingFile;
                break;
        }
    }
    // Status rows remain legible while an operation is running.
    cell.textLabel.enabled = cell.userInteractionEnabled || (indexPath.section == 1 && (indexPath.row == 0 || indexPath.row == 3));
    return cell;
}

- (void)changeForceScript:(UISwitch *)sender { setPrefBool(@"jit.force_script", sender.on); }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        setPrefObject(@"jit.method", @[@"external", @"builtin", @"wait"][indexPath.row]);
        [tableView reloadData];
        return;
    }
    __weak LauncherPrefJITViewController *weakSelf = self;
    void (^completion)(NSError *) = ^(NSError *error) {
        [weakSelf.tableView reloadData];
        if (error) showDialog(localize(@"Error", nil), error.localizedDescription);
    };
    switch (indexPath.row) {
        case 1: {
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
            picker.delegate = self;
            picker.allowsMultipleSelection = NO;
            [self presentViewController:picker animated:YES completion:nil];
            break;
        }
        case 2: [BuiltinJIT.shared prepareWithCompletion:completion]; break;
        case 5: [BuiltinJIT.shared resetDDIWithCompletion:completion]; break;
        case 6: {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"jit.pairing.remove", nil) message:localize(@"jit.pairing.remove_confirm", nil) preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"jit.pairing.remove", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                NSError *error;
                [BuiltinJIT.shared removePairingFile:&error];
                completion(error);
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            break;
        }
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;
    NSError *error;
    if (![BuiltinJIT.shared importPairingFile:urls.firstObject error:&error]) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
    }
    [self.tableView reloadData];
}

@end
