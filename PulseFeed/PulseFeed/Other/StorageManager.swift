import CloudKit
import Foundation
import UIKit

// Extension to define custom notification names
extension NSNotification.Name {
    static let NetworkStatusChanged = NSNotification.Name("NetworkStatusChanged")
}

enum StorageMethod {
    case userDefaults, cloudKit, iCloudKeyValue
}

enum StorageError: Error {
    case notFound
    case decodingFailed(Error)
    case encodingFailed(Error)
    case cloudKitError(Error)
    case networkError(Error)
    case connectionOffline
    case unknown(Error)
    
    var localizedDescription: String {
        switch self {
        case .notFound:
            return "No data found"
        case .decodingFailed(let error):
            return "Failed to decode data: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode data: \(error.localizedDescription)"
        case .cloudKitError(let error):
            return "CloudKit error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .connectionOffline:
            return "Network connection is offline"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

protocol ArticleStorage {
    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void)
    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void)
}

/// Uses local UserDefaults for storage.
struct UserDefaultsStorage: ArticleStorage {
    let defaults = UserDefaults.standard

    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: key)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void) {
        if let data = defaults.data(forKey: key) {
            do {
                let value = try JSONDecoder().decode(T.self, from: data)
                completion(.success(value))
            } catch {
                // For collection types, return empty array on decoding error
                if T.self == [String].self || T.self == [RSSFeed].self {
                    print("DEBUG: UserDefaultsStorage - Failed to decode \(key), returning empty array")
                    completion(.success([] as! T))
                } else {
                    completion(.failure(error))
                }
            }
        } else {
            // For collection types, return empty array when key doesn't exist
            if T.self == [String].self || T.self == [RSSFeed].self {
                print("DEBUG: UserDefaultsStorage - No data for \(key), returning empty array")
                completion(.success([] as! T))
            } else {
                completion(.failure(StorageError.notFound))
            }
        }
    }
}

/// Uses iCloud Key-Value Store for storage of small data and settings.
struct UbiquitousKeyValueStorage: ArticleStorage {
    let store = UbiquitousKeyValueStore.shared
    
    // A list of key prefixes that are appropriate for iCloud Key-Value storage (small data)
    private let appropriateKeys = [
        "compactArticleView",
        "hideReadArticles",
        "useInAppReader",
        "useInAppBrowser",
        "autoEnableReaderMode",
        "fontSize",
        "previewTextLength",
        "articleSortAscending",
        "enableContentFiltering",
        "feedSlowThreshold",
        "enableNewItemNotifications"
    ]
    
    // Keys that store larger amounts of data and should be synced carefully
    private let largeDataKeys = [
        "readItems",
        "bookmarkedItems",
        "heartedItems",
        "filterKeywords"
    ]
    
    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void) {
        // If this is a key that's appropriate for iCloud Key-Value storage
        if isAppropriateForKeyValueStore(key) {
            store.save(value, forKey: key, completion: completion)
        } else {
            // For larger data, we'll fall back to UserDefaultsStorage
            UserDefaultsStorage().save(value, forKey: key, completion: completion)
        }
    }
    
    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void) {
        // If this is a key that's appropriate for iCloud Key-Value storage
        if isAppropriateForKeyValueStore(key) {
            store.load(forKey: key, completion: completion)
        } else {
            // For larger data, we'll fall back to UserDefaultsStorage
            UserDefaultsStorage().load(forKey: key, completion: completion)
        }
    }
    
    // Check if a key is appropriate for iCloud Key-Value storage
    private func isAppropriateForKeyValueStore(_ key: String) -> Bool {
        // Check for direct matches
        if appropriateKeys.contains(key) {
            return true
        }
        
        // Check for key prefixes
        for prefix in appropriateKeys {
            if key.hasPrefix(prefix) {
                return true
            }
        }
        
        // Also include small data with special handling
        if largeDataKeys.contains(key) {
            return true
        }
        
        return false
    }
    
    // Sync a specific key from iCloud to UserDefaults
    func syncFromCloud(key: String) {
        store.syncFromCloud(key: key)
    }
    
    // Sync a specific large data key between UserDefaults and iCloud KV store
    func syncLargeDataKey(_ key: String, completion: @escaping (Error?) -> Void) {
        guard largeDataKeys.contains(key) else {
            completion(nil)
            return
        }
        
        // Read from UserDefaults first
        if let data = UserDefaults.standard.data(forKey: key) {
            // Save to iCloud KV store
            store.set(data, forKey: key)
            completion(nil)
        } else {
            // Try to read from iCloud KV store
            if let data = store.data(forKey: key) {
                // Save to UserDefaults
                UserDefaults.standard.set(data, forKey: key)
                completion(nil)
            } else {
                completion(nil) // No data to sync
            }
        }
    }
}

/// Uses CloudKit for storage by saving all feeds as one JSON blob in a single record.
struct CloudKitStorage: ArticleStorage {
    let container = CKContainer.default()
    let database = CKContainer.default().privateCloudDatabase
    // Fixed record ID for storing all data in separate fields.
    let recordID = CKRecord.ID(recordName: "rssFeedsRecord")
    
    // MARK: - Save and Load Methods
    
    /// Update multiple keys on the same record at once.
    func updateRecord(with updates: [String: Data], completion: @escaping (Error?) -> Void) {
        database.fetch(withRecordID: recordID) { record, error in
            if let record = record {
                // Update each provided key.
                for (key, value) in updates {
                    record[key] = value as CKRecordValue
                }
                
                let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                operation.savePolicy = .changedKeys
                
                operation.modifyRecordsResultBlock = { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            completion(nil)
                        case .failure(let error):
                            completion(error)
                        }
                    }
                }
                
                self.database.add(operation)
            } else {
                // If the record doesn't exist, create a new one.
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: self.recordID)
                for (key, value) in updates {
                    newRecord[key] = value as CKRecordValue
                }
                
                let operation = CKModifyRecordsOperation(recordsToSave: [newRecord], recordIDsToDelete: nil)
                operation.savePolicy = .changedKeys
                
                operation.modifyRecordsResultBlock = { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            completion(nil)
                        case .failure(let error):
                            completion(error)
                        }
                    }
                }
                
                self.database.add(operation)
            }
        }
    }
    
    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(value)
            saveData(data, forKey: key, completion: completion)
        } catch {
            completion(StorageError.encodingFailed(error))
        }
    }

    private func saveData(_ data: Data, forKey key: String, completion: @escaping (Error?) -> Void) {
        database.fetch(withRecordID: recordID) { record, error in
            if let ckError = error as? CKError, ckError.code != .unknownItem {
                completion(StorageError.cloudKitError(error!))
                return
            }
            
            let recordToSave = record ?? CKRecord(recordType: "RSSFeeds", recordID: self.recordID)
            recordToSave[key] = data as CKRecordValue
            
            let operation = CKModifyRecordsOperation(recordsToSave: [recordToSave], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            operation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completion(nil)
                    case .failure(let error):
                        completion(error)
                    }
                }
            }
            
            self.database.add(operation)
        }
    }

    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void) {
        database.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    // Return empty array for collection types
                    if T.self == [RSSFeed].self || T.self == [String].self || T.self == [ArticleSummary].self {
                        completion(.success([] as! T))
                        return
                    }
                    completion(.failure(StorageError.notFound))
                    return
                }
                
                if let error = error {
                    completion(.failure(StorageError.cloudKitError(error)))
                    return
                }
                
                if let record = record, let data = record[key] as? Data {
                    do {
                        let value = try JSONDecoder().decode(T.self, from: data)
                        completion(.success(value))
                    } catch {
                        completion(.failure(StorageError.decodingFailed(error)))
                    }
                } else {
                    // Return empty array for collection types
                    if T.self == [RSSFeed].self || T.self == [String].self || T.self == [ArticleSummary].self {
                        completion(.success([] as! T))
                    } else {
                        completion(.failure(StorageError.notFound))
                    }
                }
            }
        }
    }

    // MARK: - Article Management
    
    func saveArticles(forFeed feedId: String, articles newArticles: [ArticleSummary], completion: @escaping (Error?) -> Void) {
        let recordID = CKRecord.ID(recordName: "feedArticlesRecord-\(feedId)")
        
        database.fetch(withRecordID: recordID) { (record, error) in
            // Handle errors
            if let error = error as? CKError, error.code != .unknownItem {
                DispatchQueue.main.async { completion(error) }
                return
            }
            
            let currentRecord = record ?? CKRecord(recordType: "RSSFeedArticles", recordID: recordID)
            var existingArticles: [ArticleSummary] = []
            
            // Decode existing articles if the record exists and has data
            if let existingData = currentRecord["articles"] as? Data {
                do {
                    existingArticles = try JSONDecoder().decode([ArticleSummary].self, from: existingData)
                } catch {
                    print("Warning: Could not decode existing articles for feed \(feedId). Starting fresh.")
                }
            }
            
            // Merge articles with deduplication
            var combinedArticlesDict = Dictionary(existingArticles.map { ($0.link, $0) }, uniquingKeysWith: { (current, _) in current })
            for article in newArticles {
                combinedArticlesDict[article.link] = article // Add or overwrite with the new article
            }
            
            var finalArticles = Array(combinedArticlesDict.values)
            
            // Limit the saved articles to 5000 (like original) and sort by date
            if finalArticles.count > 5000 {
                finalArticles.sort { $0.pubDate > $1.pubDate }
                finalArticles = Array(finalArticles.prefix(5000))
            }
            
            // Encode and save
            do {
                let finalData = try JSONEncoder().encode(finalArticles)
                currentRecord["articles"] = finalData as CKRecordValue
                
                let operation = CKModifyRecordsOperation(recordsToSave: [currentRecord], recordIDsToDelete: nil)
                operation.savePolicy = .changedKeys
                
                operation.modifyRecordsResultBlock = { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            completion(nil)
                        case .failure(let error):
                            completion(error)
                        }
                    }
                }
                
                self.database.add(operation)
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }

    @available(*, deprecated, message: "Use instance method version loadArticles")
    func loadArticles(forFeed feedId: String, completion: @escaping (Result<[ArticleSummary], Error>) -> Void) {
        let recordID = CKRecord.ID(recordName: "feedArticlesRecord-\(feedId)")
        
        database.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
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
                    completion(.success([]))
                }
            }
        }
    }
}

/// Structure for storing full article content for offline reading
struct CachedArticleContent: Codable {
    let link: String
    let content: String
    let cachedDate: Date
    let title: String
    let source: String
    
