#import <UIKit/UIKit.h>

@interface AuthWebViewController : UIViewController

// Loads the KCLS OpenAthens redirector in an embedded web view, silently
// fills and submits the login form with the given credentials, then follows
// Seattle Times Collection -> image format -> most recent issue. On any
// failure it reports the failure and pops back to the previous screen.
- (instancetype)initWithUsername:(NSString *)username
                        password:(NSString *)password;

- (void)start;

@end
