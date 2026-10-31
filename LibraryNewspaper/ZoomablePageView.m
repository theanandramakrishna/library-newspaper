#import "ZoomablePageView.h"
#import "LibraryStore.h"

@interface ZoomablePageView () <UIScrollViewDelegate>
@end

@implementation ZoomablePageView {
    UIScrollView *_scrollView;
    UIView *_contentView;
    UIImageView *_imageView;
    UIView *_overlayContainer;
    UIActivityIndicatorView *_spinner;

    NSMutableArray<UIButton *> *_articleButtons;
    NSArray<LNArticle *> *_pageArticles;
    CGSize _imagePixelSize;
    BOOL _isAdjustingZoom;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    self.backgroundColor = [UIColor blackColor];
    self.clipsToBounds = YES;
    _showsArticleHighlights = YES;
    _articleButtons = [NSMutableArray array];
    _pageArticles = @[];
    _imagePixelSize = CGSizeZero;

    _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                   UIViewAutoresizingFlexibleHeight;
    _scrollView.delegate = self;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.bouncesZoom = YES;
    _scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    _scrollView.backgroundColor = [UIColor blackColor];
    [self addSubview:_scrollView];

    _contentView = [[UIView alloc] init];
    _contentView.backgroundColor = [UIColor clearColor];
    [_scrollView addSubview:_contentView];

    _imageView = [[UIImageView alloc] init];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.clipsToBounds = YES;
    [_contentView addSubview:_imageView];

    _overlayContainer = [[UIView alloc] init];
    _overlayContainer.backgroundColor = [UIColor clearColor];
    _overlayContainer.userInteractionEnabled = YES;
    [_contentView addSubview:_overlayContainer];

    _spinner = [[UIActivityIndicatorView alloc]
                   initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES;
    _spinner.color = [UIColor whiteColor];
    _spinner.frame = self.bounds;
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;
    [self addSubview:_spinner];

    UISwipeGestureRecognizer *leftSwipe =
        [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    leftSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
    [self addGestureRecognizer:leftSwipe];

    UISwipeGestureRecognizer *rightSwipe =
        [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    rightSwipe.direction = UISwipeGestureRecognizerDirectionRight;
    [self addGestureRecognizer:rightSwipe];

    UITapGestureRecognizer *doubleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap)];
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self addGestureRecognizer:singleTap];
}

#pragma mark - Content

- (void)setShowsArticleHighlights:(BOOL)shows {
    _showsArticleHighlights = shows;
    [self updateArticleChrome];
}

- (void)configureWithIssue:(LNIssue *)issue
                      page:(LNPage *)page
                  articles:(NSArray<LNArticle *> *)articles {
    NSMutableArray *filtered = [NSMutableArray array];
    for (LNArticle *article in articles) {
        if (article.pageNumber == page.number) {
            [filtered addObject:article];
        }
    }
    _pageArticles = filtered;
    [self clearArticleButtons];

    _imagePixelSize = CGSizeZero;
    _imageView.image = nil;
    _contentView.frame = CGRectMake(0, 0,
                                    MAX(self.bounds.size.width, 1),
                                    MAX(self.bounds.size.height, 1));
    _imageView.frame = _contentView.bounds;
    _overlayContainer.frame = _contentView.bounds;

    UIImage *cached = [[ImageLoader sharedLoader] cachedImageForURL:page.imageURL];
    if (cached != nil) {
        [self applyImage:cached page:page];
        return;
    }

    [_spinner startAnimating];
    __weak ZoomablePageView *weakSelf = self;
    [[ImageLoader sharedLoader] loadImageForURL:page.imageURL
                                  maxPixelSize:3200
                                    completion:^(UIImage *image) {
        ZoomablePageView *strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf->_spinner.isAnimating) {
            return;
        }
        if (image == nil) {
            [strongSelf->_spinner stopAnimating];
            return;
        }
        [strongSelf applyImage:image page:page];
    }];
}

- (void)applyImage:(UIImage *)image page:(LNPage *)page {
    [_spinner stopAnimating];

    _imagePixelSize = image.size;
    _contentView.frame = CGRectMake(0, 0, image.size.width, image.size.height);
    _imageView.frame = _contentView.bounds;
    _overlayContainer.frame = _contentView.bounds;
    _imageView.image = image;

    [self buildArticleButtonsForPage:page];
    [self applyFitZoom];
}

