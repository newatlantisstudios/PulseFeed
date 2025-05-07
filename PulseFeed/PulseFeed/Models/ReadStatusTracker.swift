import Foundation

// Make ReadStatusTracker a public class so it can be seen by other files
public class ReadStatusTracker {
    public static let shared = ReadStatusTracker()
    
    // Sets to track read status by normalized link
    private var readLinks: Set<String> = []
    
    // Storage key
    private let storageKey = "readItems"
    
    // Initialize with stored read items
    private init() {
        loadReadStatus()
    }
    
    // MARK: - Public API
    
    /// Check if an article is read
    /// - Parameter link: The article link
    /// - Returns: Bool indicating if the article has been read
    public func isArticleRead(link: String) -> Bool {
        let normalizedLink = normalizeLink(link)
        return readLinks.contains(normalizedLink)
    }
    
    /// Mark an article as read
    /// - Parameters:
    ///   - link: The article link
    ///   - isRead: Whether to mark as read or unread
    ///   - completion: Called when the operation completes
    public func markArticle(link: String, as isRead: Bool, completion: ((Bool) -> Void)? = nil) {
        let normalizedLink = normalizeLink(link)
        
        if isRead {
            readLinks.insert(normalizedLink)
        } else {
            readLinks.remove(normalizedLink)
        }
        
        saveReadStatus(completion: completion)
        
        // Notify that read status has changed
        NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
    }
    
    /// Mark multiple articles as read
    /// - Parameters:
    ///   - links: Array of article links
    ///   - isRead: Whether to mark as read or unread
    ///   - completion: Called when the operation completes
    public func markArticles(links: [String], as isRead: Bool, completion: ((Bool) -> Void)? = nil) {
        let normalizedLinks = links.map { normalizeLink($0) }
        
        if isRead {
            readLinks.formUnion(normalizedLinks)
        } else {
            normalizedLinks.forEach { readLinks.remove($0) }
        }
        
        saveReadStatus(completion: completion)
        
        // Notify that read status has changed
        NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
    }
    
    /// Mark all articles as read
    /// - Parameters:
    ///   - links: Array of all article links
    ///   - completion: Called when the operation completes
    public func markAllAsRead(links: [String], completion: ((Bool) -> Void)? = nil) {
        let normalizedLinks = links.map { normalizeLink($0) }
        readLinks.formUnion(normalizedLinks)
        
        saveReadStatus(completion: completion)
        
        // Notify that read status has changed
        NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
    }
    
    /// Get all read article links
    /// - Returns: Array of read article links (normalized)
    public func getAllReadLinks() -> [String] {
        return Array(readLinks)
    }
    
    /// Reset all read status
    /// - Parameter completion: Called when the operation completes
    public func resetReadStatus(completion: ((Bool) -> Void)? = nil) {
        readLinks.removeAll()
        saveReadStatus(completion: completion)
        
        // Notify that read status has been reset
        NotificationCenter.default.post(name: Notification.Name("readItemsReset"), object: nil)
    }
    
    // MARK: - Private Methods
    
    /// Save the read status to storage
    private func saveReadStatus(completion: ((Bool) -> Void)? = nil) {
        // Convert set to array for storage
        let linksArray = Array(readLinks)
        
        StorageManager.shared.save(linksArray, forKey: storageKey) { error in
            let success = error == nil
            completion?(success)
        }
    }
    
    /// Load the read status from storage
    private func loadReadStatus() {
        StorageManager.shared.load(forKey: storageKey) { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let readItems):
                    self.readLinks = Set(readItems)
                case .failure:
                    self.readLinks = []
                }
            }
        }
    }
    
    /// Helper to normalize links for consistent comparison
    private func normalizeLink(_ link: String) -> String {
        return StorageManager.shared.normalizeLink(link)
    }
}