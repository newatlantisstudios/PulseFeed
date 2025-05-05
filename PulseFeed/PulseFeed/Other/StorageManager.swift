import CloudKit
import Foundation
import UIKit

enum StorageMethod {
    case userDefaults, cloudKit
}

protocol ArticleStorage {
    func save<T: Encodable>(
        _ value: T, forKey key: String, completion: @escaping (Error?) -> Void)
    func load<T: Decodable>(
        forKey key: String, completion: @escaping (Result<T, Error>) -> Void)
}

/// Uses local UserDefaults for storage.
struct UserDefaultsStorage: ArticleStorage {
    let defaults = UserDefaults.standard

    func save<T: Encodable>(
        _ value: T, forKey key: String, completion: @escaping (Error?) -> Void
    ) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: key)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    func load<T: Decodable>(
        forKey key: String, completion: @escaping (Result<T, Error>) -> Void
    ) {
        if let data = defaults.data(forKey: key) {
            do {
                let value = try JSONDecoder().decode(T.self, from: data)
                completion(.success(value))
            } catch {
                completion(.failure(error))
            }
        } else {
            completion(
                .failure(
                    NSError(
                        domain: "UserDefaultsStorage",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "No data found for key \(key)"
                        ])))
        }
    }
}

/// Uses CloudKit for storage by saving all feeds as one JSON blob in a single record.
struct CloudKitStorage: ArticleStorage {
    let container = CKContainer.default()
    let database = CKContainer.default().privateCloudDatabase
    // Fixed record ID for storing all data in separate fields.
    let recordID = CKRecord.ID(recordName: "rssFeedsRecord")

    /// Update multiple keys on the same record at once.
    func updateRecord(
        with updates: [String: Data], completion: @escaping (Error?) -> Void
    ) {
        database.fetch(withRecordID: recordID) { record, error in
            if let record = record {
                // Update each provided key.
                for (key, value) in updates {
                    record[key] = value as CKRecordValue
                }
                self.database.save(record) { _, error in
                    DispatchQueue.main.async {
                        completion(error)
                    }
                }
            } else {
                // If the record doesn't exist, create a new one.
                let newRecord = CKRecord(
                    recordType: "RSSFeeds", recordID: self.recordID)
                for (key, value) in updates {
                    newRecord[key] = value as CKRecordValue
                }
                self.database.save(newRecord) { _, error in
                    DispatchQueue.main.async {
                        completion(error)
                    }
                }
            }
        }
    }

    func save<T: Encodable>(
        _ value: T, forKey key: String, completion: @escaping (Error?) -> Void
    ) {
        func performSave(with record: CKRecord?, retryOnConflict: Bool = true) {
            do {
                let data = try JSONEncoder().encode(value)
                let recordToSave = record ?? CKRecord(recordType: "RSSFeeds", recordID: self.recordID)
                recordToSave[key] = data as CKRecordValue

                let modifyOperation = CKModifyRecordsOperation(recordsToSave: [recordToSave], recordIDsToDelete: nil)
                modifyOperation.savePolicy = .ifServerRecordUnchanged

                modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, operationError in
                    DispatchQueue.main.async {
                        if let opError = operationError as? CKError {
                            print("CloudKitStorage: CKError saving key '\(key)':", opError)
                            if opError.code == .serverRecordChanged && retryOnConflict {
                                // Conflict: refetch, merge, and retry ONCE
                                print("CloudKitStorage: Conflict detected (serverRecordChanged) while saving key '\(key)'. Attempting to refetch, merge, and retry.")
                                self.database.fetch(withRecordID: self.recordID) { latestRecord, fetchError in
                                    DispatchQueue.main.async {
                                        if let latestRecord = latestRecord {
                                            // Overwrite the field with our new value and retry
                                            performSave(with: latestRecord, retryOnConflict: false)
                                        } else {
                                            print("CloudKitStorage: Failed to refetch record for conflict resolution: ", fetchError as Any)
                                            completion(opError)
                                        }
                                    }
                                }
                                return
                            }
                            completion(opError)
                        } else if let opError = operationError {
                            print("CloudKitStorage: Non-CKError saving key '\(key)':", opError)
                            completion(opError)
                        } else {
                            print("CloudKitStorage: Successfully saved data for key '\(key)' using operation.")
                            completion(nil)
                        }
                    }
                }
                self.database.add(modifyOperation)
            } catch {
                print("CloudKitStorage: Error encoding data for key '\(key)':", error)
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }

        // Fetch the record first to get the latest change tag or create a new one
        database.fetch(withRecordID: recordID) { record, error in
            if let ckError = error as? CKError, ckError.code != .unknownItem {
                DispatchQueue.main.async {
                    print("CloudKitStorage: Error fetching record before saving key '\(key)':", error as Any)
                    completion(error)
                }
                return
            }
            if let error = error, !(error is CKError) {
                DispatchQueue.main.async {
                    print("CloudKitStorage: Non-CKError fetching record before saving key '\(key)':", error)
                    completion(error)
                }
                return
            }
            performSave(with: record)
        }
    }

