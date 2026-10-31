#import "IssueViewController.h"
#import "ZoomablePageView.h"
#import "ArticleViewController.h"
#import "ArticleListViewController.h"

@interface IssueViewController () <ZoomablePageViewDelegate>
@property (nonatomic, strong) LibraryStore *store;
@property (nonatomic, strong) LNIssue *issue;
@property (nonatomic) NSInteger pageIndex;
@property (nonatomic, strong) NSArray<LNArticle *> *articles;
@property (nonatomic) BOOL chromeVisible;

@property (nonatomic, strong) ZoomablePageView *pageView;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *nextButton;
@end

@implementation IssueViewController

- (instancetype)initWithStore:(LibraryStore *)store
                        issue:(LNIssue *)issue
                    startPage:(NSInteger)startPage {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _store = store;
        _issue = issue;
        NSInteger index = MAX(0, MIN(issue.pageCount - 1, startPage - 1));
        _pageIndex = index;
        _chromeVisible = YES;
        _articles = @[];
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.issue.title;
    self.view.backgroundColor = [UIColor blackColor];
    self.automaticallyAdjustsScrollViewInsets = NO;

    [self setupPageView];
    [self setupToolbar];
    [self setupNavigationItems];

    self.articles = [self.store articlesForIssue:self.issue];
    [self showPageAtIndex:self.pageIndex];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:!self.chromeVisible animated:animated];
    [self applyChrome];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (BOOL)prefersStatusBarHidden {
    return !self.chromeVisible;
}

#pragma mark - Setup

- (void)setupPageView {
    self.pageView = [[ZoomablePageView alloc] initWithFrame:CGRectZero];
    self.pageView.delegate = self;
    self.pageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pageView];

    [NSLayoutConstraint activateConstraints:@[
        [self.pageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.pageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupToolbar {
    self.toolbar = [[UIView alloc] init];
    self.toolbar.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.88];
    self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.toolbar];

    self.previousButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.previousButton setTitle:@"‹" forState:UIControlStateNormal];
    self.previousButton.titleLabel.font = [UIFont systemFontOfSize:28];
    self.previousButton.tintColor = [UIColor whiteColor];
    self.previousButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.previousButton addTarget:self
                            action:@selector(previousPage)
                  forControlEvents:UIControlEventTouchUpInside];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nextButton setTitle:@"›" forState:UIControlStateNormal];
    self.nextButton.titleLabel.font = [UIFont systemFontOfSize:28];
    self.nextButton.tintColor = [UIColor whiteColor];
    self.nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nextButton addTarget:self
                        action:@selector(nextPage)
              forControlEvents:UIControlEventTouchUpInside];

    self.pageLabel = [[UILabel alloc] init];
    self.pageLabel.font = [UIFont monospacedDigitSystemFontOfSize:12
                                                          weight:UIFontWeightMedium];
    self.pageLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    self.pageLabel.textAlignment = NSTextAlignmentCenter;
    self.pageLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.slider = [[UISlider alloc] init];
    self.slider.minimumValue = 0;
    self.slider.maximumValue = 1;
    self.slider.continuous = NO;
    self.slider.minimumTrackTintColor =
        [UIColor colorWithRed:0.25 green:0.65 blue:1.0 alpha:1.0];
    self.slider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.slider addTarget:self
                    action:@selector(sliderChanged)
          forControlEvents:UIControlEventValueChanged];

    [self.toolbar addSubview:self.previousButton];
    [self.toolbar addSubview:self.pageLabel];
    [self.toolbar addSubview:self.slider];
    [self.toolbar addSubview:self.nextButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.toolbar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.toolbar.heightAnchor constraintEqualToConstant:44],

        [self.previousButton.leadingAnchor constraintEqualToAnchor:self.toolbar.leadingAnchor
                                                          constant:8],
        [self.previousButton.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor],
        [self.previousButton.widthAnchor constraintEqualToConstant:40],

        [self.nextButton.trailingAnchor constraintEqualToAnchor:self.toolbar.trailingAnchor
                                                       constant:-8],
        [self.nextButton.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor],
        [self.nextButton.widthAnchor constraintEqualToConstant:40],

        [self.pageLabel.leadingAnchor constraintEqualToAnchor:self.previousButton.trailingAnchor
                                                     constant:4],
        [self.pageLabel.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor],
        [self.pageLabel.widthAnchor constraintEqualToConstant:66],

        [self.slider.leadingAnchor constraintEqualToAnchor:self.pageLabel.trailingAnchor
                                                  constant:4],
        [self.slider.trailingAnchor constraintEqualToAnchor:self.nextButton.leadingAnchor
                                                   constant:-4],
        [self.slider.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor]
    ]];
}

