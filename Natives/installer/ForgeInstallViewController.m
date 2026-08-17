#import "AFNetworking.h"
#import "ForgeInstallViewController.h"
#import "LauncherNavigationController.h"
#import "WFWorkflowProgressView.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#include <dlfcn.h>

@interface ForgeVersionCell : UITableViewCell
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation ForgeVersionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.versionLabel = [[UILabel alloc] init];
        self.versionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.versionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:self.versionLabel];
        
        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subtitleLabel.numberOfLines = 1;
        self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:self.subtitleLabel];
        
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
        [NSLayoutConstraint activateConstraints:@[
            [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.versionLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.versionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:2],
            [self.subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8]
        ]];
    }
    return self;
}

@end

@interface MinecraftVersionHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *chevronImageView;
@property (nonatomic, strong) UIButton *expandCollapseButton;
@property (nonatomic, assign) BOOL isExpanded;
@end

@implementation MinecraftVersionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *containerView = [[UIView alloc] init];
        containerView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:containerView];
        
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [containerView addSubview:self.titleLabel];
        
        self.chevronImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        self.chevronImageView.tintColor = [UIColor systemGrayColor];
        self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
        self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
        [containerView addSubview:self.chevronImageView];
        
        self.expandCollapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.expandCollapseButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.expandCollapseButton.backgroundColor = [UIColor clearColor];
        [containerView addSubview:self.expandCollapseButton];
        
        [NSLayoutConstraint activateConstraints:@[
            [containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16],
            [self.titleLabel.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronImageView.leadingAnchor constant:-16]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.chevronImageView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16],
            [self.chevronImageView.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
            [self.chevronImageView.widthAnchor constraintEqualToConstant:20],
            [self.chevronImageView.heightAnchor constraintEqualToConstant:20]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.expandCollapseButton.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
            [self.expandCollapseButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
            [self.expandCollapseButton.topAnchor constraintEqualToAnchor:containerView.topAnchor],
            [self.expandCollapseButton.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
        ]];
    }
    return self;
}

- (void)setIsExpanded:(BOOL)isExpanded {
    _isExpanded = isExpanded;
    
    // Animate chevron rotation
    [UIView animateWithDuration:0.3 animations:^{
        self.chevronImageView.transform = isExpanded ? 
            CGAffineTransformMakeRotation(M_PI_2) : CGAffineTransformIdentity;
    }];
}

@end

@interface ForgeInstallViewController()<NSXMLParserDelegate>
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, strong) NSString *searchText;
@property(atomic) AFURLSessionManager *afManager;
@property(nonatomic) WFWorkflowProgressView *progressView;
@property(nonatomic, strong) NSString *currentVendor;

@property(nonatomic) NSDictionary *endpoints;
@property(nonatomic) NSMutableArray<NSNumber *> *visibilityList;
@property(nonatomic) NSMutableArray<NSString *> *versionList;
@property(nonatomic) NSMutableArray<NSMutableArray *> *forgeList;
@property(nonatomic) NSMutableArray<NSMutableArray *> *filteredForgeList;
@property(nonatomic, assign) BOOL isVersionElement;
@property(nonatomic, strong) NSMutableString *currentVersionValue;
@property(nonatomic, strong) NSIndexPath *currentDownloadIndexPath;
@property(atomic, assign) BOOL isDataLoading;
@property(nonatomic, strong) NSLock *dataLock;

// Performance optimizations
@property(nonatomic, strong) NSTimer *searchDebounceTimer;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *displayNameCache;
@property(nonatomic, strong) dispatch_queue_t searchQueue;
@end

@implementation ForgeInstallViewController