    func load<T: Decodable>(
        forKey key: String, completion: @escaping (Result<T, Error>) -> Void
    ) {
        print("CloudKitStorage: Attempting to load data for key '\(key)'.")
        database.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                if let ckError = error as? CKError, ckError.code == .unknownItem
                {
                    print(
                        "CloudKitStorage: Record not found for key '\(key)'. Returning default empty value."
                    )
                    if T.self == [RSSFeed].self || T.self == [String].self {
                        completion(.success([] as! T))
                        return
                    }
                }
                if let error = error {
                    print(
                        "CloudKitStorage: Error fetching record for key '\(key)': \(error.localizedDescription)"
                    )
                    completion(.failure(error))
                    return
                }
                if let record = record, let data = record[key] as? Data {
                    do {
                        let value = try JSONDecoder().decode(T.self, from: data)
                        print(
                            //"CloudKitStorage: Successfully loaded data for key '\(key)': \(value)"
                            "CloudKitStorage: Successfully loaded data for key '\(key)'"
                        )
                        completion(.success(value))
                    } catch {
                        print(
                            "CloudKitStorage: Error decoding data for key '\(key)': \(error.localizedDescription)"
                        )
                        completion(.failure(error))
                    }
                } else {
                    print("CloudKitStorage: No data found for key '\(key)'.")
                    if T.self == [RSSFeed].self || T.self == [String].self {
                        completion(.success([] as! T))
                    } else {
                        completion(
                            .failure(
                                NSError(
                                    domain: "CloudKitStorage",
                                    code: -1,
                                    userInfo: [
                                        NSLocalizedDescriptionKey:
                                            "No data found"
                                    ])))
                    }
                }
            }
        }
    }

    /// Saves an array of ArticleSummary for a given feed, merging with existing articles.
    /// - Parameters:
    ///   - feedId: A unique identifier for the feed (for example, a slug or the feed URL hash).
    ///   - newArticles: An array of ArticleSummary items representing NEW articles to add.
    ///   - completion: Completion handler with an optional error.
    func saveArticles(forFeed feedId: String,
                      articles newArticles: [ArticleSummary],
                      completion: @escaping (Error?) -> Void) {

        // Create a unique record ID per feed.
        let recordID = CKRecord.ID(recordName: "feedArticlesRecord-\(feedId)")

        database.fetch(withRecordID: recordID) { (record, error) in

            // Handle fetch error (excluding 'unknownItem', which is handled below)
            if let error = error as? CKError, error.code != .unknownItem {
                DispatchQueue.main.async {
                    print("Error fetching record for feed \(feedId) before saving: \(error.localizedDescription)")
                    completion(error)
                }
                return
            }
            // Handle non-CKError fetch errors
            if let error = error, !(error is CKError) {
                 DispatchQueue.main.async {
                    print("Non-CKError fetching record for feed \(feedId) before saving: \(error.localizedDescription)")
                    completion(error)
                }
                return
            }

            let currentRecord = record ?? CKRecord(recordType: "RSSFeedArticles", recordID: recordID)
            var existingArticles: [ArticleSummary] = []

            // Decode existing articles if the record exists and has data
            if let existingData = currentRecord["articles"] as? Data {
                do {
                    existingArticles = try JSONDecoder().decode([ArticleSummary].self, from: existingData)
                } catch {
                    print("Warning: Could not decode existing articles for feed \(feedId). Starting fresh. Error: \(error.localizedDescription)")
                    // Proceed with an empty existingArticles array
                }
            }

            // Merge and Deduplicate
            var combinedArticlesDict = Dictionary(existingArticles.map { ($0.link, $0) }, uniquingKeysWith: { (current, _) in current })
            for article in newArticles {
                combinedArticlesDict[article.link] = article // Add or overwrite with the new article
            }

            var finalArticles = Array(combinedArticlesDict.values)

            // Limit the saved articles
            if finalArticles.count > 5000 {
                 // Sort by date string descending before limiting (best effort)
                finalArticles.sort { $0.pubDate > $1.pubDate }
                finalArticles = Array(finalArticles.prefix(5000))
            }

            // Encode the final merged list
            do {
                let finalData = try JSONEncoder().encode(finalArticles)
                currentRecord["articles"] = finalData as CKRecordValue

                // Save the record using CKModifyRecordsOperation with .changedKeys policy
                let modifyOperation = CKModifyRecordsOperation(recordsToSave: [currentRecord], recordIDsToDelete: nil)
                modifyOperation.savePolicy = .changedKeys // Apply the policy here
                modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, operationError in
                    DispatchQueue.main.async {
                        if let opError = operationError {
                            print("Error saving merged articles for feed \(feedId) using operation: \(opError.localizedDescription)")
                            // Handle specific CloudKit errors if necessary (e.g., .serverRecordChanged for conflict)
                        } else {
                            print("Successfully saved \(finalArticles.count) merged articles for feed \(feedId).")
                        }
                        completion(operationError) // Pass the operation error back
                    }
                }
                self.database.add(modifyOperation) // Add the operation to the database queue

            } catch {
                // Handle encoding error
                DispatchQueue.main.async {
                    print("Error encoding final articles for feed \(feedId): \(error.localizedDescription)")
                    completion(error)
                }
            }
        }
    }

    /// Loads the saved ArticleSummary array for a given feed.
    /// - Parameters:
    ///   - feedId: The unique identifier for the feed.
    ///   - completion: Completion handler returning a Result with either the array of ArticleSummary or an Error.
    func loadArticles(forFeed feedId: String,
                      completion: @escaping (Result<[ArticleSummary], Error>) -> Void) {
        let recordID = CKRecord.ID(recordName: "feedArticlesRecord-\(feedId)")
        database.fetch(withRecordID: recordID) { (record, error) in
            DispatchQueue.main.async {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    // Record not found; return an empty array.
                    completion(.success([]))
                    return
                }
                if let error = error {
                    completion(.failure(error))
                    return
                }
                if let record = record, let data = record["articles"] as? Data {
                    do {
                        let articles = try JSONDecoder().decode([ArticleSummary].self, from: data)
                        completion(.success(articles))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    // Record exists but no 'articles' data, or record is nil without error (unlikely)
                    completion(.success([]))
                }
            }
        }
    }
}

