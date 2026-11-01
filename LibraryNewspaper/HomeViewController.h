#import <UIKit/UIKit.h>
#import "LibraryStore.h"

@class IssueViewController;

/// Root view controller. Shows the currently chosen newspaper in the offline
/// viewer, or "Paper not fetched yet" when nothing has been fetched. A footer
/// bar carries Settings / Date picker / Fetch paper.
@interface HomeViewController : UIViewController

@property (nonatomic, strong) LibraryStore *store;
@property (nonatomic, strong) LNIssue *currentIssue;
@property (nonatomic, strong) NSDate *selectedDate;

- (instancetype)initWithStore:(LibraryStore *)store;
- (void)showPaperNotFetched;
- (void)showIssue:(LNIssue *)issue;

@end