+ (NSDictionary *)endpoints {
    return @{
        @"Forge": @{
            @"installer": @"https://maven.minecraftforge.net/net/minecraftforge/forge/%1$@/forge-%1$@-installer.jar",
            @"metadata": @"https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"
        },
        @"NeoForge": @{
            @"installer": @"https://maven.neoforged.net/releases/net/neoforged/neoforge/%1$@/neoforge-%1$@-installer.jar",
            @"metadata": @"https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml"
        }
    };
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (self.navigationController) {
        self.navigationController.navigationBar.translucent = NO;
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemBackgroundColor];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.compactAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
    
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
    
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    
    self.extendedLayoutIncludesOpaqueBars = NO;
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    [self.tableView registerClass:[ForgeVersionCell class] forCellReuseIdentifier:@"ForgeVersionCell"];
    [self.tableView registerClass:[MinecraftVersionHeaderView class] forHeaderFooterViewReuseIdentifier:@"MinecraftVersionHeader"];
    
    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:@[@"Forge", @"NeoForge"]];
    segment.selectedSegmentIndex = 0;
    [segment addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = segment;
    self.currentVendor = @"Forge";

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = (id<UISearchResultsUpdating>)self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search versions";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshVersions) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    dlopen("/System/Library/PrivateFrameworks/WorkflowUIServices.framework/WorkflowUIServices", RTLD_GLOBAL);
    self.progressView = [[NSClassFromString(@"WFWorkflowProgressView") alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    self.progressView.resolvedTintColor = self.view.tintColor;
    [self.progressView addTarget:self action:@selector(actionCancelDownload) forControlEvents:UIControlEventTouchUpInside];

    self.endpoints = ForgeInstallViewController.endpoints;
    
    self.visibilityList = [NSMutableArray new];
    self.versionList = [NSMutableArray new];
    self.forgeList = [NSMutableArray new];
    self.filteredForgeList = [NSMutableArray new];
    self.currentVersionValue = [NSMutableString new];
    self.isDataLoading = NO;
    self.dataLock = [[NSLock alloc] init];
    
    self.displayNameCache = [NSMutableDictionary new];
    self.searchQueue = dispatch_queue_create("com.amethyst.forge.search", DISPATCH_QUEUE_SERIAL);
    
    [self loadMetadataFromVendor:@"Forge"];
}

- (void)dealloc {
    [self.searchDebounceTimer invalidate];
    self.searchDebounceTimer = nil;
}

- (void)actionCancelDownload {

    if (self.currentDownloadIndexPath) {
        [self resetCellAppearance:self.currentDownloadIndexPath];
        self.currentDownloadIndexPath = nil;
    }
    
    [self.afManager invalidateSessionCancelingTasks:YES resetSession:NO];
    showDialog(@"Download Cancelled", @"The download has been cancelled.");
}

- (void)resetCellAppearance:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;
    
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)segmentChanged:(UISegmentedControl *)segment {
    [self.searchDebounceTimer invalidate];
    self.searchDebounceTimer = nil;

    if (self.searchController.isActive) {
        [self.searchController dismissViewControllerAnimated:YES completion:nil];
    }
    
    NSString *vendor = [segment titleForSegmentAtIndex:segment.selectedSegmentIndex];
    self.currentVendor = vendor;
    [self loadMetadataFromVendor:vendor];
}

- (void)refreshVersions {

    [self loadMetadataFromVendor:self.currentVendor];
}

- (void)loadMetadataFromVendor:(NSString *)vendor {
    [self switchToLoadingState];
    
    self.isDataLoading = YES;
    
    [self.dataLock lock];
    [self.visibilityList removeAllObjects];
    [self.versionList removeAllObjects];
    [self.forgeList removeAllObjects];
    [self.filteredForgeList removeAllObjects];
    [self.displayNameCache removeAllObjects];
    [self.dataLock unlock];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURL *url = [[NSURL alloc] initWithString:self.endpoints[vendor][@"metadata"]];
        NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:url];
        parser.delegate = self;
        
        self.currentVersionValue = [NSMutableString new];
        
        if (![parser parse]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isDataLoading = NO;
                [self.refreshControl endRefreshing];
                showDialog(localize(@"Error", nil), parser.parserError.localizedDescription);
                [self actionClose];
            });
        }
    });
}

- (void)switchToLoadingState {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:indicator];
    [indicator startAnimating];
    self.navigationController.modalInPresentation = YES;
}

- (void)switchToReadyState {
    UIActivityIndicatorView *indicator = (id)self.navigationItem.rightBarButtonItem.customView;
    [indicator stopAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = NO;
    [self.refreshControl endRefreshing];
}

#pragma mark - Search Results Updating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    if (self.isDataLoading) {
        return;
    }
    
    NSString *searchText = searchController.searchBar.text;
    
    [self.searchDebounceTimer invalidate];
    
    self.searchDebounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.15
                                                                 target:self
                                                               selector:@selector(performSearch:)
                                                               userInfo:searchText
                                                                repeats:NO];
}