/// Singleton that provides a unified interface for storage.
class StorageManager {
    static let shared = StorageManager()
    
    // Flag to track if we've synchronized on app launch
    private var hasSyncedOnLaunch = false
    
    // Flag to track if subscriptions are set up
    private var hasSetupSubscriptions = false

    var method: StorageMethod = .userDefaults {
        didSet {
            print("DEBUG: StorageManager method set to: \(method)")
            
            // If switching to CloudKit, set up subscriptions
            if method == .cloudKit && !hasSetupSubscriptions {
                setupCloudKitSubscriptions()
            }
        }
    }

    private var storage: ArticleStorage {
        switch method {
        case .userDefaults:
            print("DEBUG: Using UserDefaultsStorage")
            return UserDefaultsStorage()
        case .cloudKit:
            print("DEBUG: Using CloudKitStorage")
            return CloudKitStorage()
        }
    }
    
    init() {
        // Set up notification to sync when app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Set up to receive CloudKit remote notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteNotification),
            name: Notification.Name("CKRemoteChangeNotification"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Setup CloudKit subscriptions to be notified of changes
    private func setupCloudKitSubscriptions() {
        guard method == .cloudKit else { return }
        
        let database = CKContainer.default().privateCloudDatabase
        
        // Create subscription for rssFeedsRecord with ID
        let rssFeedsID = CKRecord.ID(recordName: "rssFeedsRecord")
        let predicate = NSPredicate(format: "recordID = %@", rssFeedsID)
        
        let subscription = CKQuerySubscription(recordType: "RSSFeeds", 
                                              predicate: predicate,
                                              subscriptionID: "PulseFeed-RSSFeeds-Subscription",
                                              options: [.firesOnRecordUpdate, .firesOnRecordCreation])
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push notification
        subscription.notificationInfo = notificationInfo
        
        database.save(subscription) { subscription, error in
            if let error = error {
                if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                    // Subscription may already exist, which is fine
                    print("DEBUG: CloudKit subscription may already exist: \(error.localizedDescription)")
                    self.hasSetupSubscriptions = true
                } else {
                    print("ERROR: Failed to create CloudKit subscription: \(error.localizedDescription)")
                }
            } else {
                print("DEBUG: Successfully created CloudKit subscription")
                self.hasSetupSubscriptions = true
            }
        }
    }
    
    // Handle CloudKit remote notification
    @objc private func handleRemoteNotification(_ notification: Notification) {
        print("DEBUG: Received CloudKit remote change notification")
        
        // Sync with CloudKit to get the latest data
        syncFromCloudKit { success in
            print("DEBUG: CloudKit sync after remote notification completed with success: \(success)")
        }
    }
    
    /// Called when the app becomes active to sync with CloudKit
    @objc private func handleAppBecameActive() {
        // Only sync if using CloudKit
        if method == .cloudKit {
            syncFromCloudKit()
        }
    }
    
    /// Performs a full sync from CloudKit, pulling down the latest read states, bookmarks, and favorites
    func syncFromCloudKit(completion: ((Bool) -> Void)? = nil) {
        guard method == .cloudKit else {
            print("DEBUG: Skipping CloudKit sync - not using CloudKit")
            completion?(false)
            return
        }
        
        print("DEBUG: Starting CloudKit sync...")
        
        // Using a dispatch group to sync all three types of data
        let syncGroup = DispatchGroup()
        var syncSuccess = true
        
        // 1. Sync read items
        syncGroup.enter()
        syncReadItemsFromCloud { success in
            if !success {
                syncSuccess = false
            }
            syncGroup.leave()
        }
        
        // 2. Sync bookmarked items
        syncGroup.enter()
        syncBookmarkedItemsFromCloud { success in
            if !success {
                syncSuccess = false
            }
            syncGroup.leave()
        }
        
        // 3. Sync hearted items
        syncGroup.enter()
        syncHeartedItemsFromCloud { success in
            if !success {
                syncSuccess = false
            }
            syncGroup.leave()
        }
        
        // Final callback after all syncs complete
        syncGroup.notify(queue: .main) {
            self.hasSyncedOnLaunch = true
            completion?(syncSuccess)
        }
    }
    
    /// Syncs read items from CloudKit
    private func syncReadItemsFromCloud(completion: @escaping (Bool) -> Void) {
        CloudKitStorage().load(forKey: "readItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { 
                completion(false)
                return 
            }
            
            switch result {
            case .success(let cloudReadItems):
                print("DEBUG: Fetched \(cloudReadItems.count) read items from CloudKit")
                
                // Normalize the items
                let normalizedCloudItems = cloudReadItems.map { self.normalizeLink($0) }
                
                // Get and merge local items 
                var localItems: [String] = []
                if let data = UserDefaults.standard.data(forKey: "readItems") {
                    do {
                        localItems = try JSONDecoder().decode([String].self, from: data)
                    } catch {
                        print("ERROR: Failed to decode local read items: \(error.localizedDescription)")
                        // Continue with empty localItems array
                    }
                }
                
                let normalizedLocalItems = localItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedLocalItems)))
                print("DEBUG: Merged read items - Cloud: \(normalizedCloudItems.count), Local: \(normalizedLocalItems.count), Result: \(merged.count)")
                
