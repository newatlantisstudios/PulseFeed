import Foundation
import CloudKit

/// Extension to FolderManager to add Smart Folder functionality
extension FolderManager {
    /// Get all smart folders
    static func getSmartFolders(from smartFolders: [SmartFolder]) -> [SmartFolder] {
        print("DEBUG: FolderManager - Getting all smart folders from \(smartFolders.count) folders")
        return smartFolders
    }
    
    /// Get all root smart folders (those without a parent)
    static func getRootSmartFolders(from smartFolders: [SmartFolder]) -> [SmartFolder] {
        print("DEBUG: FolderManager - Getting root smart folders from \(smartFolders.count) folders")
        let rootFolders = smartFolders.filter { $0.parentId == nil }
                      .sorted { $0.sortIndex < $1.sortIndex }
        print("DEBUG: FolderManager - Found \(rootFolders.count) root smart folders")
        return rootFolders
    }
    
    /// Get direct child smart folders for a specific parent folder
    static func getChildSmartFolders(from smartFolders: [SmartFolder], forParentId parentId: String) -> [SmartFolder] {
        print("DEBUG: FolderManager - Getting child smart folders for parent ID: \(parentId)")
        let childFolders = smartFolders.filter { $0.parentId == parentId }
                      .sorted { $0.sortIndex < $1.sortIndex }
        print("DEBUG: FolderManager - Found \(childFolders.count) child smart folders for parent \(parentId)")
        return childFolders
    }
    
    /// Gets feeds that match a specific smart folder's rules
    static func getMatchingFeeds(for smartFolder: SmartFolder, allFeeds: [RSSFeed], completion: @escaping ([RSSFeed]) -> Void) {
        print("DEBUG: FolderManager - Getting matching feeds for smart folder: \(smartFolder.name)")
        var matchingFeeds: [RSSFeed] = []
        let feedGroup = DispatchGroup()
        
        for feed in allFeeds {
            feedGroup.enter()
            smartFolder.matchesFeed(feed) { matches in
                if matches {
                    matchingFeeds.append(feed)
                }
                feedGroup.leave()
            }
        }
        
        feedGroup.notify(queue: .main) {
            print("DEBUG: FolderManager - Found \(matchingFeeds.count) matching feeds for smart folder: \(smartFolder.name)")
            completion(matchingFeeds)
        }
    }
    
    /// Gets articles that match a specific smart folder's rules
    static func getMatchingArticles(for smartFolder: SmartFolder, allArticles: [RSSItem], completion: @escaping ([RSSItem]) -> Void) {
        print("DEBUG: FolderManager - Getting matching articles for smart folder: \(smartFolder.name)")
        print("DEBUG: FolderManager - Total articles to check: \(allArticles.count)")
        print("DEBUG: FolderManager - Smart folder rules: \(smartFolder.rules.map { "\($0.field) \($0.operation) \($0.value)" }.joined(separator: ", "))")
        print("DEBUG: FolderManager - Match mode: \(smartFolder.matchMode)")
        
        if !smartFolder.includesArticles {
            print("DEBUG: FolderManager - Smart folder doesn't include articles, returning empty array")
            completion([])
            return
        }
        
        // Print a few article titles for debugging
        if allArticles.count > 0 {
            print("DEBUG: FolderManager - Sample article titles:")
            for i in 0..<min(5, allArticles.count) {
                print("DEBUG: FolderManager - Article \(i): \"\(allArticles[i].title)\"")
            }
        }
        
        var matchingArticles: [RSSItem] = []
        let articleGroup = DispatchGroup()
        
        for article in allArticles {
            articleGroup.enter()
            smartFolder.matchesArticle(article) { matches in
                if matches {
                    matchingArticles.append(article)
                    print("DEBUG: FolderManager - Article matched: \"\(article.title)\"")
                }
                articleGroup.leave()
            }
        }
        
        articleGroup.notify(queue: .main) {
            print("DEBUG: FolderManager - Found \(matchingArticles.count) matching articles for smart folder: \(smartFolder.name)")
            completion(matchingArticles)
        }
    }
}