    init(link: String, content: String, title: String, source: String) {
        self.link = link
        self.content = content
        self.cachedDate = Date()
        self.title = title
        self.source = source
    }
}

/// Singleton that provides a unified interface for storage.
class StorageManager {
    // MARK: - Properties

    static let shared = StorageManager()
    
    // Flags for state tracking
    private var hasSyncedOnLaunch = false
    private var hasSetupSubscriptions = false
    
    // Network connectivity state
    private var isOffline = false
    
    // Sync items types
    private enum SyncItemType: String {
        case readItems
        case bookmarkedItems
        case heartedItems
        case feedFolders
        case cachedArticles
        case readingProgress
        case archivedItems
    }
    
    /// Dictionary to track which articles are currently being cached to prevent duplicate requests
    private var articlesBeingCached = [String: Bool]()

    var method: StorageMethod = .userDefaults {
        didSet {
            if method == .cloudKit && !hasSetupSubscriptions {
                setupCloudKitSubscriptions()
            }
            
            if method == .iCloudKeyValue {
                UbiquitousKeyValueStore.shared.synchronize()
            }
        }
    }

    private var storage: ArticleStorage {
        switch method {
        case .userDefaults: return UserDefaultsStorage()
        case .cloudKit: return CloudKitStorage()
        case .iCloudKeyValue: return UbiquitousKeyValueStorage()
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Set up notification observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteNotification),
            name: Notification.Name("CKRemoteChangeNotification"),
            object: nil
        )
        
