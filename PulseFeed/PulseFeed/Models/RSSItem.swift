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
    
    // MARK: - Tag Operations
    
    /// Get all tags for this article
    func getTags(completion: @escaping (Result<[Tag], Error>) -> Void) {
        //print("DEBUG: RSSItem.getTags - Fetching tags for item with link: \(link)")
        
        StorageManager.shared.getTagsForItem(itemId: link, itemType: .article) { result in
            switch result {
            case .success(let tags):
                //print("DEBUG: RSSItem.getTags - Found \(tags.count) tags for item: \(self.title)")
                // No need to loop through tags here
                completion(.success(tags))
            case .failure(let error):
                //print("DEBUG: RSSItem.getTags - Error fetching tags: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// Add a tag to this article
    func addTag(_ tag: Tag, completion: @escaping (Result<Bool, Error>) -> Void) {
        StorageManager.shared.addTagToItem(tagId: tag.id, itemId: link, itemType: .article) { result in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Remove a tag from this article
    func removeTag(_ tag: Tag, completion: @escaping (Result<Bool, Error>) -> Void) {
        StorageManager.shared.removeTagFromItem(tagId: tag.id, itemId: link, itemType: .article) { result in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
}
