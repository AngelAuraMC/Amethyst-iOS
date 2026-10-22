#import "ModrinthModsViewController.h"
#import "modpack/ModrinthAPI.h"
#import "modpack/CurseForgeAPI.h"
#import "modpack/ModrinthSearchFilters.h"
#import "modpack/ModrinthModInstallation.h"
#import "modpack/InstalledModsManager.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "UIImageView+AFNetworking.h"
#import "AFImageDownloader.h"
#import "utils.h"

@interface ModrinthIconView : UIImageView
@end

@implementation ModrinthIconView
+ (AFImageDownloader *)sharedImageDownloader {
    static AFImageDownloader *downloader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        downloader = [AFImageDownloader new];
        AFImageResponseSerializer *serializer = [AFImageResponseSerializer serializer];
        // Modrinth's CDN serves modern formats missing from AFNetworking's original MIME list.
        serializer.acceptableContentTypes = [serializer.acceptableContentTypes setByAddingObjectsFromArray:@[@"image/webp", @"image/avif"]];
        downloader.sessionManager.responseSerializer = serializer;
    });
    return downloader;
}
@end

@interface ModrinthModCell : UITableViewCell
@property(nonatomic) ModrinthIconView *modIconView;
@property(nonatomic) UILabel *modTitleLabel;
@property(nonatomic) UILabel *modAuthorLabel;
@property(nonatomic) UILabel *modDescriptionLabel;
- (void)configureWithProject:(NSDictionary *)project;
@end

@implementation ModrinthModCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (!self) return nil;
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    self.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 12, 8, 12);

    self.modIconView = [ModrinthIconView new];
    self.modIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.modIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.modIconView.clipsToBounds = YES;
    self.modIconView.layer.cornerRadius = 6;
    self.modIconView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.modIconView.tintColor = UIColor.secondaryLabelColor;
    [self.contentView addSubview:self.modIconView];

    self.modTitleLabel = [UILabel new];
    self.modTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.modAuthorLabel = [UILabel new];
    self.modAuthorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.modAuthorLabel.textColor = UIColor.secondaryLabelColor;
    self.modDescriptionLabel = [UILabel new];
    self.modDescriptionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.modDescriptionLabel.textColor = UIColor.secondaryLabelColor;
    for (UILabel *label in @[self.modTitleLabel, self.modAuthorLabel, self.modDescriptionLabel]) {
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.adjustsFontForContentSizeCategory = YES;
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    }
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[self.modTitleLabel, self.modAuthorLabel, self.modDescriptionLabel]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:text];

    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.modIconView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [self.modIconView.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [self.modIconView.widthAnchor constraintEqualToConstant:44],
        [self.modIconView.heightAnchor constraintEqualToConstant:44],
        [self.modIconView.bottomAnchor constraintLessThanOrEqualToAnchor:margins.bottomAnchor],
        [text.leadingAnchor constraintEqualToAnchor:self.modIconView.trailingAnchor constant:12],
        [text.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [text.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [text.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor]
    ]];
    self.separatorInset = UIEdgeInsetsMake(0, 68, 0, 0);
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    [self.modIconView cancelImageDownloadTask];
    self.modIconView.image = nil;
}
- (void)configureWithProject:(NSDictionary *)project {
    self.modTitleLabel.text = project[@"title"];
    self.modAuthorLabel.text = project[@"author"];
    self.modAuthorLabel.hidden = !self.modAuthorLabel.text.length;
    self.modDescriptionLabel.text = project[@"description"];
    self.modDescriptionLabel.hidden = !self.modDescriptionLabel.text.length;
    self.accessibilityLabel = [@[self.modTitleLabel.text ?: @"", self.modAuthorLabel.text ?: @"", self.modDescriptionLabel.text ?: @""] componentsJoinedByString:@". "];

    [self.modIconView cancelImageDownloadTask];
    UIImage *placeholder = [UIImage imageNamed:@"DefaultProfile"] ?: [UIImage systemImageNamed:@"cube.box"];
    self.modIconView.image = placeholder;
    NSString *iconURL = project[@"imageUrl"];
    if (iconURL.length) [self.modIconView setImageWithURL:[NSURL URLWithString:iconURL] placeholderImage:placeholder];
}
@end

static NSString *MRLoaderTitle(NSString *loader) {
    NSDictionary *names = @{@"fabric": @"Fabric", @"quilt": @"Quilt", @"forge": @"Forge", @"neoforge": @"NeoForge", @"liteloader": @"LiteLoader", @"rift": @"Rift"};
    return names[loader] ?: localize(@"mods.filter.any", nil);
}

static ModpackAPI *ContentAPI(NSString *provider) { return [provider isEqual:@"curseforge"] ? [CurseForgeAPI new] : [ModrinthAPI new]; }
static NSString *ContentProviderTitle(NSString *provider) { return [provider isEqual:@"curseforge"] ? @"CurseForge" : @"Modrinth"; }
static NSString *ContentFolder(NSString *type) { return @{@"mod": @"mods", @"resourcepack": @"resourcepacks", @"shader": @"shaderpacks"}[type] ?: @"mods"; }

static NSString *MRFilterSummary(NSDictionary *filters) {
    NSString *game = [filters[@"mcVersion"] length] ? filters[@"mcVersion"] : localize(@"mods.filter.any", nil);
    if (![[ModrinthSearchFilters contentTypeForFilters:filters] isEqual:@"mod"]) return [@"Minecraft " stringByAppendingString:game];
    return [NSString stringWithFormat:@"Minecraft %@ · %@", game, MRLoaderTitle(filters[@"loader"])];
}