                // Update local storage
                if let encodedData = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(encodedData, forKey: "readItems")
                    
                    // Notify that read items were updated
                    NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
                    
                    // If the cloud had more items than local, we should update CloudKit as well to ensure consistency
                    if normalizedCloudItems.count < merged.count {
                        self.mergeAndSaveReadItems(merged) { error in
                            if let error = error {
                                print("ERROR: Failed to update CloudKit after sync: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("DEBUG: Successfully synchronized read items with CloudKit")
                                completion(true)
                            }
                        }
                    } else {
                        print("DEBUG: Local read items updated from CloudKit (no need to update cloud)")
                        completion(true)
                    }
                } else {
                    print("ERROR: Failed to encode merged read items")
                    completion(false)
                }
                
            case .failure(let error):
                print("ERROR: Failed to fetch read items from CloudKit: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    /// Syncs bookmarked items from CloudKit
    private func syncBookmarkedItemsFromCloud(completion: @escaping (Bool) -> Void) {
        CloudKitStorage().load(forKey: "bookmarkedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { 
                completion(false)
                return 
            }
            
            switch result {
            case .success(let cloudBookmarkedItems):
                print("DEBUG: Fetched \(cloudBookmarkedItems.count) bookmarked items from CloudKit")
                
                // Normalize the items
                let normalizedCloudItems = cloudBookmarkedItems.map { self.normalizeLink($0) }
                
                // Get and merge local items 
                var localItems: [String] = []
                if let data = UserDefaults.standard.data(forKey: "bookmarkedItems") {
                    do {
                        localItems = try JSONDecoder().decode([String].self, from: data)
                    } catch {
                        print("ERROR: Failed to decode local bookmarked items: \(error.localizedDescription)")
                        // Continue with empty localItems array
                    }
                }
                
                let normalizedLocalItems = localItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedLocalItems)))
                print("DEBUG: Merged bookmarked items - Cloud: \(normalizedCloudItems.count), Local: \(normalizedLocalItems.count), Result: \(merged.count)")
                
