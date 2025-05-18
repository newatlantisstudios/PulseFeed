import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Sync State
enum SyncState: Equatable {
    case synced
    case syncing
    case failed(Error)
    case offline
    case pending
    
    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.synced, .synced), (.syncing, .syncing), (.offline, .offline), (.pending, .pending):
            return true
        case (.failed(_), .failed(_)):
            return true
        default:
            return false
        }
    }
}

// MARK: - Sync Operation
struct SyncOperation {
    let id: String
    let type: SyncType
    let data: Any
    let timestamp: Date
    let retryCount: Int
    
    init(type: SyncType, data: Any, retryCount: Int = 0) {
        self.id = UUID().uuidString
        self.type = type
        self.data = data
        self.timestamp = Date()
        self.retryCount = retryCount
    }
}

enum SyncType: String, Codable {
    case readStatus
    case bookmarkStatus
    case heartStatus
    case archiveStatus
    case feedFolder
    case hierarchicalFolder
}

// MARK: - Sync Manager
class SyncManager {
    static let shared = SyncManager()
    
    // Queue for sync operations
    private var syncQueue: [SyncOperation] = []
    private let syncQueueLock = NSLock()
    
    // Retry management
    private var retryCount: [String: Int] = [:]
    private let maxRetryCount = 3
    private let baseRetryDelay: TimeInterval = 5.0
    
    // State tracking
    private(set) var currentSyncState: SyncState = .synced
    private var lastSyncTime: Date?
    private var syncTimer: Timer?
    
