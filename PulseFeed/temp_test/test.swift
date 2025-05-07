import Foundation

enum FeedType {
    case rss, bookmarks, heart, folder(id: String), smartFolder(id: String)
}

// Test the pattern that's failing
func testPatterns() {
    let currentFeedType: FeedType = .rss
    
    // This is the problematic pattern we fixed
    // let isFolderFeed = { if case .folder = currentFeedType { return true } else { return false } }()
    // let isSmartFolderFeed = { if case .smartFolder = currentFeedType { return true } else { return false } }()
    // if isFolderFeed || isSmartFolderFeed {}
    
    // This is our fix
    let isFolderFeed: Bool
    if case .folder = currentFeedType {
        isFolderFeed = true
    } else {
        isFolderFeed = false
    }
    
    let isSmartFolderFeed: Bool
    if case .smartFolder = currentFeedType {
        isSmartFolderFeed = true
    } else {
        isSmartFolderFeed = false
    }
    
    if isFolderFeed || isSmartFolderFeed {
        print("In folder or smart folder")
    }
    
    // Test other pattern fixes
    let rssImageName: String
    if case .rss = currentFeedType {
        rssImageName = "rssFilled"
    } else {
        rssImageName = "rss"
    }
    
    print("RSS Image Name: \(rssImageName)")
}

testPatterns()