/// Extension to StorageManager to handle saving and loading SmartFolders
extension StorageManager {
    // MARK: - Smart Folder Management
    
    /// Get all smart folders from storage
    func getSmartFolders(completion: @escaping (Result<[SmartFolder], Error>) -> Void) {
        print("DEBUG: Getting smart folders from storage")
        
        // Try to load directly from UserDefaults first
        if let data = UserDefaults.standard.data(forKey: "smartFolders") {
            do {
                let folders = try JSONDecoder().decode([SmartFolder].self, from: data)
                print("DEBUG: Successfully loaded \(folders.count) smart folders from UserDefaults")
                if !folders.isEmpty {
                    print("DEBUG: First smart folder: \(folders.first?.name ?? "unknown"), Root folders: \(folders.filter { $0.parentId == nil }.count)")
                }
                DispatchQueue.main.async {
                    completion(.success(folders))
                }
                return
            } catch {
                print("DEBUG: Error decoding smart folders from UserDefaults: \(error.localizedDescription)")
                // Continue to try loading from the storage system if UserDefaults fails
            }
        }
        
        // If UserDefaults doesn't have folders, try the storage system
        load(forKey: "smartFolders") { (result: Result<[SmartFolder], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let folders):
                    print("DEBUG: Successfully loaded \(folders.count) smart folders from storage")
                    if !folders.isEmpty {
                        print("DEBUG: First smart folder: \(folders.first?.name ?? "unknown"), Root folders: \(folders.filter { $0.parentId == nil }.count)")
                    }
                    completion(.success(folders))
                case .failure(let error):
                    if case StorageError.notFound = error {
                        // If no folders are found, return an empty array
                        print("DEBUG: No smart folders found in storage (normal for first run)")
                        completion(.success([]))
                    } else {
                        print("DEBUG: Error loading smart folders: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Create a new smart folder
    func createSmartFolder(name: String, 
                          description: String = "",
                          parentId: String? = nil,
                          rules: [SmartFolderRule] = [],
                          matchMode: SmartFolderMatchMode = .all,
                          includesArticles: Bool = true,
                          completion: @escaping (Result<SmartFolder, Error>) -> Void) {
        print("DEBUG: Creating smart folder: '\(name)', parentId: \(parentId ?? "root")")
        
        getSmartFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(var folders):
                print("DEBUG: Got \(folders.count) existing smart folders")
                print("DEBUG: Root smart folders: \(folders.filter { $0.parentId == nil }.count)")
                
                // Determine the sort index for the new folder
                var sortIndex = 0
                if let parentId = parentId {
                    // For a subfolder, find the highest sort index of siblings and add 1
                    let siblings = folders.filter { $0.parentId == parentId }
                    print("DEBUG: Found \(siblings.count) sibling smart folders for parent \(parentId)")
                    
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
                    print("DEBUG: Found \(rootFolders.count) root smart folders")
                    
                    if let highestIndex = rootFolders.map({ $0.sortIndex }).max() {
                        sortIndex = highestIndex + 1
                        print("DEBUG: Using sort index \(sortIndex) based on root folders")
                    } else {
                        print("DEBUG: No root smart folders found, using sort index 0")
                    }
                }
                
                // Create new folder
                let newFolder = SmartFolder(
                    name: name,
                    description: description,
                    parentId: parentId,
                    rules: rules,
                    matchMode: matchMode,
                    sortIndex: sortIndex,
                    includesArticles: includesArticles
                )
                print("DEBUG: Created new smart folder with ID: \(newFolder.id)")
                folders.append(newFolder)
                
                // Log folders before saving
                print("DEBUG: Saving new smart folder \(newFolder.name) to storage. Total folders: \(folders.count)")
                print("DEBUG: Current smart folder list: \(folders.map { "\($0.name) (ID: \($0.id))" })")
                
                // Save directly to UserDefaults for immediate local access
                if let encodedData = try? JSONEncoder().encode(folders) {
                    print("DEBUG: Directly saving to UserDefaults")
                    UserDefaults.standard.set(encodedData, forKey: "smartFolders")
                    UserDefaults.standard.synchronize()
                    print("DEBUG: UserDefaults synchronized")
                } else {
                    print("DEBUG: Failed to encode smart folders for UserDefaults")
                }
                
                // Verify folder was saved in UserDefaults
                if let data = UserDefaults.standard.data(forKey: "smartFolders") {
                    do {
                        let savedFolders = try JSONDecoder().decode([SmartFolder].self, from: data)
                        let folderExists = savedFolders.contains(where: { $0.id == newFolder.id })
                        print("DEBUG: Folder exists in UserDefaults after direct save: \(folderExists)")
                    } catch {
                        print("DEBUG: Error verifying folder in UserDefaults: \(error)")
                    }
                }
                
                // Save to the storage system (CloudKit or UserDefaults)
                print("DEBUG: Saving to storage system")
                self.save(folders, forKey: "smartFolders") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("DEBUG: Error saving smart folder: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else {
                            print("DEBUG: Successfully saved smart folder to storage")
                            
                            // Double-check the folder is really there
                            self.verifySmartFolderWasSaved(newFolder.id) { exists in
                                print("DEBUG: Final verification of saved smart folder: \(exists ? "EXISTS" : "NOT FOUND")")
                                
                                completion(.success(newFolder))
                                
                                // Post notification that folders have been updated
                                print("DEBUG: Posting smartFoldersUpdated notification")
                                NotificationCenter.default.post(name: Notification.Name("smartFoldersUpdated"), object: nil)
                            }
                        }
                    }
                }
            case .failure(let error):
                print("DEBUG: Failed to get existing smart folders: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Verify a smart folder was successfully saved
    private func verifySmartFolderWasSaved(_ folderId: String, completion: @escaping (Bool) -> Void) {
        print("DEBUG: Verifying smart folder was saved: \(folderId)")
        
        // Check UserDefaults first
        if let data = UserDefaults.standard.data(forKey: "smartFolders") {
            do {
                let folders = try JSONDecoder().decode([SmartFolder].self, from: data)
                if folders.contains(where: { $0.id == folderId }) {
                    print("DEBUG: Smart folder found in UserDefaults verification")
                    completion(true)
                    return
                } else {
                    print("DEBUG: Smart folder NOT found in UserDefaults verification")
                }
            } catch {
                print("DEBUG: Error decoding smart folders during verification: \(error)")
            }
        } else {
            print("DEBUG: No smart folder data in UserDefaults during verification")
        }
        
        // Check StorageManager as backup
        self.getSmartFolders { result in
            switch result {
            case .success(let folders):
                let exists = folders.contains(where: { $0.id == folderId })
                print("DEBUG: Smart folder exists in StorageManager verification: \(exists)")
                completion(exists)
            case .failure(let error):
                print("DEBUG: Error verifying smart folder in StorageManager: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    /// Update an existing smart folder
    func updateSmartFolder(_ folder: SmartFolder, completion: @escaping (Result<Bool, Error>) -> Void) {
        getSmartFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(var folders):
                // Find and update the folder
                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    // Prevent circular hierarchies by checking if the new parent is itself or one of its descendants
                    if let newParentId = folder.parentId {
                        if newParentId == folder.id {
                            completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "A folder cannot be its own parent"])))
                            return
                        }
                        
                        // Check if new parent is a descendant of this folder
                        // Get all descendant folder IDs manually since we can't use FolderManager.getAllDescendantFolders
                        var descendants: [SmartFolder] = []
                        var toProcess = folders.filter { $0.parentId == folder.id }
                        
                        while !toProcess.isEmpty {
                            descendants.append(contentsOf: toProcess)
                            let childIds = toProcess.map { $0.id }
                            toProcess = folders.filter { $0.parentId != nil && childIds.contains($0.parentId!) }
                        }
                        
                        if descendants.contains(where: { $0.id == newParentId }) {
                            completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "Cannot create circular folder references"])))
                            return
                        }
                    }
                    
                    folders[index] = folder
                    
                    // Save updated folders list
                    self.save(folders, forKey: "smartFolders") { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                completion(.success(true))
                                
                                // Post notification that folders have been updated
                                NotificationCenter.default.post(name: Notification.Name("smartFoldersUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Smart folder not found"])))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Delete a smart folder
    func deleteSmartFolder(id: String, deleteSubfolders: Bool = false, completion: @escaping (Result<Bool, Error>) -> Void) {
        print("DEBUG: Deleting smart folder with ID: \(id), deleteSubfolders: \(deleteSubfolders)")
        
        getSmartFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(var folders):
                print("DEBUG: Found \(folders.count) smart folders before deletion")
                print("DEBUG: Current smart folders: \(folders.map { "\($0.name) (ID: \($0.id))" })")
                
                // Get descendants of this folder
                let directDescendants = folders.filter { $0.parentId == id }
                print("DEBUG: Found \(directDescendants.count) descendants for smart folder ID: \(id)")
                
                if !deleteSubfolders && !directDescendants.isEmpty {
                    // If we're not deleting subfolders and there are descendants, return an error
                    print("DEBUG: Cannot delete smart folder with subfolders unless deleteSubfolders is true")
                    completion(.failure(NSError(domain: "StorageManager", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "Folder has subfolders. Set deleteSubfolders to true to delete them or move them first."])))
                    return
                }
                