static NSString *MRCategoryTitle(NSString *category) {
    NSString *key = [@"mods.category." stringByAppendingString:category];
    NSString *title = localize(key, nil);
    return [title isEqual:key] ? [[category stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString] : title;
}

static NSString *MRCategorySymbol(NSString *category) {
    static NSDictionary *symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        symbols = @{@"adventure": @"safari", @"cursed": @"ant", @"decoration": @"house", @"economy": @"dollarsign.circle", @"equipment": @"shield", @"food": @"leaf", @"game-mechanics": @"slider.horizontal.3", @"library": @"books.vertical", @"magic": @"wand.and.stars", @"management": @"server.rack", @"minigame": @"flag", @"mobs": @"pawprint", @"optimization": @"bolt", @"social": @"person.2", @"storage": @"archivebox", @"technology": @"cpu", @"transportation": @"tram", @"utility": @"wrench.and.screwdriver", @"worldgen": @"globe", @"combat": @"shield", @"modded": @"puzzlepiece", @"realistic": @"camera", @"simplistic": @"square", @"themed": @"paintpalette", @"tweaks": @"slider.horizontal.3", @"vanilla-like": @"leaf", @"cartoon": @"pencil", @"fantasy": @"wand.and.stars", @"semi-realistic": @"camera.filters"};
    });
    return symbols[category] ?: @"tag";
}

@interface ModrinthCategoriesViewController : UITableViewController
@property(nonatomic) NSArray<NSString *> *categories;
@property(nonatomic) NSArray<NSDictionary *> *records;
@property(nonatomic) NSString *provider, *contentType;
@property(nonatomic) NSMutableSet<NSString *> *selectedCategories;
@property(nonatomic) NSError *error;
@property(nonatomic) BOOL loading;
@property(nonatomic, copy) void (^catalogLoaded)(NSArray<NSDictionary *> *);
@property(nonatomic, copy) void (^selectionApplied)(NSArray<NSString *> *);
@end

@implementation ModrinthCategoriesViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"mods.filter.categories", nil);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(apply)];
    if (!self.categories) [self loadCategories];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)apply {
    if (self.selectionApplied) self.selectionApplied([self.selectedCategories.allObjects sortedArrayUsingSelector:@selector(compare:)]);
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)loadCategories {
    if (self.loading) return;
    self.loading = YES;
    self.error = nil;
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ModpackAPI *api = ContentAPI(self.provider);
        NSArray *records = [api categoriesForContentType:self.contentType ?: @"mod"];
        NSArray *categories = [records valueForKey:@"id"];
        NSError *error = api.lastError;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            self.categories = categories;
            self.records = records;
            self.error = error;
            if (records && self.catalogLoaded) self.catalogLoaded(records);
            [self.tableView reloadData];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : MAX(1, self.categories.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 1 ? localize([self.provider isEqual:@"curseforge"] ? @"content.categories.curseforge_help" : @"mods.filter.categories_help", nil) : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    BOOL selected = NO;
    if (indexPath.section == 0) {
        cell.textLabel.text = localize(@"mods.filter.categories_all", nil);
        cell.imageView.image = [UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"];
        selected = !self.selectedCategories.count;
    } else if (self.categories.count) {
        NSString *category = self.categories[indexPath.row];
        NSDictionary *record = self.records[indexPath.row];
        cell.textLabel.text = [record[@"name"] length] ? record[@"name"] : MRCategoryTitle(record[@"slug"] ?: category);
        cell.imageView.image = [UIImage systemImageNamed:MRCategorySymbol(record[@"slug"] ?: category)] ?: [UIImage systemImageNamed:@"tag"];
        selected = [self.selectedCategories containsObject:category];
    } else {
        cell.textLabel.text = localize(self.loading ? @"mods.loading" : self.error ? @"mods.retry" : @"mods.filter.categories_empty", nil);
        cell.detailTextLabel.text = self.error.localizedDescription;
        cell.selectionStyle = self.error ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    cell.imageView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    cell.imageView.tintColor = selected ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) [self.selectedCategories removeAllObjects];
    else if (self.categories.count) {
        NSString *category = self.categories[indexPath.row];
        if ([self.selectedCategories containsObject:category]) [self.selectedCategories removeObject:category];
        else if (![self.provider isEqual:@"curseforge"] || self.selectedCategories.count < 10) [self.selectedCategories addObject:category];
    } else if (self.error) { [self loadCategories]; return; }
    [self.tableView reloadData];
}
@end

@interface ModrinthDownloadCell : UITableViewCell
@property(nonatomic) UILabel *title, *summary;
@property(nonatomic) UIProgressView *downloadProgress;
@end
@implementation ModrinthDownloadCell
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) {
        self.title = [UILabel new];
        self.title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        self.summary = [UILabel new];
        self.summary.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        self.summary.textColor = UIColor.secondaryLabelColor;
        for (UILabel *label in @[self.title, self.summary]) {
            label.numberOfLines = 0;
            label.adjustsFontForContentSizeCategory = YES;
        }
        self.downloadProgress = [UIProgressView new];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.title, self.downloadProgress, self.summary]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor], [stack.topAnchor constraintEqualToAnchor:margins.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor]]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}
@end

@interface ModrinthVersionsViewController : UITableViewController
@property(nonatomic) NSDictionary *project, *filters;
@property(nonatomic) NSArray<NSDictionary *> *versions;
@property(nonatomic) NSError *error;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSUInteger loadGeneration;
@property(nonatomic) NSArray *contextSignature;
@property(nonatomic) NSString *targetProfileName, *renderSignature;
@property(nonatomic) ModrinthModInstallation *installation;
@property(nonatomic) NSDictionary *lastAttempt;
@property(nonatomic) BOOL retryAfterChecking;
@property(nonatomic) ModrinthDownloadCell *downloadCell;
@end

@implementation ModrinthVersionsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.project[@"title"];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(profileChanged:) name:PLProfilesDidChangeNotification object:nil];
    [self refreshContext];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshContext];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)profileChanged:(NSNotification *)notification { dispatch_async(dispatch_get_main_queue(), ^{ [self refreshContext]; }); }
