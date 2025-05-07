import Foundation

/// Represents a search query with various filter options
struct SearchQuery: Codable, Hashable {
    /// Unique identifier for the search query
    let id: String
    
    /// The text to search for across all searchable fields
    var searchText: String = ""
    
    /// Whether to search in article titles
    var searchInTitle: Bool = true
    
    /// Whether to search in article content/description
    var searchInContent: Bool = true
    
    /// Whether to search by author name
    var searchInAuthor: Bool = false
    
    /// Whether to search by feed title/source
    var searchInFeedTitle: Bool = false
    
    /// Whether to search only in articles with specific tags
    var filterByTags: Bool = false
    
    /// IDs of tags to filter by (if filterByTags is true)
    var tagIds: [String] = []
    
    /// Whether to filter by read status
    var filterByReadStatus: Bool = false
    
    /// The read status to filter by (if filterByReadStatus is true)
    var isRead: Bool = false
    
    /// Whether to filter by date range
    var filterByDate: Bool = false
    
    /// Start date for date range filter (if filterByDate is true)
    var startDate: Date?
    
    /// End date for date range filter (if filterByDate is true)
    var endDate: Date?
    
    /// Whether to filter by bookmarked status
    var filterByBookmarked: Bool = false
    
    /// The bookmarked status to filter by (if filterByBookmarked is true)
    var isBookmarked: Bool = true
    
    /// Whether to filter by hearted/favorited status
    var filterByHearted: Bool = false
    
    /// The hearted/favorited status to filter by (if filterByHearted is true)
    var isHearted: Bool = true
    
    /// Create a new search query with default values and a random ID
    init() {
        self.id = UUID().uuidString
    }
    
    /// Create a new search query with specific values
    init(searchText: String, 
         searchInTitle: Bool = true,
         searchInContent: Bool = true,
         searchInAuthor: Bool = false,
         searchInFeedTitle: Bool = false,
         filterByTags: Bool = false,
         tagIds: [String] = [],
         filterByReadStatus: Bool = false,
         isRead: Bool = false,
         filterByDate: Bool = false,
         startDate: Date? = nil,
         endDate: Date? = nil,
         filterByBookmarked: Bool = false,
         isBookmarked: Bool = true,
         filterByHearted: Bool = false,
         isHearted: Bool = true) {
        self.id = UUID().uuidString
        self.searchText = searchText
        self.searchInTitle = searchInTitle
        self.searchInContent = searchInContent
        self.searchInAuthor = searchInAuthor
        self.searchInFeedTitle = searchInFeedTitle
        self.filterByTags = filterByTags
        self.tagIds = tagIds
        self.filterByReadStatus = filterByReadStatus
        self.isRead = isRead
        self.filterByDate = filterByDate
        self.startDate = startDate
        self.endDate = endDate
        self.filterByBookmarked = filterByBookmarked
        self.isBookmarked = isBookmarked
        self.filterByHearted = filterByHearted
        self.isHearted = isHearted
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SearchQuery, rhs: SearchQuery) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Extension to add search functionality
extension SearchQuery {
    /// Evaluates whether an article matches this search query
    func matchesArticle(_ article: RSSItem, 
                       in bookmarkedItems: Set<String>, 
                       heartedItems: Set<String>,
                       completion: @escaping (Bool) -> Void) {
        // Create dispatch group for async operations
        let group = DispatchGroup()
        var tagCheckResult = true
        
        // First check if there's search text to match
        if !searchText.isEmpty {
            let normalizedSearchText = searchText.lowercased()
            var textMatch = false
            
            // Search in title if enabled
            if searchInTitle {
                if article.title.lowercased().contains(normalizedSearchText) {
                    textMatch = true
                }
            }
            
            // Search in content if enabled and not already matched
            if !textMatch && searchInContent {
                let content = article.content ?? article.description ?? ""
                if content.lowercased().contains(normalizedSearchText) {
                    textMatch = true
                }
            }
            
            // Search in author if enabled and not already matched
            if !textMatch && searchInAuthor {
                if let author = article.author, author.lowercased().contains(normalizedSearchText) {
                    textMatch = true
                }
            }
            
            // Search in feed title/source if enabled and not already matched
            if !textMatch && searchInFeedTitle {
                if article.source.lowercased().contains(normalizedSearchText) {
                    textMatch = true
                }
            }
            
            // If we haven't found a match in any of the selected fields, this article doesn't match
            if !textMatch {
                completion(false)
                return
            }
        }
        
        // Check tags if enabled
        if filterByTags && !tagIds.isEmpty {
            group.enter()
            
            // Fetch tags for this article
            article.getTags { result in
                switch result {
                case .success(let tags):
                    // Check if any of the article's tags match the filter tags
                    let articleTagIds = tags.map { $0.id }
                    let hasMatchingTag = !Set(articleTagIds).isDisjoint(with: Set(self.tagIds))
                    tagCheckResult = hasMatchingTag
                case .failure:
                    // If there's an error getting tags, consider it not matching
                    tagCheckResult = false
                }
                group.leave()
            }
        }
        
        // Check read status if enabled
        if filterByReadStatus {
            if article.isRead != isRead {
                completion(false)
                return
            }
        }
        
        // Check date range if enabled
        if filterByDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
            
            // Try to parse the article publication date
            if let pubDate = dateFormatter.date(from: article.pubDate) {
                // Check if date is within range
                if let start = startDate, pubDate < start {
                    completion(false)
                    return
                }
                
                if let end = endDate, pubDate > end {
                    completion(false)
                    return
                }
            } else {
                // If date can't be parsed, consider it not matching for date filter
                completion(false)
                return
            }
        }
        
