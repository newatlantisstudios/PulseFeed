import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let iCloudEnabled = UserDefaults.standard.bool(forKey: "useICloud")
        StorageManager.shared.method = iCloudEnabled ? .cloudKit : .userDefaults
        print("DEBUG: At launch, using \(StorageManager.shared.method)")
        
        window = UIWindow(windowScene: windowScene)
        let navigationController = UINavigationController(rootViewController: HomeFeedViewController())
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }
}