- (void)refreshContext {
    PLProfiles *profiles = PLProfiles.current;
    NSDictionary *profile = profiles.selectedProfile ?: @{};
    NSString *root = profiles.profilePath.stringByDeletingLastPathComponent;
    NSString *gameDir = [profile[@"gameDir"] isKindOfClass:NSString.class] && [profile[@"gameDir"] length] ? profile[@"gameDir"] : @".";
    NSArray *signature = @[root ?: @"", profiles.selectedProfileName ?: @"", gameDir, profile[@"lastVersionId"] ?: @""];
    if ([signature isEqual:self.contextSignature]) return;
    if (self.contextSignature) {
        if (self.installation.busy) [self.installation cancel];
        id latest = getPrefObject(@"internal.latest_version");
        self.filters = [ModrinthSearchFilters defaultsForProfile:profile instanceRoot:root latestVersions:[latest isKindOfClass:NSDictionary.class] ? latest : @{} contentType:self.project[@"contentType"] ?: @"mod"];
    }
    self.contextSignature = signature;
    self.targetProfileName = profiles.selectedProfileName ?: @"";
    self.installation.stateChanged = nil;
    NSString *directory = [[NSString stringWithFormat:@"%@/%@", root, gameDir].stringByStandardizingPath stringByAppendingPathComponent:ContentFolder(self.project[@"contentType"])];
    self.installation = [ModrinthModInstallation installationForDirectory:directory projectID:self.project[@"id"] provider:self.project[@"provider"] ?: @"modrinth"];
    self.lastAttempt = nil;
    self.retryAfterChecking = NO;
    self.versions = nil;
    self.loading = NO;
    __weak typeof(self) weakSelf = self;
    self.installation.stateChanged = ^{ [weakSelf installationChanged]; };
    [self loadVersions];
}
- (void)loadVersions {
    if (self.loading) return;
    self.loading = YES;
    self.error = nil;
    NSUInteger generation = ++self.loadGeneration;
    NSString *projectID = self.project[@"id"];
    NSDictionary *filters = self.filters;
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ModpackAPI *api = ContentAPI(self.project[@"provider"]);
        // All CurseForge file identities allow recognition of older versions outside the filters.
        NSArray *knownVersions = [api versionsForProject:projectID filters:[self.project[@"provider"] isEqual:@"curseforge"] ? @{@"contentType": self.project[@"contentType"] ?: @"mod"} : filters];
        NSArray *versions = knownVersions ? [ModrinthSearchFilters versions:knownVersions matchingFilters:filters] : nil;
        NSError *error = api.lastError;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.loadGeneration) return;
            self.loading = NO;
            self.versions = versions;
            self.error = error;
            [self.installation inspectWithVersions:knownVersions ?: @[]];
            [self.tableView reloadData];
        });
    });
}
- (void)installationChanged {
    if (self.retryAfterChecking && !self.installation.checking && !self.installation.busy) {
        self.retryAfterChecking = NO;
        if (!self.installation.error) { [self.installation installVersion:self.lastAttempt resolvingDependenciesWithFilters:self.filters]; return; }
    }
    NSString *signature = [NSString stringWithFormat:@"%d/%d/%d/%@/%@", self.installation.checking, self.installation.busy, self.installation.verifying, self.installation.error, self.installation.installedVersions];
    if (![signature isEqual:self.renderSignature]) {
        self.renderSignature = signature;
        self.downloadCell = nil;
        [self.tableView reloadData];
    } else if (self.installation.busy) {
        [self updateDownloadCell];
    }
}
- (void)updateDownloadCell {
    ModrinthModInstallation *installation = self.installation;
    NSString *version = installation.installingVersion[@"version_number"] ?: installation.installingVersion[@"name"] ?: @"";
    self.downloadCell.title.text = [NSString stringWithFormat:localize(installation.verifying ? @"mods.install.verifying" : @"mods.install.downloading", nil), version];
    self.downloadCell.downloadProgress.progress = installation.progress.fractionCompleted;
    NSString *received = [NSByteCountFormatter stringFromByteCount:installation.progress.completedUnitCount countStyle:NSByteCountFormatterCountStyleFile];
    NSString *total = [NSByteCountFormatter stringFromByteCount:installation.progress.totalUnitCount countStyle:NSByteCountFormatterCountStyleFile];
    self.downloadCell.summary.text = [NSString stringWithFormat:localize(@"mods.install.progress", nil), (int)(installation.progress.fractionCompleted * 100), received, total];
    self.downloadCell.downloadProgress.accessibilityLabel = self.downloadCell.title.text;
    self.downloadCell.downloadProgress.accessibilityValue = self.downloadCell.summary.text;
}
- (BOOL)isCurrentVersion:(NSDictionary *)version {
    return self.installation.installedVersions.count == 1 && [self.installation.installedVersions.firstObject[@"version"][@"id"] isEqual:version[@"id"]];
}
- (NSString *)actionForVersion:(NSDictionary *)version {
    if ([self isCurrentVersion:version]) return @"mods.install.installed";
    if (!self.installation.installedVersions.count) return @"mods.install.install";
    NSString *present = self.installation.installedVersions.firstObject[@"version"][@"date_published"];
    NSString *candidate = version[@"date_published"];
    if ([present isKindOfClass:NSString.class] && [candidate isKindOfClass:NSString.class]) return [candidate compare:present] == NSOrderedAscending ? @"mods.install.downgrade" : @"mods.install.update";
    return @"mods.install.change";
}
- (void)installVersion:(NSDictionary *)version {
    if ([version[@"downloadUnavailable"] boolValue] || self.installation.busy || self.installation.checking || [self isCurrentVersion:version]) return;
    self.lastAttempt = version;
    [self.installation installVersion:version resolvingDependenciesWithFilters:self.filters];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (self.installation.busy || self.installation.error ? 4 : 3) : MAX(1, self.versions.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? MRFilterSummary(self.filters) : localize(@"mods.versions.title", nil);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? [NSString stringWithFormat:localize(@"content.install.profile", nil), ContentFolder(self.project[@"contentType"]), self.targetProfileName] : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 3 && self.installation.busy) {
        self.downloadCell = [ModrinthDownloadCell new];
        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        cancel.frame = CGRectMake(0, 0, 44, 44);
        [cancel setImage:[UIImage systemImageNamed:@"xmark.circle"] forState:UIControlStateNormal];
        cancel.accessibilityLabel = localize(@"mods.install.cancel", nil);
        cancel.enabled = !self.installation.verifying;
        [cancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) { [self.installation cancel]; }] forControlEvents:UIControlEventTouchUpInside];
        self.downloadCell.accessoryView = cancel;
        [self updateDownloadCell];
        return self.downloadCell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            NSMutableArray *names = [NSMutableArray new];
            for (NSDictionary *entry in self.installation.installedVersions) {
                NSDictionary *version = entry[@"version"];
                NSString *name = version[@"version_number"] ?: version[@"name"] ?: version[@"id"];
                if (name && ![names containsObject:name]) [names addObject:name];
            }
            if (self.installation.checking || (self.loading && !names.count)) cell.textLabel.text = localize(@"mods.install.checking", nil);
            else if (names.count) cell.textLabel.text = [NSString stringWithFormat:localize(@"mods.install.present", nil), [names componentsJoinedByString:@", "]];
            else cell.textLabel.text = localize(self.installation.error ? @"mods.install.unknown" : @"mods.install.absent", nil);
            cell.detailTextLabel.text = self.installation.installedVersions.count > 1 ? localize(@"mods.install.duplicates", nil) : self.installation.installedVersions.firstObject[@"filename"];
        } else if (indexPath.row == 1) cell.textLabel.text = self.project[@"description"];
        else if (indexPath.row == 2) {
            cell.textLabel.text = [NSString stringWithFormat:localize(@"content.open_project", nil), ContentProviderTitle(self.project[@"provider"])];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            cell.textLabel.text = localize(@"mods.install.retry", nil);
            cell.detailTextLabel.text = self.installation.error.localizedDescription;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else if (self.versions.count) {
        NSDictionary *version = self.versions[indexPath.row];
        cell.textLabel.text = version[@"name"] ?: version[@"version_number"];
        NSString *versionType = version[@"version_type"] ?: @"";
        if ([@[@"release", @"beta", @"alpha"] containsObject:versionType]) versionType = localize([@"content.version." stringByAppendingString:versionType], nil);
        NSMutableArray *tags = [NSMutableArray new];
        for (NSString *tag in @[[version[@"game_versions"] componentsJoinedByString:@", "] ?: @"", [version[@"loaders"] componentsJoinedByString:@", "] ?: @"", versionType]) if (tag.length) [tags addObject:tag];
        cell.detailTextLabel.text = [version[@"downloadUnavailable"] boolValue] ? localize(@"content.download.restricted", nil) : [tags componentsJoinedByString:@" · "];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *operation = localize([version[@"downloadUnavailable"] boolValue] ? @"content.download.unavailable_title" : [self actionForVersion:version], nil);
        [button setTitle:operation forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        [button sizeToFit];
        button.frame = CGRectMake(0, 0, MAX(44, button.frame.size.width), MAX(44, button.frame.size.height));
        button.enabled = ![version[@"downloadUnavailable"] boolValue] && !self.loading && !self.installation.busy && !self.installation.checking && !self.installation.error && ![ModrinthModInstallation isInstalling] && ![self isCurrentVersion:version];
        if ([self isCurrentVersion:version]) [button setTitleColor:UIColor.systemGreenColor forState:UIControlStateDisabled];
        button.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", operation, cell.textLabel.text];
        button.accessibilityHint = [NSString stringWithFormat:localize(@"content.download.hint", nil), ContentFolder(self.project[@"contentType"])];
        [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) { [self installVersion:version]; }] forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = button;
    } else {
        cell.textLabel.text = localize(self.loading ? @"mods.loading" : self.error ? @"mods.retry" : @"mods.versions.empty", nil);
        cell.detailTextLabel.text = self.error.localizedDescription;
        cell.selectionStyle = self.error ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (self.versions.count && !self.installation.error) [self installVersion:self.versions[indexPath.row]];
        else if (self.error) [self loadVersions];
    } else if (indexPath.row == 2) {
        NSString *url = self.project[@"websiteUrl"];
        if (![url length]) url = [NSString stringWithFormat:@"https://modrinth.com/%@/%@", self.project[@"contentType"] ?: @"mod", self.project[@"id"]];
        if ([[NSURL URLWithString:url].scheme.lowercaseString isEqual:@"https"]) openLink(self, [NSURL URLWithString:url]);
    } else if (indexPath.row == 3 && !self.installation.busy) {
        self.retryAfterChecking = self.lastAttempt != nil;
        [self.installation inspectWithVersions:self.versions ?: @[]];
    }
}
@end

