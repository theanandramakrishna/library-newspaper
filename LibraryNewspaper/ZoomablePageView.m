#import "ZoomablePageView.h"
#import "LibraryStore.h"
#import <QuartzCore/QuartzCore.h>

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

    // Drop the previous page's zoom before touching the content view's frame.
    _scrollView.minimumZoomScale = 0.001;
    _scrollView.maximumZoomScale = 100.0;
    _scrollView.zoomScale = 1.0;
    _contentView.transform = CGAffineTransformIdentity;

    _contentView.frame = CGRectMake(0, 0,
                                    MAX(self.bounds.size.width, 1),
                                    MAX(self.bounds.size.height, 1));
    _imageView.frame = _contentView.bounds;
    _overlayContainer.frame = _contentView.bounds;

    NSLog(@"[auth] ZoomablePageView: configureWithIssue page=%ld, view bounds=%.0fx%.0f, imageURL=%@",
          (long)page.number, self.bounds.size.width, self.bounds.size.height, page.imageURL.lastPathComponent);

    UIImage *cached = [[ImageLoader sharedLoader] cachedImageForURL:page.imageURL];
    if (cached != nil) {
        NSLog(@"[auth] ZoomablePageView: CACHE HIT for page %ld (%dx%d)", (long)page.number,
              (NSInteger)cached.size.width, (NSInteger)cached.size.height);
        [self applyImage:cached page:page];
        return;
    }

    NSLog(@"[auth] ZoomablePageView: CACHE MISS for page %ld, starting async load", (long)page.number);

    [_spinner startAnimating];
    __weak ZoomablePageView *weakSelf = self;
    [[ImageLoader sharedLoader] loadImageForURL:page.imageURL
                                  maxPixelSize:3200
                                    completion:^(UIImage *image) {
        ZoomablePageView *strongSelf = weakSelf;
        if (strongSelf == nil) {
            NSLog(@"[auth] ZoomablePageView: async completion for page %ld: self is nil", (long)page.number);
            return;
        }
        if (!strongSelf->_spinner.isAnimating) {
            NSLog(@"[auth] ZoomablePageView: async completion for page %ld: spinner NOT animating (skipping)", (long)page.number);
            return;
        }
        if (image == nil) {
            [strongSelf->_spinner stopAnimating];
            // Show an error indicator instead of a black screen.
            UILabel *errorLabel = [[UILabel alloc] initWithFrame:strongSelf.bounds];
            errorLabel.text = @"Failed to render page";
            errorLabel.textColor = [UIColor whiteColor];
            errorLabel.textAlignment = NSTextAlignmentCenter;
            errorLabel.backgroundColor = [UIColor blackColor];
            errorLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                          UIViewAutoresizingFlexibleHeight;
            [strongSelf addSubview:errorLabel];
            NSLog(@"[auth] ZoomablePageView: failed to render page %ld from %@",
                  (long)page.number, page.imageURL.path);
            return;
        }
        NSLog(@"[auth] ZoomablePageView: async completion for page %ld: applying image %dx%d",
              (long)page.number, (NSInteger)image.size.width, (NSInteger)image.size.height);
        [strongSelf applyImage:image page:page];
    }];
}

- (void)applyImage:(UIImage *)image page:(LNPage *)page {
    [_spinner stopAnimating];

    _imagePixelSize = image.size;
    _imageView.image = image;

    // Sizing the content view is left to applyFitZoom, which first clears the
    // previous page's zoom transform. Setting frame while a transform is in
    // effect rewrites the view's bounds (frame is transformed), which would
    // make the page draw several times too large.

    // Diagnostics: sample pixels to check the image isn't all black.
    BOOL hasNonBlack = [self image:image hasNonBlackPixels:NO];
    NSLog(@"[auth] ZoomablePageView: applied image %dx%d, scrollView bounds %dx%d, hasNonBlack=%d, imageView.hidden=%d, imageView.alpha=%.2f, inWindow=%d",
          (NSInteger)image.size.width, (NSInteger)image.size.height,
          (NSInteger)_scrollView.bounds.size.width, (NSInteger)_scrollView.bounds.size.height,
          hasNonBlack,
          _imageView.hidden, _imageView.alpha,
          [_imageView window] != nil);

    // Save first page image to disk for inspection.
    if (page.number == 1) {
        NSData *pngData = UIImagePNGRepresentation(image);
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = paths.firstObject;
        NSString *savePath = [docDir stringByAppendingPathComponent:@"debug_page1.png"];
        [pngData writeToFile:savePath atomically:YES];
        NSLog(@"[auth] ZoomablePageView: saved debug page1 image to %@", savePath);
    }

    [self applyFitZoom];
    [self buildArticleButtonsForPage:page];
}

