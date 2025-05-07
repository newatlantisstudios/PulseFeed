import Foundation

/// Represents a folder in a hierarchical structure to organize RSS feeds
struct HierarchicalFolder: Codable, Hashable {
    /// Unique identifier for the folder
    let id: String
    
    /// Name of the folder
    var name: String
    
    /// ID of the parent folder (nil if it's a root folder)
    var parentId: String?
    
    /// List of feed URLs contained directly in this folder (not in subfolders)
    var feedURLs: [String]
    
    /// Order index for sorting (lower numbers come first)
    var sortIndex: Int
    
    /// Create a new folder with a random ID and optional initial feeds and parent
    init(name: String, parentId: String? = nil, feedURLs: [String] = [], sortIndex: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.parentId = parentId
        self.feedURLs = feedURLs
        self.sortIndex = sortIndex
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, parentId, feedURLs, sortIndex
    }
    
    // Use id as the unique identifier
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: HierarchicalFolder, rhs: HierarchicalFolder) -> Bool {
        return lhs.id == rhs.id
    }
    
    /// Returns true if this folder is a root folder (no parent)
    var isRoot: Bool {
        return parentId == nil
    }
}