@interface ModrinthModsViewController ()
@property(nonatomic) UISearchBar *searchBar;
@property(nonatomic) UISegmentedControl *providerToggle;
@property(nonatomic) NSString *provider;
@property(nonatomic) NSMutableDictionary *filters;
@property(nonatomic) NSDictionary *profileDefaults;
@property(nonatomic) NSArray *profileSignature;
@property(nonatomic) NSString *profileName;
@property(nonatomic) NSArray<NSDictionary *> *results;
@property(nonatomic) NSError *searchError;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL reachedLastPage;
@property(nonatomic) NSUInteger requestGeneration;
@property(nonatomic) NSArray<NSDictionary *> *categoryCatalog;
@property(nonatomic) NSArray<NSDictionary *> *installedEntries;
@property(nonatomic) BOOL installedLoading;
@property(nonatomic) NSError *installedError;
@property(nonatomic) NSUInteger installedGeneration;
@property(nonatomic) ModrinthModInstallation *installedOperation;

@end

@implementation ModrinthModsViewController
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { self.title = localize([@"content.title." stringByAppendingString:self.contentType], nil); self.provider = @"modrinth"; }
    return self;
}
- (NSString *)imageName { return @"magnifyingglass"; }
- (NSString *)contentType { return @"mod"; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.providerToggle = [[UISegmentedControl alloc] initWithItems:@[@"Modrinth", @"CurseForge", localize(@"mods.installed.tab", nil)]];
    [self.providerToggle setEnabled:[CurseForgeAPI isConfigured] forSegmentAtIndex:1];
    self.providerToggle.selectedSegmentIndex = 0;
    self.providerToggle.accessibilityLabel = localize(@"content.provider", nil);
    self.providerToggle.accessibilityIdentifier = @"content-provider";
    [self.providerToggle addTarget:self action:@selector(providerChanged:) forControlEvents:UIControlEventValueChanged];
    self.searchBar = [UISearchBar new];
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.accessibilityIdentifier = @"content-search";
    [self updateSearchPlaceholder];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 110)];
    for (UIView *view in @[self.providerToggle, self.searchBar]) { view.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.providerToggle.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],
        [self.providerToggle.leadingAnchor constraintEqualToAnchor:header.safeAreaLayoutGuide.leadingAnchor constant:20],
        [self.providerToggle.trailingAnchor constraintEqualToAnchor:header.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [self.providerToggle.heightAnchor constraintEqualToConstant:32],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.providerToggle.bottomAnchor constant:6],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:header.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:header.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.searchBar.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4]
    ]];
    self.tableView.tableHeaderView = header;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(providerConfigurationChanged:) name:@"CurseForgeConfigurationDidChange" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(profileChanged:) name:PLProfilesDidChangeNotification object:nil];
    [self refreshProfile];
    [self refreshProviderAvailability];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshProfile];
    [self refreshProviderAvailability];
    if (self.isInstalledMode && !self.installedOperation.busy) [self refreshInstalled:YES];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}
