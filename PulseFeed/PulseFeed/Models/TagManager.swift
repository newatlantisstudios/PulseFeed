import Foundation

/// Class for managing tag operations
class TagManager {
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