- (void)performSearch:(NSTimer *)timer {
    NSString *searchText = timer.userInfo;
    self.searchText = searchText;
    
    if (searchText.length == 0) {
        [self.dataLock lock];
        [self.filteredForgeList removeAllObjects];
        for (NSMutableArray *forgeVersions in self.forgeList) {
            [self.filteredForgeList addObject:[forgeVersions mutableCopy]];
        }
        [self.dataLock unlock];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
        return;
    }
    
    dispatch_async(self.searchQueue, ^{
        [self.dataLock lock];
        
        NSArray *forgeListSnapshot = [self.forgeList copy];
        NSString *vendor = [self.currentVendor copy];
        
        [self.dataLock unlock];
        
        NSMutableArray *newFilteredList = [NSMutableArray new];
        NSMutableIndexSet *sectionsWithResults = [NSMutableIndexSet new];
        
        for (NSUInteger i = 0; i < forgeListSnapshot.count; i++) {
            NSArray *sectionVersions = forgeListSnapshot[i];
            NSMutableArray *filteredSectionVersions = [NSMutableArray new];
            
            for (NSString *version in sectionVersions) {
                NSString *displayName = [self getCachedDisplayName:version forVendor:vendor];
                
                if ([displayName localizedCaseInsensitiveContainsString:searchText]) {
                    [filteredSectionVersions addObject:version];
                }
            }
            
            [newFilteredList addObject:filteredSectionVersions];
            
            if (filteredSectionVersions.count > 0) {
                [sectionsWithResults addIndex:i];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.dataLock lock];
            
            NSArray *oldFilteredList = [self.filteredForgeList copy];
            
            [self.filteredForgeList removeAllObjects];
            [self.filteredForgeList addObjectsFromArray:newFilteredList];
            
            [sectionsWithResults enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                if (idx < self.visibilityList.count) {
                    self.visibilityList[idx] = @YES;
                }
            }];
            
            [self.dataLock unlock];
            
            if (![self isFilteredList:oldFilteredList equalTo:newFilteredList]) {
                [self.tableView reloadData];
            }
        });
    });
}

- (BOOL)isFilteredList:(NSArray *)list1 equalTo:(NSArray *)list2 {
    if (list1.count != list2.count) return NO;
    
    for (NSUInteger i = 0; i < list1.count; i++) {
        NSArray *section1 = list1[i];
        NSArray *section2 = list2[i];
        if (![section1 isEqualToArray:section2]) {
            return NO;
        }
    }
    
    return YES;
}

- (NSString *)getCachedDisplayName:(NSString *)version forVendor:(NSString *)vendor {
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%@", vendor, version];
    
    NSString *cached = self.displayNameCache[cacheKey];
    if (cached) {
        return cached;
    }
    
    // Compute and cache
    NSString *displayName = [self getDisplayName:version];
    self.displayNameCache[cacheKey] = displayName;
    
    return displayName;
}

#pragma mark - Version Display Methods

- (NSString *)getDisplayName:(NSString *)version {
    if ([self.currentVendor isEqualToString:@"NeoForge"]) {

        NSString *mcVersion = [self extractMinecraftVersionFromNeoForgeVersion:version];
        
        if (![mcVersion isEqualToString:@"Unknown"]) {

            if ([self isSnapshotVersion:mcVersion] || [mcVersion containsString:@"w"]) {
                return [NSString stringWithFormat:@"NeoForge %@ (Snapshot %@)", 
                        version, mcVersion];
            } else {
                return [NSString stringWithFormat:@"NeoForge %@ (Minecraft %@)", 
                        version, mcVersion];
            }
        } else {
            return [NSString stringWithFormat:@"NeoForge %@", version];
        }
    } else {

        NSString *mcVersion = [self extractMinecraftVersionFromForgeVersion:version];
        NSRange hyphenRange = [version rangeOfString:@"-"];
        
        if (hyphenRange.location != NSNotFound && ![mcVersion isEqualToString:@"Unknown"]) {
            NSString *forgeVersion = [version substringFromIndex:hyphenRange.location + 1];
            
            if ([self isSnapshotVersion:mcVersion]) {
                return [NSString stringWithFormat:@"Forge %@ (Snapshot %@)", forgeVersion, mcVersion];
            } else {
                return [NSString stringWithFormat:@"Forge %@ (Minecraft %@)", forgeVersion, mcVersion];
            }
        } else {
            return version;
        }
    }
}

