import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let store = LibraryStore.shared
        let library = LibraryViewController(store: store)
        let navigation = UINavigationController(rootViewController: library)

        navigation.navigationBar.barTintColor = UIColor(white: 0.08, alpha: 1.0)
        navigation.navigationBar.isTranslucent = false
        navigation.navigationBar.barStyle = .black
        navigation.navigationBar.tintColor = UIColor(white: 0.95, alpha: 1.0)
        navigation.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .black
        window?.rootViewController = navigation
        window?.makeKeyAndVisible()

        return true
    }
}