- (void)setupNavigationItems {
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Articles"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showArticles)],
        [[UIBarButtonItem alloc] initWithTitle:@"Text"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showPageText)]
    ];
}

#pragma mark - Paging

- (void)showPageAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.issue.pageCount) {
        return;
    }
    self.pageIndex = index;
    LNPage *page = self.issue.pages[(NSUInteger)index];

    __weak IssueViewController *weakSelf = self;
    [UIView transitionWithView:self.pageView
                      duration:0.18
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        IssueViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf.pageView configureWithIssue:strongSelf.issue
                                           page:page
                                       articles:strongSelf.articles];
    } completion:nil];

    [self updateToolbar];
    [self prefetchNeighbourOfIndex:index];
}

- (void)prefetchNeighbourOfIndex:(NSInteger)index {
    NSInteger next = index + 1;
    if (next >= self.issue.pageCount) {
        return;
    }
    LNPage *page = self.issue.pages[(NSUInteger)next];
    [[ImageLoader sharedLoader] loadImageForURL:page.imageURL maxPixelSize:3200 completion:^(UIImage *image) {}];
}

- (void)updateToolbar {
    self.pageLabel.text = [NSString stringWithFormat:@"%ld / %ld",
                           (long)(self.pageIndex + 1), (long)self.issue.pageCount];
    self.slider.maximumValue = (float)MAX(self.issue.pageCount - 1, 1);
    self.slider.value = (float)self.pageIndex;
    self.previousButton.enabled = self.pageIndex > 0;
    self.nextButton.enabled = self.pageIndex < self.issue.pageCount - 1;
}

- (void)previousPage {
    [self showPageAtIndex:self.pageIndex - 1];
}

- (void)nextPage {
    [self showPageAtIndex:self.pageIndex + 1];
}

- (void)sliderChanged {
    [self showPageAtIndex:(NSInteger)lroundf(self.slider.value)];
}

#pragma mark - Chrome

- (void)toggleChrome {
    self.chromeVisible = !self.chromeVisible;
    [self.navigationController setNavigationBarHidden:!self.chromeVisible animated:YES];
    [self setNeedsStatusBarAppearanceUpdate];
    [self applyChrome];
}

- (void)applyChrome {
    CGFloat alpha = self.chromeVisible ? 1.0 : 0.0;
    [UIView animateWithDuration:0.2
                     animations:^{
        self.toolbar.alpha = alpha;
    } completion:^(BOOL finished) {
        self.toolbar.hidden = !self.chromeVisible;
    }];
}

#pragma mark - Article actions

- (void)showArticle:(LNArticle *)article {
    ArticleViewController *controller =
        [[ArticleViewController alloc] initWithArticle:article issue:self.issue];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showArticles {
    if (self.articles.count == 0) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"No articles"
                                                message:@"This issue has no article data. "
                                                        @"Add JSON files to its articles/ folder."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    ArticleListViewController *controller =
        [[ArticleListViewController alloc] initWithArticles:self.articles];
    __weak IssueViewController *weakSelf = self;
    controller.onSelect = ^(LNArticle *article) {
        IssueViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf dismissViewControllerAnimated:YES completion:^{
            [strongSelf showPageAtIndex:article.pageNumber - 1];
            [strongSelf showArticle:article];
        }];
    };

    controller.modalPresentationStyle = UIModalPresentationPopover;
    controller.preferredContentSize = CGSizeMake(360, 440);
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    if (popover != nil) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)showPageText {
    LNPage *page = self.issue.pages[(NSUInteger)self.pageIndex];
    NSString *text = [self.store ocrTextForIssue:self.issue page:page];

    LNArticle *article = [[LNArticle alloc] init];
    article.articleID = [NSString stringWithFormat:@"page-%ld", (long)page.number];
    article.pageNumber = page.number;
    article.headline = [NSString stringWithFormat:@"Page %ld", (long)page.number];
    article.bounds = CGRectZero;
    article.text = text;

    [self.navigationController pushViewController:
        [[ArticleViewController alloc] initWithArticle:article issue:self.issue]
                                         animated:YES];
}

#pragma mark - ZoomablePageViewDelegate

- (void)pageView:(ZoomablePageView *)pageView didSelectArticle:(LNArticle *)article {
    [self showArticle:article];
}

- (void)pageView:(ZoomablePageView *)pageView didRequestPageOffset:(NSInteger)offset {
    [self showPageAtIndex:self.pageIndex + offset];
}

- (void)pageViewDidRequestChromeToggle:(ZoomablePageView *)pageView {
    [self toggleChrome];
}

@end