- (void)profileChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshProfile]; });
}
- (void)refreshProfile {
    PLProfiles *profiles = PLProfiles.current;
    NSString *root = profiles.profilePath.stringByDeletingLastPathComponent ?: @"";
    NSDictionary *profile = profiles.selectedProfile ?: @{};
    id latest = getPrefObject(@"internal.latest_version");
    NSDictionary *defaults = [ModrinthSearchFilters defaultsForProfile:profile instanceRoot:root latestVersions:[latest isKindOfClass:NSDictionary.class] ? latest : @{} contentType:self.contentType];
    NSArray *signature = @[root, profiles.selectedProfileName ?: @"", profile[@"lastVersionId"] ?: @"", profile[@"gameDir"] ?: @"", defaults];
    if ([signature isEqual:self.profileSignature]) return;
    if (self.installedOperation.busy) [self.installedOperation cancel];
    self.installedGeneration++; self.installedEntries = nil;
    self.profileSignature = signature;
    self.profileName = profiles.selectedProfileName ?: @"";
    self.profileDefaults = defaults;
    self.filters = defaults.mutableCopy;
    [self reloadSearch];
}

- (BOOL)isInstalledMode { return self.providerToggle.selectedSegmentIndex == 2; }
- (void)providerConfigurationChanged:(NSNotification *)notification { dispatch_async(dispatch_get_main_queue(), ^{ [self refreshProviderAvailability]; }); }
- (void)refreshProviderAvailability {
    BOOL enabled = [CurseForgeAPI isConfigured];
    [self.providerToggle setEnabled:enabled forSegmentAtIndex:1];
    if (!enabled && self.providerToggle.selectedSegmentIndex == 1) { self.providerToggle.selectedSegmentIndex = 0; [self providerChanged:self.providerToggle]; }
}
- (NSInteger)filterRow:(NSInteger)row { return [self.contentType isEqual:@"mod"] || row == 0 ? row : row + 1; }
- (NSString *)categoryTitle:(NSString *)identifier {
    for (NSDictionary *record in self.categoryCatalog) if ([record[@"id"] isEqual:identifier]) return [record[@"name"] length] ? record[@"name"] : MRCategoryTitle(record[@"slug"] ?: identifier);
    return MRCategoryTitle(identifier);
}
- (NSString *)sortTitle:(NSString *)value {
    return [self.provider isEqual:@"curseforge"] && [value isEqual:@"relevance"] ? localize(@"content.sort.popularity", nil) : localize([@"mods.sort." stringByAppendingString:value], nil);
}
- (NSString *)installedText:(NSString *)key {
    if ([self.contentType isEqual:@"mod"]) return localize([@"mods.installed." stringByAppendingString:key], nil);
    return localize([[@"content.installed." stringByAppendingString:self.contentType] stringByAppendingFormat:@".%@", key], nil);
}
- (void)updateSearchPlaceholder { if (self.isInstalledMode) { self.searchBar.placeholder = [self installedText:@"search"]; return; } self.searchBar.placeholder = [NSString stringWithFormat:localize(@"content.search_placeholder", nil), ContentProviderTitle(self.provider)]; }
- (void)providerChanged:(UISegmentedControl *)sender {
    [self.searchBar resignFirstResponder];
    if (sender.selectedSegmentIndex == 1 && ![CurseForgeAPI isConfigured]) { sender.selectedSegmentIndex = 0; }
    if (self.isInstalledMode) { self.requestGeneration++; [self updateSearchPlaceholder]; [self refreshInstalled:YES]; return; }
    self.provider = sender.selectedSegmentIndex == 1 ? @"curseforge" : @"modrinth";
    self.categoryCatalog = nil;
    self.filters[@"categories"] = @[];
    if ([self.provider isEqual:@"curseforge"] && [self.filters[@"index"] isEqual:@"follows"]) self.filters[@"index"] = @"relevance";
    if ([self.provider isEqual:@"curseforge"] && [self.filters[@"loader"] isEqual:@"rift"]) self.filters[@"loader"] = @"";
    [self updateSearchPlaceholder];
    [self reloadSearch];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; [self reloadSearch]; }
