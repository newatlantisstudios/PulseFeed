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
    
    // Test the parser with both feed formats
    static func runParserTests() {
        print("===== RUNNING FEED PARSER TESTS =====")
        testAtomFeed()
        testRSSFeed()
        print("===== FEED PARSER TESTS COMPLETE =====")
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
}