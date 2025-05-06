import CloudKit
import Foundation
import UIKit

enum StorageMethod {
    case userDefaults, cloudKit
}

enum StorageError: Error {
    case notFound
    case decodingFailed(Error)
    case encodingFailed(Error)
    case cloudKitError(Error)
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
                completion(.failure(error))
            }
        } else {
            completion(.failure(StorageError.notFound))
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

/// Singleton that provides a unified interface for storage.
class StorageManager {
    // MARK: - Properties

    static let shared = StorageManager()
    
    // Flags for state tracking
    private var hasSyncedOnLaunch = false
    private var hasSetupSubscriptions = false
    
    // Sync items types
    private enum SyncItemType: String {
        case readItems
        case bookmarkedItems
        case heartedItems
        case feedFolders
    }

    var method: StorageMethod = .userDefaults {
        didSet {
            if method == .cloudKit && !hasSetupSubscriptions {
                setupCloudKitSubscriptions()
            }
        }
    }

    private var storage: ArticleStorage {
        switch method {
        case .userDefaults: return UserDefaultsStorage()
        case .cloudKit: return CloudKitStorage()
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
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
        if method == .cloudKit {
            syncFromCloudKit()
        }
    }
    
    // MARK: - CloudKit Sync
    
    func syncFromCloudKit(completion: ((Bool) -> Void)? = nil) {
        guard method == .cloudKit else {
            completion?(false)
            return
        }
        
        let syncGroup = DispatchGroup()
        var syncSuccess = true
        
        // Sync all item types
        for itemType in [SyncItemType.readItems, .bookmarkedItems, .heartedItems, .feedFolders] {
            syncGroup.enter()
            syncItemsFromCloud(type: itemType) { success in
                if !success {
                    syncSuccess = false
                }
                syncGroup.leave()
            }
        }
        
        // Final callback after all syncs complete
        syncGroup.notify(queue: .main) {
            self.hasSyncedOnLaunch = true
            completion?(syncSuccess)
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
        if method == .cloudKit, let items = value as? [String] {
            switch key {
            case "readItems", "bookmarkedItems", "heartedItems":
                mergeAndSaveItems(items, forKey: key, completion: completion)
                return
            default:
                break
            }
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
}