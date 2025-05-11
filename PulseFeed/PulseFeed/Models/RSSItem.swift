import Foundation

struct RSSItem: Codable, Equatable, Hashable {
    let title: String
    let link: String
    let pubDate: String
    let source: String
    var isRead: Bool = false
    var description: String?
    var content: String?
    var author: String?
    var id: String?
    
    init(title: String, link: String, pubDate: String, source: String, description: String? = nil, content: String? = nil, author: String? = nil, id: String? = nil) {
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.source = source
        self.description = description
        self.content = content
        self.author = author
        self.id = id
    }

    enum CodingKeys: String, CodingKey {
        case title, link, pubDate, source, isRead, description, content, author, id
    }
    
    // MARK: - Hashable Implementation
    
    func hash(into hasher: inout Hasher) {
        // Use link as the primary hash since it should be unique
        hasher.combine(link)
    }
    
    static func == (lhs: RSSItem, rhs: RSSItem) -> Bool {
        // Two items are equal if they have the same link
        return lhs.link == rhs.link
    }
    
    
}
