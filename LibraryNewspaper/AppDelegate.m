#import "AppDelegate.h"
#import "LoginViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // The app opens on the KCLS logon screen. LoginViewController pushes the
    // AuthWebViewController web flow on Logon, and automatically for returning
    // users with saved credentials. The offline file reader
    // (LibraryViewController and friends) remains compiled but unreachable.
    LoginViewController *login = [[LoginViewController alloc] init];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:login];

    navigation.navigationBar.barTintColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    navigation.navigationBar.translucent = NO;
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.tintColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    navigation.navigationBar.titleTextAttributes =
        @{NSForegroundColorAttributeName: [UIColor whiteColor]};

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
