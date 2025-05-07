import Foundation

struct ArticleSummary: Codable {
    let title: String
    let link: String
    let pubDate: String
    
    // MARK: - Tag Operations
    
    /// Get all tags for this article
    func getTags(completion: @escaping (Result<[Tag], Error>) -> Void) {
        StorageManager.shared.getTagsForItem(itemId: link, itemType: .article, completion: completion)
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