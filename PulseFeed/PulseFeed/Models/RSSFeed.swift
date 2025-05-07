import Foundation

struct RSSFeed: Codable, Hashable {
    let url: String
    var title: String
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
    
    // MARK: - Tag Operations
    
    /// Get all tags for this feed
    func getTags(completion: @escaping (Result<[Tag], Error>) -> Void) {
        StorageManager.shared.getTagsForItem(itemId: url, itemType: .feed, completion: completion)
    }
    
    /// Add a tag to this feed
    func addTag(_ tag: Tag, completion: @escaping (Result<Bool, Error>) -> Void) {
        StorageManager.shared.addTagToItem(tagId: tag.id, itemId: url, itemType: .feed) { result in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Remove a tag from this feed
    func removeTag(_ tag: Tag, completion: @escaping (Result<Bool, Error>) -> Void) {
        StorageManager.shared.removeTagFromItem(tagId: tag.id, itemId: url, itemType: .feed) { result in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Folder Operations
    
    /// Get the folders this feed belongs to
    func getFolders(completion: @escaping (Result<[HierarchicalFolder], Error>) -> Void) {
        StorageManager.shared.getHierarchicalFolders { result in
            switch result {
            case .success(let folders):
                let normalizedURL = StorageManager.shared.normalizeLink(url)
                let feedFolders = folders.filter { folder in
                    folder.feedURLs.contains { StorageManager.shared.normalizeLink($0) == normalizedURL }
                }
                completion(.success(feedFolders))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Add this feed to a folder
    func addToFolder(_ folder: HierarchicalFolder, completion: @escaping (Result<Bool, Error>) -> Void) {
        StorageManager.shared.addFeedToHierarchicalFolder(feedURL: url, folderId: folder.id, completion: completion)
    }
    
    /// Remove this feed from a folder
    func removeFromFolder(_ folder: HierarchicalFolder, completion: @escaping (Result<Bool, Error>) -> Void) {
        StorageManager.shared.removeFeedFromHierarchicalFolder(feedURL: url, folderId: folder.id, completion: completion)
    }
}