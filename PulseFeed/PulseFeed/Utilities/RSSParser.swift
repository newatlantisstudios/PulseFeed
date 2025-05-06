import Foundation

class RSSParser: NSObject, XMLParserDelegate {
    private(set) var items: [RSSItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var parsingItem = false
    private var feedSource: String

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
        if elementName == "item" {
            parsingItem = true
            currentTitle = ""
            currentLink = ""
            currentPubDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if parsingItem {
            switch currentElement {
            case "title":
                currentTitle += string
            case "link":
                currentLink += string
            case "pubDate":
                currentPubDate += string
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
        if elementName == "item" {
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                pubDate: currentPubDate.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                source: feedSource)
            items.append(item)
            parsingItem = false
        }
    }
}