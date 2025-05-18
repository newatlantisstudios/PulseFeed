import Foundation
import UIKit

// Make ReadStatusTracker a public class so it can be seen by other files
public class ReadStatusTracker {
    public static let shared = ReadStatusTracker()
    
    // Sets to track read status by normalized link
    private var readLinks: Set<String> = []
    
    // Storage key
    private let storageKey = "readItems"
    
    // Device identifier for debugging
    private let deviceId: String = {
        #if targetEnvironment(macCatalyst)
        return "macOS"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }()
    
    // Initialize with stored read items
    private init() {
        print("DEBUG [\(Date())] [\(deviceId)]: ReadStatusTracker initializing...")
        loadReadStatus()
    }
    
    // MARK: - Public API
    
    /// Check if an article is read
    /// - Parameter link: The article link
    /// - Returns: Bool indicating if the article has been read
    public func isArticleRead(link: String) -> Bool {
        let normalizedLink = normalizeLink(link)
        let isRead = readLinks.contains(normalizedLink)
        print("DEBUG [\(Date())] [\(deviceId)]: Checking article read status - Original: \(link), Normalized: \(normalizedLink), IsRead: \(isRead)")
        return isRead
    }
    
    /// Mark an article as read (UserDefaults-first approach)
    /// - Parameters:
    ///   - link: The article link
    ///   - isRead: Whether to mark as read or unread
    ///   - completion: Called when the operation completes
    public func markArticle(link: String, as isRead: Bool, completion: ((Bool) -> Void)? = nil) {
        let normalizedLink = normalizeLink(link)
        
        print("DEBUG [\(Date())] [\(deviceId)]: Marking article - Original: \(link), Normalized: \(normalizedLink), IsRead: \(isRead)")
        
        let beforeCount = readLinks.count
        if isRead {
            readLinks.insert(normalizedLink)
        } else {
            readLinks.remove(normalizedLink)
        }
        let afterCount = readLinks.count
        
        print("DEBUG [\(Date())] [\(deviceId)]: Read links count changed from \(beforeCount) to \(afterCount)")
        
        // 1. ALWAYS save to UserDefaults first for immediate feedback
        saveToUserDefaultsFirst()
        
        // 2. Notify UI immediately
        print("DEBUG [\(Date())] [\(deviceId)]: Posting readItemsUpdated notification")
        NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
        
        // 3. Queue CloudKit sync (fire and forget)
        queueCloudKitSync()
        
        // 4. Call completion immediately (don't wait for CloudKit)
        completion?(true)
    }
    
    /// Mark multiple articles as read (UserDefaults-first approach)
    /// - Parameters:
    ///   - links: Array of article links
    ///   - isRead: Whether to mark as read or unread
    ///   - completion: Called when the operation completes
    public func markArticles(links: [String], as isRead: Bool, completion: ((Bool) -> Void)? = nil) {
        let normalizedLinks = links.map { normalizeLink($0) }
        
        if isRead {
            readLinks.formUnion(normalizedLinks)
        } else {
            normalizedLinks.forEach { readLinks.remove($0) }
        }
        
        // 1. ALWAYS save to UserDefaults first for immediate feedback
        saveToUserDefaultsFirst()
        
        // 2. Notify UI immediately
        NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
        
        // 3. Queue CloudKit sync (fire and forget)
        queueCloudKitSync()
        
        // 4. Call completion immediately (don't wait for CloudKit)
        completion?(true)
    }
    
    /// Mark all articles as read
    /// - Parameters:
    ///   - links: Array of all article links
    ///   - completion: Called when the operation completes
    public func markAllAsRead(links: [String], completion: ((Bool) -> Void)? = nil) {
        let normalizedLinks = links.map { normalizeLink($0) }
        readLinks.formUnion(normalizedLinks)
        
        // 1. ALWAYS save to UserDefaults first for immediate feedback
        saveToUserDefaultsFirst()
        
        // 2. Notify UI immediately
        NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
        
        // 3. Queue CloudKit sync (fire and forget)
        queueCloudKitSync()
        
        // 4. Call completion immediately (don't wait for CloudKit)
        completion?(true)
    }
    
