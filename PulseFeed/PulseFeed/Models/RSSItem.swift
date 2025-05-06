import Foundation

struct RSSItem: Codable {
    let title: String
    let link: String
    let pubDate: String
    let source: String
    var isRead: Bool = false

    enum CodingKeys: String, CodingKey {
        case title, link, pubDate, source, isRead
    }
}