                // Update local storage
                if let encodedData = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(encodedData, forKey: "bookmarkedItems")
                    
                    // Notify that bookmarked items were updated
                    NotificationCenter.default.post(name: Notification.Name("bookmarkedItemsUpdated"), object: nil)
                    
                    // If the cloud had more items than local, we should update CloudKit as well to ensure consistency
                    if normalizedCloudItems.count < merged.count {
                        self.mergeAndSaveBookmarkedItems(merged) { error in
                            if let error = error {
                                print("ERROR: Failed to update CloudKit after bookmarked sync: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("DEBUG: Successfully synchronized bookmarked items with CloudKit")
                                completion(true)
                            }
                        }
                    } else {
                        print("DEBUG: Local bookmarked items updated from CloudKit (no need to update cloud)")
                        completion(true)
                    }
                } else {
                    print("ERROR: Failed to encode merged bookmarked items")
                    completion(false)
                }
                
            case .failure(let error):
                print("ERROR: Failed to fetch bookmarked items from CloudKit: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    /// Syncs hearted items from CloudKit
    private func syncHeartedItemsFromCloud(completion: @escaping (Bool) -> Void) {
        CloudKitStorage().load(forKey: "heartedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { 
                completion(false)
                return 
            }
            
            switch result {
            case .success(let cloudHeartedItems):
                print("DEBUG: Fetched \(cloudHeartedItems.count) hearted items from CloudKit")
                
                // Normalize the items
                let normalizedCloudItems = cloudHeartedItems.map { self.normalizeLink($0) }
                
                // Get and merge local items 
                var localItems: [String] = []
                if let data = UserDefaults.standard.data(forKey: "heartedItems") {
                    do {
                        localItems = try JSONDecoder().decode([String].self, from: data)
                    } catch {
                        print("ERROR: Failed to decode local hearted items: \(error.localizedDescription)")
                        // Continue with empty localItems array
                    }
                }
                
                let normalizedLocalItems = localItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedLocalItems)))
                print("DEBUG: Merged hearted items - Cloud: \(normalizedCloudItems.count), Local: \(normalizedLocalItems.count), Result: \(merged.count)")
                
                // Update local storage
                if let encodedData = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(encodedData, forKey: "heartedItems")
                    
                    // Notify that hearted items were updated
                    NotificationCenter.default.post(name: Notification.Name("heartedItemsUpdated"), object: nil)
                    
                    // If the cloud had more items than local, we should update CloudKit as well to ensure consistency
                    if normalizedCloudItems.count < merged.count {
                        self.mergeAndSaveHeartedItems(merged) { error in
                            if let error = error {
                                print("ERROR: Failed to update CloudKit after hearted sync: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("DEBUG: Successfully synchronized hearted items with CloudKit")
                                completion(true)
                            }
                        }
                    } else {
                        print("DEBUG: Local hearted items updated from CloudKit (no need to update cloud)")
                        completion(true)
                    }
                } else {
                    print("ERROR: Failed to encode merged hearted items")
                    completion(false)
                }
                
