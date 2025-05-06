import Foundation

class RSSParser: NSObject, XMLParserDelegate {
    private(set) var items: [RSSItem] = []
    private var currentElement = ""
    private var currentPath: [String] = []
    private var currentTitle = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var currentDescription = ""
    private var currentContent = ""
    private var currentAuthor = ""
    private var currentId = ""
    private var parsingItem = false
    private var isAtomFeed = false
    private var feedSource: String
    private var linkAttributes: [String: String] = [:]

    init(source: String) {
        self.feedSource = source
        super.init()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentPath.append(elementName)
        
        if elementName == "feed" && (namespaceURI == "http://www.w3.org/2005/Atom" || namespaceURI?.contains("atom") == true) {
            isAtomFeed = true
        }
        
        // Handle RSS items or Atom entries
        if elementName == "item" || elementName == "entry" {
            parsingItem = true
            resetItemFields()
        }
        
        // Special handling for Atom link elements which use attributes
        if elementName == "link" && !attributeDict.isEmpty {
            linkAttributes = attributeDict
            
            // Get link from href attribute for Atom feeds
            if isAtomFeed, let href = attributeDict["href"], attributeDict["rel"] == "alternate" || attributeDict["rel"] == nil {
                currentLink = href
            }
        }
        
        // Handle Atom content with attributes
        if elementName == "content" && parsingItem {
            // Store content type if present
            if let type = attributeDict["type"] {
                // Handle different content types if needed
                // For now, we'll capture the content regardless of type
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard parsingItem else { return }
        
        // Last element in current path is our current element
        if let lastElement = currentPath.last {
            switch lastElement {
            case "title":
                currentTitle += string
                
            case "link":
                // For RSS feeds, the link is in the text content
                // For Atom feeds, the link is usually an attribute handled in didStartElement
                if !isAtomFeed {
                    currentLink += string
                }
                
            // RSS date formats
            case "pubDate", "published", "updated", "date":
                currentPubDate += string
                
            // Description/summary fields
            case "description", "summary":
                currentDescription += string
                
            // Content fields
            case "content", "content:encoded":
                currentContent += string
                
            // Author fields
            case "author", "creator", "dc:creator":
                currentAuthor += string
                
            // ID fields (useful for Atom feeds)
            case "id", "guid":
                currentId += string
                
            default:
                break
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        // Remove last element from path
        if !currentPath.isEmpty && currentPath.last == elementName {
            currentPath.removeLast()
        }
        
        // Handle ending of item/entry element
        if (elementName == "item" || elementName == "entry") && parsingItem {
            // Make sure we have the minimum required fields
            guard !currentTitle.isEmpty && !currentLink.isEmpty else {
                parsingItem = false
                return
            }
            
            // Create and add the item
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines),
                source: feedSource,
                description: currentDescription.isEmpty ? nil : currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                content: currentContent.isEmpty ? nil : currentContent.trimmingCharacters(in: .whitespacesAndNewlines),
                author: currentAuthor.isEmpty ? nil : currentAuthor.trimmingCharacters(in: .whitespacesAndNewlines),
                id: currentId.isEmpty ? nil : currentId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            items.append(item)
            parsingItem = false
        }
    }
    
    // Helper method to reset all item fields when starting a new item
    private func resetItemFields() {
        currentTitle = ""
        currentLink = ""
        currentPubDate = ""
        currentDescription = ""
        currentContent = ""
        currentAuthor = ""
        currentId = ""
        linkAttributes = [:]
    }
}