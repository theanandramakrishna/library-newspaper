#import <UIKit/UIKit.h>
#import "Models.h"

@class ZoomablePageView;

@protocol ZoomablePageViewDelegate <NSObject>
- (void)pageView:(ZoomablePageView *)pageView didSelectArticle:(LNArticle *)article;
- (void)pageView:(ZoomablePageView *)pageView didRequestPageOffset:(NSInteger)offset;
- (void)pageViewDidRequestChromeToggle:(ZoomablePageView *)pageView;
@end

/// Displays one replica page: pinch-zoom, double-tap zoom, tappable article
/// regions and edge swipes for page turns.
@interface ZoomablePageView : UIView

@property (nonatomic, weak) id<ZoomablePageViewDelegate> delegate;
@property (nonatomic) BOOL showsArticleHighlights;

- (void)configureWithIssue:(LNIssue *)issue
                      page:(LNPage *)page
                  articles:(NSArray<LNArticle *> *)articles;

@end
