#import <UIKit/UIKit.h>
#import "LibraryStore.h"

@interface IssueViewController : UIViewController

- (instancetype)initWithStore:(LibraryStore *)store
                        issue:(LNIssue *)issue
                    startPage:(NSInteger)startPage;

@end
