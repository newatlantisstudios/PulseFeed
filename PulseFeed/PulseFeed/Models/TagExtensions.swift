import Foundation

// MARK: - StorageManager Extensions for Tags

extension StorageManager {
    // MARK: - Tag Management
    
    // Tag cache to clear
    private static var tagCache: [String: [Tag]] = [:]
    
    /// Clear any cached tag data to force refresh
    func clearTagCache() {
        print("DEBUG: Clearing tag cache")
        StorageManager.tagCache.removeAll()
    }
    
    /// Get all tags from storage - prioritizing UserDefaults for UI responsiveness
    func getTagsFromDefaults(completion: @escaping (Result<[Tag], Error>) -> Void) {
        //print("DEBUG: StorageManager - Getting all tags")
        
        // Check UserDefaults directly first for faster UI response
        if let data = UserDefaults.standard.data(forKey: "tags") {
            do {
                let tags = try JSONDecoder().decode([Tag].self, from: data)
                //print("DEBUG: StorageManager - DIRECT loaded \(tags.count) tags from UserDefaults")
                // Skip printing tags in debug mode
                // This was causing a build error due to an unused variable reference in a comment
                DispatchQueue.main.async {
                    completion(.success(tags))
                }
                return
            } catch {
                print("DEBUG: StorageManager - Error decoding tags from UserDefaults: \(error.localizedDescription)")
                // Continue with normal loading if direct access fails
            }
        } else {
            print("DEBUG: StorageManager - No tags data found in UserDefaults")
        }
        
        // Fall back to normal loading mechanism
        load(forKey: "tags") { (result: Result<[Tag], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let tags):
                    print("DEBUG: StorageManager - Successfully loaded \(tags.count) tags")
                    // Debug info - looping through tags removed to prevent unused variable warnings
                    completion(.success(tags))
                case .failure(let error):
                    if case StorageError.notFound = error {
                        // If no tags are found, return an empty array
                        print("DEBUG: StorageManager - No tags found in storage, returning empty array")
                        completion(.success([]))
                    } else {
                        print("DEBUG: StorageManager - Error loading tags: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Create a new tag
    func createTag(name: String, colorHex: String? = nil, completion: @escaping (Result<Tag, Error>) -> Void) {
        getTagsFromDefaults { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(var tags):
                // Check if tag with this name already exists
                if tags.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "A tag with this name already exists"])))
                    }
                    return
                }
                
                // Generate a color if not provided
                let color = colorHex ?? TagManager.generateUniqueColor(existingTags: tags)
                
                // Create new tag
                let newTag = Tag(name: name, colorHex: color)
                tags.append(newTag)
                
                // Save updated tags list
                self.save(tags, forKey: "tags") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            // Also update in UserDefaults for immediate local access
                            if let encodedData = try? JSONEncoder().encode(tags) {
                                UserDefaults.standard.set(encodedData, forKey: "tags")
                                print("DEBUG: StorageManager - Directly saved tags to UserDefaults: \(tags.count) tags")
                            }
                            
                            // Force reload the storage cache to ensure we get fresh data
                            StorageManager.tagCache.removeAll()
                            
                            completion(.success(newTag))
                            