- (void)buildArticleButtonsForPage:(LNPage *)page {
    [self clearArticleButtons];

    CGFloat scaleX = page.pixelWidth > 0 ? _imagePixelSize.width / (CGFloat)page.pixelWidth : 1.0;
    CGFloat scaleY = page.pixelHeight > 0 ? _imagePixelSize.height / (CGFloat)page.pixelHeight : 1.0;

    [_pageArticles enumerateObjectsUsingBlock:^(LNArticle *article, NSUInteger index, BOOL *stop) {
        CGRect rect = CGRectMake(article.bounds.origin.x * scaleX,
                                 article.bounds.origin.y * scaleY,
                                 article.bounds.size.width * scaleX,
                                 article.bounds.size.height * scaleY);

        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = rect;
        button.tag = (NSInteger)index;
        [button addTarget:self
                   action:@selector(articleTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        button.layer.cornerRadius = 2.0;
        [self->_overlayContainer addSubview:button];
        [self->_articleButtons addObject:button];
    }];
    [self updateArticleChrome];
}

- (void)clearArticleButtons {
    for (UIButton *button in _articleButtons) {
        [button removeFromSuperview];
    }
    [_articleButtons removeAllObjects];
}

- (void)updateArticleChrome {
    CGFloat scale = MAX(_scrollView.zoomScale / MAX(_scrollView.minimumZoomScale, 0.0001), 1.0);
    CGFloat borderWidth = _showsArticleHighlights ? 1.0 / scale : 0.0;

    for (UIButton *button in _articleButtons) {
        button.layer.borderWidth = borderWidth;
        button.layer.borderColor = [UIColor colorWithRed:0.25 green:0.65 blue:1.0 alpha:0.9].CGColor;
        button.backgroundColor = _showsArticleHighlights
            ? [UIColor colorWithRed:0.25 green:0.65 blue:1.0 alpha:0.08]
            : [UIColor clearColor];
    }
}

#pragma mark - Zoom

- (CGFloat)fitScale {
    if (_imagePixelSize.width <= 0 || _imagePixelSize.height <= 0 ||
        self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
        return 1.0;
    }
    return MIN(self.bounds.size.width / _imagePixelSize.width,
               self.bounds.size.height / _imagePixelSize.height);
}

- (void)applyFitZoom {
    if (_imagePixelSize.width <= 0) {
        return;
    }
    _isAdjustingZoom = YES;
    CGFloat fit = [self fitScale];
    _scrollView.minimumZoomScale = fit;
    _scrollView.maximumZoomScale = MAX(fit * 5.0, 1.0);
    _scrollView.zoomScale = fit;
    _isAdjustingZoom = NO;
    [self centerContent];
    [self updateArticleChrome];
}

- (void)centerContent {
    CGSize zoomedSize = CGSizeMake(_contentView.bounds.size.width * _scrollView.zoomScale,
                                   _contentView.bounds.size.height * _scrollView.zoomScale);
    CGFloat insetX = MAX((self.bounds.size.width - zoomedSize.width) / 2.0, 0);
    CGFloat insetY = MAX((self.bounds.size.height - zoomedSize.height) / 2.0, 0);
    _scrollView.contentInset = UIEdgeInsetsMake(insetY, insetX, insetY, insetX);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scrollView.frame = self.bounds;
    _spinner.frame = self.bounds;

    if (_imagePixelSize.width > 0 && !_isAdjustingZoom) {
        if (fabs([self fitScale] - _scrollView.minimumZoomScale) > 0.0001) {
            [self applyFitZoom];
        } else {
            [self centerContent];
        }
    }
}

#pragma mark - Gestures

- (void)handleSwipe:(UISwipeGestureRecognizer *)recognizer {
    if (_scrollView.zoomScale > _scrollView.minimumZoomScale * 1.02) {
        return;
    }
    NSInteger offset = recognizer.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1;
    [self.delegate pageView:self didRequestPageOffset:offset];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (_scrollView.zoomScale > _scrollView.minimumZoomScale * 1.05) {
        [_scrollView setZoomScale:_scrollView.minimumZoomScale animated:YES];
        return;
    }

    CGPoint point = [recognizer locationInView:_contentView];
    CGFloat target = MIN(_scrollView.maximumZoomScale, _scrollView.minimumZoomScale * 2.5);
    CGSize size = CGSizeMake(_scrollView.bounds.size.width / target,
                             _scrollView.bounds.size.height / target);
    CGRect rect = CGRectMake(point.x - size.width / 2.0,
                             point.y - size.height / 2.0,
                             size.width,
                             size.height);
    [_scrollView zoomToRect:rect animated:YES];
}

- (void)handleSingleTap {
    [self.delegate pageViewDidRequestChromeToggle:self];
}

- (void)articleTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)_pageArticles.count) {
        return;
    }
    [self.delegate pageView:self didSelectArticle:_pageArticles[(NSUInteger)sender.tag]];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _contentView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    if (_isAdjustingZoom) {
        return;
    }
    [self centerContent];
    [self updateArticleChrome];
}

@end