    /// Get all read article links
    /// - Returns: Array of read article links (normalized)
    public func getAllReadLinks() -> [String] {
        return Array(readLinks)
    }
    
    /// Reset all read status
    /// - Parameter completion: Called when the operation completes
    public func resetReadStatus(completion: ((Bool) -> Void)? = nil) {
        readLinks.removeAll()
        
        // 1. ALWAYS save to UserDefaults first for immediate feedback
        saveToUserDefaultsFirst()
        
        // 2. Notify UI immediately
        NotificationCenter.default.post(name: Notification.Name("readItemsReset"), object: nil)
        
        // 3. Queue CloudKit sync (fire and forget)
        queueCloudKitSync()
        
        // 4. Call completion immediately (don't wait for CloudKit)
        completion?(true)
    }
    
    // MARK: - Private Methods
    
    /// Save to UserDefaults immediately (primary storage)
    private func saveToUserDefaultsFirst() {
        let linksArray = Array(readLinks)
        print("DEBUG [\(Date())] [\(deviceId)]: Saving \(linksArray.count) read links to UserDefaults")
        
        if let data = try? JSONEncoder().encode(linksArray) {
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.synchronize() // Force immediate save
            print("DEBUG [\(Date())] [\(deviceId)]: Successfully saved to UserDefaults")
        } else {
            print("ERROR [\(Date())] [\(deviceId)]: Failed to encode readLinks to UserDefaults")
        }
    }
    
