import Foundation

/// Represents a group of duplicate articles, with one designated as the "primary" version
struct DuplicateArticleGroup: Codable, Equatable {
    /// The primary (chosen) version of the article
    var primary: RSSItem
    
    /// All duplicate versions of the article
    var duplicates: [RSSItem]
    
    /// Total number of articles in this group (primary + duplicates)
    var count: Int {
        return 1 + duplicates.count
    }
    
    /// Initialize with a primary article and its duplicates
    /// - Parameters:
    ///   - primary: The primary article version
    ///   - duplicates: Array of duplicate versions
    init(primary: RSSItem, duplicates: [RSSItem] = []) {
        self.primary = primary
        self.duplicates = duplicates
    }
    
    /// Convenience initializer from an array where the first item is the primary
    /// - Parameter articles: Array of articles where the first is the primary
    init(articles: [RSSItem]) {
        guard !articles.isEmpty else {
            fatalError("Cannot create a duplicate group with no articles")
        }
        
        self.primary = articles[0]
        
        if articles.count > 1 {
            self.duplicates = Array(articles[1...])
        } else {
            self.duplicates = []
        }
    }
    
    /// Change which article is the primary
    /// - Parameter newPrimaryIndex: Index in the duplicates array to make primary
    /// - Returns: Updated group with the new primary article
    func changePrimary(to newPrimaryIndex: Int) -> DuplicateArticleGroup {
        guard newPrimaryIndex >= 0 && newPrimaryIndex < duplicates.count else {
            // Invalid index, return the group unchanged
            return self
        }
        
        // Select the new primary
        let newPrimary = duplicates[newPrimaryIndex]
        
        // Create a new array of duplicates with the old primary
        var newDuplicates = duplicates
        newDuplicates.remove(at: newPrimaryIndex)
        newDuplicates.append(primary)
        
        return DuplicateArticleGroup(primary: newPrimary, duplicates: newDuplicates)
    }
    
    /// Get all articles in this group (primary first, then duplicates)
    /// - Returns: Array with all articles in the group
    func allArticles() -> [RSSItem] {
        var result = [primary]
        result.append(contentsOf: duplicates)
        return result
    }
    
    /// Get the list of sources for all articles in this group
    /// - Returns: Array of source names
    func sources() -> [String] {
        var sources = [primary.source]
        sources.append(contentsOf: duplicates.map { $0.source })
        return sources
    }
    
    // MARK: - Equatable
    
    static func == (lhs: DuplicateArticleGroup, rhs: DuplicateArticleGroup) -> Bool {
        // Two groups are equal if they contain the same articles (regardless of which is primary)
        let lhsAll = Set(lhs.allArticles().map { $0.link })
        let rhsAll = Set(rhs.allArticles().map { $0.link })
        return lhsAll == rhsAll
    }
}