#import "LibraryViewController.h"
#import "IssueViewController.h"
#import "SearchViewController.h"
#import "Models.h"

#pragma mark - Issue cell

@interface LNIssueCell : UITableViewCell
@property (nonatomic, strong) NSURL *thumbnailURL;
- (void)configureWithIssue:(LNIssue *)issue;
@end

@implementation LNIssueCell {
    UIImageView *_thumbnail;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UILabel *_metaLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
               reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        self.backgroundColor = [UIColor whiteColor];

        _thumbnail = [[UIImageView alloc] init];
        _thumbnail.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnail.clipsToBounds = YES;
        _thumbnail.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        _thumbnail.layer.cornerRadius = 3.0;
        _thumbnail.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont boldSystemFontOfSize:17];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:14];
        _subtitleLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _metaLabel = [[UILabel alloc] init];
        _metaLabel.font = [UIFont systemFontOfSize:12];
        _metaLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self.contentView addSubview:_thumbnail];
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_subtitleLabel];
        [self.contentView addSubview:_metaLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbnail.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                     constant:16],
            [_thumbnail.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_thumbnail.widthAnchor constraintEqualToConstant:44],
            [_thumbnail.heightAnchor constraintEqualToConstant:60],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumbnail.trailingAnchor
                                                      constant:14],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                       constant:-12],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                  constant:13],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                                     constant:3],

            [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_metaLabel.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor
                                                 constant:3]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _thumbnail.image = nil;
    self.thumbnailURL = nil;
}

- (void)configureWithIssue:(LNIssue *)issue {
    _titleLabel.text = issue.title;
    _subtitleLabel.text = issue.subtitle.length > 0 ? issue.subtitle : issue.displayDate;
    _metaLabel.text = [NSString stringWithFormat:@"%ld pages%@",
                       (long)issue.pageCount,
                       issue.subtitle.length > 0
                           ? [NSString stringWithFormat:@" · %@", issue.displayDate]
                           : @""];

    LNPage *firstPage = issue.pages.firstObject;
    if (firstPage == nil) {
        return;
    }
    self.thumbnailURL = firstPage.imageURL;

    __weak LNIssueCell *weakSelf = self;
    NSURL *url = firstPage.imageURL;
    [[ImageLoader sharedLoader] loadImageForURL:url maxPixelSize:160 completion:^(UIImage *image) {
        LNIssueCell *strongSelf = weakSelf;
        if (strongSelf == nil || ![strongSelf.thumbnailURL isEqual:url]) {
            return;
        }
        strongSelf->_thumbnail.image = image;
    }];
}

@end

#pragma mark - Library view controller

@interface LibraryViewController ()
@property (nonatomic, strong) LibraryStore *store;
@property (nonatomic, strong) NSArray<LNIssue *> *issues;
@property (nonatomic, strong) UIView *emptyStateView;
@end

@implementation LibraryViewController

- (instancetype)initWithStore:(LibraryStore *)store {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _store = store;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"News Library";
    self.view.backgroundColor = [UIColor whiteColor];

    self.tableView.rowHeight = 84;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 74, 0, 0);
    [self.tableView registerClass:[LNIssueCell class] forCellReuseIdentifier:@"IssueCell"];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(refreshPulled) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Search"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showSearch)];

    [self buildEmptyState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self reloadIssues];
}

#pragma mark - Data

- (void)refreshPulled {
    [self reloadIssues];
    [self.refreshControl endRefreshing];
}

- (void)reloadIssues {
    [self.store reload];
    self.issues = [self.store issues];
    [self.tableView reloadData];
    self.emptyStateView.hidden = self.issues.count > 0;
}

#pragma mark - Actions

- (void)showSearch {
    SearchViewController *search = [[SearchViewController alloc] initWithStore:self.store];
    [self.navigationController pushViewController:search animated:YES];
}

#pragma mark - Empty state

- (void)buildEmptyState {
    self.emptyStateView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.emptyStateView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                           UIViewAutoresizingFlexibleHeight;
    self.emptyStateView.backgroundColor = [UIColor whiteColor];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"No issues yet";
    title.font = [UIFont boldSystemFontOfSize:22];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *message = [[UILabel alloc] init];
    message.text = @"Copy issue folders into\nDocuments/NewsFiles on this iPad.\n\n"
                   @"Each issue folder needs a pages/ folder\nand an optional issue.json, articles/\nand ocr/ folder.";
    message.font = [UIFont systemFontOfSize:15];
    message.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    message.textAlignment = NSTextAlignmentCenter;
    message.numberOfLines = 0;
    message.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *reload = [UIButton buttonWithType:UIButtonTypeSystem];
    [reload setTitle:@"Reload" forState:UIControlStateNormal];
    reload.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    reload.translatesAutoresizingMaskIntoConstraints = NO;
    [reload addTarget:self action:@selector(refreshPulled) forControlEvents:UIControlEventTouchUpInside];

    [self.emptyStateView addSubview:title];
    [self.emptyStateView addSubview:message];
    [self.emptyStateView addSubview:reload];
    [self.view addSubview:self.emptyStateView];

    [NSLayoutConstraint activateConstraints:@[
        [title.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:self.emptyStateView.centerYAnchor
                                            constant:-80],
        [message.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
        [message.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor
                                               constant:32],
        [message.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor
                                                constant:-32],
        [reload.topAnchor constraintEqualToAnchor:message.bottomAnchor constant:24],
        [reload.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor]
    ]];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.issues.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LNIssueCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IssueCell"
                                                       forIndexPath:indexPath];
    [cell configureWithIssue:self.issues[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LNIssue *issue = self.issues[indexPath.row];
    IssueViewController *controller = [[IssueViewController alloc] initWithStore:self.store
                                                                          issue:issue
                                                                      startPage:1];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
