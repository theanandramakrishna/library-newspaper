#import <UIKit/UIKit.h>
#import "Models.h"

@interface ArticleViewController : UIViewController

- (instancetype)initWithArticle:(LNArticle *)article issue:(LNIssue *)issue;

@end
