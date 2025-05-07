import Foundation

/// Represents an association between a tag and an item (feed or article)
struct TaggedItem: Codable, Hashable {
    /// ID of the tag
    let tagId: String
    
    /// ID of the tagged item (usually the URL or link)
    let itemId: String
    
    /// Type of the tagged item (e.g., "feed" or "article")
    let itemType: ItemType
    
    /// Timestamp when the tag was added
    let dateTagged: Date
    
    /// Types of items that can be tagged
    enum ItemType: String, Codable {
        case feed, article
    }
    
    init(tagId: String, itemId: String, itemType: ItemType) {
        self.tagId = tagId
        self.itemId = itemId
        self.itemType = itemType
        self.dateTagged = Date()
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(tagId)
        hasher.combine(itemId)
        hasher.combine(itemType)
    }
    
    static func == (lhs: TaggedItem, rhs: TaggedItem) -> Bool {
        return lhs.tagId == rhs.tagId &&
               lhs.itemId == rhs.itemId &&
               lhs.itemType == rhs.itemType
    }
}