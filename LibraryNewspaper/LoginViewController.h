#import <UIKit/UIKit.h>

@interface LoginViewController : UIViewController

// Load saved credentials from the keychain. Returns YES if both username and
// password are present.
+ (BOOL)loadSavedCredentials:(NSString **)username password:(NSString **)password;

// When NO (opened from HomeViewController's Settings), the returning-user
// auto-start is suppressed so the screen just shows pre-filled credentials.
@property (nonatomic, assign) BOOL autoStartEnabled;

@end
