import Foundation

/// Represents a tag for categorizing RSS feeds and articles
struct Tag: Codable, Hashable {
    /// Unique identifier for the tag
    let id: String
    
    /// Name of the tag
    var name: String
    
    /// Color for visual identification (stored as hex string)
    var colorHex: String
    
    /// Create a new tag with a random ID and default color
    init(name: String, colorHex: String = "#007AFF") {
        self.id = UUID().uuidString
        self.name = name
        self.colorHex = colorHex
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, colorHex
    }
    
    // Use id as the unique identifier
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Tag, rhs: Tag) -> Bool {
        return lhs.id == rhs.id
    }
}