- (NSString *)extractMinecraftVersionFromForgeVersion:(NSString *)version {

    NSRange hyphenRange = [version rangeOfString:@"-"];
    if (hyphenRange.location != NSNotFound) {
        NSString *mcPortion = [version substringToIndex:hyphenRange.location];
        
        if ([self isSnapshotVersion:mcPortion]) {
            return mcPortion;
        }
        
        NSRegularExpression *mcRegex = [NSRegularExpression 
            regularExpressionWithPattern:@"^1\\.[0-9]+(\\.[0-9]+)?$" 
            options:0 error:nil];
            
        NSRange fullRange = NSMakeRange(0, mcPortion.length);
        if ([mcRegex firstMatchInString:mcPortion options:0 range:fullRange]) {
            return mcPortion;
        }
    }
    
    return @"Unknown";
}

- (NSString *)extractMinecraftVersionFromNeoForgeVersion:(NSString *)version {
    /* NeoForge versioning: [MC version without 1.].[NeoForge version][-beta/alpha]
       Example: "21.4.114-beta" for Minecraft 1.21.4
       Special case: "0.25w14craftmine.5-beta" contains snapshot "25w14craftmine" */
    
    NSString *cleanVersion = version;
    NSRange hyphenRange = [version rangeOfString:@"-"];
    if (hyphenRange.location != NSNotFound) {
        cleanVersion = [version substringToIndex:hyphenRange.location];
    }
    
    NSRegularExpression *snapshotRegex = [NSRegularExpression 
        regularExpressionWithPattern:@"(\\d{2}w\\d{2}[a-z]*)" 
        options:NSRegularExpressionCaseInsensitive error:nil];
    
    NSTextCheckingResult *snapshotMatch = [snapshotRegex firstMatchInString:cleanVersion options:0 range:NSMakeRange(0, cleanVersion.length)];
    if (snapshotMatch) {
        NSString *snapshotVersion = [cleanVersion substringWithRange:snapshotMatch.range];
        return snapshotVersion; // Return snapshot version directly
    }
    
    NSArray *components = [cleanVersion componentsSeparatedByString:@"."];
    if (components.count >= 2) {
        NSString *majorComponent = components[0];
        NSString *minorComponent = components[1];
        
        if ([self isNumeric:majorComponent] && [self isNumeric:minorComponent]) {
            NSString *mcVersion = [NSString stringWithFormat:@"1.%@.%@", majorComponent, minorComponent];
            return mcVersion;
        }
    }
    
    NSRegularExpression *versionRegex = [NSRegularExpression 
        regularExpressionWithPattern:@"(\\d+\\.\\d+)" 
        options:0 error:nil];
    
    NSTextCheckingResult *match = [versionRegex firstMatchInString:version options:0 range:NSMakeRange(0, version.length)];
    if (match) {
        NSString *extractedPart = [version substringWithRange:match.range];
        return [NSString stringWithFormat:@"1.%@", extractedPart];
    }
    
    return @"Unknown";
}

- (BOOL)isSnapshotVersion:(NSString *)version {
    if (version.length == 0) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?i)^\\d{2}w\\d{2}[a-z]$" options:0 error:nil];
    NSRange fullRange = NSMakeRange(0, version.length);
    return [regex firstMatchInString:version options:0 range:fullRange] != nil;
}

- (UIColor *)getColorForVersionType:(NSString *)version {
    if ([version containsString:@"recommended"]) {
        return [UIColor systemGreenColor];
    } else if ([version containsString:@"beta"] || [version containsString:@"-beta"]) {
        return [UIColor systemOrangeColor];
    } else if ([version containsString:@"alpha"] || [version containsString:@"-alpha"]) {
        return [UIColor systemRedColor];
    } else {
        return [UIColor systemBlueColor]; // Release version
    }
}

- (NSString *)getLabelForVersionType:(NSString *)version {
    if ([version containsString:@"recommended"]) {
        return @"Recommended";
    } else if ([version containsString:@"beta"] || [version containsString:@"-beta"]) {
        return @"Beta";
    } else if ([version containsString:@"alpha"] || [version containsString:@"-alpha"]) {
        return @"Alpha";
    } else {
        return @"Release";
    }
}

