import UIKit
import CloudKit
import BackgroundTasks
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure background refresh first (must happen early in the launch process)
        configureBackgroundRefresh(application)
        
        // Request notification authorization for background refresh alerts
        requestNotificationAuthorization()
        
        // Migrate settings from old keys to new keys
        migrateUserSettings()
        
        // Register for remote notifications to support CloudKit subscriptions
        application.registerForRemoteNotifications()
        
        return true
    }
    
    /// Request authorization for notifications
    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("DEBUG: Notification authorization granted")
            } else if let error = error {
                print("ERROR: Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Configure background refresh capabilities
    private func configureBackgroundRefresh(_ application: UIApplication) {
        // Configure BackgroundTasks framework
        BackgroundRefreshManager.shared.configureBackgroundFetch(for: application)
            
        // Schedule the first background refresh
        BackgroundRefreshManager.shared.scheduleBackgroundRefresh()
    }
    
    /// Migrate user settings from old keys to new keys
    private func migrateUserSettings() {
        // Migrate from "showReadArticles" to "hideReadArticles"
        if UserDefaults.standard.object(forKey: "showReadArticles") != nil {
            // Transfer the same value - meaning is the same, just the label changed
            let oldValue = UserDefaults.standard.bool(forKey: "showReadArticles")
            UserDefaults.standard.set(oldValue, forKey: "hideReadArticles")
            
            // Debug log
            print("DEBUG: Migrated setting: showReadArticles (\(oldValue)) → hideReadArticles (\(oldValue))")
            
            // Remove the old key to prevent confusion
            UserDefaults.standard.removeObject(forKey: "showReadArticles")
        }
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    // Handle regular background fetch (iOS 12 and earlier)
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Delegate to background refresh manager
        BackgroundRefreshManager.shared.handleBackgroundFetch(application: application, completionHandler: completionHandler)
    }
    
    // Handle remote notifications (CloudKit subscription notifications)
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Check if this is a CloudKit notification
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo as! [String : NSObject]) {
            print("DEBUG: Received CloudKit notification: \(notification)")
            
            // Post notification for StorageManager to handle
            NotificationCenter.default.post(name: Notification.Name("CKRemoteChangeNotification"), object: notification)
            
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // Handle registration success
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("DEBUG: Successfully registered for remote notifications with token: \(token)")
    }
    
    // Handle registration failure
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("ERROR: Failed to register for remote notifications: \(error.localizedDescription)")
    }
}
