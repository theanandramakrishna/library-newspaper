#import <UIKit/UIKit.h>
#import "LibraryStore.h"

@interface IssueViewController : UIViewController

@property (nonatomic, strong) LNIssue *issue;

- (instancetype)initWithStore:(LibraryStore *)store
                        issue:(LNIssue *)issue
                    startPage:(NSInteger)startPage;

// Replaces the page list and refreshes the toolbar (called when more pages
// finish downloading in the background).
- (void)updatePages:(NSArray<LNPage *> *)pages;

// Refreshes the page count / slider after pages are added or removed.
- (void)updateToolbar;

@end