- (BOOL)isNumeric:(NSString *)string {
    if (!string || string.length == 0) return NO;
    
    NSCharacterSet *nonNumbers = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [string rangeOfCharacterFromSet:nonNumbers].location == NSNotFound;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {

    if (self.isDataLoading) {
        return 0;
    }
    
    [self.dataLock lock];
    NSInteger count = self.versionList.count;
    [self.dataLock unlock];
    
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    if (self.isDataLoading) {
        return 0;
    }
    
    [self.dataLock lock];
    
    if (section >= self.visibilityList.count) {
        [self.dataLock unlock];
        return 0;
    }
    
    NSInteger rows = 0;
    
    if (self.visibilityList[section].boolValue) {

        if (self.searchController.isActive) {
            if (section < self.filteredForgeList.count) {
                rows = self.filteredForgeList[section].count;
            }
        } else {
            if (section < self.forgeList.count) {
                rows = self.forgeList[section].count;
            }
        }
    }
    
    [self.dataLock unlock];
    return rows;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    MinecraftVersionHeaderView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"MinecraftVersionHeader"];
    
    if (self.isDataLoading) {
        headerView.titleLabel.text = @"Loading...";
        headerView.isExpanded = NO;
        headerView.expandCollapseButton.tag = section;
        [headerView.expandCollapseButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        return headerView;
    }
    
    [self.dataLock lock];
    
    if (section >= self.versionList.count || self.versionList.count == 0) {
        [self.dataLock unlock];

        headerView.titleLabel.text = @"Loading...";
        headerView.isExpanded = NO;
        headerView.expandCollapseButton.tag = section;

        [headerView.expandCollapseButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        return headerView;
    }
    
    NSString *mcVersion = self.versionList[section];
    if ([mcVersion hasPrefix:@"1."]) {
        headerView.titleLabel.text = [NSString stringWithFormat:@"Minecraft %@", mcVersion];
    } else {
        headerView.titleLabel.text = mcVersion;
    }
    
    if (section < self.visibilityList.count) {
        headerView.isExpanded = self.visibilityList[section].boolValue;
    } else {
        headerView.isExpanded = NO;
    }
    
    [self.dataLock unlock];
    
    headerView.expandCollapseButton.tag = section;
    
    [headerView.expandCollapseButton addTarget:self action:@selector(toggleSection:) forControlEvents:UIControlEventTouchUpInside];
    
    return headerView;
}

- (void)toggleSection:(UIButton *)sender {

    if (self.isDataLoading) {
        return;
    }
    
    NSInteger section = sender.tag;
    
    [self.dataLock lock];
    
    if (section >= 0 && section < self.visibilityList.count && self.versionList.count > section) {

    self.visibilityList[section] = @(!self.visibilityList[section].boolValue);
        
        [self.dataLock unlock];
        
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.dataLock unlock];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 60.0; 
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 56.0; 
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ForgeVersionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ForgeVersionCell" forIndexPath:indexPath];
    
    if (self.isDataLoading) {
        cell.versionLabel.text = @"Loading...";
        cell.subtitleLabel.text = @"";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    [self.dataLock lock];
    
    BOOL outOfBounds = NO;
    
    if (self.searchController.isActive) {
        outOfBounds = (indexPath.section >= self.filteredForgeList.count || 
                      (indexPath.section < self.filteredForgeList.count && 
                       indexPath.row >= self.filteredForgeList[indexPath.section].count));
    } else {
        outOfBounds = (indexPath.section >= self.forgeList.count || 
                      (indexPath.section < self.forgeList.count && 
                       indexPath.row >= self.forgeList[indexPath.section].count));
    }
    
    if (outOfBounds) {
        [self.dataLock unlock];
        cell.versionLabel.text = @"Loading...";
        cell.subtitleLabel.text = @"";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    NSString *version = self.searchController.isActive ? 
        self.filteredForgeList[indexPath.section][indexPath.row] : 
        self.forgeList[indexPath.section][indexPath.row];
    
    version = [version copy];
    NSString *vendor = [self.currentVendor copy];
    
    [self.dataLock unlock];
    
    // Use cached display name for better performance
    NSString *displayName = [self getCachedDisplayName:version forVendor:vendor];
    cell.versionLabel.text = displayName;
    
    NSString *typeLabel = [self getLabelForVersionType:version];
    UIColor *typeColor = [self getColorForVersionType:version];
    cell.subtitleLabel.text = typeLabel;
    cell.subtitleLabel.textColor = typeColor;
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (self.isDataLoading) {
        return;
    }
    
    [self.dataLock lock];
    
    BOOL outOfBounds = NO;
    if (self.searchController.isActive) {
        outOfBounds = (indexPath.section >= self.filteredForgeList.count || 
                      (indexPath.section < self.filteredForgeList.count && 
                       indexPath.row >= self.filteredForgeList[indexPath.section].count));
    } else {
        outOfBounds = (indexPath.section >= self.forgeList.count || 
                      (indexPath.section < self.forgeList.count && 
                       indexPath.row >= self.forgeList[indexPath.section].count));
    }
    
    if (outOfBounds) {
        [self.dataLock unlock];
        return;
    }
    
    NSString *versionString = self.searchController.isActive ? 
        self.filteredForgeList[indexPath.section][indexPath.row] : 
        self.forgeList[indexPath.section][indexPath.row];
    
    versionString = [versionString copy];
    
    [self.dataLock unlock];
    
    self.currentDownloadIndexPath = indexPath;
    
    tableView.allowsSelection = NO;
    [self switchToLoadingState];
    self.progressView.fractionCompleted = 0;

    ForgeVersionCell *cell = (ForgeVersionCell *)[tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryView = self.progressView;
    cell.accessoryType = UITableViewCellAccessoryNone;

    NSString *jarURL = [NSString stringWithFormat:self.endpoints[self.currentVendor][@"installer"], versionString];
    NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp.jar"];
    NSDebugLog(@"[%@ Installer] Downloading %@", self.currentVendor, jarURL);

    self.afManager = [AFURLSessionManager new];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:jarURL]];
    NSURLSessionDownloadTask *downloadTask = [self.afManager downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull progress){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.fractionCompleted = progress.fractionCompleted;
        });
    } destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        [NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
        return [NSURL fileURLWithPath:outPath];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            tableView.allowsSelection = YES;
            [self resetCellAppearance:indexPath];
            self.currentDownloadIndexPath = nil;
            
            if (error) {
                if (error.code != NSURLErrorCancelled) {
                    NSDebugLog(@"Error: %@", error);
                    showDialog(localize(@"Error", nil), error.localizedDescription);
                }
                [self switchToReadyState];
                return;
            }
            
            showDialog(@"Download Complete", 
                      [NSString stringWithFormat:@"%@ installer will now run. After installation completes, you will need to restart the app.", self.currentVendor]);
            
            LauncherNavigationController *navVC = (id)((UISplitViewController *)self.presentingViewController).viewControllers[1];
            
            // Dismiss search controller first if it's active, then dismiss main view controller
            if (self.searchController.isActive) {
                [self.searchController dismissViewControllerAnimated:NO completion:^{
                    [self dismissViewControllerAnimated:YES completion:^{
                        [navVC enterModInstallerWithPath:outPath hitEnterAfterWindowShown:YES];
                    }];
                }];
            } else {
                [self dismissViewControllerAnimated:YES completion:^{
                    [navVC enterModInstallerWithPath:outPath hitEnterAfterWindowShown:YES];
                }];
            }
        });
    }];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [downloadTask resume];
    });
}

