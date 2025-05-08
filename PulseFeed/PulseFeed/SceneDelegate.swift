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
        
        // Apply the app theme
        applyAppTheme()
        
        // Observe theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyAppTheme),
            name: Notification.Name("appThemeChanged"),
            object: nil
        )
        
        // Perform initial sync from CloudKit if needed
        if iCloudEnabled {
            StorageManager.shared.syncFromCloudKit { success in
                print("DEBUG: Initial CloudKit sync completed with success: \(success)")
            }
        }
    }
    
    @objc func applyAppTheme() {
        // Get the current theme
        let themeManager = AppThemeManager.shared
        
        // Apply theme to global UI elements
        if let window = window {
            // Configure UI appearance
            UINavigationBar.appearance().tintColor = AppColors.accent
            UINavigationBar.appearance().backgroundColor = AppColors.navBarBackground
            UITabBar.appearance().tintColor = AppColors.accent
            UITabBar.appearance().backgroundColor = AppColors.navBarBackground
            
            // Only set light/dark mode if theme is not system
            if themeManager.selectedTheme.name == "System" {
                window.overrideUserInterfaceStyle = .unspecified
            } else if themeManager.selectedTheme.name == "Dark" {
                window.overrideUserInterfaceStyle = .dark
            } else {
                window.overrideUserInterfaceStyle = .light
            }
            
            // Force the window to update
            window.backgroundColor = AppColors.background
        }
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // This will trigger the StorageManager's didBecomeActive handler
        // but we're adding it here for clarity
        if UserDefaults.standard.bool(forKey: "useICloud") {
            StorageManager.shared.syncFromCloudKit()
        }
    }
}