- (BOOL)image:(UIImage *)image hasNonBlackPixels:(BOOL)logDetails {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return NO;
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
    if (!data) return NO;
    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    if (length == 0) { CFRelease(data); return NO; }

    // Sample every Nth pixel for speed.
    NSUInteger stride = CGImageGetBytesPerRow(cgImage);
    NSUInteger bpp = CGImageGetBitsPerPixel(cgImage) / 8;
    BOOL found = NO;
    for (CFIndex i = 0; i < length && !found; i += stride * 7 + bpp * 11) {
        if (i + 3 < length) {
            uint8_t r = bytes[i], g = bytes[i+1], b = bytes[i+2], a = bytes[i+3];
            if (r > 30 || g > 30 || b > 30) { found = YES; break; }
        }
    }
    CFRelease(data);
    if (logDetails && found) {
        NSLog(@"[auth] ZoomablePageView: image has non-black pixels");
    }
    return found;
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

// The scale at which the whole page fits inside the area left free by the
// chrome (toolbar), so nothing of the page hides underneath it.
- (CGFloat)fitScale {
    if (_imagePixelSize.width <= 0 || _imagePixelSize.height <= 0) {
        return 1.0;
    }
    CGFloat availableWidth = self.bounds.size.width - _pageInsets.left - _pageInsets.right;
    CGFloat availableHeight = self.bounds.size.height - _pageInsets.top - _pageInsets.bottom;
    if (availableWidth <= 0 || availableHeight <= 0) {
        return 1.0;
    }
    return MIN(availableWidth / _imagePixelSize.width,
               availableHeight / _imagePixelSize.height);
}

// The scale at which the page fills the screen width. This is the default: a
// newspaper page is unreadable when the whole of it is squeezed onto the
// screen, so start at full width and let the reader scroll down.
- (CGFloat)fitWidthScale {
    if (_imagePixelSize.width <= 0) {
        return 1.0;
    }
    CGFloat availableWidth = self.bounds.size.width - _pageInsets.left - _pageInsets.right;
    if (availableWidth <= 0) {
        return 1.0;
    }
    CGFloat scale = availableWidth / _imagePixelSize.width;
    // Never upscale beyond the image's own pixels.
    CGFloat limit = MAX(1.0, [self fitScale]);
    return MIN(scale, limit);
}

- (void)setPageInsets:(UIEdgeInsets)pageInsets {
    if (UIEdgeInsetsEqualToEdgeInsets(_pageInsets, pageInsets)) {
        return;
    }
    _pageInsets = pageInsets;
    if (_imagePixelSize.width <= 0) {
        return;
    }
    CGFloat fit = [self fitScale];
    BOOL wasAtFit = fabs(_scrollView.zoomScale - _scrollView.minimumZoomScale) < 0.01;
    if (wasAtFit) {
        [self applyFitZoom];
    } else {
        _scrollView.minimumZoomScale = fit;
        _scrollView.maximumZoomScale = [self maximumScaleForFit:fit];
        [self centerContent];
    }
}

- (CGFloat)maximumScaleForFit:(CGFloat)fit {
    CGFloat fitWidth = [self fitWidthScale];
    return MAX(MAX(fitWidth * 3.0, 1.0), fit);
}

// iOS 9 does not reliably recompute contentSize after a programmatic zoom, so
// the scroll view can keep the old (unzoomed) extent and let the reader pan
// past the end of the page into black space. Keep it equal to the scaled
// content.
- (void)syncContentSizeToZoom {
    if (_contentView.bounds.size.width <= 0 || _contentView.bounds.size.height <= 0) {
        return;
    }
    CGSize scaled = CGSizeMake(_contentView.bounds.size.width * _scrollView.zoomScale,
                               _contentView.bounds.size.height * _scrollView.zoomScale);
    if (fabs(_scrollView.contentSize.width - scaled.width) > 0.5 ||
        fabs(_scrollView.contentSize.height - scaled.height) > 0.5) {
        _scrollView.contentSize = scaled;
    }
}

- (void)applyFitZoom {
    if (_imagePixelSize.width <= 0) {
        return;
    }
    _isAdjustingZoom = YES;

    // Clear any zoom left over from the previous page first. UIScrollView zooms
    // its content view with a transform, and UIView.frame is expressed in the
    // transformed space, so sizing the content view while zoomed rewrites its
    // bounds and the page then draws at the wrong scale.
    _scrollView.minimumZoomScale = 0.001;
    _scrollView.maximumZoomScale = 100.0;
    _scrollView.zoomScale = 1.0;
    _contentView.transform = CGAffineTransformIdentity;

    _contentView.frame = CGRectMake(0, 0, _imagePixelSize.width, _imagePixelSize.height);
    _imageView.frame = _contentView.bounds;
    _overlayContainer.frame = _contentView.bounds;
    _scrollView.contentSize = _imagePixelSize;

    // Zooming all the way out shows the whole page; the default fills the width.
    CGFloat fitPage = MAX([self fitScale], 0.0001);
    CGFloat fitWidth = MAX([self fitWidthScale], fitPage);
    _scrollView.minimumZoomScale = fitPage;
    _scrollView.maximumZoomScale = [self maximumScaleForFit:fitPage];
    _scrollView.zoomScale = fitWidth;

    _isAdjustingZoom = NO;

    [self syncContentSizeToZoom];

    NSLog(@"[auth] ZoomablePageView: pageFit=%.4f widthFit=%.4f image=%.0fx%.0f content=%.0fx%.0f "
           "contentSize=%.0fx%.0f insets=(%.0f,%.0f,%.0f,%.0f) visible=%.0fx%.0f",
          fitPage, fitWidth, _imagePixelSize.width, _imagePixelSize.height,
          _contentView.bounds.size.width, _contentView.bounds.size.height,
          _scrollView.contentSize.width, _scrollView.contentSize.height,
          _pageInsets.top, _pageInsets.left, _pageInsets.bottom, _pageInsets.right,
          _imagePixelSize.width * fitWidth, _imagePixelSize.height * fitWidth);

    [self centerContent];
    [self updateArticleChrome];
}

// Keeps the page centred in the free area and pads the scroll view so its
// content always ends exactly at the view edges.
- (void)centerContent {
    CGSize zoomedSize = CGSizeMake(_contentView.bounds.size.width * _scrollView.zoomScale,
                                   _contentView.bounds.size.height * _scrollView.zoomScale);

    CGFloat freeWidth = self.bounds.size.width - _pageInsets.left - _pageInsets.right;
    CGFloat freeHeight = self.bounds.size.height - _pageInsets.top - _pageInsets.bottom;

    CGFloat left = 0;
    CGFloat right = 0;
    CGFloat top = 0;
    CGFloat bottom = 0;

    if (zoomedSize.width < freeWidth) {
        left = _pageInsets.left + (freeWidth - zoomedSize.width) / 2.0;
    }
    if (zoomedSize.height < freeHeight) {
        top = _pageInsets.top + (freeHeight - zoomedSize.height) / 2.0;
    }
    right = MAX(self.bounds.size.width - left - zoomedSize.width, 0);
    bottom = MAX(self.bounds.size.height - top - zoomedSize.height, 0);

    _scrollView.contentInset = UIEdgeInsetsMake(top, left, bottom, right);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scrollView.frame = self.bounds;
    _spinner.frame = self.bounds;

    if (_imagePixelSize.width > 0 && !_isAdjustingZoom) {
        if (fabs([self fitScale] - _scrollView.minimumZoomScale) > 0.0001) {
            BOOL wasAtFit = fabs(_scrollView.zoomScale - _scrollView.minimumZoomScale) < 0.01;
            if (wasAtFit) {
                [self applyFitZoom];
            } else {
                CGFloat fit = [self fitScale];
                _scrollView.minimumZoomScale = fit;
                _scrollView.maximumZoomScale = [self maximumScaleForFit:fit];
                [self centerContent];
            }
        } else {
            [self syncContentSizeToZoom];
            [self centerContent];
        }
    }
}

#pragma mark - Gestures

- (void)handleSwipe:(UISwipeGestureRecognizer *)recognizer {
    // Page turns work at the resting "fill the width" zoom; once the user zooms
    // in past that, swipes pan the page instead.
    if (_scrollView.zoomScale > [self fitWidthScale] * 1.05) {
        return;
    }
    NSInteger offset = recognizer.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1;
    [self.delegate pageView:self didRequestPageOffset:offset];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    // The resting zoom is "fill the width"; double-tap zooms in from there and
    // the second double-tap comes back. Zooming right out (pinch) shows the
    // whole page.
    CGFloat fitWidth = [self fitWidthScale];
    if (_scrollView.zoomScale > fitWidth * 1.05) {
        [_scrollView setZoomScale:fitWidth animated:YES];
        return;
    }

    CGPoint point = [recognizer locationInView:_contentView];
    CGFloat target = MIN(_scrollView.maximumZoomScale, fitWidth * 2.0);
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

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView
                       withView:(UIView *)view
                        atScale:(CGFloat)scale {
    if (_isAdjustingZoom) {
        return;
    }
    // Pinch-zooming leaves contentSize stale on iOS 9 as well; fix it up once
    // the gesture settles so the page cannot be panned past its edges.
    [self syncContentSizeToZoom];
    [self centerContent];
}

@end