    /// Queue a CloudKit sync operation (secondary storage)
    private func queueCloudKitSync() {
        // Only queue sync if CloudKit is enabled
        guard StorageManager.shared.method == .cloudKit else {
            print("DEBUG [\(Date())] [\(deviceId)]: CloudKit sync skipped - not using CloudKit storage")
            return
        }
        
        let linksArray = Array(readLinks)
        print("DEBUG [\(Date())] [\(deviceId)]: Queueing CloudKit sync with \(linksArray.count) read links")
        
        // Use chunked sync for large datasets
        if linksArray.count > 3000 {
            print("DEBUG [\(Date())] [\(deviceId)]: Using chunked sync for \(linksArray.count) items")
            ChunkedSyncManager.shared.saveReadStatusInChunks(linksArray) { success, error in
                if success {
                    print("DEBUG [\(Date())] [\(self.deviceId)]: Chunked sync to CloudKit completed")
                } else {
                    print("ERROR [\(Date())] [\(self.deviceId)]: Chunked sync to CloudKit failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        } else {
            let syncOperation = SyncOperation(type: .readStatus, data: linksArray)
            SyncManager.shared.queueSync(operation: syncOperation)
        }
    }
    
    /// Load the read status from storage (UserDefaults first, then CloudKit)
    private func loadReadStatus() {
        print("DEBUG [\(Date())] [\(deviceId)]: Loading read status...")
        
        // 1. Load from UserDefaults first (primary source)
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                let readItems = try JSONDecoder().decode([String].self, from: data)
                self.readLinks = Set(readItems)
                print("DEBUG [\(Date())] [\(deviceId)]: Loaded \(readItems.count) read links from UserDefaults")
            } catch {
                print("ERROR [\(Date())] [\(deviceId)]: Failed to decode read items from UserDefaults: \(error)")
                self.readLinks = []
            }
        } else {
            print("DEBUG [\(Date())] [\(deviceId)]: No read items found in UserDefaults")
        }
        
        // 2. If CloudKit is enabled, sync from CloudKit in background
        if StorageManager.shared.method == .cloudKit {
            print("DEBUG [\(Date())] [\(deviceId)]: CloudKit is enabled, initiating sync from CloudKit")
            syncFromCloudKit()
        } else {
            print("DEBUG [\(Date())] [\(deviceId)]: CloudKit is not enabled, skipping CloudKit sync")
        }
    }
    
    /// Sync from CloudKit and merge with local data
    private func syncFromCloudKit() {
        print("DEBUG [\(Date())] [\(deviceId)]: Starting CloudKit sync...")
        let beforeCount = readLinks.count
        
        // First try chunked loading
        ChunkedSyncManager.shared.loadReadStatusFromChunks { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let cloudItems):
                    print("DEBUG [\(Date())] [\(self.deviceId)]: Loaded \(cloudItems.count) items from CloudKit (chunked)")
                    self.mergeCloudKitData(cloudItems, beforeCount: beforeCount)
                    
                case .failure:
                    // Fallback to regular loading if chunked loading fails
                    print("DEBUG [\(Date())] [\(self.deviceId)]: Chunked load failed, trying regular sync")
                    self.syncFromCloudKitRegular(beforeCount: beforeCount)
                }
            }
        }
    }
    
    private func syncFromCloudKitRegular(beforeCount: Int) {
        StorageManager.shared.load(forKey: storageKey) { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let cloudItems):
                    print("DEBUG [\(Date())] [\(self.deviceId)]: Received \(cloudItems.count) items from CloudKit (regular)")
                    self.mergeCloudKitData(cloudItems, beforeCount: beforeCount)
                    
                case .failure(let error):
                    print("ERROR [\(Date())] [\(self.deviceId)]: Failed to sync read items from CloudKit: \(error)")
                    // Continue using local data if CloudKit fails
                }
            }
        }
    }
    
    private func mergeCloudKitData(_ cloudItems: [String], beforeCount: Int) {
        // Merge CloudKit items with local items
        let normalizedCloudItems = Set(cloudItems.map { self.normalizeLink($0) })
        self.readLinks.formUnion(normalizedCloudItems)
        
        let afterCount = self.readLinks.count
        print("DEBUG [\(Date())] [\(self.deviceId)]: After merge - Before: \(beforeCount), CloudKit: \(normalizedCloudItems.count), After: \(afterCount)")
        
        // Save merged data back to UserDefaults
        self.saveToUserDefaultsFirst()
        
        // Check if we need to update CloudKit with merged data
        if afterCount > cloudItems.count {
            print("DEBUG [\(Date())] [\(self.deviceId)]: Local has more items than CloudKit (\(afterCount) > \(cloudItems.count)), updating CloudKit...")
            self.queueCloudKitSync()
        } else {
            print("DEBUG [\(Date())] [\(self.deviceId)]: CloudKit is up to date or has same/more items")
        }
        
        // Notify UI of potential changes
        print("DEBUG [\(Date())] [\(self.deviceId)]: Posting readItemsUpdated notification after CloudKit sync")
        NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
    }
    
    /// Helper to normalize links for consistent comparison
    private func normalizeLink(_ link: String) -> String {
        let normalized = StorageManager.shared.normalizeLink(link)
        if link != normalized {
            print("DEBUG [\(Date())] [\(deviceId)]: Link normalization - Original: \(link) -> Normalized: \(normalized)")
        }
        return normalized
    }
    
    // MARK: - Debug Methods
    
    /// Force a sync and print current read status
    public func debugSyncAndPrintStatus() {
        print("\n========== DEBUG SYNC STATUS [\(Date())] [\(deviceId)] ==========")
        print("Current read items count: \(readLinks.count)")
        print("Storage method: \(String(describing: StorageManager.shared.method))")
        
        // Print a few sample read links for debugging
        let sampleLinks = Array(readLinks.prefix(5))
        print("Sample read links:")
        for (index, link) in sampleLinks.enumerated() {
            print("  \(index + 1). \(link)")
        }
        
        // Force sync from CloudKit
        print("\nForcing sync from CloudKit...")
        syncFromCloudKit()
        
        // Check sync state
        SyncManager.shared.forceSyncAll { success, error in
            if success {
                print("DEBUG: Force sync completed successfully")
            } else {
                print("ERROR: Force sync failed - \(error?.localizedDescription ?? "Unknown error")")
            }
            
            // Print status after sync
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                print("\nAfter sync - Read items count: \(self.readLinks.count)")
                print("================================================\n")
            }
        }
    }
    
    /// Force push local read status to CloudKit
    public func forcePushToCloudKit() {
        guard StorageManager.shared.method == .cloudKit else {
            print("DEBUG [\(Date())] [\(deviceId)]: Cannot push to CloudKit - not using CloudKit storage")
            return
        }
        
        print("DEBUG [\(Date())] [\(deviceId)]: Force pushing \(readLinks.count) read items to CloudKit...")
        queueCloudKitSync()
    }
    
    /// Manually merge read status from another device
    public func manualMergeFromDevice(deviceType: String) {
        print("DEBUG [\(Date())] [\(deviceId)]: Starting manual merge from \(deviceType)...")
        
        // Load from CloudKit
        StorageManager.shared.load(forKey: storageKey) { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let cloudItems):
                    print("DEBUG [\(Date())] [\(self.deviceId)]: Loaded \(cloudItems.count) items from CloudKit")
                    
                    let beforeCount = self.readLinks.count
                    
                    // Merge with normalization
                    let normalizedCloudItems = Set(cloudItems.map { self.normalizeLink($0) })
                    self.readLinks.formUnion(normalizedCloudItems)
                    
                    let afterCount = self.readLinks.count
                    print("DEBUG [\(Date())] [\(self.deviceId)]: Manual merge complete - Before: \(beforeCount), After: \(afterCount), Added: \(afterCount - beforeCount)")
                    
                    // Save merged data
                    self.saveToUserDefaultsFirst()
                    
                    // Push back to CloudKit to ensure consistency
                    if afterCount > cloudItems.count {
                        print("DEBUG [\(Date())] [\(self.deviceId)]: Pushing merged data back to CloudKit...")
                        self.queueCloudKitSync()
                    }
                    
                    // Notify UI
                    NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
                    
                case .failure(let error):
                    print("ERROR [\(Date())] [\(self.deviceId)]: Failed to load from CloudKit for manual merge: \(error)")
                }
            }
        }
    }
    
    /// Force overwrite CloudKit with local data (use with caution)
    public func forceOverwriteCloudKit() {
        guard StorageManager.shared.method == .cloudKit else {
            print("DEBUG [\(Date())] [\(deviceId)]: Cannot overwrite CloudKit - not using CloudKit storage")
            return
        }
        
        print("WARNING [\(Date())] [\(deviceId)]: Force overwriting CloudKit with \(readLinks.count) local items...")
        
        // Convert read links to array
        let readLinksArray = Array(readLinks)
        
        // Use chunked sync for large datasets
        if readLinksArray.count > 3000 {
            print("DEBUG [\(Date())] [\(deviceId)]: Using chunked sync for \(readLinksArray.count) items")
            ChunkedSyncManager.shared.saveReadStatusInChunks(readLinksArray) { success, error in
                if success {
                    print("DEBUG [\(Date())] [\(self.deviceId)]: Chunked overwrite to CloudKit completed")
                } else {
                    print("ERROR [\(Date())] [\(self.deviceId)]: Chunked overwrite to CloudKit failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        } else {
            // Save directly to CloudKit, bypassing merge logic
            let operation = SyncOperation(type: .readStatus, data: readLinksArray)
            SyncManager.shared.queueSync(operation: operation)
            
            // Also trigger sync to ensure it happens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SyncManager.shared.forceSyncAll { success, error in
                    if success {
                        print("DEBUG [\(Date())] [\(self.deviceId)]: Force overwrite to CloudKit completed")
                    } else {
                        print("ERROR [\(Date())] [\(self.deviceId)]: Force overwrite to CloudKit failed: \(error?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
        }
    }
}