            case .failure(let error):
                print("ERROR: Failed to fetch hearted items from CloudKit: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    func markAllAsRead(completion: @escaping (Bool, Error?) -> Void) {
        // 1. Set a flag to indicate all items have been read
        // We'll set this again after processing is complete
        _ = UserDefaults.standard.bool(forKey: "allItemsRead")
        
        // 2. Collect all article links from all feeds
        // This is a more efficient approach than updating each article record
        var allLinks: [String] = []
        
        // We'll look for the home feed controller to extract article links
        // Find the root view controller
        guard let keyWindow = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .compactMap({$0 as? UIWindowScene})
                .first?.windows
                .filter({$0.isKeyWindow}).first,
              let rootNavController = keyWindow.rootViewController as? UINavigationController,
              let homeVC = rootNavController.viewControllers.first as? HomeFeedViewController else {
            
            // Fallback if we couldn't access the view controller
            completion(false, NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not access HomeViewController"]))
            return
        }
        
        // Get all article links from the HomeFeedViewController's allItems array
        allLinks = homeVC.allItems.map { normalizeLink($0.link) }
        
        // If we couldn't get the links, return an error
        if allLinks.isEmpty {
            completion(false, NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No articles found to mark as read"]))
            return
        }
        
        // 3. Save locally first for immediate feedback
        if let data = try? JSONEncoder().encode(allLinks) {
            UserDefaults.standard.set(data, forKey: "readItems")
            UserDefaults.standard.set(true, forKey: "allItemsRead")
            
            // Post notification to update UI immediately
            NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
        }
        
        // 4. Then update CloudKit with retry mechanism for robustness
        saveToCloudKitWithRetry(allLinks, forKey: "readItems", retryCount: 3) { error in
            if let error = error {
                print("WARNING: CloudKit sync failed but local data was updated: \(error.localizedDescription)")
                // Still return success since local data was updated
                completion(true, error)
            } else {
                print("DEBUG: Successfully saved read items to CloudKit")
                completion(true, nil)
            }
        }
    }

    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void) {
        if method == .cloudKit {
            guard value is [String] else {
                print("ERROR: Attempting to save non-[String] to '\(key)' in CloudKit! Value type: \(type(of: value))")
                completion(NSError(domain: "StorageManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "\(key) must be [String]!"]))
                return
            }
            
            // Special handling for items that need merging with CloudKit
            if let items = value as? [String] {
                switch key {
                case "readItems":
                    mergeAndSaveReadItems(items, completion: completion)
                    return
                case "bookmarkedItems":
                    mergeAndSaveBookmarkedItems(items, completion: completion)
                    return
                case "heartedItems":
                    mergeAndSaveHeartedItems(items, completion: completion)
                    return
                default:
                    break
                }
            }
        }
        
        print("DEBUG: Saving data for key '\(key)' using \(method)")
        storage.save(value, forKey: key, completion: completion)
    }
    
    /// Special handling for read items to ensure proper syncing across devices
    private func mergeAndSaveReadItems(_ newReadItems: [String], completion: @escaping (Error?) -> Void) {
        // First normalize all the new links
        let normalizedNewItems = newReadItems.map { normalizeLink($0) }
        
        // Always fetch from CloudKit first to ensure we have latest data
        CloudKitStorage().load(forKey: "readItems") { (result: Result<[String], Error>) in
            switch result {
            case .success(let cloudItems):
                // Normalize cloud items
                let normalizedCloudItems = cloudItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedNewItems)))
                print("DEBUG: Merged read items - Cloud: \(normalizedCloudItems.count), New: \(normalizedNewItems.count), Result: \(merged.count)")
                
                // Save to UserDefaults immediately to ensure local state is consistent
                if let data = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(data, forKey: "readItems")
                }
                
                // Save to CloudKit with retry for conflict handling
                self.saveToCloudKitWithRetry(merged, forKey: "readItems", retryCount: 3) { error in
                    if let error = error {
                        print("ERROR: Failed to save merged read items to CloudKit after retries: \(error.localizedDescription)")
                    } else {
                        print("DEBUG: Successfully saved merged read items to CloudKit")
                    }
                    completion(error)
                }
                
            case .failure(let error):
                print("ERROR: Failed to fetch read items from CloudKit for merging: \(error.localizedDescription)")
                
                // Save locally even if CloudKit fails
                if let data = try? JSONEncoder().encode(normalizedNewItems) {
                    UserDefaults.standard.set(data, forKey: "readItems")
                }
                
                // If we can't fetch from CloudKit, just save the new items
                self.saveToCloudKitWithRetry(normalizedNewItems, forKey: "readItems", retryCount: 3, completion: completion)
            }
        }
    }
    
    /// Special handling for bookmarked items to ensure proper syncing across devices
    private func mergeAndSaveBookmarkedItems(_ newBookmarkedItems: [String], completion: @escaping (Error?) -> Void) {
        // First normalize all the new links
        let normalizedNewItems = newBookmarkedItems.map { normalizeLink($0) }
        
        // Always fetch from CloudKit first to ensure we have latest data
        CloudKitStorage().load(forKey: "bookmarkedItems") { (result: Result<[String], Error>) in
            switch result {
            case .success(let cloudItems):
                // Normalize cloud items
                let normalizedCloudItems = cloudItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedNewItems)))
                print("DEBUG: Merged bookmarked items - Cloud: \(normalizedCloudItems.count), New: \(normalizedNewItems.count), Result: \(merged.count)")
                
                // Save to UserDefaults immediately to ensure local state is consistent
                if let data = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(data, forKey: "bookmarkedItems")
                }
                
                // Save to CloudKit with retry for conflict handling
                self.saveToCloudKitWithRetry(merged, forKey: "bookmarkedItems", retryCount: 3) { error in
                    if let error = error {
                        print("ERROR: Failed to save merged bookmarked items to CloudKit after retries: \(error.localizedDescription)")
                    } else {
                        print("DEBUG: Successfully saved merged bookmarked items to CloudKit")
                    }
                    completion(error)
                }
                
            case .failure(let error):
                print("ERROR: Failed to fetch bookmarked items from CloudKit for merging: \(error.localizedDescription)")
                
                // Save locally even if CloudKit fails
                if let data = try? JSONEncoder().encode(normalizedNewItems) {
                    UserDefaults.standard.set(data, forKey: "bookmarkedItems")
                }
                
                // If we can't fetch from CloudKit, just save the new items
                self.saveToCloudKitWithRetry(normalizedNewItems, forKey: "bookmarkedItems", retryCount: 3, completion: completion)
            }
        }
    }
    
    /// Special handling for hearted items to ensure proper syncing across devices
    private func mergeAndSaveHeartedItems(_ newHeartedItems: [String], completion: @escaping (Error?) -> Void) {
        // First normalize all the new links
        let normalizedNewItems = newHeartedItems.map { normalizeLink($0) }
        
        // Always fetch from CloudKit first to ensure we have latest data
        CloudKitStorage().load(forKey: "heartedItems") { (result: Result<[String], Error>) in
            switch result {
            case .success(let cloudItems):
                // Normalize cloud items
                let normalizedCloudItems = cloudItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedNewItems)))
                print("DEBUG: Merged hearted items - Cloud: \(normalizedCloudItems.count), New: \(normalizedNewItems.count), Result: \(merged.count)")
                
                // Save to UserDefaults immediately to ensure local state is consistent
                if let data = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(data, forKey: "heartedItems")
                }
                
                // Save to CloudKit with retry for conflict handling
                self.saveToCloudKitWithRetry(merged, forKey: "heartedItems", retryCount: 3) { error in
                    if let error = error {
                        print("ERROR: Failed to save merged hearted items to CloudKit after retries: \(error.localizedDescription)")
                    } else {
                        print("DEBUG: Successfully saved merged hearted items to CloudKit")
                    }
                    completion(error)
                }
                
            case .failure(let error):
                print("ERROR: Failed to fetch hearted items from CloudKit for merging: \(error.localizedDescription)")
                
                // Save locally even if CloudKit fails
                if let data = try? JSONEncoder().encode(normalizedNewItems) {
                    UserDefaults.standard.set(data, forKey: "heartedItems")
                }
                
                // If we can't fetch from CloudKit, just save the new items
                self.saveToCloudKitWithRetry(normalizedNewItems, forKey: "heartedItems", retryCount: 3, completion: completion)
            }
        }
    }
    
    /// Helper method to save to CloudKit with retries for conflict handling
    private func saveToCloudKitWithRetry<T: Encodable>(_ value: T, forKey key: String, retryCount: Int, completion: @escaping (Error?) -> Void) {
        guard retryCount > 0 else {
            completion(NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retry count exceeded"]))
            return
        }
        
        // We'll handle CloudKit operations directly
        
        // Setup database and recordID
        let database = CKContainer.default().privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "rssFeedsRecord")
        
        // First fetch the record to get the latest version
        database.fetch(withRecordID: recordID) { record, error in
            // Handle specific server record not found error
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Record doesn't exist yet, create new one
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: recordID)
                
                do {
                    let data = try JSONEncoder().encode(value)
                    newRecord[key] = data as CKRecordValue
                    
                    database.save(newRecord) { savedRecord, saveError in
                        DispatchQueue.main.async {
                            if let saveError = saveError {
                                print("ERROR: Failed to save new record: \(saveError.localizedDescription)")
                                // Try again with one less retry
                                self.saveToCloudKitWithRetry(value, forKey: key, retryCount: retryCount - 1, completion: completion)
                            } else {
                                print("DEBUG: Successfully created new record with key \(key)")
                                completion(nil)
                            }
                        }
                    }
                } catch {
                    print("ERROR: Failed to encode data: \(error.localizedDescription)")
                    completion(error)
                }
                return
            }
            
            // Handle other fetch errors
            if let error = error {
                print("ERROR: Failed to fetch record: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            // We got the record, update it
            if let record = record {
                do {
                    let data = try JSONEncoder().encode(value)
                    record[key] = data as CKRecordValue
                    
                    // Use modify operation for better conflict handling
                    let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                    modifyOperation.savePolicy = .changedKeys
                    
                    modifyOperation.modifyRecordsResultBlock = { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                print("DEBUG: Successfully saved data for key \(key)")
                                completion(nil)
                                
                            case .failure(let error):
                                if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                                    print("DEBUG: Server record changed, retrying with updated record")
                                    // Retry with one less retry count
                                    self.saveToCloudKitWithRetry(value, forKey: key, retryCount: retryCount - 1, completion: completion)
                                } else {
                                    print("ERROR: Failed to save data: \(error.localizedDescription)")
                                    completion(error)
                                }
                            }
                        }
                    }
                    
                    database.add(modifyOperation)
                    
                } catch {
                    print("ERROR: Failed to encode data: \(error.localizedDescription)")
                    completion(error)
                }
            } else {
                // No record and no error, shouldn't happen but create new record just in case
                print("WARNING: No record and no error, creating new record")
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: recordID)
                
                do {
                    let data = try JSONEncoder().encode(value)
                    newRecord[key] = data as CKRecordValue
                    
                    database.save(newRecord) { savedRecord, saveError in
                        DispatchQueue.main.async {
                            completion(saveError)
                        }
                    }
                } catch {
                    completion(error)
                }
            }
        }
    }
    
    /// Helper to normalize links for consistent comparison across devices
    /// This is a public method so it can be used by the rest of the app
    func normalizeLink(_ link: String) -> String {
        var urlString = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        
        // Standardize on https if the URL has http
        if urlString.lowercased().hasPrefix("http://") {
            urlString = "https://" + urlString.dropFirst(7)
        }
        
        return urlString
    }

    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void) {
        print("DEBUG: Loading data for key '\(key)' using \(method)")
        storage.load(forKey: key) { (result: Result<T, Error>) in
            switch result {
            case .success(let value):
                completion(.success(value))
            case .failure(let error):
                // Special handling for readItems decoding error
                if key == "readItems" {
                    print("Decoding error detected for readItems. Attempting CloudKit reset.")
                    if self.method == .cloudKit {
                        self.save([String](), forKey: "readItems") { saveError in
                            if saveError == nil {
                                print("Successfully reset CloudKit readItems to empty array.")
                                completion(.success([] as! T))
                            } else {
                                completion(.failure(saveError!))
                            }
                        }
                        return
                    }
                }
                completion(.failure(error))
            }
        }
    }
}

// MARK: - ArticleSummary Model
struct ArticleSummary: Codable {
    let title: String
    let link: String
    let pubDate: String
}
