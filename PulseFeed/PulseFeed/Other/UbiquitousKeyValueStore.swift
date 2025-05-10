import Foundation

/// A wrapper class for NSUbiquitousKeyValueStore with methods for synchronizing with UserDefaults
/// This class provides an easy interface for storing small amounts of data in iCloud Key-Value storage
class UbiquitousKeyValueStore {
    // Singleton instance
    static let shared = UbiquitousKeyValueStore()
    
    // Notification name for KV store changes
    static let didChangeExternallyNotification = Notification.Name("UbiquitousKeyValueStoreDidChangeExternally")
    
    // The underlying iCloud Key-Value store
    private let store = NSUbiquitousKeyValueStore.default
    
    // Dictionary to keep track of synced keys
    private var syncedKeys = Set<String>()
    
    // MARK: - Initialization
    
    private init() {
        // Set up notification observer for changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        
        // Start syncing with iCloud
        store.synchronize()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Sync Methods
    
    /// Synchronize the store with iCloud
    @discardableResult
    func synchronize() -> Bool {
        return store.synchronize()
    }
    
    /// Register a key for synchronization between UserDefaults and iCloud
    func registerKeyForSync(_ key: String) {
        syncedKeys.insert(key)
    }
    
    /// Register multiple keys for synchronization
    func registerKeysForSync(_ keys: [String]) {
        for key in keys {
            registerKeyForSync(key)
        }
    }
    
    /// Sync a specific key from UserDefaults to iCloud
    func syncToCloud(key: String) {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        store.set(data, forKey: key)
        store.synchronize()
    }
    
    /// Sync a specific key from iCloud to UserDefaults
    func syncFromCloud(key: String) {
        // Check if the key exists in the store
        if store.data(forKey: key) != nil {
            // Data exists, sync it to UserDefaults
            guard let data = store.data(forKey: key) else { return }
            UserDefaults.standard.set(data, forKey: key)
        } else if store.string(forKey: key) != nil {
            // String value exists
            let value = store.string(forKey: key)
            UserDefaults.standard.set(value, forKey: key)
        } else if store.bool(forKey: key) != false || key.hasSuffix("Enabled") || key.hasSuffix("Disabled") {
            // Boolean value exists or key suggests boolean
            let value = store.bool(forKey: key)
            UserDefaults.standard.set(value, forKey: key)
        } else if store.double(forKey: key) != 0 {
            // Double value exists
            let value = store.double(forKey: key)
            UserDefaults.standard.set(value, forKey: key)
        } else if store.longLong(forKey: key) != 0 {
            // Integer value exists
            let value = store.longLong(forKey: key)
            UserDefaults.standard.set(value, forKey: key)
        }
        // If none of the above conditions match, there's no data to sync
    }
    
    /// Sync all registered keys to iCloud
    func syncAllToCloud() {
        for key in syncedKeys {
            syncToCloud(key: key)
        }
    }
    
    /// Sync all registered keys from iCloud
    func syncAllFromCloud() {
        for key in syncedKeys {
            syncFromCloud(key: key)
        }
    }
    
    // MARK: - Key-Value Store Operations
    
    /// Set a value in both UserDefaults and iCloud
    func set(_ data: Data, forKey key: String) {
        // Store in UserDefaults
        UserDefaults.standard.set(data, forKey: key)
        
        // Store in iCloud
        store.set(data, forKey: key)
        store.synchronize()
        
        // Register for future syncing
        registerKeyForSync(key)
    }
    
    /// Get a value from the key-value store, preferring iCloud but falling back to UserDefaults
    func data(forKey key: String) -> Data? {
        // First try to get from iCloud
        if let data = store.data(forKey: key) {
            // Make sure UserDefaults is up to date
            UserDefaults.standard.set(data, forKey: key)
            return data
        }
        
        // Fall back to UserDefaults
        return UserDefaults.standard.data(forKey: key)
    }
    
    /// Remove a value from both UserDefaults and iCloud
    func removeValue(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        store.removeObject(forKey: key)
        store.synchronize()
    }
    
    // MARK: - Type-specific convenience methods
    
    /// Get a boolean value from storage
    func bool(forKey key: String) -> Bool {
        return store.bool(forKey: key)
    }
    
    /// Set a boolean value in storage
    func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        store.set(value, forKey: key)
        store.synchronize()
        registerKeyForSync(key)
    }
    
    /// Get a string value from storage
    func string(forKey key: String) -> String? {
        return store.string(forKey: key)
    }
    
    /// Set a string value in storage
    func set(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        store.set(value, forKey: key)
        store.synchronize()
        registerKeyForSync(key)
    }
    
    /// Get a double value from storage
    func double(forKey key: String) -> Double {
        return store.double(forKey: key)
    }
    
    /// Set a double value in storage
    func set(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        store.set(value, forKey: key)
        store.synchronize()
        registerKeyForSync(key)
    }
    
    /// Get a float value from storage
    func float(forKey key: String) -> Float {
        return Float(store.double(forKey: key))
    }
    
    /// Set a float value in storage
    func set(_ value: Float, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        store.set(Double(value), forKey: key)
        store.synchronize()
        registerKeyForSync(key)
    }
    
    /// Get an integer value from storage
    func integer(forKey key: String) -> Int {
        return Int(store.longLong(forKey: key))
    }
    
    /// Set an integer value in storage
    func set(_ value: Int, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        store.set(Int64(value), forKey: key)
        store.synchronize()
        registerKeyForSync(key)
    }
    
    /// Save a Codable object to both UserDefaults and iCloud
    func save<T: Encodable>(_ value: T, forKey key: String, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(value)
            set(data, forKey: key)
            completion(nil)
        } catch {
            completion(error)
        }
    }
    
    /// Load a Codable object from storage, preferring iCloud but falling back to UserDefaults
    func load<T: Decodable>(forKey key: String, completion: @escaping (Result<T, Error>) -> Void) {
        // Get data from storage
        guard let data = self.data(forKey: key) else {
            if T.self == [Tag].self || T.self == [TaggedItem].self || 
               T.self == [String].self || T.self == [RSSFeed].self {
                print("DEBUG: UbiquitousKeyValueStore - No data for \(key), returning empty array")
                completion(.success([] as! T))
            } else {
                completion(.failure(StorageError.notFound))
            }
            return
        }
        
        // Decode the data
        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            completion(.success(value))
        } catch {
            // For collection types, return empty array on decoding error
            if T.self == [Tag].self || T.self == [TaggedItem].self || 
               T.self == [String].self || T.self == [RSSFeed].self {
                print("DEBUG: UbiquitousKeyValueStore - Failed to decode \(key), returning empty array")
                completion(.success([] as! T))
            } else {
                completion(.failure(StorageError.decodingFailed(error)))
            }
        }
    }
    
    // MARK: - Notification Handling
    
    @objc private func storeDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }
        
        // Update UserDefaults for each changed key
        for key in changedKeys {
            if syncedKeys.contains(key), let data = store.data(forKey: key) {
                UserDefaults.standard.set(data, forKey: key)
                // Post notification about the changed key
                NotificationCenter.default.post(
                    name: UbiquitousKeyValueStore.didChangeExternallyNotification,
                    object: nil,
                    userInfo: ["key": key]
                )
            }
        }
    }
}