                            // Post notification that tags have been updated with a slight delay
                            // to ensure persistence is complete
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                print("DEBUG: StorageManager - Posting tagsUpdated notification for new tag: \(newTag.name)")
                                NotificationCenter.default.post(name: Notification.Name("tagsUpdated"), object: nil, userInfo: ["tagId": newTag.id])
                            }
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
    
    /// Update an existing tag
    func updateTag(_ tag: Tag, completion: @escaping (Result<Bool, Error>) -> Void) {
        getTagsFromDefaults { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(var tags):
                // Find and update the tag
                if let index = tags.firstIndex(where: { $0.id == tag.id }) {
                    // Check if the new name conflicts with another tag
                    if tags.contains(where: { $0.id != tag.id && $0.name.lowercased() == tag.name.lowercased() }) {
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "Another tag with this name already exists"])))
                        }
                        return
                    }
                    
                    tags[index] = tag
                    
                    // Save updated tags list
                    self.save(tags, forKey: "tags") { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                completion(.success(true))
                                
                                // Post notification that tags have been updated
                                NotificationCenter.default.post(name: Notification.Name("tagsUpdated"), object: nil)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "StorageManager", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Tag not found"])))
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Delete a tag
    func deleteTag(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        getTagsFromDefaults { [weak self] tagsResult in
            guard let self = self else { return }
            
            switch tagsResult {
            case .success(var tags):
                // Remove the tag
                tags.removeAll { $0.id == id }
                
                // Save updated tags list
                self.save(tags, forKey: "tags") { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    
                    // Now remove all tagged items for this tag
                    self.getTaggedItems { taggedItemsResult in
                        switch taggedItemsResult {
                        case .success(var taggedItems):
                            // Remove all tagged items with this tag ID
                            taggedItems.removeAll { $0.tagId == id }
                            
                            // Save updated tagged items list
                            self.save(taggedItems, forKey: "taggedItems") { error in
                                if let error = error {
                                    completion(.failure(error))
                                } else {
                                    // Post notifications that both tags and tagged items were updated
                                    NotificationCenter.default.post(name: Notification.Name("tagsUpdated"), object: nil)
                                    NotificationCenter.default.post(name: Notification.Name("taggedItemsUpdated"), object: nil)
                                    completion(.success(true))
                                }
                            }
                            
                        case .failure(let error):
                            // Still consider the tag deletion successful even if we can't update tagged items
                            print("Warning: Could not update tagged items after tag deletion: \(error.localizedDescription)")
                            NotificationCenter.default.post(name: Notification.Name("tagsUpdated"), object: nil)
                            completion(.success(true))
                        }
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Tagged Item Management
    
    /// Get all tagged items from storage
    func getTaggedItems(completion: @escaping (Result<[TaggedItem], Error>) -> Void) {
        load(forKey: "taggedItems") { (result: Result<[TaggedItem], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let taggedItems):
                    completion(.success(taggedItems))
                case .failure(let error):
                    if case StorageError.notFound = error {
                        // If no tagged items are found, return an empty array
                        completion(.success([]))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Add a tag to an item
    func addTagToItem(tagId: String, itemId: String, itemType: TaggedItem.ItemType, completion: @escaping (Result<Bool, Error>) -> Void) {
        // First verify that the tag exists
        getTagsFromDefaults { [weak self] tagsResult in
            guard let self = self else { return }
            
            switch tagsResult {
            case .success(let tags):
                if !tags.contains(where: { $0.id == tagId }) {
                    completion(.failure(NSError(domain: "StorageManager", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "Tag not found"])))
                    return
                }
                
                // Now get all tagged items
                self.getTaggedItems { taggedItemsResult in
                    switch taggedItemsResult {
                    case .success(var taggedItems):
                        // Check if this item is already tagged with this tag
                        if taggedItems.contains(where: { $0.tagId == tagId && $0.itemId == itemId && $0.itemType == itemType }) {
                            completion(.success(true)) // Already tagged
                            return
                        }
                        
                        // Add the new tagged item
                        let newTaggedItem = TaggedItem(tagId: tagId, itemId: itemId, itemType: itemType)
                        taggedItems.append(newTaggedItem)
                        
                        // Save updated tagged items list
                        self.save(taggedItems, forKey: "taggedItems") { error in
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                // Clear the tag cache for this item
                                let cacheKey = "\(itemId)-\(itemType.rawValue)"
                                StorageManager.tagCache.removeValue(forKey: cacheKey)
                                
                                print("DEBUG: Tag added to item, cleared cache for: \(cacheKey)")
                                
                                // Post notification that tagged items have been updated
                                // Include the itemId in the notification so we can update just the affected cells
                                NotificationCenter.default.post(
                                    name: Notification.Name("taggedItemsUpdated"),
                                    object: nil,
                                    userInfo: ["itemId": itemId, "tagId": tagId, "itemType": itemType.rawValue]
                                )
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
    
    /// Remove a tag from an item
    func removeTagFromItem(tagId: String, itemId: String, itemType: TaggedItem.ItemType, completion: @escaping (Result<Bool, Error>) -> Void) {
        getTaggedItems { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(var taggedItems):
                // Remove the tagged item
                taggedItems.removeAll { $0.tagId == tagId && $0.itemId == itemId && $0.itemType == itemType }
                
                // Save updated tagged items list
                self.save(taggedItems, forKey: "taggedItems") { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        // Clear the tag cache for this item
                        let cacheKey = "\(itemId)-\(itemType.rawValue)"
                        StorageManager.tagCache.removeValue(forKey: cacheKey)
                        
                        print("DEBUG: Tag removed from item, cleared cache for: \(cacheKey)")
                        
                        // Post notification that tagged items have been updated
                        // Include the itemId in the notification so we can update just the affected cells
                        NotificationCenter.default.post(
                            name: Notification.Name("taggedItemsUpdated"),
                            object: nil,
                            userInfo: ["itemId": itemId, "tagId": tagId, "itemType": itemType.rawValue]
                        )
                        completion(.success(true))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Get all tags for an item
    func getTagsForItem(itemId: String, itemType: TaggedItem.ItemType, completion: @escaping (Result<[Tag], Error>) -> Void) {
        // Generate a cache key
        let cacheKey = "\(itemId)-\(itemType.rawValue)"
        
        // Check if we have a cached result
        if let cachedTags = StorageManager.tagCache[cacheKey] {
            //print("DEBUG: Using cached tags for item: \(itemId)")
            completion(.success(cachedTags))
            return
        }
        
        //print("DEBUG: Fetching tags from storage for item: \(itemId)")
        
        // Get all tags and tagged items
        let group = DispatchGroup()
        
        var tagsResult: Result<[Tag], Error>?
        var taggedItemsResult: Result<[TaggedItem], Error>?
        
        group.enter()
        getTagsFromDefaults { result in
            tagsResult = result
            group.leave()
        }
        
        group.enter()
        getTaggedItems { result in
            taggedItemsResult = result
            group.leave()
        }
        
        group.notify(queue: .main) {
            // Extract tag data or handle errors
            var tags: [Tag] = []
            var taggedItems: [TaggedItem] = []
            var extractionError: Error? = nil
            
            if let tagResult = tagsResult {
                switch tagResult {
                case .success(let loadedTags):
                    tags = loadedTags
                case .failure(let error):
                    extractionError = error
                }
            }
            
            if extractionError == nil, let taggedItemResult = taggedItemsResult {
                switch taggedItemResult {
                case .success(let loadedItems):
                    taggedItems = loadedItems
                case .failure(let error):
                    extractionError = error
                }
            }
            
            // If we have an error, return it
            if let error = extractionError {
                completion(.failure(error))
                return
            }
            
            // If we don't have error but data extraction was incomplete
            if tagsResult == nil || taggedItemsResult == nil {
                completion(.failure(NSError(domain: "StorageManager", code: -1,
                                         userInfo: [NSLocalizedDescriptionKey: "Failed to load tags or tagged items"])))
                return
            }
            
            // Get tags for this item
            let itemTags = TagManager.getTags(for: itemId, itemType: itemType, from: tags, taggedItems: taggedItems)
            
            //print("DEBUG: Found \(itemTags.count) tags for item: \(itemId)")
            
            // Cache the result
            StorageManager.tagCache[cacheKey] = itemTags
            
            completion(.success(itemTags))
        }
    }
    
    /// Get all items with a specific tag
    func getItemsWithTag(tagId: String, itemType: TaggedItem.ItemType, completion: @escaping (Result<[String], Error>) -> Void) {
        getTaggedItems { result in
            switch result {
            case .success(let taggedItems):
                let items = TagManager.getItems(withTagId: tagId, itemType: itemType, from: taggedItems)
                completion(.success(items))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Get all tags with their item counts
    func getTagsWithCounts(completion: @escaping (Result<[(tag: Tag, count: Int)], Error>) -> Void) {
        print("DEBUG: StorageManager - Getting tags with counts")
        
        // First, clear the cache to force a fresh load
        StorageManager.tagCache.removeAll()
        
        // Check UserDefaults directly first for faster UI response with tags
        var directTags: [Tag]? = nil
        if let data = UserDefaults.standard.data(forKey: "tags") {
            do {
                let tags = try JSONDecoder().decode([Tag].self, from: data)
                //print("DEBUG: StorageManager - DIRECT loaded \(tags.count) tags from UserDefaults for counts")
                directTags = tags
            } catch {
                print("DEBUG: StorageManager - Error decoding tags from UserDefaults for counts: \(error.localizedDescription)")
            }
        }
        
        // If we have direct tags, use them with empty tagged items for initial display
        if let tags = directTags, !tags.isEmpty {
            print("DEBUG: StorageManager - Using direct tags for immediate display: \(tags.count) tags")
            let simpleTagsWithCounts = tags.map { (tag: $0, count: 0) }
            
            // Return these immediately for UI responsiveness
            DispatchQueue.main.async {
                completion(.success(simpleTagsWithCounts))
            }
            
            // Continue with full loading in background to get accurate counts
        }
        
        // Get all tags and tagged items
        let group = DispatchGroup()
        
        var tagsResult: Result<[Tag], Error>?
        var taggedItemsResult: Result<[TaggedItem], Error>?
        
        group.enter()
        getTagsFromDefaults { result in
            tagsResult = result
            group.leave()
        }
        
        group.enter()
        getTaggedItems { result in
            taggedItemsResult = result
            group.leave()
        }
        
        group.notify(queue: .main) {
            // Extract tag data or handle errors
            var tags: [Tag] = []
            var taggedItems: [TaggedItem] = []
            var extractionError: Error? = nil
            
            if let tagResult = tagsResult {
                switch tagResult {
                case .success(let loadedTags):
                    print("DEBUG: StorageManager - Loaded \(loadedTags.count) tags")
                    tags = loadedTags
                case .failure(let error):
                    print("DEBUG: StorageManager - Error loading tags: \(error.localizedDescription)")
                    extractionError = error
                }
            }
            
            if extractionError == nil, let taggedItemResult = taggedItemsResult {
                switch taggedItemResult {
                case .success(let loadedItems):
                    print("DEBUG: StorageManager - Loaded \(loadedItems.count) tagged items")
                    taggedItems = loadedItems
                case .failure(let error):
                    print("DEBUG: StorageManager - Error loading tagged items: \(error.localizedDescription)")
                    extractionError = error
                }
            }
            
            // If we have an error, return it (unless we already returned direct tags)
            if let error = extractionError, directTags == nil {
                completion(.failure(error))
                return
            }
            
            // If we don't have error but data extraction was incomplete (unless we already returned direct tags)
            if (tagsResult == nil || taggedItemsResult == nil) && directTags == nil {
                completion(.failure(NSError(domain: "StorageManager", code: -1,
                                         userInfo: [NSLocalizedDescriptionKey: "Failed to load tags or tagged items"])))
                return
            }
            
            // Skip further processing if we have no tags
            if tags.isEmpty && directTags == nil {
                completion(.success([]))
                return
            }
            
            // Get tags with counts
            let tagsWithCounts = TagManager.getTagsWithCounts(from: tags, taggedItems: taggedItems)
            print("DEBUG: StorageManager - Returning \(tagsWithCounts.count) tags with counts")
            for tagWithCount in tagsWithCounts {
                print("DEBUG: StorageManager - Tag: \(tagWithCount.tag.name), Count: \(tagWithCount.count)")
            }
            
            // Don't call completion again if we already returned direct tags
            if directTags == nil || !tagsWithCounts.isEmpty {
                completion(.success(tagsWithCounts))
            }
        }
    }
}
