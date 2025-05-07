import Foundation

class FeedParserTester {
    
    // Sample Atom feed XML for testing
    static let atomFeedSample = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Example Atom Feed</title>
      <link href="https://example.com/"/>
      <updated>2023-05-07T12:34:56Z</updated>
      <author>
        <name>Author Name</name>
      </author>
      <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
      <entry>
        <title>Test Entry 1</title>
        <link href="https://example.com/entry1"/>
        <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
        <updated>2023-05-06T17:30:00Z</updated>
        <summary>This is a test entry in an Atom feed</summary>
        <content type="html">&lt;p&gt;Content for Test Entry 1&lt;/p&gt;</content>
        <author>
          <name>John Doe</name>
        </author>
      </entry>
      <entry>
        <title>Test Entry 2</title>
        <link href="https://example.com/entry2"/>
        <id>urn:uuid:1225c695-cfb8-4ebb-bbbb-80da344efa6b</id>
        <updated>2023-05-05T10:15:00Z</updated>
        <summary>This is another test entry</summary>
        <content type="html">&lt;p&gt;Content for Test Entry 2&lt;/p&gt;</content>
        <author>
          <name>Jane Smith</name>
        </author>
      </entry>
    </feed>
    """
    
    // Sample RSS feed XML for testing
    static let rssFeedSample = """
    <?xml version="1.0" encoding="UTF-8" ?>
    <rss version="2.0">
    <channel>
      <title>RSS Test Feed</title>
      <link>https://example.com/rss</link>
      <description>Sample RSS feed for testing</description>
      <item>
        <title>RSS Test Item 1</title>
        <link>https://example.com/rss/item1</link>
        <description>This is a test item in an RSS feed</description>
        <pubDate>Wed, 06 May 2023 17:30:00 GMT</pubDate>
      </item>
      <item>
        <title>RSS Test Item 2</title>
        <link>https://example.com/rss/item2</link>
        <description>This is another test item</description>
        <pubDate>Tue, 05 May 2023 10:15:00 GMT</pubDate>
      </item>
    </channel>
    </rss>
    """
    
    // Sample partial feed items for testing detection
    static let partialItems = [
        RSSItem(
            title: "Test Partial Item 1",
            link: "https://example.com/partial1",
            pubDate: "Wed, 06 May 2023 17:30:00 GMT",
            source: "Partial Feed",
            description: "This is a short description... Read more",
            content: nil
        ),
        RSSItem(
            title: "Test Partial Item 2",
            link: "https://example.com/partial2",
            pubDate: "Tue, 05 May 2023 10:15:00 GMT",
            source: "Partial Feed",
            description: "Just a brief preview. Continue reading...",
            content: nil
        )
    ]
    
    // Sample full-content items for testing detection
    static let fullItems = [
        RSSItem(
            title: "Test Full Item 1",
            link: "https://example.com/full1",
            pubDate: "Wed, 06 May 2023 17:30:00 GMT",
            source: "Full Feed",
            description: "This is a comprehensive description with multiple paragraphs of text that would be considered full content. It includes detailed information about the topic and covers all the important points that a reader would expect in a complete article. The length is sufficient to convey the entire message without requiring the reader to visit the original website for more information.",
            content: "<p>This is a comprehensive article with multiple paragraphs of text that would be considered full content. It includes detailed information about the topic and covers all the important points that a reader would expect in a complete article.</p><p>The second paragraph adds even more depth to the content, discussing additional aspects of the topic. There might be lists, code samples, or other rich content that provides value to the reader.</p><p>In conclusion, this sample article demonstrates what full content looks like in an RSS feed, with sufficient detail and length to be considered complete.</p>"
        ),
        RSSItem(
            title: "Test Full Item 2",
            link: "https://example.com/full2",
            pubDate: "Tue, 05 May 2023 10:15:00 GMT",
            source: "Full Feed",
            description: "Another comprehensive article with sufficient content to be considered a full article without requiring the reader to visit the website for more information. This description contains enough text to pass the threshold for being considered full content.",
            content: "<p>Another comprehensive article with sufficient content to be considered a full article without requiring the reader to visit the website for more information.</p><p>This article has multiple paragraphs, images, and other elements that make it a complete piece of content rather than just a preview or summary.</p><p>The third paragraph continues to add information and value, ensuring that the reader gets the complete picture without needing to click through to the original website.</p>"
        )
    ]
    
    // Test the parser with both feed formats
    static func runParserTests() {
        print("===== RUNNING FEED PARSER TESTS =====")
        testAtomFeed()
        testRSSFeed()
        testPartialContentDetection()
        testFullTextExtraction()
        print("===== FEED PARSER TESTS COMPLETE =====")
    }
    
    // Test detection of partial vs. full content
    static func testPartialContentDetection() {
        print("Testing partial content detection...")
        
        // Test with partial items
        let isPartial = isPartialFeed(partialItems)
        print("Partial feed detection result: \(isPartial ? "✅ Correctly identified as partial" : "❌ Incorrectly identified as full")")
        
        // Test with full items
        let isFull = !isPartialFeed(fullItems)
        print("Full feed detection result: \(isFull ? "✅ Correctly identified as full" : "❌ Incorrectly identified as partial")")
        
        // Test individual items
        for (i, item) in partialItems.enumerated() {
            let result = isPartialContent(item)
            print("Partial item \(i+1): \(result ? "✅ Correctly identified as partial" : "❌ Incorrectly identified as full")")
        }
        
        for (i, item) in fullItems.enumerated() {
            let result = !isPartialContent(item)
            print("Full item \(i+1): \(result ? "✅ Correctly identified as full" : "❌ Incorrectly identified as partial")")
        }
    }
    
    // Test the full-text extraction system
    static func testFullTextExtraction() {
        print("Testing full-text extraction...")
        print("To test with a real URL, call: FeedParserTester.testContentExtraction(urlString: \"https://example.com/article\")")
    }
    
    private static func testAtomFeed() {
        print("Testing Atom feed parsing...")
        
        // Convert string to data
        guard let data = atomFeedSample.data(using: .utf8) else {
            print("Failed to convert Atom sample to data")
            return
        }
        
        // Create parser and parse
        let parser = XMLParser(data: data)
        let rssParser = RSSParser(source: "Atom Test Feed")
        parser.delegate = rssParser
        
        if parser.parse() {
            print("✅ Successfully parsed Atom feed")
            print("Found \(rssParser.items.count) items")
            
            // Print details of the items
            for (index, item) in rssParser.items.enumerated() {
                print("Item \(index + 1):")
                print("  Title: \(item.title)")
                print("  Link: \(item.link)")
                print("  Date: \(item.pubDate)")
                print("  Author: \(item.author ?? "N/A")")
                print("  ID: \(item.id ?? "N/A")")
                print("  Description: \(item.description ?? "N/A")")
                print("  Content: \(item.content?.prefix(50) ?? "N/A")...\(item.content != nil ? ")" : "")")
                print("")
            }
        } else {
            print("❌ Failed to parse Atom feed")
            if let error = parser.parserError {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    private static func testRSSFeed() {
        print("Testing RSS feed parsing...")
        
        // Convert string to data
        guard let data = rssFeedSample.data(using: .utf8) else {
            print("Failed to convert RSS sample to data")
            return
        }
        
        // Create parser and parse
        let parser = XMLParser(data: data)
        let rssParser = RSSParser(source: "RSS Test Feed")
        parser.delegate = rssParser
        
        if parser.parse() {
            print("✅ Successfully parsed RSS feed")
            print("Found \(rssParser.items.count) items")
            
            // Print details of the items
            for (index, item) in rssParser.items.enumerated() {
                print("Item \(index + 1):")
                print("  Title: \(item.title)")
                print("  Link: \(item.link)")
                print("  Date: \(item.pubDate)")
                print("  Description: \(item.description ?? "N/A")")
                print("")
            }
        } else {
            print("❌ Failed to parse RSS feed")
            if let error = parser.parserError {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Tests if a feed appears to provide partial content
    /// - Parameter items: Array of RSS items from a feed
    /// - Returns: True if feed appears to provide partial content
    static func isPartialFeed(_ items: [RSSItem]) -> Bool {
        guard !items.isEmpty else { return false }
        
        var partialItemCount = 0
        
        for item in items {
            if isPartialContent(item) {
                partialItemCount += 1
            }
        }
        
        // If more than 70% of items appear to have partial content, consider it a partial feed
        let threshold = 0.7
        let partialRatio = Double(partialItemCount) / Double(items.count)
        
        return partialRatio > threshold
    }
    
    /// Determines if an item appears to have partial content
    /// - Parameter item: The RSS item to check
    /// - Returns: True if the content appears to be partial
    static func isPartialContent(_ item: RSSItem) -> Bool {
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
        let plainText = removeTags(from: contentText)
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
    
    
    /// Removes HTML tags from a string
    private static func removeTags(from html: String) -> String {
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
    
    /// Tests content extraction from a URL
    /// - Parameter urlString: The URL to extract content from
    /// - Parameter completion: Closure called with extracted content
    static func testContentExtraction(urlString: String, completion: @escaping (String?, Error?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, NSError(domain: "FeedParserTester", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(nil, NSError(domain: "FeedParserTester", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode HTML"]))
                return
            }
            
            // Extract content using ContentExtractor
            let extractedContent = ContentExtractor.extractReadableContent(from: html, url: url)
            completion(extractedContent, nil)
        }
        
        task.resume()
    }
}