                let foldersCountBefore = folders.count
                
                // Remove the folder and its descendants if requested
                if deleteSubfolders {
                    // Delete folder and all descendants
                    var allDescendants: [SmartFolder] = []
                    var toProcess = directDescendants
                    
                    // Get all descendants recursively
                    while !toProcess.isEmpty {
                        allDescendants.append(contentsOf: toProcess)
                        let childIds = toProcess.map { $0.id }
                        toProcess = folders.filter { $0.parentId != nil && childIds.contains($0.parentId!) }
                    }
                    
                    let folderIdsToDelete = [id] + allDescendants.map { $0.id }
                    print("DEBUG: Deleting smart folder IDs: \(folderIdsToDelete)")
                    folders.removeAll { folderIdsToDelete.contains($0.id) }
                } else {
                    // Just delete the folder
                    print("DEBUG: Deleting just smart folder ID: \(id)")
                    folders.removeAll { $0.id == id }
                }
                
                let foldersCountAfter = folders.count
                print("DEBUG: Deleted \(foldersCountBefore - foldersCountAfter) smart folders")
                print("DEBUG: Remaining smart folders: \(folders.map { "\($0.name) (ID: \($0.id))" })")
                
                // Save directly to UserDefaults for immediate local access
                if let encodedData = try? JSONEncoder().encode(folders) {
                    print("DEBUG: Directly saving updated smart folders to UserDefaults after deletion")
                    UserDefaults.standard.set(encodedData, forKey: "smartFolders")
                    UserDefaults.standard.synchronize()
                }
                