- (void)addVersionToList:(NSString *)version {
    if (version.length == 0) {
        return;
    }
    
    [self.dataLock lock];
    
    if ([self.currentVendor isEqualToString:@"NeoForge"]) {
        NSArray *skipPatterns = @[
            @"sources", @"userdev", @"javadoc", @"universal", @"slim", 
            @"-javadoc", @"-sources", @"-all", @"-changelog", 
            @"-installer-win", @"-mdk"
        ];
        
        for (NSString *pattern in skipPatterns) {
            if ([version containsString:pattern]) {
                NSLog(@"[ForgeInstall] Skipping problematic NeoForge version: %@", version);
                [self.dataLock unlock];
                return;
            }
        }
        
        NSString *minecraftVersion = [self extractMinecraftVersionFromNeoForgeVersion:version];
        
        if ([minecraftVersion isEqualToString:@"Unknown"]) {
            NSLog(@"[ForgeInstall] Skipping NeoForge version with unknown MC version: %@", version);
            [self.dataLock unlock];
            return;
        }
        
        NSUInteger sectionIndex = NSNotFound;
        for (NSUInteger i = 0; i < self.versionList.count; i++) {
            if ([self.versionList[i] isEqualToString:minecraftVersion]) {
                sectionIndex = i;
                break;
            }
        }
        
        if (sectionIndex == NSNotFound) {
            [self.versionList addObject:minecraftVersion];
            [self.visibilityList addObject:@NO]; // Start collapsed
            [self.forgeList addObject:[NSMutableArray new]];
            sectionIndex = self.versionList.count - 1;
        }
        
        if (![self.forgeList[sectionIndex] containsObject:version]) {
            [self.forgeList[sectionIndex] addObject:version];
            NSLog(@"[ForgeInstall] Added NeoForge %@ to %@ section", version, minecraftVersion);
        }
    } else {
        if (![version containsString:@"-"]) {
            NSLog(@"[ForgeInstall] Skipping invalid Forge version format: %@", version);
            [self.dataLock unlock];
            return;
        }
        
        NSArray *skipPatterns = @[
            @"mdk", @"userdev", @"javadoc", @"src", @"sources", @"universal",
            @"-all", @"-changelog", @"-client", @"-server", @"-launcher"
        ];
        
        for (NSString *pattern in skipPatterns) {
            if ([version containsString:pattern]) {
                NSLog(@"[ForgeInstall] Skipping problematic Forge version: %@", version);
                [self.dataLock unlock];
                return;
            }
        }
        
        NSRange hyphenRange = [version rangeOfString:@"-"];
        if (hyphenRange.location == NSNotFound) {
            [self.dataLock unlock];
        return;
    }
    
        NSString *minecraftVersion = [version substringToIndex:hyphenRange.location];
        
        NSUInteger sectionIndex = NSNotFound;
        for (NSUInteger i = 0; i < self.versionList.count; i++) {
            if ([self.versionList[i] isEqualToString:minecraftVersion]) {
                sectionIndex = i;
                break;
            }
        }
        
        if (sectionIndex == NSNotFound) {
            [self.versionList addObject:minecraftVersion];
            [self.visibilityList addObject:@NO];
        [self.forgeList addObject:[NSMutableArray new]];
            sectionIndex = self.versionList.count - 1;
        }
        
        if (![self.forgeList[sectionIndex] containsObject:version]) {
            [self.forgeList[sectionIndex] addObject:version];
            NSLog(@"[ForgeInstall] Added Forge %@ to %@ section", version, minecraftVersion);
        }
    }
    
    [self.dataLock unlock];
}

