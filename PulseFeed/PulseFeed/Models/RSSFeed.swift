import Foundation

struct RSSFeed: Codable, Hashable {
    let url: String
    let title: String
    var lastUpdated: Date
    
    private enum CodingKeys: String, CodingKey {
        case url, title, lastUpdated
    }
    
    // Use url as the unique identifier.
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    static func == (lhs: RSSFeed, rhs: RSSFeed) -> Bool {
        return lhs.url == rhs.url
    }
}