- (void)clearResults {
    self.requestGeneration++;
    self.results = @[];
    self.searchError = nil;
    self.reachedLastPage = NO;
    self.loading = YES;
    [self.tableView reloadData];
}
- (void)reloadSearch {
    if (self.isInstalledMode) { [self refreshInstalled:NO]; return; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadSearch) object:nil];
    [self clearResults];
    [self loadPage:NO];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (self.isInstalledMode) { [self.tableView reloadData]; return; }
    if (!self.filters || [self.filters[@"name"] isEqualToString:searchText ?: @""]) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadSearch) object:nil];
    // Invalidate in-flight responses immediately, before the debounce fires.
    [self clearResults];
    [self performSelector:@selector(reloadSearch) withObject:nil afterDelay:0.35];
}
- (void)loadPage:(BOOL)append {
    if (append && (self.loading || self.reachedLastPage)) return;
    self.loading = YES;
    self.searchError = nil;
    self.filters[@"name"] = self.searchBar.text ?: @"";
    self.filters[@"provider"] = self.provider;
    NSDictionary *filters = [self.filters copy];
    NSMutableArray *previous = append ? [self.results mutableCopy] : nil;
    NSUInteger generation = ++self.requestGeneration;
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Separate API objects keep overlapping requests from sharing pagination/error state.
        ModpackAPI *api = ContentAPI(filters[@"provider"]);
        NSArray *results = [api searchModWithFilters:filters previousPageResult:previous];
        NSError *error = api.lastError;
        BOOL lastPage = api.reachedLastPage;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.requestGeneration) return;
            self.loading = NO;
            self.searchError = error;
            if (results) {
                self.results = results;
                self.reachedLastPage = lastPage;
            }
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isInstalledMode) return section == 0 ? (self.installedOperation.busy || ![self.contentType isEqual:@"mod"] ? 1 : 2) : MAX(1, self.visibleInstalledEntries.count);
    if (section == 0) return [self.contentType isEqual:@"mod"] ? 5 : 4;
    return self.results.count + ((self.loading || self.searchError || !self.results.count || !self.reachedLastPage) ? 1 : 0);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.isInstalledMode) return localize(section == 0 ? @"mods.installed.actions" : @"mods.installed.tab", nil);
    return localize(section == 0 ? @"mods.filters" : [@"content.title." stringByAppendingString:self.contentType], nil);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.isInstalledMode) return section == 0 ? self.profileName : nil;
    if (section != 0) return nil;
    return [NSString stringWithFormat:localize(@"mods.profile_footer", nil), self.profileName];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isInstalledMode) return [self installedCell:tableView indexPath:indexPath];
    if (indexPath.section == 0) {
        NSInteger filterRow = [self filterRow:indexPath.row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = localize(@[@"mods.filter.minecraft", @"mods.filter.loader", @"mods.filter.categories", @"mods.filter.sort", @"mods.filter.reset"][filterRow], nil);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (filterRow == 0) cell.detailTextLabel.text = [self.filters[@"mcVersion"] length] ? self.filters[@"mcVersion"] : localize(@"mods.filter.any", nil);
        if (filterRow == 1) cell.detailTextLabel.text = MRLoaderTitle(self.filters[@"loader"]);
        if (filterRow == 2) {
            NSArray *categories = self.filters[@"categories"];
            cell.detailTextLabel.text = !categories.count ? localize(@"mods.filter.categories_all", nil) : categories.count == 1 ? [self categoryTitle:categories.firstObject] : [NSString stringWithFormat:localize(@"mods.filter.categories_count", nil), (unsigned long)categories.count];
            NSMutableArray *titles = [NSMutableArray new];
            for (NSString *category in categories) [titles addObject:[self categoryTitle:category]];
            cell.accessibilityValue = [titles componentsJoinedByString:@", "];
        }
        if (filterRow == 3) cell.detailTextLabel.text = [self sortTitle:self.filters[@"index"]];
        return cell;
    }
    if (indexPath.row == self.results.count) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        NSString *key = self.loading ? @"mods.loading" : self.searchError ? @"mods.retry" : !self.results.count ? @"mods.empty" : @"mods.load_more";
        BOOL unconfigured = [self.provider isEqual:@"curseforge"] && ![CurseForgeAPI isConfigured];
        cell.textLabel.text = unconfigured ? localize(@"content.curseforge.pending", nil) : localize(key, nil);
        cell.detailTextLabel.text = self.searchError.localizedDescription;
        if (unconfigured) { cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell; }
        cell.selectionStyle = self.loading || (!self.searchError && !self.results.count) ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
        return cell;
    }
    ModrinthModCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mod"];
    if (!cell) cell = [[ModrinthModCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"mod"];
    [cell configureWithProject:self.results[indexPath.row]];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.isInstalledMode) { [self selectInstalled:indexPath]; return; }
    if (indexPath.section == 0) {
        [self.searchBar resignFirstResponder];
        NSInteger filterRow = [self filterRow:indexPath.row];
        if (filterRow == 0) [self editMinecraftVersion];
        else if (filterRow == 1) [self pickValues:[self.provider isEqual:@"curseforge"] ? @[@"", @"fabric", @"quilt", @"forge", @"neoforge", @"liteloader"] : @[@"", @"fabric", @"quilt", @"forge", @"neoforge", @"liteloader", @"rift"] key:@"loader" indexPath:indexPath];
        else if (filterRow == 2) [self pickCategories];
        else if (filterRow == 3) [self pickValues:[self.provider isEqual:@"curseforge"] ? @[@"relevance", @"downloads", @"newest", @"updated"] : @[@"relevance", @"downloads", @"follows", @"newest", @"updated"] key:@"index" indexPath:indexPath];
        else { self.filters = self.profileDefaults.mutableCopy; [self reloadSearch]; }
    } else if (indexPath.row < self.results.count) {
        ModrinthVersionsViewController *vc = [[ModrinthVersionsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        vc.project = self.results[indexPath.row];
        vc.filters = [self.filters copy];
        [self.searchBar resignFirstResponder];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (!self.loading) {
        [self loadPage:self.results.count > 0];
    }
}
- (NSString *)installedDirectory {
    PLProfiles *profiles = PLProfiles.current;
    NSString *root = profiles.profilePath.stringByDeletingLastPathComponent ?: @"";
    NSString *game = [profiles.selectedProfile[@"gameDir"] isKindOfClass:NSString.class] && [profiles.selectedProfile[@"gameDir"] length] ? profiles.selectedProfile[@"gameDir"] : @".";
    return [[NSString stringWithFormat:@"%@/%@", root, game].stringByStandardizingPath stringByAppendingPathComponent:ContentFolder(self.contentType)];
}
- (NSArray *)visibleInstalledEntries {
    NSString *query = self.searchBar.text ?: @"";
    if (!query.length) return self.installedEntries ?: @[];
    return [self.installedEntries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        return [entry[@"filename"] localizedCaseInsensitiveContainsString:query] || [entry[@"project"][@"title"] localizedCaseInsensitiveContainsString:query];
    }]];
}
- (void)refreshInstalled:(BOOL)updates {
    NSUInteger generation = ++self.installedGeneration;
    NSString *directory = self.installedDirectory; NSArray *context = self.profileSignature;
    NSDictionary *filters = self.profileDefaults;
    self.installedLoading = YES; self.installedError = nil; [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        NSArray *entries = [InstalledModsManager entriesInDirectory:directory identify:updates error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.installedGeneration || ![context isEqual:self.profileSignature]) return;
            self.installedEntries = entries; self.installedError = error;
            self.installedLoading = updates && !error; [self.tableView reloadData];
        });
        if (updates && entries) entries = [InstalledModsManager checkUpdates:entries filters:filters];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.installedGeneration || ![context isEqual:self.profileSignature]) return;
            self.installedEntries = entries; self.installedError = error; self.installedLoading = NO; [self.tableView reloadData];
        });
    });
}
- (UITableViewCell *)installedCell:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    if (indexPath.section == 0) {
        if (self.installedOperation.busy) {
            cell.textLabel.text = self.installedOperation.checking ? localize([self.contentType isEqual:@"mod"] ? @"mods.installed.resolving" : @"mods.loading", nil) : [self installedText:@"downloading"];
            cell.detailTextLabel.text = self.installedOperation.installingVersion[@"version_number"];
            if (self.installedOperation.progress.totalUnitCount > 0) cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %d%%", cell.detailTextLabel.text ?: @"", (int)(100 * self.installedOperation.progress.fractionCompleted)];
            UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem]; [cancel setTitle:localize(@"mods.install.cancel", nil) forState:UIControlStateNormal]; [cancel sizeToFit]; cancel.enabled = !self.installedOperation.verifying;
            [cancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) { [self.installedOperation cancel]; }] forControlEvents:UIControlEventTouchUpInside]; cell.accessoryView = cancel;
        } else {
            cell.textLabel.text = localize(indexPath.row == 0 ? @"mods.installed.check_updates" : @"mods.installed.dependencies", nil);
            cell.detailTextLabel.text = indexPath.row == 0 && self.installedLoading ? localize(@"mods.loading", nil) : nil;
            cell.textLabel.textColor = [ModrinthModInstallation isInstalling] || self.installedLoading ? UIColor.secondaryLabelColor : self.view.tintColor;
        }
        return cell;
    }
    NSArray *entries = self.visibleInstalledEntries;
    if (!entries.count) {
        cell.textLabel.text = self.installedLoading ? localize(@"mods.loading", nil) : self.installedError ? localize(@"mods.retry", nil) : [self installedText:@"empty"];
        cell.detailTextLabel.text = self.installedError.localizedDescription; return cell;
    }
    NSDictionary *entry = entries[indexPath.row];
    cell.textLabel.text = entry[@"project"][@"title"] ?: entry[@"filename"];
    NSString *status = localize([entry[@"enabled"] boolValue] ? @"mods.installed.enabled" : @"mods.installed.disabled", nil);
    NSString *version = entry[@"version"][@"version_number"] ?: entry[@"version"][@"name"] ?: @"";
    NSString *update = entry[@"update"] ? [NSString stringWithFormat:localize(@"mods.installed.update_available", nil), entry[@"update"][@"version_number"] ?: entry[@"update"][@"name"]] : entry[@"updateError"] ?: entry[@"lookupError"] ?: (!entry[@"version"] ? [self installedText:@"unidentified"] : localize([entry[@"noCompatibleVersion"] boolValue] ? @"mods.installed.no_compatible" : [entry[@"updatesChecked"] boolValue] ? @"mods.installed.up_to_date" : @"mods.installed.not_checked", nil));
    NSString *summary = [NSString stringWithFormat:@"%@%@%@", version, version.length ? @" · " : @"", status];
    ModrinthModCell *mod = [tableView dequeueReusableCellWithIdentifier:@"installed-mod"];
    if (!mod) mod = [[ModrinthModCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"installed-mod"];
    [mod configureWithProject:@{@"title":cell.textLabel.text, @"author":summary, @"description":[NSString stringWithFormat:@"%@\n%@", update, entry[@"filename"]], @"imageUrl":entry[@"project"][@"imageUrl"] ?: @""}];
    mod.accessibilityIdentifier = [@"installed-" stringByAppendingString:entry[@"filename"]];
    return mod;
}
- (void)runInstalledVersion:(NSDictionary *)version entry:(NSDictionary *)entry enable:(BOOL)enable {
    if ([ModrinthModInstallation isInstalling] || self.installedLoading) return;
    NSString *directory = self.installedDirectory; NSArray *context = self.profileSignature;
    self.installedOperation = [ModrinthModInstallation installationForDirectory:directory projectID:entry[@"version"][@"project_id"] ?: @"" provider:entry[@"provider"] ?: @"modrinth"];
    __weak typeof(self) weakSelf = self;
    __block BOOL wasBusy = NO;
    self.installedOperation.stateChanged = ^{
        typeof(self) self = weakSelf; if (!self || ![context isEqual:self.profileSignature]) return;
        if (self.installedOperation.busy) wasBusy = YES;
        if (wasBusy && !self.installedOperation.busy && !self.installedOperation.checking) {
            wasBusy = NO;
            if (self.installedOperation.error) [self showInstalledError:self.installedOperation.error];
            [self refreshInstalled:YES];
        } else if (self.isInstalledMode) [self.tableView reloadData];
    };
    if (!version) [self.installedOperation resolveDependenciesWithFilters:self.profileDefaults];
    else if (enable) [self.installedOperation enableVersion:version resolvingDependenciesWithFilters:self.profileDefaults];
    else [self.installedOperation installVersion:version resolvingDependenciesWithFilters:self.profileDefaults];
}
- (void)showInstalledError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"Error", nil) message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
    if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}
