import Foundation

/// Class for managing tag operations
class TagManager {
    // Singleton instance
    static let shared = TagManager()
    
    // Storage for instance methods
    private var cachedTags: [Tag] = []
    private var cachedTaggedItems: [TaggedItem] = []
    private var isCacheLoaded = false
    
    // MARK: - Instance Methods
    
    /// Initialize with storage
    init() {
        // Load tags and tagged items into cache on initialization
        loadCache()
    }
    
    /// Load tags and tagged items from storage
    private func loadCache() {
        StorageManager.shared.load(forKey: "tags") { [weak self] (result: Result<[Tag], Error>) in
            guard let self = self else { return }
            if case .success(let tags) = result {
                self.cachedTags = tags
            }
            
            StorageManager.shared.load(forKey: "taggedItems") { [weak self] (result: Result<[TaggedItem], Error>) in
                guard let self = self else { return }
                if case .success(let taggedItems) = result {
                    self.cachedTaggedItems = taggedItems
                }
                self.isCacheLoaded = true
            }
        }
    }
    
    /// Get all tags
    func getTags(completion: @escaping (Result<[Tag], Error>) -> Void) {
        if isCacheLoaded {
            completion(.success(cachedTags))
        } else {
            StorageManager.shared.load(forKey: "tags", completion: completion)
        }
    }
    
    /// Get a specific tag by ID
    func getTag(id: String, completion: @escaping (Result<Tag, Error>) -> Void) {
        getTags { result in
            switch result {
            case .success(let tags):
                if let tag = tags.first(where: { $0.id == id }) {
                    completion(.success(tag))
                } else {
                    completion(.failure(NSError(domain: "TagManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tag not found"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Get items with a specific tag
    func getItemsWithTag(tagId: String, itemType: TaggedItem.ItemType, completion: @escaping (Result<[String], Error>) -> Void) {
        StorageManager.shared.load(forKey: "taggedItems") { (result: Result<[TaggedItem], Error>) in
            switch result {
            case .success(let taggedItems):
                let items = TagManager.getItems(withTagId: tagId, itemType: itemType, from: taggedItems)
                completion(.success(items))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Static Helper Methods
    
    /// Get all tags for a specific item
    static func getTags(for itemId: String, itemType: TaggedItem.ItemType, from tags: [Tag], taggedItems: [TaggedItem]) -> [Tag] {
        let tagIds = taggedItems.filter { $0.itemId == itemId && $0.itemType == itemType }
                               .map { $0.tagId }
        
        return tags.filter { tagIds.contains($0.id) }
                  .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    /// Get all items with a specific tag
    static func getItems(withTagId tagId: String, itemType: TaggedItem.ItemType, from taggedItems: [TaggedItem]) -> [String] {
        return taggedItems.filter { $0.tagId == tagId && $0.itemType == itemType }
                         .map { $0.itemId }
    }
    
    /// Get all tags with their item counts
    static func getTagsWithCounts(from tags: [Tag], taggedItems: [TaggedItem]) -> [(tag: Tag, count: Int)] {
        return tags.map { tag in
            let count = taggedItems.filter { $0.tagId == tag.id }.count
            return (tag: tag, count: count)
        }.sorted { $0.tag.name.lowercased() < $1.tag.name.lowercased() }
    }
    
    /// Add a tag to an item
    static func addTag(tagId: String, toItemId itemId: String, itemType: TaggedItem.ItemType) -> TaggedItem {
        return TaggedItem(tagId: tagId, itemId: itemId, itemType: itemType)
    }
    
    /// Remove a tag from an item
    static func removeTag(tagId: String, fromItemId itemId: String, itemType: TaggedItem.ItemType, in taggedItems: [TaggedItem]) -> [TaggedItem] {
        return taggedItems.filter { !($0.tagId == tagId && $0.itemId == itemId && $0.itemType == itemType) }
    }
    
    /// Generate a unique color for a new tag
    static func generateUniqueColor(existingTags: [Tag]) -> String {
        let predefinedColors = [
            "#007AFF", // Blue
            "#FF9500", // Orange
            "#FF2D55", // Pink
            "#5856D6", // Purple
            "#34C759", // Green
            "#AF52DE", // Purple
            "#FF3B30", // Red
            "#5AC8FA", // Light Blue
            "#FFCC00", // Yellow
            "#4CD964", // Green
            "#FF2D55", // Pink
            "#8E8E93"  // Gray
        ]
        
        let existingColors = Set(existingTags.map { $0.colorHex })
        
        // First try to find an unused predefined color
        for color in predefinedColors {
            if !existingColors.contains(color) {
                return color
            }
        }
        
        // If all predefined colors are used, generate a random one
        let randomRed = Int.random(in: 0...255)
        let randomGreen = Int.random(in: 0...255)
        let randomBlue = Int.random(in: 0...255)
        
        return String(format: "#%02X%02X%02X", randomRed, randomGreen, randomBlue)
    }
}