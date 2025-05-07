import Foundation

/// Protocol for objects that can be tagged
protocol Taggable {
    /// Get the unique identifier used for tagging
    var taggableId: String { get }
}

/// Extension to RSSFeed to make it taggable
extension RSSFeed: Taggable {
    var taggableId: String {
        return url // Use URL as the unique identifier
    }
}

/// Extension to RSSItem to make it taggable
extension RSSItem: Taggable {
    var taggableId: String {
        return link // Use link as the unique identifier
    }
}