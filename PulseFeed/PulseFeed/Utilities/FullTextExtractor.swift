import Foundation

class FullTextExtractor {
    
    // MARK: - Types
    
    /// Completion handler for a batch of extraction tasks
    typealias BatchCompletionHandler = ([RSSItem]) -> Void
    
    /// Completion handler for a single extraction task
    typealias ExtractionCompletionHandler = (RSSItem) -> Void
    
    // MARK: - Properties
    
    /// Singleton instance
    static let shared = FullTextExtractor()
    
    /// Whether full-text extraction is enabled
    var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "enableFullTextExtraction")
    }
    
    /// Number of concurrent extraction tasks allowed
    private let maxConcurrentExtractions = 3
    
    /// Active operation queue for extraction tasks
    private let extractionQueue = OperationQueue()
    
    /// Set of feeds known to provide partial content
    private var partialFeedSources: Set<String> = []
    
    /// Cache mapping link URLs to extracted content
    private var contentCache: [String: String] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // Set maximum concurrent operations
        extractionQueue.maxConcurrentOperationCount = maxConcurrentExtractions
        extractionQueue.qualityOfService = .utility
        
        // Load saved partial feed sources
        loadPartialFeedSources()
    }
    
    // MARK: - Public Methods
    
    /// Extracts full content for a batch of RSSItems from partial feeds
    /// - Parameters:
    ///   - items: Array of RSS items that need full content extraction
    ///   - completion: Closure called when all extractions are complete
    func extractFullContentForItems(_ items: [RSSItem], completion: @escaping BatchCompletionHandler) {
        guard isEnabled else {
            // If feature is disabled, return original items unchanged
            completion(items)
            return
        }
        
        // Make a mutable copy of the items
        var mutableItems = items
        
        // Stop if no items
        if items.isEmpty {
            completion(mutableItems)
            return
        }
        
        // Track number of items that need processing
        let itemsNeedingExtraction = DispatchGroup()
        
        // For each item, check if it needs full content extraction
        for (index, item) in items.enumerated() {
            // Skip if item already has full content or doesn't need extraction
            if item.content != nil && !item.content!.isEmpty {
                // Item already has full content
                continue
            }
            
            if !shouldAttemptExtraction(for: item) {
                // Item doesn't need extraction
                continue
            }
            
            // Check if we have cached content for this item
            let normalizedLink = normalizeLink(item.link)
            if let cachedContent = getCachedContent(for: normalizedLink) {
                // Use cached content
                mutableItems[index].content = cachedContent
                continue
            }
            
            // The item needs content extraction
            itemsNeedingExtraction.enter()
            
            // Create extraction operation
            let extractionOperation = BlockOperation { [weak self] in
                guard let self = self else {
                    itemsNeedingExtraction.leave()
                    return
                }
                
                self.extractFullContent(for: item) { updatedItem in
                    // Replace the item in our mutable array
                    DispatchQueue.main.async {
                        if let idx = mutableItems.firstIndex(where: { $0.link == updatedItem.link }) {
                            mutableItems[idx] = updatedItem
                        }
                        itemsNeedingExtraction.leave()
                    }
                }
            }
            
            // Add operation to queue
            extractionQueue.addOperation(extractionOperation)
        }
        
        // After all extractions are complete, call completion handler
        itemsNeedingExtraction.notify(queue: .main) {
            completion(mutableItems)
        }
    }
    
    /// Extracts full content for a single RSSItem if needed
    /// - Parameters:
    ///   - item: RSS item that might need full content extraction
    ///   - completion: Closure called when extraction is complete with the updated item
    func extractFullContentIfNeeded(for item: RSSItem, completion: @escaping ExtractionCompletionHandler) {
        guard isEnabled else {
            // If feature is disabled, return original item unchanged
            completion(item)
            return
        }
        
        // If the item already has full content or doesn't need extraction, return it as is
        if (item.content != nil && !item.content!.isEmpty) || !shouldAttemptExtraction(for: item) {
            completion(item)
            return
        }
        
        // Check if we have cached content for this item
        let normalizedLink = normalizeLink(item.link)
        if let cachedContent = getCachedContent(for: normalizedLink) {
            // Use cached content
            var updatedItem = item
            updatedItem.content = cachedContent
            completion(updatedItem)
            return
        }
        
        // Perform the extraction
        extractFullContent(for: item, completion: completion)
    }
    
    /// Process a feed's items and mark the feed as partial if appropriate
    /// - Parameter items: Array of items from a single feed
    /// - Parameter source: The feed source/title
    func analyzeAndTrackPartialFeed(items: [RSSItem], source: String) {
        // If most items have empty or very short content/description, mark as partial feed
        let totalItems = items.count
        guard totalItems > 0 else { return }
        
        var partialItemCount = 0
        
        for item in items {
            // Check if the item has partial or no content
            if isPartialContent(item) {
                partialItemCount += 1
            }
        }
        
        // If more than 70% of items appear to have partial content, mark as partial feed
        let threshold = 0.7
        let partialRatio = Double(partialItemCount) / Double(totalItems)
        
        if partialRatio > threshold {
            // Add to set of partial feeds if not already there
            if !partialFeedSources.contains(source) {
                partialFeedSources.insert(source)
                savePartialFeedSources()
            }
        } else {
            // If we previously marked this as partial but it now appears to have full content,
            // remove it from the set
            if partialFeedSources.contains(source) {
                partialFeedSources.remove(source)
                savePartialFeedSources()
            }
        }
    }
    
    /// Clears the content cache to free memory
    func clearCache() {
        contentCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// Determines if full-text extraction should be attempted for an item
    /// - Parameter item: The RSS item to check
    /// - Returns: True if extraction should be attempted
    private func shouldAttemptExtraction(for item: RSSItem) -> Bool {
        // If feed source is known to provide partial content, attempt extraction
        if partialFeedSources.contains(item.source) {
            return true
        }
        
        // Otherwise, check content directly
        return isPartialContent(item)
    }
    
    /// Function to remove HTML tags from a string (used internally)
    private static func removeHTMLTags(from html: String) -> String {
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
    
    /// Determines if an item appears to have partial content
    /// - Parameter item: The RSS item to check
    /// - Returns: True if the content appears to be partial
    private func isPartialContent(_ item: RSSItem) -> Bool {
        // Get the longest available content from the item
        let contentText = item.content ?? item.description ?? ""
        
        // Empty content is definitely partial
        if contentText.isEmpty {
            return true
        }
        
        // Check for common indicators of partial content
        let lowerContent = contentText.lowercased()
        let partialContentMarkers = ["read more", "continue reading", "... "]
        for marker in partialContentMarkers {
            if lowerContent.contains(marker) {
                return true
            }
        }
        
        // If content is very short (less than 200 chars), it's likely partial
        if contentText.count < 200 {
            return true
        }
        
        // If the content is HTML, remove tags and check length
        let plainText = Self.removeHTMLTags(from: contentText)
        if plainText.count < 200 {
            return true
        }
        
        // Check if there's significantly less text than a typical article
        // Typical articles have 300+ words
        let words = plainText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.count < 100 {
            return true
        }
        
        // Content seems substantial
        return false
    }
    
    /// Extracts full content for a single RSSItem
    /// - Parameters:
    ///   - item: RSS item that needs full content extraction
    ///   - completion: Closure called when extraction is complete with the updated item
    private func extractFullContent(for item: RSSItem, completion: @escaping ExtractionCompletionHandler) {
        guard let url = URL(string: item.link) else {
            // Invalid URL, return original item
            completion(item)
            return
        }
        
        // Create a task to fetch the article HTML
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil,
                  let html = String(data: data, encoding: .utf8) else {
                // Failed to fetch or decode HTML, return original item
                DispatchQueue.main.async {
                    completion(item)
                }
                return
            }
            
            // Use the ContentExtractor to extract readable content
            let extractedContent = ContentExtractor.extractReadableContent(from: html, url: url)
            
            // Create updated item with the full content
            var updatedItem = item
            updatedItem.content = extractedContent
            
            // Cache the extracted content
            let normalizedLink = self.normalizeLink(item.link)
            self.cacheContent(extractedContent, for: normalizedLink)
            
            // Return the updated item
            DispatchQueue.main.async {
                completion(updatedItem)
            }
        }
        
        task.resume()
    }
    
    /// Normalizes a link for consistent caching
    /// - Parameter link: The link URL string
    /// - Returns: A normalized version of the link
    private func normalizeLink(_ link: String) -> String {
        return StorageManager.shared.normalizeLink(link)
    }
    
    /// Caches extracted content for a link
    /// - Parameters:
    ///   - content: The extracted content
    ///   - link: The normalized link URL string
    private func cacheContent(_ content: String, for link: String) {
        contentCache[link] = content
    }
    
    /// Retrieves cached content for a link if available
    /// - Parameter link: The normalized link URL string
    /// - Returns: The cached content, or nil if not in cache
    private func getCachedContent(for link: String) -> String? {
        return contentCache[link]
    }
    
    /// Loads the set of partial feed sources from UserDefaults
    private func loadPartialFeedSources() {
        StorageManager.shared.load(forKey: "partialFeedSources") { [weak self] (result: Result<[String], Error>) in
            if case .success(let sources) = result {
                self?.partialFeedSources = Set(sources)
            }
        }
    }
    
    /// Saves the set of partial feed sources to UserDefaults
    private func savePartialFeedSources() {
        StorageManager.shared.save(Array(partialFeedSources), forKey: "partialFeedSources") { error in
            if let error = error {
                print("Error saving partial feed sources: \(error.localizedDescription)")
            }
        }
    }
}