        // Check bookmarked status if enabled
        if filterByBookmarked {
            let isArticleBookmarked = bookmarkedItems.contains(article.link)
            if isArticleBookmarked != isBookmarked {
                completion(false)
                return
            }
        }
        
        // Check hearted status if enabled
        if filterByHearted {
            let isArticleHearted = heartedItems.contains(article.link)
            if isArticleHearted != isHearted {
                completion(false)
                return
            }
        }
        
        // Wait for all async operations to complete
        group.notify(queue: .main) {
            // If tags check failed, the article doesn't match
            if !tagCheckResult {
                completion(false)
                return
            }
            
            // If we've passed all filters, the article matches
            completion(true)
        }
    }
    
    /// Helper function to match multiple articles efficiently
    func filterArticles(_ articles: [RSSItem],
                       in bookmarkedItems: Set<String>,
                       heartedItems: Set<String>,
                       completion: @escaping ([RSSItem]) -> Void) {
        // Create a dispatch group to handle concurrent matching
        let group = DispatchGroup()
        var matchingArticles: [RSSItem] = []
        
        // Lock for thread-safe access to matchingArticles
        let lock = NSLock()
        
        // Process each article
        for article in articles {
            group.enter()
            
            matchesArticle(article, in: bookmarkedItems, heartedItems: heartedItems) { matches in
                if matches {
                    lock.lock()
                    matchingArticles.append(article)
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        // When all matching operations are complete, return the matching articles
        group.notify(queue: .main) {
            completion(matchingArticles)
        }
    }
}

/// Manager for saving and loading search queries
class SearchManager {
    /// Shared instance
    static let shared = SearchManager()
    
    /// Save a search query for later use
    func saveSearchQuery(_ query: SearchQuery, completion: @escaping (Error?) -> Void) {
        getSavedSearchQueries { result in
            switch result {
            case .success(var queries):
                // Check if this query ID already exists
                if let index = queries.firstIndex(where: { $0.id == query.id }) {
                    // Update existing query
                    queries[index] = query
                } else {
                    // Add new query
                    queries.append(query)
                }
                
                // Save updated queries
                StorageManager.shared.save(queries, forKey: "savedSearchQueries", completion: completion)
                
            case .failure:
                // If there are no saved queries yet, create a new array with this query
                StorageManager.shared.save([query], forKey: "savedSearchQueries", completion: completion)
            }
        }
    }
    
    /// Get all saved search queries
    func getSavedSearchQueries(completion: @escaping (Result<[SearchQuery], Error>) -> Void) {
        StorageManager.shared.load(forKey: "savedSearchQueries", completion: completion)
    }
    
    /// Delete a saved search query
    func deleteSearchQuery(id: String, completion: @escaping (Error?) -> Void) {
        getSavedSearchQueries { result in
            switch result {
            case .success(var queries):
                // Remove the query with the given ID
                queries.removeAll { $0.id == id }
                
                // Save updated queries
                StorageManager.shared.save(queries, forKey: "savedSearchQueries", completion: completion)
                
            case .failure(let error):
                completion(error)
            }
        }
    }
}