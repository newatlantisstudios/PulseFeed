import CloudKit
import Foundation

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
        do {
            let data = try JSONEncoder().encode(value)
            print(
                "CloudKitStorage: Attempting to save data for key '\(key)' with size \(data.count) bytes."
            )
            database.fetch(withRecordID: recordID) { record, error in
                if let record = record {
                    record[key] = data as CKRecordValue
                    self.database.save(record) { _, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print(
                                    "CloudKitStorage: Error saving data for key '\(key)': \(error.localizedDescription)"
                                )
                            } else {
                                print(
                                    "CloudKitStorage: Successfully saved data for key '\(key)'."
                                )
                            }
                            completion(error)
                        }
                    }
                } else {
                    let newRecord = CKRecord(
                        recordType: "RSSFeeds", recordID: self.recordID)
                    newRecord[key] = data as CKRecordValue
                    self.database.save(newRecord) { _, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print(
                                    "CloudKitStorage: Error creating new record for key '\(key)': \(error.localizedDescription)"
                                )
                            } else {
                                print(
                                    "CloudKitStorage: Successfully created new record and saved data for key '\(key)'."
                                )
                            }
                            completion(error)
                        }
                    }
                }
            }
        } catch {
            print(
                "CloudKitStorage: Error encoding data for key '\(key)': \(error.localizedDescription)"
            )
            completion(error)
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

    var method: StorageMethod = .userDefaults {
        didSet {
            print("DEBUG: StorageManager method set to: \(method)")
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
    
    func markAllAsRead(completion: @escaping (Bool, Error?) -> Void) {
        // 1. Update local storage (UserDefaults)
        UserDefaults.standard.set(true, forKey: "allItemsRead")
        
        // 2. Check if iCloud syncing is enabled
        let iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        guard iCloudSyncEnabled else {
            // If iCloud sync is disabled, complete after updating local storage.
            completion(true, nil)
            return
        }
        
        // 3. Proceed with CloudKit sync if enabled.
        let container = CKContainer.default()
        let publicDB = container.publicCloudDatabase
        let predicate = NSPredicate(value: true) // Adjust this predicate as needed.
        let query = CKQuery(recordType: "FeedItem", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { records, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            guard let records = records, !records.isEmpty else {
                completion(true, nil)
                return
            }
            
            // Update the "isRead" flag for each record.
            for record in records {
                record["isRead"] = true as CKRecordValue
            }
            
            let modifyOperation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, operationError in
                if let operationError = operationError {
                    completion(false, operationError)
                } else {
                    completion(true, nil)
                }
            }
            publicDB.add(modifyOperation)
        }
    }

    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void) {
        print("DEBUG: Saving data for key '\(key)' using \(method)")
        storage.save(value, forKey: key, completion: completion)
    }

    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void) {
        print("DEBUG: Loading data for key '\(key)' using \(method)")
        storage.load(forKey: key, completion: completion)
    }
}

// MARK: - ArticleSummary Model
struct ArticleSummary: Codable {
    let title: String
    let link: String
    let pubDate: String
}