- (void)changeInstalledEntry:(NSDictionary *)entry remove:(BOOL)remove {
    NSString *directory = self.installedDirectory; NSArray *context = self.profileSignature;
    self.installedLoading = YES; [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        if (remove) [InstalledModsManager removeEntry:entry directory:directory error:&error];
        else [InstalledModsManager setEntry:entry enabled:![entry[@"enabled"] boolValue] directory:directory error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![context isEqual:self.profileSignature]) return;
            self.installedLoading = NO; if (error) [self showInstalledError:error]; [self refreshInstalled:YES];
        });
    });
}
- (void)selectInstalled:(NSIndexPath *)indexPath {
    if ([ModrinthModInstallation isInstalling] || self.installedLoading) return;
    if (indexPath.section == 0) { if (indexPath.row == 0) [self refreshInstalled:YES]; else [self runInstalledVersion:nil entry:nil enable:NO]; return; }
    NSArray *entries = self.visibleInstalledEntries;
    if (!entries.count) { if (self.installedError) [self refreshInstalled:YES]; return; }
    NSDictionary *entry = entries[indexPath.row];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:entry[@"project"][@"title"] ?: entry[@"filename"] message:entry[@"filename"] preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:localize([entry[@"enabled"] boolValue] ? @"mods.installed.disable" : entry[@"version"] && [self.contentType isEqual:@"mod"] ? @"mods.installed.enable" : @"mods.installed.enable_file", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![entry[@"enabled"] boolValue] && entry[@"version"] && [self.contentType isEqual:@"mod"]) [self runInstalledVersion:entry[@"version"] entry:entry enable:YES]; else [self changeInstalledEntry:entry remove:NO];
    }]];
    if (entry[@"update"]) [menu addAction:[UIAlertAction actionWithTitle:localize(@"mods.install.update", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self runInstalledVersion:entry[@"update"] entry:entry enable:NO]; }]];
    if (entry[@"project"]) [menu addAction:[UIAlertAction actionWithTitle:localize(@"mods.installed.versions", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        ModrinthVersionsViewController *vc = [[ModrinthVersionsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; vc.project = entry[@"project"]; vc.filters = self.profileDefaults; [self.navigationController pushViewController:vc animated:YES];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:[self installedText:@"remove"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:[self installedText:@"remove"] message:[NSString stringWithFormat:[self installedText:@"remove_confirm"], entry[@"filename"]] preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:[self installedText:@"remove"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self changeInstalledEntry:entry remove:YES]; }]];
        [self presentViewController:confirm animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath]; menu.popoverPresentationController.sourceView = cell ?: self.view; menu.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self.searchBar resignFirstResponder]; [self presentViewController:menu animated:YES completion:nil];
}

- (void)pickCategories {
    ModrinthCategoriesViewController *picker = [[ModrinthCategoriesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.records = self.categoryCatalog;
    picker.categories = [self.categoryCatalog valueForKey:@"id"];
    picker.provider = self.provider;
    picker.contentType = self.contentType;
    picker.selectedCategories = [NSMutableSet setWithArray:self.filters[@"categories"] ?: @[]];
    NSArray *context = self.profileSignature;
    NSString *provider = self.provider;
    __weak typeof(self) weakSelf = self;
    picker.catalogLoaded = ^(NSArray *categories) { if ([weakSelf.provider isEqual:provider]) weakSelf.categoryCatalog = categories; };
    picker.selectionApplied = ^(NSArray *categories) {
        typeof(self) self = weakSelf;
        if (!self || ![context isEqual:self.profileSignature] || ![self.provider isEqual:provider]) return;
        if ([self.filters[@"categories"] isEqual:categories]) return;
        self.filters[@"categories"] = categories;
        [self reloadSearch];
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    navigation.preferredContentSize = CGSizeMake(420, 720);
    [self.searchBar resignFirstResponder];
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)editMinecraftVersion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"mods.filter.minecraft", nil) message:localize(@"mods.filter.minecraft_help", nil) preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = self.filters[@"mcVersion"];
        field.placeholder = self.profileDefaults[@"mcVersion"];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Done", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.filters[@"mcVersion"] = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        [self reloadSearch];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)pickValues:(NSArray<NSString *> *)values key:(NSString *)key indexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:cell.textLabel.text message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *value in values) {
        NSString *title = [key isEqualToString:@"loader"] ? MRLoaderTitle(value) : [self sortTitle:value];
        if ([self.filters[key] isEqual:value]) title = [@"✓ " stringByAppendingString:title];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.filters[key] = value;
            [self reloadSearch];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = cell;
    alert.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@implementation LauncherResourcePacksViewController
- (NSString *)contentType { return @"resourcepack"; }
- (NSString *)imageName { return @"photo.on.rectangle.angled"; }
@end
@implementation LauncherShaderPacksViewController
- (NSString *)contentType { return @"shader"; }
- (NSString *)imageName { return @"sun.max"; }
@end
