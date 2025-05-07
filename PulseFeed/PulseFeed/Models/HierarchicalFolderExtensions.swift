import Foundation

// MARK: - StorageManager Extensions for Hierarchical Folders

extension StorageManager {
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
        
        getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(var folders):
                print("DEBUG: Got \(folders.count) existing folders")
                print("DEBUG: Root folders: \(folders.filter { $0.parentId == nil }.count)")
                
                // Determine the sort index for the new folder
                var sortIndex = 0
                if let parentId = parentId {
                    // For a subfolder, find the highest sort index of siblings and add 1
                    let siblings = folders.filter { $0.parentId == parentId }
                    print("DEBUG: Found \(siblings.count) sibling folders for parent \(parentId)")
                    
                    if let highestIndex = siblings.map({ $0.sortIndex }).max() {
                        sortIndex = highestIndex + 1
                        print("DEBUG: Using sort index \(sortIndex) based on siblings")
                    } else {
                        print("DEBUG: No siblings found, using sort index 0")
                    }
                    
                    // Verify parent exists
                    if !folders.contains(where: { $0.id == parentId }) {
                        print("DEBUG: WARNING - Parent folder \(parentId) does not exist!")
                    }
                } else {
                    // For a root folder, find the highest sort index of root folders and add 1
                    let rootFolders = folders.filter { $0.parentId == nil }
                    print("DEBUG: Found \(rootFolders.count) root folders")
                    
                    if let highestIndex = rootFolders.map({ $0.sortIndex }).max() {
                        sortIndex = highestIndex + 1
                        print("DEBUG: Using sort index \(sortIndex) based on root folders")
                    } else {
                        print("DEBUG: No root folders found, using sort index 0")
                    }
                }
                
                // Create new folder
                let newFolder = HierarchicalFolder(name: name, parentId: parentId, sortIndex: sortIndex)
                print("DEBUG: Created new folder with ID: \(newFolder.id)")
                folders.append(newFolder)
                
                // Log folders before saving
                print("DEBUG: Saving new folder \(newFolder.name) to storage. Total folders: \(folders.count)")
                print("DEBUG: Current folder list: \(folders.map { "\($0.name) (ID: \($0.id))" })")
                
                // Save directly to UserDefaults for immediate local access
                if let encodedData = try? JSONEncoder().encode(folders) {
                    print("DEBUG: Directly saving to UserDefaults")
                    UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                    UserDefaults.standard.synchronize()
                    print("DEBUG: UserDefaults synchronized")
                } else {
                    print("DEBUG: Failed to encode folders for UserDefaults")
                }
                
                // Verify folder was saved in UserDefaults
                if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
                    do {
                        let savedFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                        let folderExists = savedFolders.contains(where: { $0.id == newFolder.id })
                        print("DEBUG: Folder exists in UserDefaults after direct save: \(folderExists)")
                    } catch {
                        print("DEBUG: Error verifying folder in UserDefaults: \(error)")
                    }
                }
                
                // Save to the storage system (CloudKit or UserDefaults)
                print("DEBUG: Saving to storage system")
                self.save(folders, forKey: "hierarchicalFolders") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("DEBUG: Error saving folder: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else {
                            print("DEBUG: Successfully saved folder to storage")
                            
                            // Double-check the folder is really there
                            self.verifyFolderWasSaved(newFolder.id) { exists in
                                print("DEBUG: Final verification of saved folder: \(exists ? "EXISTS" : "NOT FOUND")")
                                
                                completion(.success(newFolder))
                                
                                // Post notification that folders have been updated
                                print("DEBUG: Posting hierarchicalFoldersUpdated notification")
                                NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                            }
                        }
                    }
                }
            case .failure(let error):
                print("DEBUG: Failed to get existing folders: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
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
}

// Note: We're using the existing FolderManager class from FolderManager.swift
// No duplicate class definition here to avoid the compilation error