#pragma mark - NSXMLParserDelegate

- (void)parserDidEndDocument:(NSXMLParser *)parser {
        dispatch_async(dispatch_get_main_queue(), ^{

        [self.dataLock lock];
        
        NSString *vendor = self.currentVendor;

        NSMutableArray<NSNumber *> *indices = [NSMutableArray new];
        for (NSInteger i = 0; i < self.versionList.count; i++) {
            [indices addObject:@(i)];
        }
        [indices sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            NSString *va = self.versionList[a.integerValue];
            NSString *vb = self.versionList[b.integerValue];
            BOOL vaIsSnapshot = [self isSnapshotVersion:va];
            BOOL vbIsSnapshot = [self isSnapshotVersion:vb];
            if (vaIsSnapshot != vbIsSnapshot) {

            }
            if (vaIsSnapshot && vbIsSnapshot) {

            }

            NSArray *pa = [va componentsSeparatedByString:@"."];
            NSArray *pb = [vb componentsSeparatedByString:@"."];
            NSInteger aMinor = pa.count > 1 ? [pa[1] integerValue] : 0;
            NSInteger bMinor = pb.count > 1 ? [pb[1] integerValue] : 0;
            if (aMinor != bMinor) return aMinor < bMinor ? NSOrderedDescending : NSOrderedAscending;
            NSInteger aPatch = pa.count > 2 ? [pa[2] integerValue] : 0;
            NSInteger bPatch = pb.count > 2 ? [pb[2] integerValue] : 0;
            if (aPatch != bPatch) return aPatch < bPatch ? NSOrderedDescending : NSOrderedAscending;
            return NSOrderedSame;
        }];

        NSMutableArray *newVisibility = [NSMutableArray new];
        NSMutableArray *newVersionList = [NSMutableArray new];
        NSMutableArray *newForgeList = [NSMutableArray new];
        for (NSNumber *idx in indices) {
            [newVisibility addObject:self.visibilityList[idx.integerValue]];
            [newVersionList addObject:self.versionList[idx.integerValue]];
            [newForgeList addObject:self.forgeList[idx.integerValue]];
        }
        self.visibilityList = newVisibility;
        self.versionList = newVersionList;
        self.forgeList = newForgeList;

        for (NSMutableArray<NSString *> *versions in self.forgeList) {
            [versions sortUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
                if ([vendor isEqualToString:@"Forge"]) {

                    NSRange dashL = [lhs rangeOfString:@"-"];
                    NSRange dashR = [rhs rangeOfString:@"-"];
                    NSString *lv = dashL.location != NSNotFound ? [lhs substringFromIndex:dashL.location + 1] : lhs;
                    NSString *rv = dashR.location != NSNotFound ? [rhs substringFromIndex:dashR.location + 1] : rhs;
                    NSArray *lp = [lv componentsSeparatedByString:@"."];
                    NSArray *rp = [rv componentsSeparatedByString:@"."];
                    NSInteger lA = lp.count > 0 ? [lp[0] integerValue] : 0;
                    NSInteger rA = rp.count > 0 ? [rp[0] integerValue] : 0;
                    if (lA != rA) return lA < rA ? NSOrderedDescending : NSOrderedAscending;
                    NSInteger lB = lp.count > 1 ? [lp[1] integerValue] : 0;
                    NSInteger rB = rp.count > 1 ? [rp[1] integerValue] : 0;
                    if (lB != rB) return lB < rB ? NSOrderedDescending : NSOrderedAscending;
                    NSInteger lC = lp.count > 2 ? [lp[2] integerValue] : 0;
                    NSInteger rC = rp.count > 2 ? [rp[2] integerValue] : 0;
                    if (lC != rC) return lC < rC ? NSOrderedDescending : NSOrderedAscending;
                    return NSOrderedSame;
                } else {

                    BOOL lBeta = [lhs containsString:@"-beta"];
                    BOOL rBeta = [rhs containsString:@"-beta"];
                    NSString *lClean = [lhs stringByReplacingOccurrencesOfString:@"-beta" withString:@""];
                    NSString *rClean = [rhs stringByReplacingOccurrencesOfString:@"-beta" withString:@""];
                    NSArray *lc = [lClean componentsSeparatedByString:@"."];
                    NSArray *rc = [rClean componentsSeparatedByString:@"."];
                    NSInteger lBuild = lc.count > 2 ? [lc[2] integerValue] : 0;
                    NSInteger rBuild = rc.count > 2 ? [rc[2] integerValue] : 0;
                    if (lBuild != rBuild) return lBuild < rBuild ? NSOrderedDescending : NSOrderedAscending;

                    return NSOrderedSame;
                }
            }];
        }
        
        [self.filteredForgeList removeAllObjects];
        for (NSMutableArray *forgeVersions in self.forgeList) {
            [self.filteredForgeList addObject:[forgeVersions mutableCopy]];
        }
        
        [self.dataLock unlock];
        
        self.isDataLoading = NO;

        [self switchToReadyState];
        [self.tableView reloadData];
        
        if (self.versionList.count > 0) {
            [self.tableView setContentOffset:CGPointZero animated:YES];
        }
    });
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict {
    self.isVersionElement = [elementName isEqualToString:@"version"];
    if (self.isVersionElement) {
        [self.currentVersionValue setString:@""];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.isVersionElement) {
        [self.currentVersionValue appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"version"]) {
        NSString *versionString = [self.currentVersionValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (versionString.length > 0) {
            [self addVersionToList:versionString];
        }
        self.isVersionElement = NO;
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isDataLoading = NO;
        
        [self.refreshControl endRefreshing];
        showDialog(@"Error Loading Versions", parseError.localizedDescription);
        [self switchToReadyState];
    });
}

@end