        // Observe network status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkStatusChanged(_:)),
            name: NSNotification.Name.NetworkStatusChanged,
            object: nil
        )
        
        // Observe iCloud Key-Value store changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyValueStoreChanged(_:)),
            name: UbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil
        )
        
        // Initialize network status
        checkNetworkConnectivity()
        
        // Register common keys for iCloud Key-Value sync
        registerCommonKeysForSync()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Network Connectivity
    
    /// Check current network connectivity
    private func checkNetworkConnectivity() {
        // For now, we'll rely on the notification system
        // In a real app, this would be implemented with network reachability checking
        // like NWPathMonitor or SCNetworkReachability
        isOffline = false
    }
    
    @objc private func handleNetworkStatusChanged(_ notification: Notification) {
        if let isConnected = notification.userInfo?["isConnected"] as? Bool {
            isOffline = !isConnected
            
            // Notify the app about offline status change
            NotificationCenter.default.post(
                name: Notification.Name("OfflineStatusChanged"),
                object: nil,
                userInfo: ["isOffline": isOffline]
            )
        }
    }
    
    /// Check if the device is currently offline
    var isDeviceOffline: Bool {
        return isOffline
    }
    
    /// Manually set offline state (for testing or when network status detection fails)
    func setOfflineState(_ offline: Bool) {
        isOffline = offline
        
        // Notify the app about offline status change
        NotificationCenter.default.post(
            name: Notification.Name("OfflineStatusChanged"),
            object: nil,
            userInfo: ["isOffline": isOffline]
        )
    }
    
    // MARK: - CloudKit Setup
    
    private func setupCloudKitSubscriptions() {
        guard method == .cloudKit else { return }
        
        let database = CKContainer.default().privateCloudDatabase
        let rssFeedsID = CKRecord.ID(recordName: "rssFeedsRecord")
        let predicate = NSPredicate(format: "recordID = %@", rssFeedsID)
        
        let subscription = CKQuerySubscription(
            recordType: "RSSFeeds", 
            predicate: predicate,
            subscriptionID: "PulseFeed-RSSFeeds-Subscription",
            options: [.firesOnRecordUpdate, .firesOnRecordCreation]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push notification
        subscription.notificationInfo = notificationInfo
        
        database.save(subscription) { _, error in
            if let error = error {
                if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                    print("DEBUG: CloudKit subscription may already exist")
                } else {
                    print("ERROR: Failed to create CloudKit subscription: \(error.localizedDescription)")
                }
            }
            self.hasSetupSubscriptions = true
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleRemoteNotification(_ notification: Notification) {
        syncFromCloudKit()
    }
    
    @objc private func handleAppBecameActive() {
        switch method {
        case .cloudKit:
            syncFromCloudKit()
        case .iCloudKeyValue:
            syncFromKeyValueStore()
        default:
            break
        }
    }
    
    @objc private func handleKeyValueStoreChanged(_ notification: Notification) {
        guard method == .iCloudKeyValue,
              let userInfo = notification.userInfo,
              let key = userInfo["key"] as? String else {
            return
        }
        
        // Post notification about the changed data
        NotificationCenter.default.post(
            name: Notification.Name("\(key)Updated"),
            object: nil
        )
    }
    
    // Register common keys used throughout the app for iCloud Key-Value syncing
    private func registerCommonKeysForSync() {
        let kvStore = UbiquitousKeyValueStore.shared
        
        // App settings
        let appSettingsKeys = [
            "enhancedArticleStyle",
            "compactArticleView",
            "hideReadArticles",
            "useInAppReader",
            "useInAppBrowser",
            "readerFontSize",
            "readerLineHeight",
            "autoEnableReaderMode",
            "fontSize",
            "previewTextLength",
            "articleSortAscending",
            "enableContentFiltering",
            "feedSlowThreshold",
            "enableNewItemNotifications"
        ]
        
        // User data keys (these are larger, but still appropriate for KV store)
        let userDataKeys = [
            "readItems",
            "bookmarkedItems",
            "heartedItems",
            "filterKeywords"
        ]
        
        kvStore.registerKeysForSync(appSettingsKeys)
        kvStore.registerKeysForSync(userDataKeys)
    }
    
    // MARK: - Sync Methods
    
    // Sync from iCloud Key-Value Store
    func syncFromKeyValueStore(completion: ((Bool) -> Void)? = nil) {
        guard method == .iCloudKeyValue else {
            completion?(false)
            return
        }
        
        // Always ensure article summarization is enabled, regardless of synced value
        UserDefaults.standard.set(true, forKey: "enableArticleSummarization")
        
        let syncGroup = DispatchGroup()
        var syncSuccess = true
        let kvStore = UbiquitousKeyValueStore.shared
        
        // Force a sync first to ensure we have the latest data
        let syncResult = kvStore.synchronize()
        if !syncResult {
            print("WARNING: Failed to synchronize iCloud Key-Value store")
        }
        
        // Sync app settings (these are typically small and can be synced quickly)
        let appSettingsKeys = [
            "enhancedArticleStyle",
            "compactArticleView",
            "hideReadArticles",
            "useInAppReader",
            "useInAppBrowser",
            "enableArticleSummarization",
            "readerFontSize",
            "readerLineHeight",
            "autoEnableReaderMode",
            "fontSize",
            "previewTextLength",
            "articleSortAscending",
            "enableContentFiltering",
            "feedSlowThreshold",
            "enableNewItemNotifications"
        ]
        
        for key in appSettingsKeys {
            syncGroup.enter()
            if let kvStorage = storage as? UbiquitousKeyValueStorage {
                kvStorage.syncFromCloud(key: key)
                syncGroup.leave()
            } else {
                syncGroup.leave()
                syncSuccess = false
            }
        }
        
        // Sync user data (these might be larger and require special handling)
        let userDataKeys = [
            "readItems",
            "bookmarkedItems",
            "heartedItems",
            "filterKeywords"
        ]
        
        for key in userDataKeys {
            syncGroup.enter()
            if let kvStorage = storage as? UbiquitousKeyValueStorage {
                kvStorage.syncLargeDataKey(key) { error in
                    if error != nil {
                        syncSuccess = false
                    }
                    syncGroup.leave()
                }
            } else {
                syncGroup.leave()
                syncSuccess = false
            }
        }
        
        // Final callback after all syncs complete
        syncGroup.notify(queue: .main) {
            completion?(syncSuccess)
        }
    }
    
    // MARK: - CloudKit Sync
    
    func syncFromCloudKit(completion: ((Bool) -> Void)? = nil) {
        guard method == .cloudKit else {
            completion?(false)
            return
        }
        
        // Always ensure article summarization is enabled, regardless of synced value
        UserDefaults.standard.set(true, forKey: "enableArticleSummarization")
        
        let syncGroup = DispatchGroup()
        var syncSuccess = true
        
        // Sync all item types including hierarchical folders
        for itemType in [SyncItemType.readItems, .bookmarkedItems, .heartedItems, .archivedItems, .feedFolders] {
            syncGroup.enter()
            syncItemsFromCloud(type: itemType) { success in
                if !success {
                    syncSuccess = false
                }
                syncGroup.leave()
            }
        }
        
        // Sync hierarchical folders separately
        syncGroup.enter()
        syncHierarchicalFolders { success in
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
    
    // Sync hierarchical folders from CloudKit
    func syncHierarchicalFolders(completion: @escaping (Bool) -> Void) {
        print("DEBUG-PERSIST: Syncing hierarchical folders from CloudKit")

        // Fetch folders from CloudKit
        CloudKitStorage().load(forKey: "hierarchicalFolders") { (result: Result<[HierarchicalFolder], Error>) in
            switch result {
            case .success(let cloudFolders):
                print("DEBUG-PERSIST: Successfully loaded \(cloudFolders.count) hierarchical folders from CloudKit")

                // Check if we need to merge with local folders
                if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
                    do {
                        let localFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                        print("DEBUG-PERSIST: Found \(localFolders.count) local folders in UserDefaults")

                        // Create a dictionary for easy lookup and merging
                        var folderDict: [String: HierarchicalFolder] = [:]

                        // Add all local folders to dictionary first
                        for folder in localFolders {
                            folderDict[folder.id] = folder
                        }

                        // If cloud has folders, merge them with local folders (local takes precedence to preserve existing folders)
                        if !cloudFolders.isEmpty {
                            print("DEBUG-PERSIST: Merging cloud and local folders...")

                            // Merge with cloud folders (but don't overwrite local folders)
                            for cloudFolder in cloudFolders {
                                // Only add cloud folder if it doesn't exist locally
                                if folderDict[cloudFolder.id] == nil {
                                    folderDict[cloudFolder.id] = cloudFolder
                                }
                            }
                        }

                        // Convert back to array
                        let mergedFolders = Array(folderDict.values)
                        print("DEBUG-PERSIST: Merged to \(mergedFolders.count) folders")

                        // Always save back to CloudKit to ensure cloud is up-to-date
                        self.saveToCloudKit(mergedFolders, forKey: "hierarchicalFolders", retryCount: 3) { error in
                            if let error = error {
                                print("DEBUG-PERSIST: Error saving merged folders to CloudKit: \(error.localizedDescription)")
                            } else {
                                print("DEBUG-PERSIST: Successfully saved merged folders to CloudKit")
                            }
                        }

                        // Save merged folders to UserDefaults
                        if let encodedData = try? JSONEncoder().encode(mergedFolders) {
                            UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                            UserDefaults.standard.synchronize()

                            // Notify that folders were updated
                            NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                            completion(true)
                            return
                        }
                    } catch {
                        print("DEBUG-PERSIST: Error decoding local folders: \(error)")
                    }
                } else if !cloudFolders.isEmpty {
                    // No local folders but we have cloud folders, save cloud folders to UserDefaults
                    print("DEBUG-PERSIST: No local folders found, saving cloud folders to UserDefaults")
                    if let encodedData = try? JSONEncoder().encode(cloudFolders) {
                        UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                        UserDefaults.standard.synchronize()

                        // Notify that folders were updated
                        NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                        completion(true)
                    } else {
                        print("ERROR: Failed to encode hierarchical folders")
                        completion(false)
                    }
                } else {
                    // No folders anywhere
                    print("DEBUG-PERSIST: No folders found locally or in CloudKit")
                    completion(true)
                }

            case .failure(let error):
                // If error is "not found", try to load from UserDefaults only
                if case StorageError.notFound = error {
                    print("DEBUG-PERSIST: No hierarchical folders found in CloudKit (normal for first run)")

                    // Check if we have local folders
                    if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
                        do {
                            let localFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                            print("DEBUG-PERSIST: Using \(localFolders.count) local folders from UserDefaults")

                            // Sync local folders to CloudKit if we have any
                            if !localFolders.isEmpty {
                                self.saveToCloudKit(localFolders, forKey: "hierarchicalFolders", retryCount: 3) { error in
                                    if let error = error {
                                        print("DEBUG-PERSIST: Error saving local folders to CloudKit: \(error.localizedDescription)")
                                    } else {
                                        print("DEBUG-PERSIST: Successfully saved local folders to CloudKit")
                                    }
                                }
                            }

                            completion(true)
                        } catch {
                            print("DEBUG-PERSIST: Error decoding local folders: \(error)")
                            completion(false)
                        }
                    } else {
                        // No folders anywhere
                        print("DEBUG-PERSIST: No folders found locally or in CloudKit")
                        completion(true)
                    }
                } else {
                    print("ERROR: Failed to load hierarchical folders from CloudKit: \(error.localizedDescription)")

                    // If CloudKit fails, try to use local folders only
                    if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
                        do {
                            let localFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                            print("DEBUG-PERSIST: Using \(localFolders.count) local folders from UserDefaults despite CloudKit error")
                            completion(true)
                        } catch {
                            print("DEBUG-PERSIST: Error decoding local folders: \(error)")
                            completion(false)
                        }
                    } else {
                        completion(false)
                    }
                }
            }
        }
    }
    
    // For testing purposes - simulates clearing local cache and syncing from CloudKit
    #if DEBUG
    func testFolderSyncingFromCloudKit(completion: @escaping (Bool) -> Void) {
        print("DEBUG: Starting folder syncing test")
        
        // 1. Create a test folder
        let testFolder = FeedFolder(name: "Test Folder \(Int.random(in: 1000...9999))")
        var folders: [FeedFolder] = []
        
        // 2. First get existing folders
        getFolders { [weak self] result in
            guard let self = self else {
                completion(false)
                return
            }
            
            if case .success(let existingFolders) = result {
                folders = existingFolders
            }
            
            // 3. Add the test folder
            folders.append(testFolder)
            
            // 4. Save to CloudKit
            print("DEBUG: Saving test folder to CloudKit")
            self.saveToCloudKit(folders, forKey: "feedFolders", retryCount: 3) { error in
                if let error = error {
                    print("DEBUG: Failed to save test folder: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                // 5. Clear local cache
                print("DEBUG: Clearing local folder cache")
                UserDefaults.standard.removeObject(forKey: "feedFolders")
                
                // 6. Sync from CloudKit to verify folders are restored
                print("DEBUG: Syncing from CloudKit")
                self.syncFoldersFromCloud { success in
                    if success {
                        // 7. Verify the test folder was synced
                        self.getFolders { result in
                            if case .success(let syncedFolders) = result {
                                let found = syncedFolders.contains { $0.id == testFolder.id }
                                print("DEBUG: Test folder found after sync: \(found)")
                                completion(found)
                            } else {
                                print("DEBUG: Failed to get folders after sync")
                                completion(false)
                            }
                        }
                    } else {
                        print("DEBUG: Sync from CloudKit failed")
                        completion(false)
                    }
                }
            }
        }
    }
    #endif
    
    // Generic method to sync different item types
    private func syncItemsFromCloud(type: SyncItemType, completion: @escaping (Bool) -> Void) {
        let key = type.rawValue
        
        // Special handling for folders which are complex objects rather than simple string arrays
        if type == .feedFolders {
            syncFoldersFromCloud(completion: completion)
            return
        }
        
        CloudKitStorage().load(forKey: key) { (result: Result<[String], Error>) in
            
            switch result {
            case .success(let cloudItems):
                // Normalize the items
                let normalizedCloudItems = cloudItems.map { self.normalizeLink($0) }
                
                // Get and merge local items 
                var localItems: [String] = []
                if let data = UserDefaults.standard.data(forKey: key) {
                    do {
                        localItems = try JSONDecoder().decode([String].self, from: data)
                    } catch {
                        print("ERROR: Failed to decode local \(key): \(error.localizedDescription)")
                    }
                }
                
                let normalizedLocalItems = localItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedLocalItems)))
                
                // Update local storage
                if let encodedData = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(encodedData, forKey: key)
                    
                    // Notify that items were updated
                    NotificationCenter.default.post(name: Notification.Name("\(key)Updated"), object: nil)
                    
                    // If the cloud had more items than local, update CloudKit for consistency
                    if normalizedCloudItems.count < merged.count {
                        self.mergeAndSaveItems(merged, forKey: key) { error in
                            completion(error == nil)
                        }
                    } else {
                        completion(true)
                    }
                } else {
                    completion(false)
                }
                
            case .failure:
                completion(false)
            }
        }
    }
    
    // Special method to sync folders from CloudKit
    private func syncFoldersFromCloud(completion: @escaping (Bool) -> Void) {
        let key = SyncItemType.feedFolders.rawValue
        
        // Fetch folders from CloudKit
        CloudKitStorage().load(forKey: key) { (result: Result<[FeedFolder], Error>) in
            switch result {
            case .success(let cloudFolders):
                // Get local folders
                var localFolders: [FeedFolder] = []
                if let data = UserDefaults.standard.data(forKey: key) {
                    do {
                        localFolders = try JSONDecoder().decode([FeedFolder].self, from: data)
                    } catch {
                        print("ERROR: Failed to decode local folders: \(error.localizedDescription)")
                    }
                }
                
                // Merge folders by ID
                var mergedFolders: [FeedFolder] = []
                var folderDict: [String: FeedFolder] = [:]
                
                // Add all local folders to dictionary
                for folder in localFolders {
                    folderDict[folder.id] = folder
                }
                
                // Merge with cloud folders
                for cloudFolder in cloudFolders {
                    if let existingFolder = folderDict[cloudFolder.id] {
                        // If folder exists locally, merge feed URLs
                        var updatedFolder = existingFolder
                        
                        // Normalize all feed URLs
                        let normalizedLocalURLs = existingFolder.feedURLs.map { self.normalizeLink($0) }
                        let normalizedCloudURLs = cloudFolder.feedURLs.map { self.normalizeLink($0) }
                        
                        // Merge the URLs
                        let mergedURLs = Array(Set(normalizedLocalURLs).union(Set(normalizedCloudURLs)))
                        updatedFolder.feedURLs = mergedURLs
                        
                        // Use the most recent name (prefer cloud for simplicity)
                        updatedFolder.name = cloudFolder.name
                        
                        // Update dictionary
                        folderDict[cloudFolder.id] = updatedFolder
                    } else {
                        // If folder doesn't exist locally, add it
                        folderDict[cloudFolder.id] = cloudFolder
                    }
                }
                
                // Convert dictionary back to array
                mergedFolders = Array(folderDict.values)
                
                // Save merged folders locally
                if let encodedData = try? JSONEncoder().encode(mergedFolders) {
                    UserDefaults.standard.set(encodedData, forKey: key)
                    
                    // Notify that folders were updated
                    NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                    
                    // If there were changes (more local folders or merged feed URLs), update CloudKit
                    if localFolders.count > cloudFolders.count || mergedFolders != cloudFolders {
                        self.saveToCloudKit(mergedFolders, forKey: key, retryCount: 3) { error in
                            completion(error == nil)
                        }
                    } else {
                        completion(true)
                    }
                } else {
                    completion(false)
                }
                
            case .failure(let error):
                print("ERROR: Failed to load folders from CloudKit: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    // MARK: - Article Caching
    
    /// Cache article content for offline reading
    /// - Parameters:
    ///   - link: The article URL
    ///   - content: The HTML content of the article
    ///   - title: The article title
    ///   - source: The source/publisher of the article
    ///   - completion: Called with success or error
    func cacheArticleContent(link: String, content: String, title: String, source: String, completion: @escaping (Bool, Error?) -> Void) {
        // Normalize the link
        let normalizedLink = normalizeLink(link)
        
        // Prevent duplicate caching requests for the same article
        if articlesBeingCached[normalizedLink] == true {
            completion(false, nil)
            return
        }
        
        // Mark article as being cached
        articlesBeingCached[normalizedLink] = true
        
        // Create new cached article
        let cachedArticle = CachedArticleContent(
            link: normalizedLink,
            content: content,
            title: title,
            source: source
        )
        
        // Load existing cached articles
        load(forKey: "cachedArticles") { [weak self] (result: Result<[CachedArticleContent], Error>) in
            guard let self = self else {
                completion(false, NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage manager no longer exists"]))
                return
            }
            
            var cachedArticles: [CachedArticleContent] = []
            
            if case .success(let existingArticles) = result {
                cachedArticles = existingArticles
            }
            
            // Remove any existing version of this article
            cachedArticles.removeAll { self.normalizeLink($0.link) == normalizedLink }
            
            // Add the new article
            cachedArticles.append(cachedArticle)
            
            // Limit to most recent 50 articles to prevent excessive storage use
            if cachedArticles.count > 50 {
                cachedArticles.sort { $0.cachedDate > $1.cachedDate }
                cachedArticles = Array(cachedArticles.prefix(50))
            }
            
            // Save the updated list
            self.save(cachedArticles, forKey: "cachedArticles") { error in
                // Remove from being cached list
                self.articlesBeingCached[normalizedLink] = nil
                
                if let error = error {
                    completion(false, error)
                } else {
                    // Post notification that article was cached
                    NotificationCenter.default.post(
                        name: Notification.Name("ArticleCached"),
                        object: nil,
                        userInfo: ["link": normalizedLink]
                    )
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Get cached content for an article
    /// - Parameters:
    ///   - link: The article URL
    ///   - completion: Called with the cached content or an error
    func getCachedArticleContent(link: String, completion: @escaping (Result<CachedArticleContent, Error>) -> Void) {
        let normalizedLink = normalizeLink(link)
        
        load(forKey: "cachedArticles") { (result: Result<[CachedArticleContent], Error>) in
            switch result {
            case .success(let cachedArticles):
                if let article = cachedArticles.first(where: { self.normalizeLink($0.link) == normalizedLink }) {
                    completion(.success(article))
                } else {
                    completion(.failure(StorageError.notFound))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Check if article has cached content
    /// - Parameters:
    ///   - link: The article URL
    ///   - completion: Called with bool indicating whether content is cached
    func isArticleCached(link: String, completion: @escaping (Bool) -> Void) {
        let normalizedLink = normalizeLink(link)
        
        load(forKey: "cachedArticles") { (result: Result<[CachedArticleContent], Error>) in
            switch result {
            case .success(let cachedArticles):
                let isCached = cachedArticles.contains { self.normalizeLink($0.link) == normalizedLink }
                completion(isCached)
            case .failure:
                completion(false)
            }
        }
    }
    
    /// Remove a specific article from cache
    /// - Parameters:
    ///   - link: The article URL
    ///   - completion: Called with success or error
    func removeCachedArticle(link: String, completion: @escaping (Bool, Error?) -> Void) {
        let normalizedLink = normalizeLink(link)
        
        // Load existing cached articles
        load(forKey: "cachedArticles") { [weak self] (result: Result<[CachedArticleContent], Error>) in
            guard let self = self else {
                completion(false, NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage manager no longer exists"]))
                return
            }
            
            switch result {
            case .success(var cachedArticles):
                // Check if article exists in cache
                if !cachedArticles.contains(where: { self.normalizeLink($0.link) == normalizedLink }) {
                    completion(true, nil) // Already not in cache
                    return
                }
                
                // Remove the article
                cachedArticles.removeAll { self.normalizeLink($0.link) == normalizedLink }
                
                // Save the updated list
                self.save(cachedArticles, forKey: "cachedArticles") { error in
                    if let error = error {
                        completion(false, error)
                    } else {
                        // Post notification that article was removed from cache
                        NotificationCenter.default.post(
                            name: Notification.Name("ArticleRemovedFromCache"),
                            object: nil,
                            userInfo: ["link": normalizedLink]
                        )
                        completion(true, nil)
                    }
                }
            case .failure(let error):
                completion(false, error)
            }
        }
    }
    
    /// Remove all cached articles
    /// - Parameter completion: Called with success or error
    func clearArticleCache(completion: @escaping (Bool, Error?) -> Void) {
        // Save an empty array to clear the cache
        save([CachedArticleContent](), forKey: "cachedArticles") { error in
            if let error = error {
                completion(false, error)
            } else {
                // Post notification that cache was cleared
                NotificationCenter.default.post(
                    name: Notification.Name("ArticleCacheCleared"),
                    object: nil
                )
                completion(true, nil)
            }
        }
    }
    
    /// Get all cached articles
    /// - Parameter completion: Called with the list of cached articles or an error
    func getAllCachedArticles(completion: @escaping (Result<[CachedArticleContent], Error>) -> Void) {
        load(forKey: "cachedArticles", completion: completion)
    }
    
    // MARK: - Public API
    
    func markAllAsRead(completion: @escaping (Bool, Error?) -> Void) {
        // Find all article links to mark as read
        guard let keyWindow = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .compactMap({$0 as? UIWindowScene})
                .first?.windows
                .filter({$0.isKeyWindow}).first,
              let rootNavController = keyWindow.rootViewController as? UINavigationController,
              let homeVC = rootNavController.viewControllers.first as? HomeFeedViewController else {
            completion(false, NSError(domain: "StorageManager", code: -1, 
                                    userInfo: [NSLocalizedDescriptionKey: "Could not access HomeViewController"]))
            return
        }
        
        // Get all article links from the HomeFeedViewController
        let allLinks = homeVC.allItems.map { normalizeLink($0.link) }
        
        if allLinks.isEmpty {
            completion(false, NSError(domain: "StorageManager", code: -1, 
                                    userInfo: [NSLocalizedDescriptionKey: "No articles found to mark as read"]))
            return
        }
        
        // Save locally first for immediate feedback
        if let data = try? JSONEncoder().encode(allLinks) {
            UserDefaults.standard.set(data, forKey: "readItems")
            UserDefaults.standard.set(true, forKey: "allItemsRead")
            
            // Post notification to update UI immediately
            NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
        }
        
        // Update CloudKit if using it
        if method == .cloudKit {
            saveToCloudKit(allLinks, forKey: "readItems", retryCount: 3) { error in
                completion(true, error) // Still return success since local data was updated
            }
        } else {
            completion(true, nil)
        }
    }

    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void) {
        if method == .cloudKit {
            if let items = value as? [String] {
                switch key {
                case "readItems", "bookmarkedItems", "heartedItems":
                    mergeAndSaveItems(items, forKey: key, completion: completion)
                    return
                default:
                    break
                }
            }
            // --- END ADDED ---
        }
        
        storage.save(value, forKey: key, completion: completion)
    }
    
    // Generic method to merge and save different item types
    private func mergeAndSaveItems(_ newItems: [String], forKey key: String, completion: @escaping (Error?) -> Void) {
        // First normalize all the new links
        let normalizedNewItems = newItems.map { normalizeLink($0) }
        
        // Always fetch from CloudKit first to ensure we have latest data
        CloudKitStorage().load(forKey: key) { (result: Result<[String], Error>) in
            
            switch result {
            case .success(let cloudItems):
                // Normalize cloud items
                let normalizedCloudItems = cloudItems.map { self.normalizeLink($0) }
                
                // Merge the two sets
                let merged = Array(Set(normalizedCloudItems).union(Set(normalizedNewItems)))
                
                // Save to UserDefaults immediately for local consistency
                if let data = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                
                // Save to CloudKit with retry
                self.saveToCloudKit(merged, forKey: key, retryCount: 3, completion: completion)
                
            case .failure:
                // If we can't fetch from CloudKit, save the new items locally and to CloudKit
                if let data = try? JSONEncoder().encode(normalizedNewItems) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                self.saveToCloudKit(normalizedNewItems, forKey: key, retryCount: 3, completion: completion)
            }
        }
    }
    
    // Force a sync of all data with the appropriate storage method
    func forceSync(completion: @escaping (Bool) -> Void) {
        switch method {
        case .cloudKit:
            syncFromCloudKit(completion: completion)
        case .iCloudKeyValue:
            syncFromKeyValueStore(completion: completion)
        case .userDefaults:
            // Nothing to sync for local-only storage
            completion(true)
        }
    }
    
    // Helper method for reliable CloudKit saving with retries
    private func saveToCloudKit<T: Encodable>(_ value: T, forKey key: String, retryCount: Int, completion: @escaping (Error?) -> Void) {
        guard retryCount > 0 else {
            completion(NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retry count exceeded"]))
            return
        }
        
        // Setup database and recordID
        let database = CKContainer.default().privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "rssFeedsRecord")
        
        // First fetch the record to get the latest version
        database.fetch(withRecordID: recordID) { record, error in
            
            // Handle record not found error
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Create new record
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: recordID)
                
                do {
                    let data = try JSONEncoder().encode(value)
                    newRecord[key] = data as CKRecordValue
                    
                    // Save new record
                    self.saveRecord(newRecord, database: database, retryCount: retryCount, key: key, value: value, completion: completion)
                } catch {
                    completion(error)
                }
                return
            }
            
            // Handle other fetch errors
            if let error = error {
                completion(error)
                return
            }
            
            // Update existing record
            if let record = record {
                do {
                    let data = try JSONEncoder().encode(value)
                    record[key] = data as CKRecordValue
                    
                    // Save updated record
                    self.saveRecord(record, database: database, retryCount: retryCount, key: key, value: value, completion: completion)
                } catch {
                    completion(error)
                }
            } else {
                // No record and no error (should not happen)
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: recordID)
                
                do {
                    let data = try JSONEncoder().encode(value)
                    newRecord[key] = data as CKRecordValue
                    
                    // Save new record
                    self.saveRecord(newRecord, database: database, retryCount: retryCount, key: key, value: value, completion: completion)
                } catch {
                    completion(error)
                }
            }
        }
    }
    
    // Helper method to save a record with retry logic
    private func saveRecord<T: Encodable>(_ record: CKRecord, database: CKDatabase, retryCount: Int, key: String, value: T, completion: @escaping (Error?) -> Void) {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        
        operation.modifyRecordsResultBlock = { result in
            
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(nil)
                    
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        // Retry with updated record
                        self.saveToCloudKit(value, forKey: key, retryCount: retryCount - 1, completion: completion)
                    } else {
                        completion(error)
                    }
                }
            }
        }
        
        database.add(operation)
    }

    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void) {
        storage.load(forKey: key) { (result: Result<T, Error>) in
            switch result {
            case .success(let value):
                completion(.success(value))
            case .failure(let error):
                // Special handling for readItems decoding error
                if key == "readItems", self.method == .cloudKit {
                    self.save([String](), forKey: "readItems") { saveError in
                        if saveError == nil {
                            completion(.success([] as! T))
                        } else {
                            completion(.failure(saveError!))
                        }
                    }
                    return
                }
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// Helper to normalize links for consistent comparison across devices
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
    
    // MARK: - Feed Folder Management
    
    /// Get all feed folders from storage
    func getFolders(completion: @escaping (Result<[FeedFolder], Error>) -> Void) {
        load(forKey: "feedFolders") { (result: Result<[FeedFolder], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let folders):
                    completion(.success(folders))
                case .failure(let error):
                    if case StorageError.notFound = error {
                        // If no folders are found, return an empty array
                        completion(.success([]))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Create a new folder
    func createFolder(name: String, completion: @escaping (Result<FeedFolder, Error>) -> Void) {
        getFolders { result in
            switch result {
            case .success(var folders):
                // Create new folder
                let newFolder = FeedFolder(name: name)
                folders.append(newFolder)
                
                // Save updated folders list with CloudKit sync and retry
                self.saveToCloudKit(folders, forKey: "feedFolders", retryCount: 3) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            // Also update in UserDefaults for immediate local access
                            if let encodedData = try? JSONEncoder().encode(folders) {
                                UserDefaults.standard.set(encodedData, forKey: "feedFolders")
                            }
                            
                            completion(.success(newFolder))
                            
                            // Post notification that folders have been updated
                            NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Update an existing folder
    func updateFolder(_ folder: FeedFolder, completion: @escaping (Result<Bool, Error>) -> Void) {
        getFolders { result in
            switch result {
            case .success(var folders):
                // Find and update the folder
                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    // Normalize feed URLs in the updated folder
                    var normalizedFolder = folder
                    normalizedFolder.feedURLs = folder.feedURLs.map { self.normalizeLink($0) }
                    
                    folders[index] = normalizedFolder
                    
                    // Save updated folders list with CloudKit sync and retry
                    self.saveToCloudKit(folders, forKey: "feedFolders", retryCount: 3) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                // Also update in UserDefaults for immediate local access
                                if let encodedData = try? JSONEncoder().encode(folders) {
                                    UserDefaults.standard.set(encodedData, forKey: "feedFolders")
                                }
                                
                                completion(.success(true))
                                
                                // Post notification that folders have been updated
                                NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1, 
                                        userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Delete a folder
    func deleteFolder(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        getFolders { result in
            switch result {
            case .success(var folders):
                // Remove the folder
                folders.removeAll { $0.id == id }
                
                // Save updated folders list with CloudKit sync and retry
                self.saveToCloudKit(folders, forKey: "feedFolders", retryCount: 3) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            // Also update in UserDefaults for immediate local access
                            if let encodedData = try? JSONEncoder().encode(folders) {
                                UserDefaults.standard.set(encodedData, forKey: "feedFolders")
                            }
                            
                            completion(.success(true))
                            
                            // Post notification that folders have been updated
                            NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Add a feed to a folder
    func addFeedToFolder(feedURL: String, folderId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        getFolders { result in
            switch result {
            case .success(var folders):
                // Find the folder
                if let index = folders.firstIndex(where: { $0.id == folderId }) {
                    // Add feed to folder if it's not already there
                    let normalizedURL = self.normalizeLink(feedURL)
                    
                    // Check if the feed is already in the folder (using normalized URLs)
                    let normalizedFolderURLs = folders[index].feedURLs.map { self.normalizeLink($0) }
                    if !normalizedFolderURLs.contains(normalizedURL) {
                        folders[index].feedURLs.append(normalizedURL)
                        
                        // Save updated folders list with CloudKit sync and retry
                        self.saveToCloudKit(folders, forKey: "feedFolders", retryCount: 3) { error in
                            DispatchQueue.main.async {
                                if let error = error {
                                    completion(.failure(error))
                                } else {
                                    // Also update in UserDefaults for immediate local access
                                    if let encodedData = try? JSONEncoder().encode(folders) {
                                        UserDefaults.standard.set(encodedData, forKey: "feedFolders")
                                    }
                                    
                                    completion(.success(true))
                                    
                                    // Post notification that folders have been updated
                                    NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                                }
                            }
                        }
                    } else {
                        // Feed already in folder
                        DispatchQueue.main.async {
                            completion(.success(true))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1, 
                                        userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Remove a feed from a folder
    func removeFeedFromFolder(feedURL: String, folderId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        getFolders { result in
            switch result {
            case .success(var folders):
                // Find the folder
                if let index = folders.firstIndex(where: { $0.id == folderId }) {
                    // Remove feed from folder using normalized URLs for comparison
                    let normalizedURL = self.normalizeLink(feedURL)
                    folders[index].feedURLs.removeAll { self.normalizeLink($0) == normalizedURL }
                    
                    // Save updated folders list with CloudKit sync and retry
                    self.saveToCloudKit(folders, forKey: "feedFolders", retryCount: 3) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                // Also update in UserDefaults for immediate local access
                                if let encodedData = try? JSONEncoder().encode(folders) {
                                    UserDefaults.standard.set(encodedData, forKey: "feedFolders")
                                }
                                
                                completion(.success(true))
                                
                                // Post notification that folders have been updated
                                NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1, 
                                        userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Get all feeds in a specific folder
    func getFeedsInFolder(folderId: String, completion: @escaping (Result<[RSSFeed], Error>) -> Void) {
        // First get the folder to get the feed URLs
        getFolders { result in
            switch result {
            case .success(let folders):
                // Find the folder
                if let folder = folders.first(where: { $0.id == folderId }) {
                    // Load all feeds
                    self.load(forKey: "rssFeeds") { (result: Result<[RSSFeed], Error>) in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let allFeeds):
                                // Filter feeds that are in the folder
                                let folderFeeds = allFeeds.filter { feed in
                                    folder.feedURLs.contains(where: { self.normalizeLink($0) == self.normalizeLink(feed.url) })
                                }
                                completion(.success(folderFeeds))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1, 
                                        userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Article Archiving
    
    /// Archive an article
    /// - Parameters:
    ///   - link: The URL of the article to archive
    ///   - completion: Called with success or error information
    func archiveArticle(link: String, completion: @escaping (Bool, Error?) -> Void) {
        // Use normalized link for consistency
        let normalizedLink = normalizeLink(link)
        
        load(forKey: "archivedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else {
                completion(false, NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage manager no longer exists"]))
                return
            }
            
            var archivedItems: [String] = []
            
            if case .success(let items) = result {
                archivedItems = items
            }
            
            // Check if already archived
            if archivedItems.contains(where: { self.normalizeLink($0) == normalizedLink }) {
                // Already archived, return success
                completion(true, nil)
                return
            }
            
            // Add to archived items
            archivedItems.append(normalizedLink)
            
            // Save the updated list
            if self.method == .cloudKit {
                self.mergeAndSaveItems(archivedItems, forKey: "archivedItems") { error in
                    completion(error == nil, error)
                }
            } else {
                self.save(archivedItems, forKey: "archivedItems") { error in
                    if let error = error {
                        completion(false, error)
                    } else {
                        // Post notification that an article was archived
                        NotificationCenter.default.post(
                            name: Notification.Name("archivedItemsUpdated"),
                            object: nil,
                            userInfo: ["link": normalizedLink, "action": "archive"]
                        )
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    /// Unarchive an article
    /// - Parameters:
    ///   - link: The URL of the article to unarchive
    ///   - completion: Called with success or error information
    func unarchiveArticle(link: String, completion: @escaping (Bool, Error?) -> Void) {
        // Use normalized link for consistency
        let normalizedLink = normalizeLink(link)
        
        load(forKey: "archivedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else {
                completion(false, NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage manager no longer exists"]))
                return
            }
            
            var archivedItems: [String] = []
            
            if case .success(let items) = result {
                archivedItems = items
            } else {
                // No archived items, nothing to unarchive
                completion(true, nil)
                return
            }
            
            // Check if not archived
            if !archivedItems.contains(where: { self.normalizeLink($0) == normalizedLink }) {
                // Not archived, return success
                completion(true, nil)
                return
            }
            
            // Remove from archived items
            archivedItems.removeAll { self.normalizeLink($0) == normalizedLink }
            
            // Save the updated list
            if self.method == .cloudKit {
                self.mergeAndSaveItems(archivedItems, forKey: "archivedItems") { error in
                    completion(error == nil, error)
                }
            } else {
                self.save(archivedItems, forKey: "archivedItems") { error in
                    if let error = error {
                        completion(false, error)
                    } else {
                        // Post notification that an article was unarchived
                        NotificationCenter.default.post(
                            name: Notification.Name("archivedItemsUpdated"),
                            object: nil,
                            userInfo: ["link": normalizedLink, "action": "unarchive"]
                        )
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    /// Check if an article is archived
    /// - Parameters:
    ///   - link: The URL of the article to check
    ///   - completion: Called with a boolean indicating whether the article is archived
    func isArticleArchived(link: String, completion: @escaping (Bool) -> Void) {
        // Use normalized link for consistency
        let normalizedLink = normalizeLink(link)
        
        load(forKey: "archivedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else {
                completion(false)
                return
            }
            
            if case .success(let items) = result {
                let isArchived = items.contains { self.normalizeLink($0) == normalizedLink }
                completion(isArchived)
            } else {
                completion(false)
            }
        }
    }
    
    /// Get all archived articles
    /// - Parameter completion: Called with the list of archived article URLs
    func getArchivedArticles(completion: @escaping (Result<[String], Error>) -> Void) {
        load(forKey: "archivedItems", completion: completion)
    }
    
    /// Get the folder that contains a specific feed
    func getFolderForFeed(feedURL: String, completion: @escaping (Result<FeedFolder?, Error>) -> Void) {
        getFolders { result in
            switch result {
            case .success(let folders):
                let normalizedURL = self.normalizeLink(feedURL)
                let containingFolder = folders.first { folder in
                    folder.feedURLs.contains { self.normalizeLink($0) == normalizedURL }
                }
                DispatchQueue.main.async {
                    completion(.success(containingFolder))
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Hierarchical Folder Management

    /// Get all hierarchical folders from storage
    func getHierarchicalFolders(completion: @escaping (Result<[HierarchicalFolder], Error>) -> Void) {
        print("DEBUG: Getting hierarchical folders from storage")

        // Try to load directly from UserDefaults first
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                let folders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                print("DEBUG: Successfully loaded \(folders.count) folders from UserDefaults")
                if !folders.isEmpty {
                    print("DEBUG: First folder: \(folders.first?.name ?? "unknown"), Root folders: \(folders.filter { $0.parentId == nil }.count)")
                }
                DispatchQueue.main.async {
                    completion(.success(folders))
                }
                return
            } catch {
                print("DEBUG: Error decoding folders from UserDefaults: \(error.localizedDescription)")
                // Continue to try loading from the storage system if UserDefaults fails
            }
        }

        // If UserDefaults doesn't have folders, try the storage system
        load(forKey: "hierarchicalFolders") { (result: Result<[HierarchicalFolder], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let folders):
                    print("DEBUG: Successfully loaded \(folders.count) folders from storage")
                    if !folders.isEmpty {
                        print("DEBUG: First folder: \(folders.first?.name ?? "unknown"), Root folders: \(folders.filter { $0.parentId == nil }.count)")
                    }
                    completion(.success(folders))
                case .failure(let error):
                    if case StorageError.notFound = error {
                        // If no folders are found, return an empty array
                        print("DEBUG: No folders found in storage (normal for first run)")
                        completion(.success([]))
                    } else {
                        print("DEBUG: Error loading folders: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    /// Create a new hierarchical folder
    func createHierarchicalFolder(name: String, parentId: String? = nil, completion: @escaping (Result<HierarchicalFolder, Error>) -> Void) {
        print("DEBUG: Creating hierarchical folder: '\(name)', parentId: \(parentId ?? "root")")

        // Always create folder directly without relying on existing folders
        var mutableFolders: [HierarchicalFolder] = []

        // Try to load existing folders from UserDefaults first
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                mutableFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                print("DEBUG-FOLDER: Loaded \(mutableFolders.count) existing folders from UserDefaults")
            } catch {
                print("DEBUG-FOLDER: Error decoding folders from UserDefaults: \(error.localizedDescription)")
                // Continue with empty array
            }
        }

        // Determine the sort index for the new folder
        var sortIndex = 0
        if let parentId = parentId {
            // For a subfolder, find the highest sort index of siblings and add 1
            let siblings = mutableFolders.filter { $0.parentId == parentId }
            print("DEBUG-FOLDER: Found \(siblings.count) sibling folders for parent \(parentId)")

            if let highestIndex = siblings.map({ $0.sortIndex }).max() {
                sortIndex = highestIndex + 1
                print("DEBUG-FOLDER: Using sort index \(sortIndex) based on siblings")
            } else {
                print("DEBUG-FOLDER: No siblings found, using sort index 0")
            }

            // Verify parent exists
            if !mutableFolders.contains(where: { $0.id == parentId }) {
                print("DEBUG-FOLDER: WARNING - Parent folder \(parentId) does not exist!")
            }
        } else {
            // For a root folder, find the highest sort index of root folders and add 1
            let rootFolders = mutableFolders.filter { $0.parentId == nil }
            print("DEBUG-FOLDER: Found \(rootFolders.count) root folders")

            if let highestIndex = rootFolders.map({ $0.sortIndex }).max() {
                sortIndex = highestIndex + 1
                print("DEBUG-FOLDER: Using sort index \(sortIndex) based on root folders")
            } else {
                print("DEBUG-FOLDER: No root folders found, using sort index 0")
            }
        }

        // Create new folder
        let newFolder = HierarchicalFolder(name: name, parentId: parentId, sortIndex: sortIndex)
        print("DEBUG-FOLDER: Created new folder with ID: \(newFolder.id)")
        mutableFolders.append(newFolder)

        // Log folders before saving
        print("DEBUG-FOLDER: Saving new folder \(newFolder.name) to storage. Total folders: \(mutableFolders.count)")

        // Save directly to UserDefaults for immediate local access
        if let encodedData = try? JSONEncoder().encode(mutableFolders) {
            print("DEBUG-FOLDER: Directly saving to UserDefaults")
            UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
            UserDefaults.standard.synchronize()
            print("DEBUG-FOLDER: UserDefaults synchronized")
        } else {
            print("DEBUG-FOLDER: Failed to encode folders for UserDefaults")
            completion(.failure(NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode folders"])))
            return
        }

        // Verify folder was saved in UserDefaults
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                let savedFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                let folderExists = savedFolders.contains(where: { $0.id == newFolder.id })
                print("DEBUG-FOLDER: Folder exists in UserDefaults after direct save: \(folderExists ? "YES" : "NO")")

                if !folderExists {
                    print("DEBUG-FOLDER: ERROR - Folder not found in UserDefaults after save!")
                    completion(.failure(NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Folder not found after save"])))
                    return
                }
            } catch {
                print("DEBUG-FOLDER: Error verifying folder in UserDefaults: \(error)")
            }
        }

        // Post notification immediately after successful UserDefaults save
        NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)

        // Also save to CloudKit if available
        if self.method == .cloudKit {
            print("DEBUG-FOLDER: Also saving to CloudKit")
            self.saveToCloudKit(mutableFolders, forKey: "hierarchicalFolders", retryCount: 3) { error in
                if let error = error {
                    print("DEBUG-FOLDER: Error saving folder to CloudKit: \(error.localizedDescription)")
                } else {
                    print("DEBUG-FOLDER: Successfully saved folder to CloudKit")
                }
            }
        }

        // Save to the storage system as well (redundant backup)
        print("DEBUG-FOLDER: Saving to storage system")
        self.save(mutableFolders, forKey: "hierarchicalFolders") { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                print("DEBUG-FOLDER: Error saving to storage system: \(error.localizedDescription)")
                // We already saved to UserDefaults, so we can still report success
                completion(.success(newFolder))
            } else {
                print("DEBUG-FOLDER: Successfully saved folder to storage system")

                // Double-check the folder is really there
                self.verifyFolderWasSaved(newFolder.id) { exists in
                    print("DEBUG-FOLDER: Final verification of saved folder: \(exists ? "EXISTS" : "NOT FOUND")")

                    // Even if verification fails, we know we saved to UserDefaults
                    completion(.success(newFolder))
                }
            }
        }
    }

    /// Verify a folder was successfully saved
    private func verifyFolderWasSaved(_ folderId: String, completion: @escaping (Bool) -> Void) {
        print("DEBUG: Verifying folder was saved: \(folderId)")

        // Check UserDefaults first
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                let folders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                if folders.contains(where: { $0.id == folderId }) {
                    print("DEBUG: Folder found in UserDefaults verification")
                    completion(true)
                    return
                } else {
                    print("DEBUG: Folder NOT found in UserDefaults verification")
                }
            } catch {
                print("DEBUG: Error decoding folders during verification: \(error)")
            }
        } else {
            print("DEBUG: No folder data in UserDefaults during verification")
        }

        // Check StorageManager as backup
        self.getHierarchicalFolders { result in
            switch result {
            case .success(let folders):
                let exists = folders.contains(where: { $0.id == folderId })
                print("DEBUG: Folder exists in StorageManager verification: \(exists)")
                completion(exists)
            case .failure(let error):
                print("DEBUG: Error verifying folder in StorageManager: \(error.localizedDescription)")
                completion(false)
            }
        }
    }

    /// Update an existing hierarchical folder
    func updateHierarchicalFolder(_ folder: HierarchicalFolder, completion: @escaping (Result<Bool, Error>) -> Void) {
        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                // Find and update the folder
                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    // Normalize feed URLs in the updated folder
                    var normalizedFolder = folder
                    normalizedFolder.feedURLs = folder.feedURLs.map { self.normalizeLink($0) }

                    // Prevent circular hierarchies by checking if the new parent is itself or one of its descendants
                    if let newParentId = normalizedFolder.parentId {
                        if newParentId == folder.id {
                            completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "A folder cannot be its own parent"])))
                            return
                        }

                        // Check if new parent is a descendant of this folder
                        let descendants = FolderManager.getAllDescendantFolders(from: folders, forFolderId: folder.id)
                        if descendants.contains(where: { $0.id == newParentId }) {
                            completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "Cannot create circular folder references"])))
                            return
                        }
                    }

                    folders[index] = normalizedFolder

                    // Save updated folders list
                    self.save(folders, forKey: "hierarchicalFolders") { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                completion(.success(true))

                                // Post notification that folders have been updated
                                NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Delete a hierarchical folder
    func deleteHierarchicalFolder(id: String, deleteSubfolders: Bool = false, completion: @escaping (Result<Bool, Error>) -> Void) {
        print("DEBUG: Deleting folder with ID: \(id), deleteSubfolders: \(deleteSubfolders)")

        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                print("DEBUG: Found \(folders.count) folders before deletion")
                print("DEBUG: Current folders: \(folders.map { "\($0.name) (ID: \($0.id))" })")

                // Get descendants of this folder
                let descendants = FolderManager.getAllDescendantFolders(from: folders, forFolderId: id)
                print("DEBUG: Found \(descendants.count) descendants for folder ID: \(id)")

                if !deleteSubfolders && !descendants.isEmpty {
                    // If we're not deleting subfolders and there are descendants, return an error
                    print("DEBUG: Cannot delete folder with subfolders unless deleteSubfolders is true")
                    completion(.failure(NSError(domain: "StorageManager", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "Folder has subfolders. Set deleteSubfolders to true to delete them or move them first."])))
                    return
                }

                let foldersCountBefore = folders.count

                // Remove the folder and its descendants if requested
                if deleteSubfolders {
                    // Delete folder and all descendants
                    let folderIdsToDelete = [id] + descendants.map { $0.id }
                    print("DEBUG: Deleting folder IDs: \(folderIdsToDelete)")
                    folders.removeAll { folderIdsToDelete.contains($0.id) }
                } else {
                    // Just delete the folder
                    print("DEBUG: Deleting just folder ID: \(id)")
                    folders.removeAll { $0.id == id }
                }

                let foldersCountAfter = folders.count
                print("DEBUG: Deleted \(foldersCountBefore - foldersCountAfter) folders")
                print("DEBUG: Remaining folders: \(folders.map { "\($0.name) (ID: \($0.id))" })")

                // Save directly to UserDefaults for immediate local access
                if let encodedData = try? JSONEncoder().encode(folders) {
                    print("DEBUG: Directly saving updated folders to UserDefaults after deletion")
                    UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                    UserDefaults.standard.synchronize()
                }

                // Save updated folders list
                self.save(folders, forKey: "hierarchicalFolders") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("DEBUG: Error saving updated folders after deletion: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else {
                            print("DEBUG: Successfully saved updated folders after deletion")

                            // Verify the deletion in UserDefaults
                            if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
                                do {
                                    let savedFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                                    let folderStillExists = savedFolders.contains(where: { $0.id == id })
                                    print("DEBUG: After deletion, folder still exists in UserDefaults: \(folderStillExists)")

                                    if folderStillExists {
                                        print("DEBUG: WARNING - UserDefaults deletion failed, trying again")
                                        // If folder still exists, try saving to UserDefaults again
                                        if let encodedData = try? JSONEncoder().encode(folders) {
                                            UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                                            UserDefaults.standard.synchronize()
                                        }
                                    }
                                } catch {
                                    print("DEBUG: Error checking UserDefaults after deletion: \(error)")
                                }
                            }

                            completion(.success(true))

                            // Post notification that folders have been updated
                            print("DEBUG: Posting hierarchicalFoldersUpdated notification after deletion")
                            NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                        }
                    }
                }
            case .failure(let error):
                print("DEBUG: Error getting folders for deletion: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Add a feed to a hierarchical folder
    func addFeedToHierarchicalFolder(feedURL: String, folderId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        print("DEBUG: Adding feed URL: \(feedURL) to folder: \(folderId)")
        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                // Find the folder
                if let index = folders.firstIndex(where: { $0.id == folderId }) {
                    print("DEBUG: Found folder at index \(index): \(folders[index].name)")

                    // Add feed to folder if it's not already there
                    let normalizedURL = self.normalizeLink(feedURL)
                    print("DEBUG: Normalized feed URL: \(normalizedURL)")

                    // Check if the feed is already in the folder (using normalized URLs)
                    let normalizedFolderURLs = folders[index].feedURLs.map { self.normalizeLink($0) }
                    print("DEBUG: Current folder has \(normalizedFolderURLs.count) feeds")

                    if !normalizedFolderURLs.contains(normalizedURL) {
                        print("DEBUG: Adding feed to folder")
                        folders[index].feedURLs.append(normalizedURL)

                        // Save directly to UserDefaults for immediate local access
                        if let encodedData = try? JSONEncoder().encode(folders) {
                            print("DEBUG: Directly saving updated folders to UserDefaults")
                            UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                            UserDefaults.standard.synchronize()
                        }

                        // Save updated folders list
                        self.save(folders, forKey: "hierarchicalFolders") { error in
                            DispatchQueue.main.async {
                                if let error = error {
                                    print("DEBUG: Error saving updated folders: \(error.localizedDescription)")
                                    completion(.failure(error))
                                } else {
                                    print("DEBUG: Successfully saved updated folders")
                                    completion(.success(true))

                                    // Post notification that folders have been updated
                                    print("DEBUG: Posting hierarchicalFoldersUpdated notification")
                                    NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                                }
                            }
                        }
                    } else {
                        // Feed already in folder
                        print("DEBUG: Feed already in folder")
                        DispatchQueue.main.async {
                            completion(.success(true))
                        }
                    }
                } else {
                    print("DEBUG: Folder not found")
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                print("DEBUG: Error loading folders: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Remove a feed from a hierarchical folder
    func removeFeedFromHierarchicalFolder(feedURL: String, folderId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                // Find the folder
                if let index = folders.firstIndex(where: { $0.id == folderId }) {
                    // Remove feed from folder using normalized URLs for comparison
                    let normalizedURL = self.normalizeLink(feedURL)
                    folders[index].feedURLs.removeAll { self.normalizeLink($0) == normalizedURL }

                    // Save updated folders list
                    self.save(folders, forKey: "hierarchicalFolders") { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                completion(.success(true))

                                // Post notification that folders have been updated
                                NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Remove multiple feeds from a hierarchical folder at once
    func bulkRemoveFeedsFromHierarchicalFolder(feedURLs: [String], folderId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        print("DEBUG: Bulk removing \(feedURLs.count) feeds from folder ID: \(folderId)")

        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                // Find the folder
                if let index = folders.firstIndex(where: { $0.id == folderId }) {
                    print("DEBUG: Found folder at index \(index): \(folders[index].name)")
                    print("DEBUG: Current feed count: \(folders[index].feedURLs.count)")

                    // Normalize URLs for consistent comparison
                    let normalizedURLsToRemove = Set(feedURLs.map { self.normalizeLink($0) })
                    print("DEBUG: Removing normalized URLs: \(normalizedURLsToRemove)")

                    // Filter out the feeds to be removed
                    let originalCount = folders[index].feedURLs.count
                    folders[index].feedURLs.removeAll { normalizedURLsToRemove.contains(self.normalizeLink($0)) }
                    let newCount = folders[index].feedURLs.count
                    let removedCount = originalCount - newCount

                    print("DEBUG: Removed \(removedCount) feeds, new count: \(newCount)")

                    // Save directly to UserDefaults for immediate local access
                    if let encodedData = try? JSONEncoder().encode(folders) {
                        print("DEBUG: Directly saving updated folders to UserDefaults")
                        UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                        UserDefaults.standard.synchronize()
                    }

                    // Save updated folders list
                    self.save(folders, forKey: "hierarchicalFolders") { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("DEBUG: Error saving updated folders: \(error.localizedDescription)")
                                completion(.failure(error))
                            } else {
                                print("DEBUG: Successfully saved updated folders")
                                completion(.success(true))

                                // Post notification that folders have been updated
                                print("DEBUG: Posting hierarchicalFoldersUpdated notification")
                                NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    print("DEBUG: Folder not found")
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                print("DEBUG: Error loading folders: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Add multiple feeds to a hierarchical folder at once
    func bulkAddFeedsToHierarchicalFolder(feedURLs: [String], folderId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        print("DEBUG: Bulk adding \(feedURLs.count) feeds to folder ID: \(folderId)")

        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                // Find the folder
                if let index = folders.firstIndex(where: { $0.id == folderId }) {
                    print("DEBUG: Found folder at index \(index): \(folders[index].name)")
                    print("DEBUG: Current feed count: \(folders[index].feedURLs.count)")

                    // Normalize all URLs for consistent comparison
                    let normalizedURLs = feedURLs.map { self.normalizeLink($0) }
                    print("DEBUG: Normalized feed URLs: \(normalizedURLs)")

                    // Filter out already existing feeds
                    let existingURLs = Set(folders[index].feedURLs.map { self.normalizeLink($0) })
                    let newURLs = normalizedURLs.filter { !existingURLs.contains($0) }

                    print("DEBUG: New URLs to add: \(newURLs.count) of \(normalizedURLs.count)")

                    // Add new URLs to folder
                    folders[index].feedURLs.append(contentsOf: newURLs)

                    // Save directly to UserDefaults for immediate local access
                    if let encodedData = try? JSONEncoder().encode(folders) {
                        print("DEBUG: Directly saving updated folders to UserDefaults")
                        UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                        UserDefaults.standard.synchronize()
                    }

                    // Save updated folders list
                    self.save(folders, forKey: "hierarchicalFolders") { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("DEBUG: Error saving updated folders: \(error.localizedDescription)")
                                completion(.failure(error))
                            } else {
                                print("DEBUG: Successfully saved updated folders")
                                completion(.success(true))

                                // Post notification that folders have been updated
                                print("DEBUG: Posting hierarchicalFoldersUpdated notification")
                                NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    print("DEBUG: Folder not found")
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    }
                }
            case .failure(let error):
                print("DEBUG: Error loading folders: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Get all feeds in a specific hierarchical folder and optionally its subfolders
    func getFeedsInHierarchicalFolder(folderId: String, includeSubfolders: Bool = false, completion: @escaping (Result<[RSSFeed], Error>) -> Void) {
        print("DEBUG: Getting feeds in hierarchical folder: \(folderId), includeSubfolders: \(includeSubfolders)")

        // Try to get folders directly from UserDefaults first for faster access
        var folder: HierarchicalFolder?
        var folders: [HierarchicalFolder] = []

        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                folders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                print("DEBUG: Decoded \(folders.count) folders from UserDefaults")
                print("DEBUG: All folder IDs: \(folders.map { $0.id })")

                folder = folders.first(where: { $0.id == folderId })
                print("DEBUG: Found folder from UserDefaults: \(folder?.name ?? "not found")")

                if let f = folder {
                    print("DEBUG: Folder contains \(f.feedURLs.count) feeds")
                    print("DEBUG: Feed URLs: \(f.feedURLs)")

                    // Check if feeds are normalized
                    let normalizedURLs = f.feedURLs.map { normalizeLink($0) }
                    print("DEBUG: Normalized Feed URLs: \(normalizedURLs)")

                    // Check for differences after normalization
                    if Set(f.feedURLs) != Set(normalizedURLs) {
                        print("DEBUG: WARNING - Some feed URLs are not normalized")
                        let differences = Set(f.feedURLs).symmetricDifference(Set(normalizedURLs))
                        print("DEBUG: Differences: \(differences)")
                    }
                }
            } catch {
                print("DEBUG: Error decoding folders from UserDefaults: \(error)")
            }
        } else {
            print("DEBUG: No hierarchical folders data found in UserDefaults")
        }

        if folder == nil {
            // If not found in UserDefaults, try getting from the storage system
            print("DEBUG: Folder not found in UserDefaults, trying StorageManager")
            getHierarchicalFolders { [weak self] foldersResult in
                guard let self = self else { return }

                switch foldersResult {
                case .success(let loadedFolders):
                    print("DEBUG: Loaded \(loadedFolders.count) folders from StorageManager")
                    print("DEBUG: All folder IDs from StorageManager: \(loadedFolders.map { $0.id })")

                    // Find the folder
                    if let folder = loadedFolders.first(where: { $0.id == folderId }) {
                        print("DEBUG: Found folder in StorageManager: \(folder.name) with \(folder.feedURLs.count) feeds")
                        self.getFeedsForFolder(folder, folders: loadedFolders, includeSubfolders: includeSubfolders, completion: completion)
                    } else {
                        print("DEBUG: Folder not found in StorageManager")
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                        }
                    }
                case .failure(let error):
                    print("DEBUG: Error loading folders from StorageManager: \(error)")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        } else {
            // Found in UserDefaults, proceed with loaded folder
            print("DEBUG: Using folder from UserDefaults")
            getFeedsForFolder(folder!, folders: folders, includeSubfolders: includeSubfolders, completion: completion)
        }
    }

    private func getFeedsForFolder(_ folder: HierarchicalFolder, folders: [HierarchicalFolder], includeSubfolders: Bool, completion: @escaping (Result<[RSSFeed], Error>) -> Void) {
        print("DEBUG: Getting feeds for folder: \(folder.name) (ID: \(folder.id))")

        // Get feed URLs in this folder and, if requested, its subfolders
        var feedURLs: [String] = folder.feedURLs

        print("DEBUG: Initial feed URLs in folder: \(feedURLs)")

        if includeSubfolders {
            print("DEBUG: Including subfolders")

            // Find direct subfolders first for debugging
            let directSubfolders = folders.filter { $0.parentId == folder.id }
            print("DEBUG: Direct subfolder count: \(directSubfolders.count)")
            if !directSubfolders.isEmpty {
                print("DEBUG: Direct subfolder names: \(directSubfolders.map { $0.name })")
                for subFolder in directSubfolders {
                    print("DEBUG: Subfolder \(subFolder.name) has \(subFolder.feedURLs.count) feeds")
                }
            }

            // Add feeds from subfolders
            let subfolderFeeds = FolderManager.getAllFeeds(from: folders, forFolderId: folder.id)
            print("DEBUG: Found \(subfolderFeeds.count) feeds in subfolders")
            feedURLs.append(contentsOf: subfolderFeeds)

            // Ensure URLs are unique
            let beforeDeduplication = feedURLs.count
            feedURLs = Array(Set(feedURLs))
            let afterDeduplication = feedURLs.count

            if beforeDeduplication != afterDeduplication {
                print("DEBUG: Removed \(beforeDeduplication - afterDeduplication) duplicate feed URLs")
            }
        }

        print("DEBUG: Total feed URLs to load: \(feedURLs.count)")
        print("DEBUG: Feed URLs: \(feedURLs)")

        // Normalize all URLs for consistency
        let normalizedFeedURLs = feedURLs.map { normalizeLink($0) }
        print("DEBUG: Normalized feed URLs: \(normalizedFeedURLs)")

        // Load all feeds
        self.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let allFeeds):
                    print("DEBUG: Loaded \(allFeeds.count) feeds from system")

                    // Filter feeds that are in the folder or its subfolders
                    let folderFeeds = allFeeds.filter { feed in
                        let normalizedFeedURL = self.normalizeLink(feed.url)
                        let isInFolder = normalizedFeedURLs.contains(normalizedFeedURL)
                        if isInFolder {
                            print("DEBUG: Found matching feed: \(feed.title) - \(feed.url)")
                        }
                        return isInFolder
                    }

                    print("DEBUG: Filtered to \(folderFeeds.count) feeds in folder")

                    // Print missing feeds for debugging
                    if folderFeeds.count < feedURLs.count {
                        print("DEBUG: Some feeds in folder were not found in the system")
                        let foundURLs = folderFeeds.map { self.normalizeLink($0.url) }
                        let missingURLs = normalizedFeedURLs.filter { !foundURLs.contains($0) }
                        print("DEBUG: Missing feed URLs: \(missingURLs)")

                        // Check if all feeds in system's database
                        let allFeedURLs = allFeeds.map { self.normalizeLink($0.url) }
                        for missingURL in missingURLs {
                            let isInSystem = allFeedURLs.contains(missingURL)
                            print("DEBUG: Missing URL '\(missingURL)' exists in system database: \(isInSystem ? "YES" : "NO")")
                        }
                    }

                    completion(.success(folderFeeds))
                case .failure(let error):
                    print("DEBUG: Error loading RSS feeds: \(error)")
                    completion(.failure(error))
                }
            }
        }
    }

    /// Move a hierarchical folder to a new parent
    func moveHierarchicalFolder(folderId: String, toParentId: String?, completion: @escaping (Result<Bool, Error>) -> Void) {
        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                // Find the folder to move
                guard let folderIndex = folders.firstIndex(where: { $0.id == folderId }) else {
                    completion(.failure(NSError(domain: "StorageManager", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    return
                }

                var folder = folders[folderIndex]

                // Ensure we're not creating a circular hierarchy
                if let newParentId = toParentId {
                    // Can't move to itself
                    if newParentId == folderId {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "A folder cannot be its own parent"])))
                        return
                    }

                    // Check if new parent exists
                    guard folders.contains(where: { $0.id == newParentId }) else {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Parent folder not found"])))
                        return
                    }

                    // Check if new parent is a descendant of this folder
                    let descendants = FolderManager.getAllDescendantFolders(from: folders, forFolderId: folderId)
                    if descendants.contains(where: { $0.id == newParentId }) {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Cannot create circular folder references"])))
                        return
                    }
                }

                // Update the folder's parent
                folder.parentId = toParentId

                // Determine the new sort index
                var sortIndex = 0
                if let parentId = toParentId {
                    // For a subfolder, find the highest sort index of siblings and add 1
                    let siblings = folders.filter { $0.parentId == parentId }
                    if let highestIndex = siblings.map({ $0.sortIndex }).max() {
                        sortIndex = highestIndex + 1
                    }
                } else {
                    // For a root folder, find the highest sort index of root folders and add 1
                    let rootFolders = folders.filter { $0.parentId == nil }
                    if let highestIndex = rootFolders.map({ $0.sortIndex }).max() {
                        sortIndex = highestIndex + 1
                    }
                }

                folder.sortIndex = sortIndex
                folders[folderIndex] = folder

                // Save updated folders list
                self.save(folders, forKey: "hierarchicalFolders") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(true))

                            // Post notification that folders have been updated
                            NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Reorder a hierarchical folder
    func reorderHierarchicalFolder(folderId: String, newSortIndex: Int, completion: @escaping (Result<Bool, Error>) -> Void) {
        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(var folders):
                // Find the folder to reorder
                guard let folderIndex = folders.firstIndex(where: { $0.id == folderId }) else {
                    completion(.failure(NSError(domain: "StorageManager", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "Folder not found"])))
                    return
                }

                var folder = folders[folderIndex]

                // Update the sort index
                folder.sortIndex = newSortIndex
                folders[folderIndex] = folder

                // Save updated folders list
                self.save(folders, forKey: "hierarchicalFolders") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(true))

                            // Post notification that folders have been updated
                            NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Import existing flat folders into the hierarchical structure
    func importFlatFoldersToHierarchical(completion: @escaping (Result<Bool, Error>) -> Void) {
        // Get existing flat folders
        getFolders { [weak self] flatFoldersResult in
            guard let self = self else { return }

            switch flatFoldersResult {
            case .success(let flatFolders):
                if flatFolders.isEmpty {
                    completion(.success(true)) // No folders to import
                    return
                }

                // Get existing hierarchical folders
                self.getHierarchicalFolders { hierarchicalFoldersResult in
                    switch hierarchicalFoldersResult {
                    case .success(var hierarchicalFolders):
                        // Convert each flat folder to a hierarchical one
                        for (index, flatFolder) in flatFolders.enumerated() {
                            // Skip if a folder with this name already exists
                            if hierarchicalFolders.contains(where: { $0.name == flatFolder.name }) {
                                continue
                            }

                            // Create a new hierarchical folder
                            let newFolder = HierarchicalFolder(
                                name: flatFolder.name,
                                parentId: nil,
                                feedURLs: flatFolder.feedURLs,
                                sortIndex: index
                            )

                            hierarchicalFolders.append(newFolder)
                        }

                        // Save the updated hierarchical folders
                        self.save(hierarchicalFolders, forKey: "hierarchicalFolders") { error in
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                                completion(.success(true))
                            }
                        }

                    case .failure(let error):
                        completion(.failure(error))
                    }
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // Sync hierarchical folders from CloudKit

    // MARK: - Reading Progress Management
    
    /// Save reading progress for an article
    func saveReadingProgress(for link: String, progress: Float, completion: @escaping (Bool, Error?) -> Void) {
        let normalizedLink = normalizeLink(link)
        let readingProgress = ReadingProgress(link: normalizedLink, progress: progress)
        
        // Get existing reading progress data
        load(forKey: "readingProgress") { [weak self] (result: Result<[ReadingProgress], Error>) in
            guard let self = self else {
                completion(false, NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Storage manager no longer exists"]))
                return
            }
            
            var progressItems: [ReadingProgress] = []
            
            if case .success(let existingItems) = result {
                progressItems = existingItems
            }
            
            // Remove existing progress for this article if it exists
            progressItems.removeAll { self.normalizeLink($0.link) == normalizedLink }
            
            // Only add progress if it's greater than 0 (to save space)
            if progress > 0 {
                // Add the new progress
                progressItems.append(readingProgress)
            }
            
            // Limit to most recent 500 items to prevent excessive storage use
            if progressItems.count > 500 {
                progressItems.sort { $0.lastReadDate > $1.lastReadDate }
                progressItems = Array(progressItems.prefix(500))
            }
            
            // Save the updated list
            self.save(progressItems, forKey: "readingProgress") { error in
                if let error = error {
                    completion(false, error)
                } else {
                    // Post notification that reading progress was updated
                    NotificationCenter.default.post(
                        name: Notification.Name("ReadingProgressUpdated"),
                        object: nil,
                        userInfo: ["link": normalizedLink, "progress": progress]
                    )
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Get reading progress for an article
    func getReadingProgress(for link: String, completion: @escaping (Result<Float, Error>) -> Void) {
        let normalizedLink = normalizeLink(link)
        
        load(forKey: "readingProgress") { (result: Result<[ReadingProgress], Error>) in
            switch result {
            case .success(let progressItems):
                if let item = progressItems.first(where: { self.normalizeLink($0.link) == normalizedLink }) {
                    completion(.success(item.progress))
                } else {
                    // No progress recorded for this article
                    completion(.success(0))
                }
            case .failure:
                // If there's an error or no data, return 0 progress
                completion(.success(0))
            }
        }
    }
    
    /// Get all reading progress items
    func getAllReadingProgress(completion: @escaping (Result<[ReadingProgress], Error>) -> Void) {
        load(forKey: "readingProgress", completion: completion)
    }
    
    /// Clear reading progress for an article
    func clearReadingProgress(for link: String, completion: @escaping (Bool, Error?) -> Void) {
        saveReadingProgress(for: link, progress: 0, completion: completion)
    }
    
    /// Clear all reading progress
    func clearAllReadingProgress(completion: @escaping (Bool, Error?) -> Void) {
        // Save an empty array to clear all progress
        save([ReadingProgress](), forKey: "readingProgress") { error in
            if let error = error {
                completion(false, error)
            } else {
                // Post notification that all reading progress was cleared
                NotificationCenter.default.post(
                    name: Notification.Name("AllReadingProgressCleared"),
                    object: nil
                )
                completion(true, nil)
            }
        }
    }
}
