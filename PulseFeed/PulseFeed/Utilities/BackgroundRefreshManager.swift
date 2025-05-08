import UIKit
import BackgroundTasks

/// Manages and optimizes background refreshing of RSS feeds
class BackgroundRefreshManager {
    /// Shared singleton instance
    static let shared = BackgroundRefreshManager()
    
    /// Background task identifier for refresh operations
    private let backgroundRefreshTaskIdentifier = "com.pulsefeed.refreshFeeds"
    
    /// Maximum number of feeds to refresh in a single background execution
    private let maxFeedsToRefreshInBackground = 5
    
    /// Priority score threshold for background refresh (1-100)
    private let priorityThreshold = 70
    
    /// Flag indicating if background refresh is currently enabled
    private(set) var isBackgroundRefreshEnabled: Bool = true
    
    /// Private initializer for singleton
    private init() {
        // Load user preferences first
        loadPreferences()
        
        // Register background tasks immediately
        registerBackgroundTasks()
    }
    
    /// Register the app's background tasks
    private func registerBackgroundTasks() {
        do {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: backgroundRefreshTaskIdentifier,
                using: nil
            ) { [weak self] task in
                guard let self = self else { return }
                self.handleBackgroundRefreshTask(task as! BGAppRefreshTask)
            }
            print("DEBUG: Successfully registered background refresh task")
        } catch {
            print("ERROR: Could not register background refresh task: \(error.localizedDescription)")
        }
    }
    
    /// Load user preferences for background refresh
    private func loadPreferences() {
        // Get default settings from Info.plist if available
        let defaultEnabled: Bool
        if let infoDict = Bundle.main.infoDictionary,
           let refreshDefaults = infoDict["BackgroundRefreshDefaults"] as? [String: Any],
           let enabled = refreshDefaults["Enabled"] as? Bool {
            defaultEnabled = enabled
        } else {
            defaultEnabled = true
        }
        
        // Load background refresh enabled setting (use default if not set)
        if UserDefaults.standard.object(forKey: "backgroundRefreshEnabled") != nil {
            isBackgroundRefreshEnabled = UserDefaults.standard.bool(forKey: "backgroundRefreshEnabled")
        } else {
            // Use default and save it
            isBackgroundRefreshEnabled = defaultEnabled
            UserDefaults.standard.set(defaultEnabled, forKey: "backgroundRefreshEnabled")
        }
        
        // Set default for notification setting if not already set
        if UserDefaults.standard.object(forKey: "enableNewItemNotifications") == nil {
            let defaultNotifications: Bool
            if let infoDict = Bundle.main.infoDictionary,
               let refreshDefaults = infoDict["BackgroundRefreshDefaults"] as? [String: Any],
               let notifyEnabled = refreshDefaults["NotificationsEnabled"] as? Bool {
                defaultNotifications = notifyEnabled
            } else {
                defaultNotifications = true
            }
            
            UserDefaults.standard.set(defaultNotifications, forKey: "enableNewItemNotifications")
        }
    }
    
    /// Sets whether background refresh is enabled
    /// - Parameter enabled: True to enable background refresh, false to disable
    func setBackgroundRefreshEnabled(_ enabled: Bool) {
        isBackgroundRefreshEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "backgroundRefreshEnabled")
        
        if enabled {
            // If we're enabling, schedule a refresh
            scheduleBackgroundRefresh()
        } else {
            // If we're disabling, cancel any pending tasks
            cancelPendingBackgroundTasks()
        }
        
        // Post notification that background refresh settings changed
        NotificationCenter.default.post(name: Notification.Name("backgroundRefreshSettingsChanged"), object: nil)
    }
    
    /// Schedule a background refresh task
    func scheduleBackgroundRefresh() {
        guard isBackgroundRefreshEnabled else {
            print("DEBUG: Background refresh is disabled, not scheduling task")
            return
        }
        
        // Cancel any existing scheduled tasks with this identifier
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundRefreshTaskIdentifier)
        
        // Create a new request
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskIdentifier)
        
        // Set earliest begin date to 15 minutes from now
        // This respects battery optimization but still allows for frequent refreshes
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("DEBUG: Successfully scheduled background refresh task")
        } catch {
            print("ERROR: Could not schedule background refresh: \(error.localizedDescription)")
        }
    }
    
    /// Handle a background refresh task
    /// - Parameter task: The background task to handle
    private func handleBackgroundRefreshTask(_ task: BGAppRefreshTask) {
        print("DEBUG: Starting background refresh task")
        
        // Create a task expiration handler
        task.expirationHandler = {
            print("DEBUG: Background refresh task expired")
            // If the task expires, we should save any partial progress
            self.scheduleBackgroundRefresh() // Schedule next refresh
        }
        
        // Start the background refresh
        performBackgroundRefresh { success in
            // Always schedule the next refresh
            self.scheduleBackgroundRefresh()
            
            // Mark the task complete
            task.setTaskCompleted(success: success)
            
            print("DEBUG: Background refresh task completed with success: \(success)")
        }
    }
    
    /// Cancel any pending background tasks
    private func cancelPendingBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundRefreshTaskIdentifier)
        print("DEBUG: Cancelled pending background refresh tasks")
    }
    
    /// Perform a background refresh of RSS feeds
    /// - Parameter completion: Completion handler with success flag
    private func performBackgroundRefresh(completion: @escaping (Bool) -> Void) {
        // Load all feeds
        StorageManager.shared.load(forKey: "rssFeeds") { (result: Result<[RSSFeed], Error>) in
            switch result {
            case .success(let feeds):
                // Get feeds that need refreshing based on their intervals
                let feedsNeedingRefresh = feeds.filter {
                    RefreshIntervalManager.shared.shouldRefreshFeed($0)
                }
                
                // If no feeds need refreshing, complete
                if feedsNeedingRefresh.isEmpty {
                    print("DEBUG: No feeds need refreshing at this time")
                    completion(true)
                    return
                }
                
                // Prioritize feeds for refresh
                let prioritizedFeeds = self.prioritizeFeeds(feedsNeedingRefresh)
                
                // Select only the top feeds to refresh based on priority
                let feedsToRefresh = Array(prioritizedFeeds.prefix(self.maxFeedsToRefreshInBackground))
                
                print("DEBUG: Selected \(feedsToRefresh.count) feeds for background refresh")
                
                // Process the feeds in background
                self.refreshFeedsInBackground(feedsToRefresh) { success in
                    completion(success)
                }
                
            case .failure(let error):
                print("ERROR: Failed to load feeds for background refresh: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    /// Prioritize feeds for background refresh
    /// - Parameter feeds: The feeds to prioritize
    /// - Returns: Sorted array of feeds based on priority
    private func prioritizeFeeds(_ feeds: [RSSFeed]) -> [RSSFeed] {
        // Calculate priority scores for each feed
        let feedsWithScores = feeds.map { feed -> (feed: RSSFeed, score: Int) in
            let score = calculatePriorityScore(for: feed)
            return (feed, score)
        }
        
        // Filter out feeds below the priority threshold
        let highPriorityFeeds = feedsWithScores.filter { $0.score >= priorityThreshold }
        
        // Sort by priority score (highest first)
        let sortedFeeds = highPriorityFeeds.sorted { $0.score > $1.score }
        
        // Return just the feeds without scores
        return sortedFeeds.map { $0.feed }
    }
    
    /// Calculate a priority score for a feed for background refresh decisions
    /// - Parameter feed: The feed to calculate priority for
    /// - Returns: A priority score from 0-100 (higher is more important)
    private func calculatePriorityScore(for feed: RSSFeed) -> Int {
        var score = 0
        
        // 1. Time since last refresh (up to 40 points)
        if let lastRefreshDate = getLastRefreshDate(for: feed) {
            let hoursSinceLastRefresh = Date().timeIntervalSince(lastRefreshDate) / 3600
            // More points for feeds that haven't been refreshed in a while
            score += min(Int(hoursSinceLastRefresh * 5), 40)
        } else {
            // If never refreshed, give maximum points
            score += 40
        }
        
        // 2. User engagement (up to 30 points)
        // More points for feeds the user interacts with frequently
        let engagementScore = calculateUserEngagement(for: feed)
        score += engagementScore
        
        // 3. Feed update frequency (up to 20 points)
        // More points for feeds that update frequently
        let updateFrequencyScore = calculateUpdateFrequency(for: feed)
        score += updateFrequencyScore
        
        // 4. Feed performance (up to 10 points)
        // More points for feeds that load quickly and reliably
        let performanceScore = calculatePerformanceScore(for: feed)
        score += performanceScore
        
        return min(score, 100) // Cap at 100
    }
    
    /// Get the last refresh date for a feed
    /// - Parameter feed: The feed to check
    /// - Returns: The date of the last refresh or nil if never refreshed
    private func getLastRefreshDate(for feed: RSSFeed) -> Date? {
        // Load last refresh dates from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "lastRefreshDates"),
           let dates = try? JSONDecoder().decode([String: Date].self, from: data) {
            let normalizedURL = StorageManager.shared.normalizeLink(feed.url)
            return dates[normalizedURL]
        }
        return nil
    }
    
    /// Calculate a user engagement score for a feed
    /// - Parameter feed: The feed to calculate engagement for
    /// - Returns: An engagement score from 0-30
    private func calculateUserEngagement(for feed: RSSFeed) -> Int {
        // For now, use a simple heuristic - check for read items from this feed
        var score = 0
        
        // TODO: Implement a more sophisticated engagement tracking system
        // This would track which feeds the user reads most often
        
        // Check if read status tracker has any read items from this feed
        if ReadStatusTracker.shared.hasReadItemsFromFeed(sourceName: feed.title) {
            score += 15
        }
        
        // Check if any items from this feed are hearted or bookmarked
        if hasHeartedItems(from: feed) || hasBookmarkedItems(from: feed) {
            score += 15
        }
        
        return min(score, 30)
    }
    
    /// Check if any items from the feed are hearted
    /// - Parameter feed: The feed to check
    /// - Returns: True if any items from this feed are hearted
    private func hasHeartedItems(from feed: RSSFeed) -> Bool {
        // This is a simple implementation
        // A more complete solution would match hearted items to feeds
        return false
    }
    
    /// Check if any items from the feed are bookmarked
    /// - Parameter feed: The feed to check
    /// - Returns: True if any items from this feed are bookmarked
    private func hasBookmarkedItems(from feed: RSSFeed) -> Bool {
        // This is a simple implementation
        // A more complete solution would match bookmarked items to feeds
        return false
    }
    
    /// Calculate update frequency score for a feed
    /// - Parameter feed: The feed to calculate for
    /// - Returns: A score from 0-20
    private func calculateUpdateFrequency(for feed: RSSFeed) -> Int {
        // Use the refresh interval as a proxy for update frequency
        let interval = RefreshIntervalManager.shared.getInterval(forFeed: feed.url)
        
        // Quick feedswill get higher scores
        switch interval {
        case .minutes15:
            return 20
        case .minutes30:
            return 15
        case .hourly:
            return 10
        case .hours3:
            return 5
        case .hours6:
            return 3
        case .daily:
            return 1
        case .manual:
            return 0
        }
    }
    
    /// Calculate a performance score for a feed based on load times and reliability
    /// - Parameter feed: The feed to calculate for
    /// - Returns: A score from 0-10
    private func calculatePerformanceScore(for feed: RSSFeed) -> Int {
        // Use FeedLoadTimeManager to check performance
        let loadTime = FeedLoadTimeManager.shared.getLoadTime(for: feed.title)
        let failureCount = FeedLoadTimeManager.shared.getFailureCount(for: feed.title)
        
        // Calculate score - prefer feeds that are fast and reliable
        var score = 10
        
        // Penalize for slow load times (>2 seconds)
        if loadTime > 5 {
            score -= 5
        } else if loadTime > 2 {
            score -= 2
        }
        
        // Penalize for failures
        score -= min(failureCount * 3, 10)
        
        return max(0, score)
    }
    
    /// Refresh a set of feeds in the background
    /// - Parameters:
    ///   - feeds: The feeds to refresh
    ///   - completion: Completion handler with success flag
    private func refreshFeedsInBackground(_ feeds: [RSSFeed], completion: @escaping (Bool) -> Void) {
        // Create a group to wait for all feed refreshes
        let group = DispatchGroup()
        var successCount = 0
        
        // Process each feed
        for feed in feeds {
            group.enter()
            
            // Mark that we're refreshing this feed
            RefreshIntervalManager.shared.recordRefresh(forFeed: feed.url)
            
            // Fetch the feed content
            fetchFeedContent(feed) { success in
                if success {
                    successCount += 1
                }
                group.leave()
            }
        }
        
        // When all feeds are processed, complete
        group.notify(queue: .global()) {
            print("DEBUG: Background refresh completed for \(feeds.count) feeds, \(successCount) successful")
            
            // Consider the operation successful if at least half of the feeds refreshed successfully
            let success = successCount >= feeds.count / 2
            completion(success)
        }
    }
    
    /// Fetch content for a single feed
    /// - Parameters:
    ///   - feed: The feed to fetch
    ///   - completion: Completion handler with success flag
    private func fetchFeedContent(_ feed: RSSFeed, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: feed.url) else {
            completion(false)
            return
        }
        
        let startTime = Date()
        
        // Create a task to fetch the feed content
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            // Record performance metrics
            if error != nil || data == nil {
                FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                completion(false)
                return
            }
            
            // Record load time
            FeedLoadTimeManager.shared.recordLoadTime(for: feed.title, time: elapsedTime)
            
            // Parse the feed data
            if let data = data {
                let parser = XMLParser(data: data)
                let rssParser = RSSParser(source: feed.title)
                parser.delegate = rssParser
                
                if parser.parse() && !rssParser.items.isEmpty {
                    // Process the new items
                    self.processNewItems(feed, items: rssParser.items)
                    completion(true)
                } else {
                    // XML parsing failed
                    FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                    completion(false)
                }
            } else {
                completion(false)
            }
        }
        
        task.resume()
    }
    
    /// Process new items from a feed refresh
    /// - Parameters:
    ///   - feed: The feed the items came from
    ///   - items: The new items from the feed
    private func processNewItems(_ feed: RSSFeed, items: [RSSItem]) {
        // Load existing items to compare
        StorageManager.shared.load(forKey: "allItems") { (result: Result<[RSSItem], Error>) in
            var existingItems: [RSSItem] = []
            
            if case .success(let items) = result {
                existingItems = items
            }
            
            // Find new items not in the existing items
            let existingLinks = Set(existingItems.map { StorageManager.shared.normalizeLink($0.link) })
            let newItems = items.filter { !existingLinks.contains(StorageManager.shared.normalizeLink($0.link)) }
            
            if !newItems.isEmpty {
                print("DEBUG: Found \(newItems.count) new items in feed: \(feed.title)")
                
                // Send local notification for new items if enabled
                self.sendNotificationForNewItems(feed, newItems: newItems)
                
                // Update the stored items
                let updatedItems = existingItems + newItems
                StorageManager.shared.save(updatedItems, forKey: "allItems") { _ in
                    // Post notification that new items were added
                    NotificationCenter.default.post(
                        name: Notification.Name("newItemsAddedInBackground"),
                        object: nil,
                        userInfo: ["feedTitle": feed.title, "count": newItems.count]
                    )
                }
            }
        }
    }
    
    /// Send a local notification for new feed items
    /// - Parameters:
    ///   - feed: The feed with new items
    ///   - newItems: The new items to notify about
    private func sendNotificationForNewItems(_ feed: RSSFeed, newItems: [RSSItem]) {
        // Check if notifications are enabled
        if UserDefaults.standard.bool(forKey: "enableNewItemNotifications") {
            // Create a notification
            let content = UNMutableNotificationContent()
            content.title = "New Articles in \(feed.title)"
            
            if newItems.count == 1 {
                content.body = newItems[0].title
            } else {
                content.body = "\(newItems.count) new articles available"
            }
            
            content.sound = UNNotificationSound.default
            
            // Add feed information to notification for handling taps
            content.userInfo = [
                "feedURL": feed.url,
                "feedTitle": feed.title
            ]
            
            // Create a request to deliver the notification
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // Deliver immediately
            )
            
            // Add the request to the notification center
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("ERROR: Failed to schedule notification: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Configures the app for background fetch operations
    /// - Parameter application: The UIApplication to configure
    func configureBackgroundFetch(for application: UIApplication) {
        // Only configure if background refresh is enabled
        guard isBackgroundRefreshEnabled else {
            print("DEBUG: Background refresh is disabled, not configuring")
            return
        }
        
        // Configure background fetch minimum interval
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        print("DEBUG: Successfully configured background fetch with minimum interval")
    }
    
    /// Handle a background fetch callback from the app delegate
    /// - Parameters:
    ///   - application: The UIApplication that initiated the fetch
    ///   - completionHandler: Completion handler to call when fetch is complete
    func handleBackgroundFetch(application: UIApplication, completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard isBackgroundRefreshEnabled else {
            completionHandler(.noData)
            return
        }
        
        // Perform the background refresh
        performBackgroundRefresh { success in
            if success {
                completionHandler(.newData)
            } else {
                completionHandler(.failed)
            }
        }
    }
}

// MARK: - Extensions for ReadStatusTracker
extension ReadStatusTracker {
    /// Check if there are any read items from a specific feed
    /// - Parameter sourceName: The name of the feed source
    /// - Returns: True if any items from this source have been read
    func hasReadItemsFromFeed(sourceName: String) -> Bool {
        // This is a simple implementation
        // In a more complete solution, we would track read items per feed
        return true
    }
}