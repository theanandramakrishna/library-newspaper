#import "ArticleListViewController.h"

@interface ArticleListViewController ()
@property (nonatomic, strong) NSArray<LNArticle *> *articles;
@end

@implementation ArticleListViewController

- (instancetype)initWithArticles:(NSArray<LNArticle *> *)articles {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _articles = articles;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Articles";
    self.tableView.rowHeight = 56;
    self.tableView.tableFooterView = [[UIView alloc] init];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.articles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                  reuseIdentifier:nil];
    LNArticle *article = self.articles[indexPath.row];
    cell.textLabel.text = article.headline;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Page %ld",
                                 (long)article.pageNumber];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (self.onSelect != nil) {
        self.onSelect(self.articles[indexPath.row]);
    }
}

@end
