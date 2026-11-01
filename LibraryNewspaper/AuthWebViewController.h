#import <UIKit/UIKit.h>

@class LNIssue;

typedef void (^LNAuthCompletion)(LNIssue *fetchedIssue, NSError *error);

/// Loads the KCLS OpenAthens redirector in an embedded web view, silently
/// fills and submits the login form with the given credentials, then follows
/// Seattle Times Collection -> image format -> issue for the target date.
/// When the page-1 image viewer is reached, downloads the paper's page images
/// to Documents/NewsFiles/<issue-id>/ and invokes onComplete with the saved
/// issue (or an error). On any failure it reports the failure and stays in
/// the web view (Retry/Dismiss).
@interface AuthWebViewController : UIViewController

- (instancetype)initWithUsername:(NSString *)username
                        password:(NSString *)password
                       targetDate:(NSString *)targetDate; // yyyy-MM-dd, may be nil

@property (nonatomic, copy) NSString *targetDate;
@property (nonatomic, copy) LNAuthCompletion onComplete;
@property (nonatomic, assign) BOOL downloadActive;
@property (nonatomic, assign) NSInteger nextDownloadPage;
@property (nonatomic, assign) NSInteger downloadRetries;
@property (nonatomic, strong) NSTimer *downloadRetryTimer;
@property (nonatomic, strong) NSMutableArray *pageImageURLs;
@property (nonatomic, copy) NSString *issueIDString;
@property (nonatomic, strong) NSString *issueTitle;
@property (nonatomic, strong) NSString *issueDateText;
@property (nonatomic, strong) NSURLSession *downloadSession;

- (void)start;

@end
