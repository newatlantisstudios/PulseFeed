import Foundation

class ArticleSummarizer {
    
    // MARK: - Types
    
    /// Completion handler for summarization
    typealias SummarizationCompletionHandler = (Result<String, Error>) -> Void
    
    // MARK: - Properties
    
    /// Singleton instance
    static let shared = ArticleSummarizer()
    
    /// Whether article summarization is enabled
    var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "enableArticleSummarization")
    }
    
    /// Cache mapping link URLs to generated summaries
    private var summaryCache: [String: String] = [:]
    
    /// Queue for summarization tasks
    private let summarizationQueue = OperationQueue()
    
    // MARK: - Errors
    
    enum SummarizerError: Error {
        case missingContent
        case failedToSummarize
        case summarizationDisabled
    }
    
    // MARK: - Initialization
    
    private init() {
        // Set maximum concurrent operations
        summarizationQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount
        summarizationQueue.qualityOfService = .utility
    }
    
    // MARK: - Public Methods
    
    /// Summarizes an article based on its content
    /// - Parameters:
    ///   - item: The RSS item to summarize
    ///   - completion: Closure called when summarization is complete
    func summarizeArticle(item: RSSItem, completion: @escaping SummarizationCompletionHandler) {
        guard isEnabled else {
            completion(.failure(SummarizerError.summarizationDisabled))
            return
        }
        
        // Check if we have a cached summary for this item
        let normalizedLink = normalizeLink(item.link)
        if let cachedSummary = getCachedSummary(for: normalizedLink) {
            completion(.success(cachedSummary))
            return
        }
        
        // Check if we need to extract full content first
        let articleContent = item.content ?? item.description ?? ""
        if articleContent.isEmpty {
            // We need full content first
            FullTextExtractor.shared.extractFullContentIfNeeded(for: item) { [weak self] updatedItem in
                guard let self = self else {
                    completion(.failure(SummarizerError.failedToSummarize))
                    return
                }
                
                // Now that we have the full content, try to summarize again
                self.generateSummary(for: updatedItem, completion: completion)
            }
        } else {
            // We already have content, summarize directly
            generateSummary(for: item, completion: completion)
        }
    }
    
    /// Clears the summary cache
    func clearCache() {
        summaryCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// Generates a summary for an article with content
    /// - Parameters:
    ///   - item: The RSS item to summarize
    ///   - completion: Closure called when summarization is complete
    private func generateSummary(for item: RSSItem, completion: @escaping SummarizationCompletionHandler) {
        // Get the article content
        let articleContent = item.content ?? item.description ?? ""
        
        if articleContent.isEmpty {
            completion(.failure(SummarizerError.missingContent))
            return
        }
        
        // Use a background queue for the summarization
        summarizationQueue.addOperation { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(.failure(SummarizerError.failedToSummarize))
                }
                return
            }
            
            // This is where we would integrate with an AI summarization API
            // For now, we'll create a simple rule-based summarizer
            let summary = self.createSimpleSummary(from: articleContent, title: item.title)
            
            // Cache the summary
            let normalizedLink = self.normalizeLink(item.link)
            self.cacheSummary(summary, for: normalizedLink)
            
            // Return the summary
            DispatchQueue.main.async {
                completion(.success(summary))
            }
        }
    }
    
    /// Creates a simple summary from article content
    /// - Parameters:
    ///   - content: The article content
    ///   - title: The article title
    /// - Returns: A generated summary
    private func createSimpleSummary(from content: String, title: String) -> String {
        // Remove HTML tags from content
        let plainText = content.removingHTMLTags()
        
        // Split into sentences
        let sentences = plainText.components(separatedBy: ".").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // If we have too few sentences, return a shortened version of what we have
        if sentences.count <= 3 {
            let combinedText = sentences.joined(separator: ". ")
            if combinedText.count <= 200 {
                return combinedText + "."
            } else {
                return String(combinedText.prefix(200)) + "..."
            }
        }
        
        // For a simple summary, use the first 3 sentences
        // In a real implementation, you would use NLP or an AI API to generate a better summary
        let leadSentences = Array(sentences.prefix(3))
        var summary = leadSentences.joined(separator: ". ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure summary ends with proper punctuation
        if !summary.hasSuffix(".") {
            summary += "."
        }
        
        return summary
    }
    
    /// Normalizes a link for consistent caching
    /// - Parameter link: The link URL string
    /// - Returns: A normalized version of the link
    private func normalizeLink(_ link: String) -> String {
        // Use StorageManager's normalize method if available, otherwise DIY
        return StorageManager.shared.normalizeLink(link)
    }
    
    /// Caches a summary for a link
    /// - Parameters:
    ///   - summary: The generated summary
    ///   - link: The normalized link URL string
    private func cacheSummary(_ summary: String, for link: String) {
        summaryCache[link] = summary
    }
    
    /// Retrieves a cached summary for a link if available
    /// - Parameter link: The normalized link URL string
    /// - Returns: The cached summary, or nil if not in cache
    private func getCachedSummary(for link: String) -> String? {
        return summaryCache[link]
    }
}

// Note: No need to redefine String.removingHTMLTags() extension
// It's already defined in ContentExtractor.swift