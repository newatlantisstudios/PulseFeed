import Foundation

class FeedLoadTimeManager {
    static let shared = FeedLoadTimeManager()
    private init() {}
    // Dictionary mapping feed title to its load time in seconds.
    var loadTimes: [String: TimeInterval] = [:]
    
    // Record the load time for a feed
    func recordLoadTime(for feedTitle: String, time: TimeInterval) {
        loadTimes[feedTitle] = time
        NotificationCenter.default.post(name: Notification.Name("feedLoadTimeUpdated"), object: nil, userInfo: ["feedTitle": feedTitle, "loadTime": time])
    }
    
    // Get the load time for a specific feed
    func getLoadTime(for feedTitle: String) -> TimeInterval {
        return loadTimes[feedTitle] ?? 0
    }
}
