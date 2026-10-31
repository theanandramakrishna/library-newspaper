#import "SearchViewController.h"
#import "IssueViewController.h"

@interface SearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) LibraryStore *store;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<LNSearchHit *> *results;
@property (nonatomic, strong) NSTimer *pendingSearch;
@end

@implementation SearchViewController

- (instancetype)initWithStore:(LibraryStore *)store {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _store = store;
        _results = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Search";
    self.automaticallyAdjustsScrollViewInsets = NO;

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search all issues";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, 44);
    self.tableView.tableHeaderView = self.searchBar;

    self.tableView.rowHeight = 76;
    self.tableView.tableFooterView = [[UIView alloc] init];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.pendingSearch invalidate];
    self.pendingSearch = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                          target:self
                                                        selector:@selector(runPendingSearch)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self.pendingSearch invalidate];
    self.pendingSearch = nil;
    self.results = [self.store search:searchBar.text limit:200];
    [self.tableView reloadData];
}

- (void)runPendingSearch {
    self.pendingSearch = nil;
    NSString *query = self.searchBar.text ?: @"";
    self.results = [self.store search:query limit:200];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                  reuseIdentifier:nil];
    LNSearchHit *hit = self.results[indexPath.row];

    cell.textLabel.attributedText = [self highlighted:hit.headline
                                                query:self.searchBar.text ?: @""];
    cell.textLabel.numberOfLines = 1;

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · Page %ld — %@",
                                 hit.issue.title, (long)hit.pageNumber, hit.snippet];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LNSearchHit *hit = self.results[indexPath.row];
    IssueViewController *controller = [[IssueViewController alloc] initWithStore:self.store
                                                                          issue:hit.issue
                                                                      startPage:hit.pageNumber];
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - Highlighting

- (NSAttributedString *)highlighted:(NSString *)text query:(NSString *)query {
    NSMutableAttributedString *attributed =
        [[NSMutableAttributedString alloc] initWithString:text
                                               attributes:@{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.1 alpha:1.0]
        }];
    if (query.length == 0) {
        return attributed;
    }

    NSRange searchRange = NSMakeRange(0, text.length);
    while (searchRange.length > 0) {
        NSRange found = [text rangeOfString:query
                                    options:NSCaseInsensitiveSearch
                                      range:searchRange];
        if (found.location == NSNotFound) {
            break;
        }
        [attributed addAttribute:NSForegroundColorAttributeName
                           value:[UIColor colorWithRed:0.1 green:0.45 blue:0.9 alpha:1.0]
                           range:found];

        NSUInteger nextLocation = found.location + found.length;
        if (nextLocation >= text.length) {
            break;
        }
        searchRange = NSMakeRange(nextLocation, text.length - nextLocation);
    }
    return attributed;
}

@end
