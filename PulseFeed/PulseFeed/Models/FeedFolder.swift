import Foundation

/// Represents a folder to organize RSS feeds
struct FeedFolder: Codable, Hashable {
    /// Unique identifier for the folder
    let id: String
    
    /// Name of the folder
    var name: String
    
    /// List of feed URLs contained in this folder
    var feedURLs: [String]
    
    /// Create a new folder with a random ID and optional initial feeds
    init(name: String, feedURLs: [String] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.feedURLs = feedURLs
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, feedURLs
    }
    
    // Use id as the unique identifier
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FeedFolder, rhs: FeedFolder) -> Bool {
        return lhs.id == rhs.id
    }
}