    // CloudKit references
    private let container = CKContainer.default()
    private let database = CKContainer.default().privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "rssFeedsRecord")
    
    // Error tracking
    private var syncErrors: [SyncError] = []
    
    private init() {
        // Start monitoring CloudKit availability
        setupCloudKitMonitoring()
        
        // Setup periodic state check to prevent pending state getting stuck
        setupPeriodicStateCheck()
    }
    
    // MARK: - Public API
    
    /// Queue a sync operation to be processed
    func queueSync(operation: SyncOperation) {
        syncQueueLock.lock()
        syncQueue.append(operation)
        syncQueueLock.unlock()
        
        // Process queue if not already processing
        if currentSyncState != .syncing {
            processSyncQueue()
        }
    }
    
    /// Force sync all pending operations
    func forceSyncAll(completion: @escaping (Bool, Error?) -> Void) {
        updateSyncState(.syncing)
        
        let group = DispatchGroup()
        var overallSuccess = true
        var lastError: Error?
        
        // Process all operations in parallel where possible
        for operation in syncQueue {
            group.enter()
            performSync(operation: operation) { success, error in
                if !success {
                    overallSuccess = false
                    lastError = error
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if overallSuccess {
                self.updateSyncState(.synced)
                self.syncQueue.removeAll()
            } else {
                self.updateSyncState(.failed(lastError ?? NSError(domain: "SyncManager", code: -1)))
            }
            completion(overallSuccess, lastError)
        }
    }
    
    /// Get current sync status
    func getSyncStatus() -> (state: SyncState, lastSync: Date?, pendingCount: Int) {
        return (currentSyncState, lastSyncTime, syncQueue.count)
    }
    
    /// Refresh sync status - useful for UI elements that need immediate update
    func refreshSyncStatus() {
        if currentSyncState == .pending {
            if syncQueue.isEmpty {
                // No pending operations, should be synced
                updateSyncState(.synced)
            }
        }
    }
    
    /// Clear sync errors
    func clearSyncErrors() {
        syncErrors.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func processSyncQueue() {
        guard !syncQueue.isEmpty else {
            // No operations to process, ensure we're in synced state
            if currentSyncState == .pending || currentSyncState == .syncing {
                updateSyncState(.synced)
            }
            return
        }
        
        updateSyncState(.syncing)
        
        // Process operations with rate limiting
        processNextOperation()
    }
    
    private func processNextOperation() {
        syncQueueLock.lock()
        guard let operation = syncQueue.first else {
            syncQueueLock.unlock()
            // No more operations, check if we should update to synced
            if currentSyncState == .syncing || currentSyncState == .pending {
                updateSyncState(.synced)
            }
            return
        }
        syncQueueLock.unlock()
        
        let startTime = Date()
        
        performSync(operation: operation) { [weak self] success, error in
            guard let self = self else { return }
            
            if success {
                self.syncQueueLock.lock()
                self.syncQueue.removeFirst()
                self.syncQueueLock.unlock()
                self.lastSyncTime = Date()
                
                // Log successful sync
                let duration = Date().timeIntervalSince(startTime)
                SyncHistory.shared.logEvent(SyncEvent(
                    type: operation.type,
                    status: .completed,
                    details: "Sync completed successfully",
                    duration: duration
                ))
                
                // Process next operation
                self.processNextOperation()
            } else {
                self.handleSyncError(operation: operation, error: error)
            }
        }
    }
    
    private func performSync(operation: SyncOperation, completion: @escaping (Bool, Error?) -> Void) {
        // Log sync start
        SyncHistory.shared.logEvent(SyncEvent(
            type: operation.type,
            status: .started,
            details: "Starting sync operation"
        ))
        switch operation.type {
        case .readStatus:
            syncReadStatus(data: operation.data, completion: completion)
        case .bookmarkStatus:
            syncBookmarkStatus(data: operation.data, completion: completion)
        case .heartStatus:
            syncHeartStatus(data: operation.data, completion: completion)
        case .archiveStatus:
            syncArchiveStatus(data: operation.data, completion: completion)
        case .feedFolder:
            syncFeedFolder(data: operation.data, completion: completion)
        case .hierarchicalFolder:
            syncHierarchicalFolder(data: operation.data, completion: completion)
        }
    }
    
    // MARK: - Specific Sync Operations
    
    private func syncReadStatus(data: Any, completion: @escaping (Bool, Error?) -> Void) {
        guard let readLinks = data as? [String] else {
            completion(false, NSError(domain: "SyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data type"]))
            return
        }
        
        print("DEBUG [\(Date())]: SyncManager starting to sync read status with \(readLinks.count) items")
        
        // Load existing items from CloudKit first
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let error = error as? CKError, error.code == .unknownItem {
                print("DEBUG [\(Date())]: CloudKit record doesn't exist, creating new record with \(readLinks.count) items")
                // Create new record
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: self.recordID)
                self.saveReadStatus(readLinks, to: newRecord, completion: completion)
            } else if let record = record {
                print("DEBUG [\(Date())]: Found existing CloudKit record, merging with \(readLinks.count) local items")
                // Update existing record
                self.mergeAndSaveReadStatus(readLinks, to: record, completion: completion)
            } else {
                print("ERROR [\(Date())]: Failed to fetch CloudKit record: \(error?.localizedDescription ?? "Unknown error")")
                completion(false, error)
            }
        }
    }
    
    private func mergeAndSaveReadStatus(_ newLinks: [String], to record: CKRecord, completion: @escaping (Bool, Error?) -> Void) {
        // Get existing read items from CloudKit
        var existingLinks: [String] = []
        if let data = record["readItems"] as? Data {
            do {
                existingLinks = try JSONDecoder().decode([String].self, from: data)
                print("DEBUG [\(Date())]: Decoded \(existingLinks.count) existing items from CloudKit")
            } catch {
                print("ERROR [\(Date())]: Failed to decode existing read items: \(error)")
            }
        } else {
            print("DEBUG [\(Date())]: No existing read items found in CloudKit record")
        }
        
        // Merge with normalization
        let normalizedNew = newLinks.map { StorageManager.shared.normalizeLink($0) }
        let normalizedExisting = existingLinks.map { StorageManager.shared.normalizeLink($0) }
        let beforeMergeCount = normalizedExisting.count
        
        // Always prefer the larger dataset to avoid data loss
        let merged: [String]
        if normalizedNew.count > normalizedExisting.count {
            // If local has more items, use local as the base and add any unique items from CloudKit
            merged = Array(Set(normalizedNew).union(Set(normalizedExisting)))
            print("DEBUG [\(Date())]: Using local dataset as base (has more items)")
        } else {
            // If CloudKit has more items, use CloudKit as the base and add any unique items from local
            merged = Array(Set(normalizedExisting).union(Set(normalizedNew)))
            print("DEBUG [\(Date())]: Using CloudKit dataset as base (has more items)")
        }
        
        print("DEBUG [\(Date())]: Merge stats - Local: \(normalizedNew.count), CloudKit: \(beforeMergeCount), Merged: \(merged.count)")
        
        // Save merged data
        saveReadStatus(merged, to: record, completion: completion)
    }
    
    private func saveReadStatus(_ links: [String], to record: CKRecord, completion: @escaping (Bool, Error?) -> Void) {
        do {
            print("DEBUG [\(Date())]: Preparing to save \(links.count) read items to CloudKit")
            
            // Log current record state before modification
            if let existingData = record["readItems"] as? Data,
               let existingItems = try? JSONDecoder().decode([String].self, from: existingData) {
                print("DEBUG [\(Date())]: Record currently has \(existingItems.count) items")
            } else {
                print("DEBUG [\(Date())]: Record has no existing items")
            }
            
            let data = try JSONEncoder().encode(links)
            let dataSize = Double(data.count) / (1024.0 * 1024.0) // Size in MB
            print("DEBUG [\(Date())]: Data size: \(String(format: "%.2f", dataSize)) MB for \(links.count) items")
            record["readItems"] = data as CKRecordValue
            // Add a timestamp to track when this was last updated
            record["readItemsTimestamp"] = Date() as CKRecordValue
            // Add device identifier to track source of update
            #if targetEnvironment(macCatalyst)
            let deviceId = "macOS"
            #else
            let deviceId = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
            #endif
            record["readItemsDevice"] = deviceId as CKRecordValue
            
            print("DEBUG [\(Date())]: Record prepared with \(links.count) items from \(deviceId)")
            
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            // Use .allKeys to force overwrite and avoid conflicts
            operation.savePolicy = .allKeys
            operation.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success(let savedRecord):
                    print("DEBUG [\(Date())]: Per-record save success for \(recordID)")
                case .failure(let error):
                    print("ERROR [\(Date())]: Per-record save failed for \(recordID): \(error.localizedDescription)")
                }
            }
            
            operation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let savedRecords):
                        print("DEBUG [\(Date())]: CloudKit save reported success for \(links.count) items")
                        
                        // Verify the save actually worked by reading back immediately
                        self.database.fetch(withRecordID: self.recordID) { verifyRecord, verifyError in
                            if let verifyRecord = verifyRecord,
                               let data = verifyRecord["readItems"] as? Data,
                               let verifiedLinks = try? JSONDecoder().decode([String].self, from: data) {
                                print("DEBUG [\(Date())]: VERIFICATION - CloudKit now contains \(verifiedLinks.count) items")
                                if verifiedLinks.count != links.count {
                                    print("ERROR [\(Date())]: VERIFICATION FAILED - Saved \(links.count) but CloudKit has \(verifiedLinks.count)")
                                }
                                completion(true, nil)
                            } else {
                                print("ERROR [\(Date())]: VERIFICATION FAILED - Could not read back saved data")
                                completion(false, verifyError ?? NSError(domain: "SyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Verification failed"]))
                            }
                        }
                    case .failure(let error):
                        print("ERROR [\(Date())]: Failed to save to CloudKit: \(error.localizedDescription)")
                        if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                            print("DEBUG [\(Date())]: Server record changed, retrying...")
                            // Retry with the latest version
                            self.syncReadStatus(data: links, completion: completion)
                        } else {
                            completion(false, error)
                        }
                    }
                }
            }
            
            database.add(operation)
        } catch {
            print("ERROR [\(Date())]: Failed to encode read items: \(error)")
            completion(false, error)
        }
    }
    
    // Similar implementations for other sync types...
    private func syncBookmarkStatus(data: Any, completion: @escaping (Bool, Error?) -> Void) {
        guard let bookmarkLinks = data as? [String] else {
            completion(false, NSError(domain: "SyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data type"]))
            return
        }
        
        // Load existing items from CloudKit first
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let error = error as? CKError, error.code == .unknownItem {
                // Create new record
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: self.recordID)
                self.saveBookmarkStatus(bookmarkLinks, to: newRecord, completion: completion)
            } else if let record = record {
                // Update existing record
                self.mergeAndSaveBookmarkStatus(bookmarkLinks, to: record, completion: completion)
            } else {
                completion(false, error)
            }
        }
    }
    
    private func mergeAndSaveBookmarkStatus(_ newLinks: [String], to record: CKRecord, completion: @escaping (Bool, Error?) -> Void) {
        // Get existing bookmarked items from CloudKit
        var existingLinks: [String] = []
        if let data = record["bookmarkedItems"] as? Data {
            do {
                existingLinks = try JSONDecoder().decode([String].self, from: data)
            } catch {
                print("ERROR: Failed to decode existing bookmarked items: \(error)")
            }
        }
        
        // Merge with normalization
        let normalizedNew = newLinks.map { StorageManager.shared.normalizeLink($0) }
        let normalizedExisting = existingLinks.map { StorageManager.shared.normalizeLink($0) }
        let merged = Array(Set(normalizedNew).union(Set(normalizedExisting)))
        
        // Save merged data
        saveBookmarkStatus(merged, to: record, completion: completion)
    }
    
    private func saveBookmarkStatus(_ links: [String], to record: CKRecord, completion: @escaping (Bool, Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(links)
            record["bookmarkedItems"] = data as CKRecordValue
            
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            operation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completion(true, nil)
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                            // Retry with the latest version
                            self.syncBookmarkStatus(data: links, completion: completion)
                        } else {
                            completion(false, error)
                        }
                    }
                }
            }
            
            database.add(operation)
        } catch {
            completion(false, error)
        }
    }
    
    private func syncHeartStatus(data: Any, completion: @escaping (Bool, Error?) -> Void) {
        // Similar implementation as bookmarks but for hearted items
        guard let heartedLinks = data as? [String] else {
            completion(false, NSError(domain: "SyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data type"]))
            return
        }
        
        // Load existing items from CloudKit first
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let error = error as? CKError, error.code == .unknownItem {
                // Create new record
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: self.recordID)
                self.mergeAndSaveStatus(heartedLinks, to: newRecord, forKey: "heartedItems", completion: completion)
            } else if let record = record {
                // Update existing record
                self.mergeAndSaveStatus(heartedLinks, to: record, forKey: "heartedItems", completion: completion)
            } else {
                completion(false, error)
            }
        }
    }
    
    private func syncArchiveStatus(data: Any, completion: @escaping (Bool, Error?) -> Void) {
        // Similar implementation as bookmarks but for archived items
        guard let archivedLinks = data as? [String] else {
            completion(false, NSError(domain: "SyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data type"]))
            return
        }
        
        // Load existing items from CloudKit first
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let error = error as? CKError, error.code == .unknownItem {
                // Create new record
                let newRecord = CKRecord(recordType: "RSSFeeds", recordID: self.recordID)
                self.mergeAndSaveStatus(archivedLinks, to: newRecord, forKey: "archivedItems", completion: completion)
            } else if let record = record {
                // Update existing record
                self.mergeAndSaveStatus(archivedLinks, to: record, forKey: "archivedItems", completion: completion)
            } else {
                completion(false, error)
            }
        }
    }
    
    // Generic method to merge and save status for any key
    private func mergeAndSaveStatus(_ newLinks: [String], to record: CKRecord, forKey key: String, completion: @escaping (Bool, Error?) -> Void) {
        // Get existing items from CloudKit
        var existingLinks: [String] = []
        if let data = record[key] as? Data {
            do {
                existingLinks = try JSONDecoder().decode([String].self, from: data)
            } catch {
                print("ERROR: Failed to decode existing \(key): \(error)")
            }
        }
        
        // Merge with normalization
        let normalizedNew = newLinks.map { StorageManager.shared.normalizeLink($0) }
        let normalizedExisting = existingLinks.map { StorageManager.shared.normalizeLink($0) }
        let merged = Array(Set(normalizedNew).union(Set(normalizedExisting)))
        
        // Save merged data
        do {
            let data = try JSONEncoder().encode(merged)
            record[key] = data as CKRecordValue
            
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            operation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completion(true, nil)
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                            // Retry with the latest version
                            self.mergeAndSaveStatus(newLinks, to: record, forKey: key, completion: completion)
                        } else {
                            completion(false, error)
                        }
                    }
                }
            }
            
            database.add(operation)
        } catch {
            completion(false, error)
        }
    }
    
    private func syncFeedFolder(data: Any, completion: @escaping (Bool, Error?) -> Void) {
        // Implementation for feed folders
        completion(true, nil) // TODO: Implement folder sync
    }
    
    private func syncHierarchicalFolder(data: Any, completion: @escaping (Bool, Error?) -> Void) {
        // Implementation for hierarchical folders
        completion(true, nil) // TODO: Implement hierarchical folder sync
    }
    
    // MARK: - Error Handling
    
    private func handleSyncError(operation: SyncOperation, error: Error?) {
        // Log error
        SyncHistory.shared.logEvent(SyncEvent(
            type: operation.type,
            status: .failed,
            details: "Sync failed",
            error: error
        ))
        
        let syncError = SyncError(operation: operation, error: error ?? NSError(domain: "SyncManager", code: -1), timestamp: Date())
        syncErrors.append(syncError)
        
        // Handle rate limiting
        if let ckError = error as? CKError {
            switch ckError.code {
            case .requestRateLimited:
                let retryAfter = ckError.retryAfterSeconds ?? baseRetryDelay
                
                // Log rate limiting
                SyncHistory.shared.logEvent(SyncEvent(
                    type: operation.type,
                    status: .rateLimited,
                    details: "Rate limited by CloudKit, retry after \(retryAfter)s",
                    error: error
                ))
                
                scheduleRetry(operation: operation, after: retryAfter)
            case .serviceUnavailable, .networkFailure, .networkUnavailable:
                scheduleRetry(operation: operation, after: baseRetryDelay)
            default:
                updateSyncState(.failed(error!))
                logError(syncError)
            }
        } else {
            // Generic error handling
            scheduleRetry(operation: operation, after: baseRetryDelay)
        }
    }
    
    private func scheduleRetry(operation: SyncOperation, after delay: TimeInterval) {
        // Log retry
        SyncHistory.shared.logEvent(SyncEvent(
            type: operation.type,
            status: .retrying,
            details: "Scheduling retry \(operation.retryCount + 1) after \(delay)s"
        ))
        
        guard operation.retryCount < maxRetryCount else {
            updateSyncState(.failed(NSError(domain: "SyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retry count exceeded"])))
            return
        }
        
        // Calculate exponential backoff
        let actualDelay = delay * pow(2.0, Double(operation.retryCount))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + actualDelay) { [weak self] in
            guard let self = self else { return }
            
            // Create new operation with incremented retry count
            let retryOperation = SyncOperation(
                type: operation.type,
                data: operation.data,
                retryCount: operation.retryCount + 1
            )
            
            // Remove old operation and add retry
            self.syncQueueLock.lock()
            if let index = self.syncQueue.firstIndex(where: { $0.id == operation.id }) {
                self.syncQueue.remove(at: index)
            }
            self.syncQueue.append(retryOperation)
            self.syncQueueLock.unlock()
            
            // Continue processing
            self.processNextOperation()
        }
    }
    
    // MARK: - State Management
    
    private func updateSyncState(_ state: SyncState) {
        currentSyncState = state
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: Notification.Name("SyncStateChanged"),
            object: nil,
            userInfo: ["state": state]
        )
    }
    
    // MARK: - Monitoring
    
    private func setupPeriodicStateCheck() {
        // Check sync state every 30 seconds to prevent stuck pending state
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // If we've been in pending state for too long, check if we need to update
            if self.currentSyncState == .pending {
                if self.syncQueue.isEmpty {
                    // No pending operations, should be synced
                    self.updateSyncState(.synced)
                } else {
                    // Have pending operations, process them
                    self.processSyncQueue()
                }
            }
        }
    }
    
    private func setupCloudKitMonitoring() {
        // Monitor CloudKit account status
        container.accountStatus { status, error in
            switch status {
            case .available:
                self.updateSyncState(.pending)
                // Immediately process sync queue when account is available
                if !self.syncQueue.isEmpty {
                    self.processSyncQueue()
                } else {
                    // No pending operations, set to synced
                    self.updateSyncState(.synced)
                }
            case .noAccount, .restricted:
                self.updateSyncState(.offline)
            case .temporarilyUnavailable:
                self.updateSyncState(.offline)
            @unknown default:
                self.updateSyncState(.offline)
            }
        }
    }
    
    // MARK: - Logging
    
    private func logError(_ error: SyncError) {
        // Log to SyncHistory
        SyncHistory.shared.logEvent(SyncEvent(
            type: error.operation.type,
            status: .failed,
            details: "Sync error: \(error.error.localizedDescription)",
            error: error.error
        ))
        
        print("SYNC ERROR: \(error.error.localizedDescription) for operation: \(error.operation.type)")
        
        // Optionally save to file for debugging
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logPath = documentsPath.appendingPathComponent("sync_errors.log")
            let logEntry = "\(Date()): \(error.error.localizedDescription) - \(error.operation.type)\n"
            
            if let data = logEntry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: logPath) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: logPath)
                }
            }
        }
    }
}

// MARK: - Sync Error
struct SyncError {
    let operation: SyncOperation
    let error: Error
    let timestamp: Date
}

// MARK: - Extensions
extension Notification.Name {
    static let syncStateChanged = Notification.Name("SyncStateChanged")
}