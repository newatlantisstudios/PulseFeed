import Foundation

/// Defines the possible refresh intervals for feeds
enum RefreshInterval: Int, Codable, CaseIterable {
    case manual = 0       // Manual refresh only
    case minutes15 = 15   // 15 minutes
    case minutes30 = 30   // 30 minutes
    case hourly = 60      // 1 hour
    case hours3 = 180     // 3 hours
    case hours6 = 360     // 6 hours
    case daily = 1440     // 24 hours
    
    /// Returns the interval in seconds
    var timeInterval: TimeInterval {
        return TimeInterval(self.rawValue * 60)
    }
    
    /// Returns a human-readable description of the interval
    var description: String {
        switch self {
        case .manual:
            return "Manual Only"
        case .minutes15:
            return "15 Minutes"
        case .minutes30:
            return "30 Minutes"
        case .hourly:
            return "1 Hour"
        case .hours3:
            return "3 Hours"
        case .hours6:
            return "6 Hours"
        case .daily:
            return "Daily"
        }
    }
}

/// Class to manage refresh interval settings both globally and per feed
class RefreshIntervalManager {
    /// Singleton instance
    static let shared = RefreshIntervalManager()
    
    /// Default global refresh interval
    private let defaultGlobalInterval: RefreshInterval = .hourly
    
    /// Dictionary mapping feed URLs to their refresh intervals
    private var feedIntervals: [String: RefreshInterval] = [:]
    
    /// Flag indicating whether to use per-feed custom intervals
    private var useCustomIntervals: Bool = false
    
    /// Global refresh interval used when individual customization is disabled
    private var globalInterval: RefreshInterval = .hourly
    
    /// Date of the last refresh per feed
    private var lastRefreshDates: [String: Date] = [:]
    
    private init() {
        // Load saved settings
        if let data = UserDefaults.standard.data(forKey: "refreshIntervalSettings"),
           let settings = try? JSONDecoder().decode([String: Int].self, from: data) {
            
            var loadedIntervals: [String: RefreshInterval] = [:]
            
            for (key, value) in settings {
                if key == "global" {
                    globalInterval = RefreshInterval(rawValue: value) ?? defaultGlobalInterval
                } else if key == "useCustom" {
                    useCustomIntervals = value == 1
                } else if let interval = RefreshInterval(rawValue: value) {
                    loadedIntervals[key] = interval
                }
            }
            
            feedIntervals = loadedIntervals
        } else {
            // Default settings if none saved
            globalInterval = defaultGlobalInterval
            useCustomIntervals = false
        }
        
        // Load last refresh dates
        if let data = UserDefaults.standard.data(forKey: "lastRefreshDates"),
           let dates = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastRefreshDates = dates
        }
    }
    
    /// Save all settings to UserDefaults
    private func saveSettings() {
        var settings: [String: Int] = [
            "global": globalInterval.rawValue,
            "useCustom": useCustomIntervals ? 1 : 0
        ]
        
        // Add all feed-specific intervals
        for (feedURL, interval) in feedIntervals {
            settings[feedURL] = interval.rawValue
        }
        
        // Save to UserDefaults
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "refreshIntervalSettings")
        }
        
        // Save last refresh dates
        if let data = try? JSONEncoder().encode(lastRefreshDates) {
            UserDefaults.standard.set(data, forKey: "lastRefreshDates")
        }
        
        // Post notification that settings changed
        NotificationCenter.default.post(name: NSNotification.Name("refreshIntervalSettingsChanged"), object: nil)
    }
    
    /// Get the current global refresh interval
    var currentGlobalInterval: RefreshInterval {
        get { return globalInterval }
        set {
            globalInterval = newValue
            saveSettings()
        }
    }
    
    /// Check whether custom intervals are enabled
    var areCustomIntervalsEnabled: Bool {
        get { return useCustomIntervals }
        set {
            useCustomIntervals = newValue
            saveSettings()
        }
    }
    
    /// Set a custom interval for a specific feed
    /// - Parameters:
    ///   - interval: The refresh interval to set
    ///   - feedURL: The URL of the feed
    func setInterval(_ interval: RefreshInterval, forFeed feedURL: String) {
        let normalizedURL = StorageManager.shared.normalizeLink(feedURL)
        feedIntervals[normalizedURL] = interval
        saveSettings()
    }
    
    /// Get the refresh interval for a specific feed
    /// - Parameter feedURL: The URL of the feed
    /// - Returns: The feed's refresh interval (or the global interval if not customized)
    func getInterval(forFeed feedURL: String) -> RefreshInterval {
        if !useCustomIntervals {
            return globalInterval
        }
        
        let normalizedURL = StorageManager.shared.normalizeLink(feedURL)
        return feedIntervals[normalizedURL] ?? globalInterval
    }
    
    /// Check if a feed is due for refresh
    /// - Parameter feed: The RSS feed to check
    /// - Returns: Whether the feed should be refreshed now
    func shouldRefreshFeed(_ feed: RSSFeed) -> Bool {
        let normalizedURL = StorageManager.shared.normalizeLink(feed.url)
        let interval = getInterval(forFeed: normalizedURL)
        
        // Manual refresh means the feed is never automatically refreshed
        if interval == .manual {
            return false
        }
        
        // Get the last refresh time
        if let lastRefresh = lastRefreshDates[normalizedURL] {
            // Check if enough time has passed since last refresh
            let timeElapsed = Date().timeIntervalSince(lastRefresh)
            return timeElapsed >= interval.timeInterval
        }
        
        // If never refreshed before, refresh now
        return true
    }
    
    /// Record that a feed was just refreshed
    /// - Parameter feedURL: The URL of the feed that was refreshed
    func recordRefresh(forFeed feedURL: String) {
        let normalizedURL = StorageManager.shared.normalizeLink(feedURL)
        lastRefreshDates[normalizedURL] = Date()
        saveSettings()
    }
    
    /// Get the next scheduled refresh time for a feed
    /// - Parameter feed: The RSS feed to check
    /// - Returns: The date of the next scheduled refresh, or nil if on manual refresh
    func nextRefreshDate(for feed: RSSFeed) -> Date? {
        let normalizedURL = StorageManager.shared.normalizeLink(feed.url)
        let interval = getInterval(forFeed: normalizedURL)
        
        // Manual refresh means there's no scheduled refresh
        if interval == .manual {
            return nil
        }
        
        let lastRefresh = lastRefreshDates[normalizedURL] ?? Date()
        return lastRefresh.addingTimeInterval(interval.timeInterval)
    }
    
    /// Clear all custom intervals and reset to defaults
    func resetToDefaults() {
        globalInterval = defaultGlobalInterval
        useCustomIntervals = false
        feedIntervals.removeAll()
        saveSettings()
    }
}