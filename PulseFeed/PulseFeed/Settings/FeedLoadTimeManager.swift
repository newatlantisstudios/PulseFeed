import Foundation

class FeedLoadTimeManager {
    static let shared = FeedLoadTimeManager()
    private init() {
        // Load saved slow/failed feeds from UserDefaults when initialized
        if let data = UserDefaults.standard.data(forKey: "slowOrFailedFeeds") {
            if let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
                failureCount = saved
            }
        }
    }
    
    // Dictionary mapping feed title to its load time in seconds
    var loadTimes: [String: TimeInterval] = [:]
    
    // Dictionary tracking consecutive failures or slow loads for feeds
    private var failureCount: [String: Int] = [:]
    
    // Default threshold in seconds before a feed is considered "slow"
    private let defaultSlowThreshold: TimeInterval = 10.0
    
    // Get the user-configured slow threshold
    var slowThreshold: TimeInterval {
        return UserDefaults.standard.double(forKey: "feedSlowThreshold") > 0 
            ? UserDefaults.standard.double(forKey: "feedSlowThreshold") 
            : defaultSlowThreshold
    }
    
    // Maximum failures before suggesting to remove a feed
    let maxFailures = 3
    
    // Record the load time for a feed
    func recordLoadTime(for feedTitle: String, time: TimeInterval) {
        loadTimes[feedTitle] = time
        
        // Consider this a failure if time is excessive (45+ seconds) or negative (error)
        if time >= 45 || time < 0 {
            increaseFailureCount(for: feedTitle)
        } else if time > slowThreshold {
            // For slow but not completely failed feeds, increment but with less weight
            if let currentCount = failureCount[feedTitle] {
                failureCount[feedTitle] = currentCount < maxFailures ? currentCount + 1 : currentCount
            } else {
                failureCount[feedTitle] = 1
            }
            saveFailureCounts()
        } else {
            // If successful and fast, reset failure count
            failureCount[feedTitle] = 0
            saveFailureCounts()
        }
        
        NotificationCenter.default.post(name: Notification.Name("feedLoadTimeUpdated"), 
                                       object: nil, 
                                       userInfo: ["feedTitle": feedTitle, "loadTime": time])
    }
    
    // Record a failed feed with negative time value to distinguish from slow
    func recordFailedFeed(for feedTitle: String) {
        recordLoadTime(for: feedTitle, time: -1)
    }
    
    // Get the load time for a specific feed
    func getLoadTime(for feedTitle: String) -> TimeInterval {
        return loadTimes[feedTitle] ?? 0
    }
    
    // Increase the failure count for a feed
    private func increaseFailureCount(for feedTitle: String) {
        if let currentCount = failureCount[feedTitle] {
            failureCount[feedTitle] = currentCount + 1
        } else {
            failureCount[feedTitle] = 1
        }
        saveFailureCounts()
    }
    
    // Save failure counts to UserDefaults
    private func saveFailureCounts() {
        if let data = try? JSONEncoder().encode(failureCount) {
            UserDefaults.standard.set(data, forKey: "slowOrFailedFeeds")
        }
    }
    
    // Check if a feed should be skipped based on historical performance
    func shouldSkipFeed(titled feedTitle: String) -> Bool {
        let failCount = failureCount[feedTitle] ?? 0
        // Skip if it has failed maxFailures times
        return failCount >= maxFailures
    }
    
    // Get failure count for a feed
    func getFailureCount(for feedTitle: String) -> Int {
        return failureCount[feedTitle] ?? 0
    }
    
    // Reset failure count for a specific feed
    func resetFailureCount(for feedTitle: String) {
        failureCount[feedTitle] = 0
        saveFailureCounts()
    }
    
    // Check if a feed is considered slow
    func isFeedSlow(titled feedTitle: String) -> Bool {
        let time = getLoadTime(for: feedTitle)
        return time > slowThreshold && time > 0
    }
}