                // Save updated folders list
                self.save(folders, forKey: "smartFolders") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("DEBUG: Error saving updated smart folders after deletion: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else {
                            print("DEBUG: Successfully saved updated smart folders after deletion")
                            
                            // Verify the deletion in UserDefaults
                            if let data = UserDefaults.standard.data(forKey: "smartFolders") {
                                do {
                                    let savedFolders = try JSONDecoder().decode([SmartFolder].self, from: data)
                                    let folderStillExists = savedFolders.contains(where: { $0.id == id })
                                    print("DEBUG: After deletion, smart folder still exists in UserDefaults: \(folderStillExists)")
                                    
                                    if folderStillExists {
                                        print("DEBUG: WARNING - UserDefaults deletion failed, trying again")
                                        // If folder still exists, try saving to UserDefaults again
                                        if let encodedData = try? JSONEncoder().encode(folders) {
                                            UserDefaults.standard.set(encodedData, forKey: "smartFolders")
                                            UserDefaults.standard.synchronize()
                                        }
                                    }
                                } catch {
                                    print("DEBUG: Error checking UserDefaults after deletion: \(error)")
                                }
                            }
                            
                            completion(.success(true))
                            
                            // Post notification that folders have been updated
                            print("DEBUG: Posting smartFoldersUpdated notification after deletion")
                            NotificationCenter.default.post(name: Notification.Name("smartFoldersUpdated"), object: nil)
                        }
                    }
                }
            case .failure(let error):
                print("DEBUG: Error getting smart folders for deletion: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Get all feeds that match a smart folder's rules
    func getMatchingFeeds(forSmartFolderId folderId: String, completion: @escaping (Result<[RSSFeed], Error>) -> Void) {
        print("DEBUG: Getting matching feeds for smart folder ID: \(folderId)")
        
        // Create a dispatch group to wait for all async operations
        let group = DispatchGroup()
        
        // Variables to hold our results
        var smartFolder: SmartFolder?
        var allFeeds: [RSSFeed] = []
        var matchingFeeds: [RSSFeed] = []
        var loadError: Error?
        
        // Load the smart folder
        group.enter()
        getSmartFolders { result in
            switch result {
            case .success(let folders):
                smartFolder = folders.first { $0.id == folderId }
                if smartFolder == nil {
                    loadError = NSError(domain: "StorageManager", code: -1, 
                                       userInfo: [NSLocalizedDescriptionKey: "Smart folder not found"])
                }
            case .failure(let error):
                loadError = error
            }
            group.leave()
        }
        
        // Load all feeds
        group.enter()
        load(forKey: "rssFeeds") { (result: Result<[RSSFeed], Error>) in
            switch result {
            case .success(let feeds):
                allFeeds = feeds
            case .failure(let error):
                if loadError == nil {
                    loadError = error
                }
            }
            group.leave()
        }
        
        // When all async operations complete
        group.notify(queue: .main) {
            // Check for errors
            if let error = loadError {
                completion(.failure(error))
                return
            }
            
            // Make sure we found the smart folder
            guard let folder = smartFolder else {
                completion(.failure(NSError(domain: "StorageManager", code: -1, 
                                          userInfo: [NSLocalizedDescriptionKey: "Smart folder not found"])))
                return
            }
            
            // Find feeds that match the smart folder's rules
            let matchGroup = DispatchGroup()
            
            for feed in allFeeds {
                matchGroup.enter()
                folder.matchesFeed(feed) { matches in
                    if matches {
                        matchingFeeds.append(feed)
                    }
                    matchGroup.leave()
                }
            }
            
            matchGroup.notify(queue: .main) {
                print("DEBUG: Found \(matchingFeeds.count) matching feeds for smart folder: \(folder.name)")
                completion(.success(matchingFeeds))
            }
        }
    }
    
    /// Get all articles that match a smart folder's rules
    func getMatchingArticles(forSmartFolderId folderId: String, completion: @escaping (Result<[RSSItem], Error>) -> Void) {
        print("DEBUG: Getting matching articles for smart folder ID: \(folderId)")
        
        // Create a dispatch group to wait for all async operations
        let group = DispatchGroup()
        
        // Variables to hold our results
        var smartFolder: SmartFolder?
        var matchingFeeds: [RSSFeed] = []
        var allArticles: [RSSItem] = []
        var matchingArticles: [RSSItem] = []
        var loadError: Error?
        
        // Load the smart folder
        group.enter()
        getSmartFolders { result in
            switch result {
            case .success(let folders):
                smartFolder = folders.first { $0.id == folderId }
                if smartFolder == nil {
                    loadError = NSError(domain: "StorageManager", code: -1, 
                                       userInfo: [NSLocalizedDescriptionKey: "Smart folder not found"])
                }
            case .failure(let error):
                loadError = error
            }
            group.leave()
        }
        
        // When the smart folder is loaded
        group.notify(queue: .main) {
            // Check for errors
            if let error = loadError {
                completion(.failure(error))
                return
            }
            
            // Make sure we found the smart folder
            guard let folder = smartFolder else {
                completion(.failure(NSError(domain: "StorageManager", code: -1, 
                                          userInfo: [NSLocalizedDescriptionKey: "Smart folder not found"])))
                return
            }
            
            // If the folder doesn't include articles, return an empty array
            if !folder.includesArticles {
                print("DEBUG: Smart folder doesn't include articles, returning empty array")
                completion(.success([]))
                return
            }
            
            // First get matching feeds
            self.getMatchingFeeds(forSmartFolderId: folderId) { feedResult in
                switch feedResult {
                case .success(let feeds):
                    matchingFeeds = feeds
                    
                    // If we don't have any matching feeds, we won't have any matching articles
                    if matchingFeeds.isEmpty && !folder.rules.isEmpty {
                        completion(.success([]))
                        return
                    }
                    
                    // Load articles for all feeds
                    let articleGroup = DispatchGroup()
                    
                    for feed in matchingFeeds {
                        articleGroup.enter()
                        // This will use the articles in memory first, then fall back to loading from storage
                        self.getArticlesForFeed(url: feed.url) { articleResult in
                            switch articleResult {
                            case .success(let feedArticles):
                                // Convert RSSItem from ArticleSummary
                                let items = feedArticles.map { summary in
                                    RSSItem(
                                        title: summary.title,
                                        link: summary.link,
                                        pubDate: summary.pubDate,
                                        source: feed.url
                                    )
                                }
                                allArticles.append(contentsOf: items)
                            case .failure(let error):
                                print("DEBUG: Error loading articles for feed \(feed.title): \(error.localizedDescription)")
                            }
                            articleGroup.leave()
                        }
                    }
                    
                    articleGroup.notify(queue: .main) {
                        // Find articles that match the smart folder's rules
                        let matchGroup = DispatchGroup()
                        
                        for article in allArticles {
                            matchGroup.enter()
                            folder.matchesArticle(article) { matches in
                                if matches {
                                    matchingArticles.append(article)
                                }
                                matchGroup.leave()
                            }
                        }
                        
                        matchGroup.notify(queue: .main) {
                            print("DEBUG: Found \(matchingArticles.count) matching articles for smart folder: \(folder.name)")
                            completion(.success(matchingArticles))
                        }
                    }
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Helper method to get articles for a feed
    private func getArticlesForFeed(url: String, completion: @escaping (Result<[ArticleSummary], Error>) -> Void) {
        // This will implement the article loading logic
        // Look up the articles in memory, then fall back to loading from storage
        let normalizedURL = normalizeLink(url)
        
        // Check if we have a CloudKit database
        if method == .cloudKit {
            let cloudKit = CloudKitStorage()
            // Use CloudKit's database directly to load articles
            // Creates a record ID using the feed's normalized URL
            let recordID = CKRecord.ID(recordName: "feedArticlesRecord-\(normalizedURL)")
            
            cloudKit.database.fetch(withRecordID: recordID) { record, error in
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
        } else {
            // Try to load from UserDefaults
            let key = "articles-\(normalizedURL)"
            if let data = UserDefaults.standard.data(forKey: key) {
                do {
                    let articles = try JSONDecoder().decode([ArticleSummary].self, from: data)
                    completion(.success(articles))
                } catch {
                    print("DEBUG: Error decoding articles from UserDefaults: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            } else {
                completion(.failure(StorageError.notFound))
            }
        }
    }
}