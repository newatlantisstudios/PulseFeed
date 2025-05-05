import UIKit
import CloudKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register for remote notifications to support CloudKit subscriptions
        application.registerForRemoteNotifications()
        
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
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
