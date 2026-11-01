#import "AppDelegate.h"
#import "HomeViewController.h"
#import "LibraryStore.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    LibraryStore *store = [LibraryStore sharedStore];
    HomeViewController *home = [[HomeViewController alloc] initWithStore:store];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:home];

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
