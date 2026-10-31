#import "ArticleViewController.h"

@interface ArticleViewController ()
@property (nonatomic, strong) LNArticle *article;
@property (nonatomic, strong) LNIssue *issue;
@end

@implementation ArticleViewController

- (instancetype)initWithArticle:(LNArticle *)article issue:(LNIssue *)issue {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _article = article;
        _issue = issue;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.issue.title;
    self.view.backgroundColor = [UIColor colorWithWhite:0.99 alpha:1.0];
    self.automaticallyAdjustsScrollViewInsets = NO;

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;
    textView.backgroundColor = [UIColor clearColor];
    textView.editable = NO;
    textView.selectable = YES;
    textView.alwaysBounceVertical = YES;
    textView.textContainerInset = UIEdgeInsetsMake(24, 22, 48, 22);
    textView.attributedText = [self content];
    [self.view addSubview:textView];
}

- (NSAttributedString *)content {
    NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];

    NSMutableParagraphStyle *headlineStyle = [[NSMutableParagraphStyle alloc] init];
    headlineStyle.paragraphSpacing = 8;
    [content appendAttributedString:
        [[NSAttributedString alloc] initWithString:[self.article.headline stringByAppendingString:@"\n"]
                                       attributes:@{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:26],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.08 alpha:1.0],
            NSParagraphStyleAttributeName: headlineStyle
        }]];

    NSString *meta = [NSString stringWithFormat:@"%@ · Page %ld",
                      self.issue.title, (long)self.article.pageNumber];
    NSMutableParagraphStyle *metaStyle = [[NSMutableParagraphStyle alloc] init];
    metaStyle.paragraphSpacing = 18;
    [content appendAttributedString:
        [[NSAttributedString alloc] initWithString:[meta stringByAppendingString:@"\n"]
                                       attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:13],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.45 alpha:1.0],
            NSParagraphStyleAttributeName: metaStyle
        }]];

    NSString *body = self.article.text.length > 0
        ? self.article.text
        : @"No text was found for this article. Add a transcription to the OCR folder "
          @"or include a \"text\" value in the article JSON.";

    NSMutableParagraphStyle *bodyStyle = [[NSMutableParagraphStyle alloc] init];
    bodyStyle.lineSpacing = 5;
    bodyStyle.paragraphSpacing = 14;
    UIFont *bodyFont = [UIFont fontWithName:@"Georgia" size:18] ?: [UIFont systemFontOfSize:18];
    [content appendAttributedString:
        [[NSAttributedString alloc] initWithString:body
                                       attributes:@{
            NSFontAttributeName: bodyFont,
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.12 alpha:1.0],
            NSParagraphStyleAttributeName: bodyStyle
        }]];

    return content;
}

@end
