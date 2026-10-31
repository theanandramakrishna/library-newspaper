#import <UIKit/UIKit.h>
#import "Models.h"

@interface ArticleListViewController : UITableViewController

@property (nonatomic, copy) void (^onSelect)(LNArticle *article);

- (instancetype)initWithArticles:(NSArray<LNArticle *> *)articles;

@end
