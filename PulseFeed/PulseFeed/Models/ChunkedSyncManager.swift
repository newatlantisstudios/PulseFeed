import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

/// Manages chunked sync operations for large datasets that exceed CloudKit's record size limits
class ChunkedSyncManager {
    static let shared = ChunkedSyncManager()
    
    private let chunkSize = 1000 // Number of items per chunk
    private let database = CKContainer.default().privateCloudDatabase
    
    private init() {}
    
    /// Save read status in chunks to avoid CloudKit record size limits
    func saveReadStatusInChunks(_ links: [String], completion: @escaping (Bool, Error?) -> Void) {
        let deviceId = getDeviceId()
        print("DEBUG [\(Date())]: Starting chunked save of \(links.count) items from \(deviceId)")
        
        // Create chunks
        let chunks = links.chunked(into: chunkSize)
        print("DEBUG [\(Date())]: Split into \(chunks.count) chunks of max \(chunkSize) items each")
        
        // Save chunk metadata first
        saveChunkMetadata(totalItems: links.count, chunkCount: chunks.count) { [weak self] success, error in
            guard success else {
                print("ERROR [\(Date())]: Failed to save chunk metadata: \(error?.localizedDescription ?? "Unknown error")")
                completion(false, error)
                return
            }
            
            // Save each chunk
            self?.saveChunks(chunks, completion: completion)
        }
    }
    
    /// Load read status from all chunks
    func loadReadStatusFromChunks(completion: @escaping (Result<[String], Error>) -> Void) {
        let deviceId = getDeviceId()
        print("DEBUG [\(Date())]: Loading chunked read status on \(deviceId)")
        
        // Load chunk metadata first
        loadChunkMetadata { [weak self] metadata, error in
            guard let metadata = metadata else {
                print("ERROR [\(Date())]: Failed to load chunk metadata: \(error?.localizedDescription ?? "Unknown error")")
                completion(.failure(error ?? NSError(domain: "ChunkedSyncManager", code: -1)))
                return
            }
            
            print("DEBUG [\(Date())]: Found \(metadata.chunkCount) chunks with \(metadata.totalItems) total items")
            
            // Load all chunks
            self?.loadChunks(count: metadata.chunkCount, completion: completion)
        }
    }
    
    // MARK: - Private Methods
    
    private func saveChunkMetadata(totalItems: Int, chunkCount: Int, completion: @escaping (Bool, Error?) -> Void) {
        let recordID = CKRecord.ID(recordName: "readStatusMetadata")
        
        database.fetch(withRecordID: recordID) { [weak self] existingRecord, error in
            let record = existingRecord ?? CKRecord(recordType: "ReadStatusMetadata", recordID: recordID)
            
            record["totalItems"] = totalItems as CKRecordValue
            record["chunkCount"] = chunkCount as CKRecordValue
            record["lastUpdated"] = Date() as CKRecordValue
            record["deviceId"] = self?.getDeviceId() as CKRecordValue?
            
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("DEBUG [\(Date())]: Successfully saved chunk metadata")
                    completion(true, nil)
                case .failure(let error):
                    print("ERROR [\(Date())]: Failed to save chunk metadata: \(error)")
                    completion(false, error)
                }
            }
            
            self?.database.add(operation)
        }
    }
    
    private func loadChunkMetadata(completion: @escaping ((totalItems: Int, chunkCount: Int)?, Error?) -> Void) {
        let recordID = CKRecord.ID(recordName: "readStatusMetadata")
        
        database.fetch(withRecordID: recordID) { record, error in
            guard let record = record,
                  let totalItems = record["totalItems"] as? Int,
                  let chunkCount = record["chunkCount"] as? Int else {
                completion(nil, error)
                return
            }
            
            completion((totalItems: totalItems, chunkCount: chunkCount), nil)
        }
    }
    
    private func saveChunks(_ chunks: [[String]], completion: @escaping (Bool, Error?) -> Void) {
        let saveGroup = DispatchGroup()
        var errors: [Error] = []
        var savedCount = 0
        
        for (index, chunk) in chunks.enumerated() {
            saveGroup.enter()
            
            let recordID = CKRecord.ID(recordName: "readStatusChunk_\(index)")
            
            database.fetch(withRecordID: recordID) { [weak self] existingRecord, error in
                let record = existingRecord ?? CKRecord(recordType: "ReadStatusChunk", recordID: recordID)
                
                do {
                    let data = try JSONEncoder().encode(chunk)
                    let dataSize = Double(data.count) / (1024.0 * 1024.0)
                    print("DEBUG [\(Date())]: Chunk \(index) size: \(String(format: "%.2f", dataSize)) MB for \(chunk.count) items")
                    
                    record["data"] = data as CKRecordValue
                    record["itemCount"] = chunk.count as CKRecordValue
                    record["chunkIndex"] = index as CKRecordValue
                    record["lastUpdated"] = Date() as CKRecordValue
                    
                    let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                    operation.savePolicy = .allKeys
                    
                    operation.modifyRecordsResultBlock = { result in
                        defer { saveGroup.leave() }
                        
                        switch result {
                        case .success:
                            savedCount += 1
                            print("DEBUG [\(Date())]: Successfully saved chunk \(index) with \(chunk.count) items")
                        case .failure(let error):
                            errors.append(error)
                            print("ERROR [\(Date())]: Failed to save chunk \(index): \(error)")
                        }
                    }
                    
                    self?.database.add(operation)
                } catch {
                    errors.append(error)
                    print("ERROR [\(Date())]: Failed to encode chunk \(index): \(error)")
                    saveGroup.leave()
                }
            }
        }
        
        saveGroup.notify(queue: .main) {
            if errors.isEmpty {
                print("DEBUG [\(Date())]: Successfully saved all \(chunks.count) chunks")
                completion(true, nil)
            } else {
                print("ERROR [\(Date())]: Failed to save \(errors.count) chunks out of \(chunks.count)")
                completion(false, errors.first)
            }
        }
    }
    
    private func loadChunks(count: Int, completion: @escaping (Result<[String], Error>) -> Void) {
        let loadGroup = DispatchGroup()
        var allItems: [String] = []
        var errors: [Error] = []
        
        for index in 0..<count {
            loadGroup.enter()
            
            let recordID = CKRecord.ID(recordName: "readStatusChunk_\(index)")
            
            database.fetch(withRecordID: recordID) { record, error in
                defer { loadGroup.leave() }
                
                if let error = error {
                    errors.append(error)
                    print("ERROR [\(Date())]: Failed to load chunk \(index): \(error)")
                    return
                }
                
                guard let record = record,
                      let data = record["data"] as? Data,
                      let items = try? JSONDecoder().decode([String].self, from: data) else {
                    errors.append(NSError(domain: "ChunkedSyncManager", code: -1))
                    return
                }
                
                print("DEBUG [\(Date())]: Loaded chunk \(index) with \(items.count) items")
                allItems.append(contentsOf: items)
            }
        }
        
        loadGroup.notify(queue: .main) {
            if errors.isEmpty {
                print("DEBUG [\(Date())]: Successfully loaded all \(count) chunks with \(allItems.count) total items")
                completion(.success(allItems))
            } else {
                print("ERROR [\(Date())]: Failed to load \(errors.count) chunks out of \(count)")
                completion(.failure(errors.first!))
            }
        }
    }
    
    private func getDeviceId() -> String {
        #if targetEnvironment(macCatalyst)
        return "macOS"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

// MARK: - Array Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}