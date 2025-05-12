import Foundation
import SwiftSoup

class ContentExtractor {
    
    // MARK: - Properties
    
    // Common article content class/id names used by popular websites
    private static let contentSelectors = [
        // Classes often used for main article content
        ".article",
        ".article-content",
        ".article-body",
        ".article-text",
        ".article__body",
        ".article__content",
        ".entry-content",
        ".post-content",
        ".post-body",
        ".content",
        ".main-content",
        ".page-content",
        ".story",
        ".story-body",
        
        // IDs often used for main article content
        "#article",
        "#article-content",
        "#articleBody",
        "#article-body",
        "#content",
        "#main-content",
        "#post-content",
        "#story",
        "#story-body",
        
        // Tag selectors as fallbacks
        "article",
        "main"
    ]
    
    // Elements to remove for cleaner reading
    private static let removeSelectors = [
        // Navigation elements
        "header", "footer", "nav", ".navigation", ".navbar", ".menu", ".nav", ".top-nav", 
        
        // Sidebars and non-essential content
        ".sidebar", ".side-bar", ".related", ".recommended", ".trending", 
        
        // Advertising and promotions
        ".ad", ".ads", ".advertisement", ".banner", ".promo", ".promotion", ".sponsored", "[class*='ad-']", "[id*='ad-']",
        
        // Social and sharing elements
        ".social", ".share", ".sharing", ".social-links", ".follow", ".subscribe",
        
        // Comments and user-generated content
        ".comments", ".comment-section", "#comments", ".user-comments", ".disqus",
        
        // Newsletter and subscription forms
        ".newsletter", ".subscribe", "form", ".subscribe-form", ".email-signup",
        
        // Widgets and external content
        ".widget", ".plugin", ".embed",
        
        // Code elements (if not a tech article)
        "script", "style", "iframe:not(.video-embed)",
        
        // Other non-essential elements
        "aside", ".popup", ".modal", ".tooltip", ".cookie-notice", ".gdpr"
    ]
    
    // Attributes to clean from elements that can contain tracking info
    private static let attributesToClean = [
        "data-src", "data-srcset", "data-lazy-src", "data-tracking", "data-ga", 
        "data-ad", "data-analytics", "data-target", "onclick", "onload"
    ]
    
    // Recognized article content markers/schema
    private static let schemaTypes = [
        "application/ld+json", "NewsArticle", "Article", "BlogPosting"
    ]
    
    // MARK: - Content Extraction
    
    /// Extracts the readable content from HTML using SwiftSoup
    static func extractReadableContent(from html: String, url: URL?) -> String {
        let domain = url?.host ?? ""
        do {
            let doc: Document = try SwiftSoup.parse(html, url?.absoluteString ?? "")

            // First look for schema.org metadata which often contains the full article content
            if let schemaContent = extractSchemaContent(from: html) {
                return cleanContent(schemaContent, baseUrl: url)
            }

            // Look for structured article content using common selectors
            for selector in contentSelectors {
                if let element = try? doc.select(selector).first(), let content = try? element.outerHtml() {
                    if isValidArticleContent(content) {
                        return cleanContent(content, baseUrl: url)
                    }
                }
            }

            // Try site-specific extractors for known domains
            if let content = extractContentForSpecificSite(doc: doc, html: html, domain: domain) {
                return cleanContent(content, baseUrl: url)
            }

            // Fallback: extract article using heuristics
            if let content = extractArticleUsingHeuristics(doc: doc) {
                return cleanContent(content, baseUrl: url)
            }

            // Last resort: just clean up the whole body
            if let body = try? doc.body(), let bodyContent = try? body.html() {
                return cleanContent(bodyContent, baseUrl: url)
            }

            // Ultimate fallback
            return cleanContent(html, baseUrl: url)
        } catch {
            // If SwiftSoup fails, fallback to old method
            return cleanContent(html, baseUrl: url)
        }
    }
    
    /// Look for schema.org metadata which often contains the full article content
    private static func extractSchemaContent(from html: String) -> String? {
        let ldJsonPattern = "<script[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        
        guard let jsonScripts = html.ranges(of: ldJsonPattern, options: []) else {
            return nil
        }
        
        for range in jsonScripts {
            let scriptTag = String(html[range])
            
            // Extract just the JSON content
            if let contentRange = scriptTag.range(of: ">(.*?)</script>", options: [.regularExpression]) {
                let startIndex = scriptTag.index(contentRange.lowerBound, offsetBy: 1)
                let endIndex = scriptTag.index(contentRange.upperBound, offsetBy: -9) // Remove "</script>"
                let jsonString = String(scriptTag[startIndex..<endIndex])
                
                // Try to parse the JSON
                do {
                    guard let data = jsonString.data(using: String.Encoding.utf8),
                          let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        continue
                    }
                    
                    // Look for article content
                    if let schemaType = json["@type"] as? String,
                       schemaTypes.contains(schemaType) {
                        
                        // Extract article content
                        if let articleBody = json["articleBody"] as? String {
                            return "<article>\(articleBody)</article>"
                        }
                        
                        // If the article has both headline and text, format them together
                        if let headline = json["headline"] as? String,
                           let text = json["text"] as? String {
                            return "<article><h1>\(headline)</h1><div>\(text)</div></article>"
                        }
                    }
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    /// Site-specific content extraction for known domains using SwiftSoup
    private static func extractContentForSpecificSite(doc: Document, html: String, domain: String) -> String? {
        do {
            // Medium and similar platforms
            if domain.contains("medium.com") || html.contains("data-selectable-paragraph") {
                let paragraphs = try doc.select("p[data-selectable-paragraph]")
                if !paragraphs.isEmpty() {
                    let joined = try paragraphs.map { try $0.outerHtml() }.joined()
                    return "<article>\(joined)</article>"
                }
            }
            // WordPress sites
            if html.contains("wp-content") || html.contains("wordpress") {
                if let wpContent = try doc.select(".wp-content, .entry-content").first() {
                    return try wpContent.outerHtml()
                }
            }
            // Substack newsletters
            if domain.contains("substack.com") {
                if let substackContent = try doc.select(".post-content").first() {
                    return try substackContent.outerHtml()
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    /// Checks if extracted content appears to be valid article content
    private static func isValidArticleContent(_ content: String) -> Bool {
        // Check if the content has at least some paragraphs
        let paragraphCount = content.matches(for: "<p[^>]*>.*?</p>").count
        
        // Check if the content has a reasonable length
        let textLength = content.removingHTMLTags().count
        
        // Basic criteria for valid article content
        return paragraphCount >= 2 && textLength > 500
    }
    
    /// Attempts to extract article content using heuristics (find div with most paragraphs and text density)
    private static func extractArticleUsingHeuristics(doc: Document) -> String? {
        do {
            let divs = try doc.select("div")
            var bestDiv: Element?
            var maxScore = 0.0
            for div in divs.array() {
                let paragraphs = try div.select("p")
                let paragraphCount = paragraphs.size()
                if paragraphCount < 3 { continue }
                let textContent = try div.text()
                let textLength = textContent.count
                let htmlLength = try div.outerHtml().count
                guard htmlLength > 0 else { continue }
                let textDensity = Double(textLength) / Double(htmlLength)
                let score = Double(paragraphCount) * textDensity * 100.0
                let contentKeywords = ["article", "content", "story", "post", "text", "body"]
                var keywordBonus = 0.0
                let divHtml = try div.outerHtml().lowercased()
                for keyword in contentKeywords {
                    if divHtml.contains(keyword) { keywordBonus += 20.0 }
                }
                let finalScore = score + keywordBonus
                if finalScore > maxScore {
                    maxScore = finalScore
                    bestDiv = div
                }
            }
            if let bestDiv = bestDiv, maxScore > 50 {
                return try bestDiv.outerHtml()
            }
        } catch {
            return nil
        }
        return nil
    }
    
    /// Cleans the extracted content for better readability using SwiftSoup
    private static func cleanContent(_ content: String, baseUrl: URL?) -> String {
        do {
            let doc = try SwiftSoup.parseBodyFragment(content, baseUrl?.absoluteString ?? "")
            // Remove unwanted elements
            for selector in removeSelectors {
                try doc.select(selector).remove()
            }
            // Remove tracking/unwanted attributes
            for attr in attributesToClean {
                let elements = try doc.select("[*|\(attr)]")
                for el in elements.array() {
                    try el.removeAttr(attr)
                }
            }
            // Fix relative image URLs
            if let baseUrl = baseUrl {
                let images = try doc.select("img[src]")
                for img in images.array() {
                    let src = try img.attr("src")
                    if src.hasPrefix("/") && !src.hasPrefix("//") {
                        let absoluteUrl = "\(baseUrl.scheme ?? "http")://\(baseUrl.host ?? "")\(src)"
                        try img.attr("src", absoluteUrl)
                    }
                }
            }
            // Add lazy loading and class to images
            let images = try doc.select("img")
            for img in images.array() {
                try img.attr("loading", "lazy")
                try img.addClass("article-image")
            }
            // Mark video embeds
            let iframes = try doc.select("iframe")
            for iframe in iframes.array() {
                let src = try iframe.attr("src")
                if src.contains("youtube.com") || src.contains("vimeo.com") {
                    try iframe.addClass("video-embed")
                    try iframe.attr("loading", "lazy")
                }
            }
            // Remove empty paragraphs and excessive breaks
            let paragraphs = try doc.select("p")
            for p in paragraphs.array() {
                if try p.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try p.remove()
                }
            }
            // Ensure content is wrapped in <article>
            let html = try doc.body()?.html() ?? content
            let wrapped = html.hasPrefix("<article") ? html : "<article>\(html)</article>"
            return wrapped
        } catch {
            return content
        }
    }
    
    // MARK: - HTML Wrapping
    
    /// Wraps the extracted content in a reader-friendly HTML document
    static func wrapInReadableHTML(content: String, fontSize: CGFloat, lineHeight: CGFloat, fontColor: String, backgroundColor: String, accentColor: String) -> String {
        // The hexString property already includes the # prefix
        let fontColorHex = fontColor
        let backgroundColorHex = backgroundColor
        let accentColorHex = accentColor
        // Enhanced style sheet with better typography and responsive design
        // Get font family from the current settings
        let fontFamily = UserDefaults.standard.string(forKey: "readerFontFamily") ?? "System"
        
        // Get the correct font name based on the font family
        let fontName: String
        switch fontFamily {
        case "Georgia":
            fontName = "Georgia"
        case "Times New Roman":
            fontName = "TimesNewRomanPSMT"
        case "Palatino":
            fontName = "Palatino-Roman"
        case "Avenir":
            fontName = "Avenir-Book"
        case "Helvetica Neue":
            fontName = "HelveticaNeue"
        case "Menlo":
            fontName = "Menlo-Regular"
        default:
            fontName = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', system-ui"
        }
        
        let styleSheet = """
        <style>
            :root {
                --font-size: \(fontSize)px;
                --line-height: \(lineHeight);
                --text-color: \(fontColorHex);
                --background-color: \(backgroundColorHex);
                --accent-color: \(accentColorHex);
                --secondary-color: rgba(127, 127, 127, 0.7);
                --spacing: 20px;
                --border-radius: 8px;
                --max-width: 720px;
            }
            
            * {
                box-sizing: border-box;
            }
            
            body {
                font-family: '\(fontName)', -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif;
                font-size: var(--font-size);
                line-height: var(--line-height);
                color: var(--text-color);
                background-color: var(--background-color);
                margin: 0;
                padding: var(--spacing);
            }
            
            .article-container {
                max-width: var(--max-width);
                margin: 0 auto;
                padding-bottom: 40px;
            }
            
            /* Typography */
            h1, h2, h3, h4, h5, h6 {
                line-height: 1.3;
                margin-top: calc(var(--spacing) * 1.5);
                margin-bottom: var(--spacing);
                font-weight: 600;
            }
            
            h1 {
                font-size: calc(var(--font-size) * 1.6);
                margin-top: 0;
            }
            
            h2 {
                font-size: calc(var(--font-size) * 1.4);
            }
            
            h3 {
                font-size: calc(var(--font-size) * 1.2);
            }
            
            p {
                margin-bottom: var(--spacing);
            }
            
            /* Links */
            a {
                color: var(--accent-color);
                text-decoration: none;
                border-bottom: 1px solid transparent;
                transition: border-color 0.2s ease;
            }
            
            a:hover, a:focus {
                border-bottom-color: var(--accent-color);
            }
            
            /* Images */
            img, picture, video, canvas, svg {
                display: block;
                max-width: 100%;
                height: auto;
                margin: calc(var(--spacing) * 1.5) auto;
                border-radius: var(--border-radius);
            }
            
            .article-image {
                box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
            }
            
            figure {
                margin: calc(var(--spacing) * 1.5) 0;
            }
            
            figcaption {
                font-size: 0.9em;
                color: var(--secondary-color);
                text-align: center;
                margin-top: calc(var(--spacing) / 2);
            }
            
            /* Code blocks */
            pre, code {
                background-color: rgba(0, 0, 0, 0.05);
                padding: 8px;
                overflow-x: auto;
                border-radius: calc(var(--border-radius) / 2);
                font-family: 'SF Mono', 'Monaco', 'Menlo', 'Courier New', monospace;
                font-size: 0.9em;
            }
            
            /* Blockquotes */
            blockquote {
                border-left: 4px solid rgba(0, 0, 0, 0.1);
                padding-left: 16px;
                margin-left: 0;
                font-style: italic;
                color: var(--secondary-color);
            }
            
            /* Lists */
            ul, ol {
                padding-left: calc(var(--spacing) * 1.5);
                margin-bottom: var(--spacing);
            }
            
            li {
                margin-bottom: calc(var(--spacing) / 2);
            }
            
            /* Tables */
            table {
                width: 100%;
                border-collapse: collapse;
                margin: var(--spacing) 0;
                font-size: 0.9em;
            }
            
            th, td {
                padding: 8px;
                text-align: left;
                border-bottom: 1px solid rgba(127, 127, 127, 0.2);
            }
            
            /* Video embeds */
            .video-embed {
                aspect-ratio: 16/9;
                width: 100%;
                border: none;
                border-radius: var(--border-radius);
                margin: calc(var(--spacing) * 1.5) 0;
            }
            
            /* Dark mode adjustments */
            @media (prefers-color-scheme: dark) {
                blockquote {
                    border-left-color: rgba(255, 255, 255, 0.2);
                }
                
                pre, code {
                    background-color: rgba(255, 255, 255, 0.1);
                }
                
                th, td {
                    border-bottom-color: rgba(255, 255, 255, 0.1);
                }
                
                .article-image {
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
                }
            }
            
            /* Responsive adjustments */
            @media screen and (max-width: 600px) {
                body {
                    padding: calc(var(--spacing) / 2);
                }
                
                h1 {
                    font-size: calc(var(--font-size) * 1.4);
                }
                
                h2 {
                    font-size: calc(var(--font-size) * 1.3);
                }
                
                h3 {
                    font-size: calc(var(--font-size) * 1.1);
                }
            }
        </style>
        """
        
        // Add metadata and scripts for better handling
        let readableHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <meta name="color-scheme" content="light dark">
            <meta name="format-detection" content="telephone=no">
            <title>Article Reader</title>
            \(styleSheet)
            <script>
                // Basic script to handle image loading errors
                document.addEventListener('DOMContentLoaded', function() {
                    const images = document.querySelectorAll('img');
                    images.forEach(img => {
                        img.onerror = function() {
                            this.style.display = 'none';
                        }
                    });
                    
                    // Make external links open in Safari
                    const links = document.querySelectorAll('a');
                    links.forEach(link => {
                        if (link.hostname !== window.location.hostname && link.href.startsWith('http')) {
                            link.setAttribute('target', '_blank');
                        }
                    });
                });
            </script>
        </head>
        <body>
            <div class="article-container">
                \(content)
            </div>
        </body>
        </html>
        """
        
        return readableHTML
    }
}

// MARK: - String Extensions

extension String {
    /// Returns all matches for a regex pattern
    func matches(for pattern: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let results = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            return results.map {
                String(self[Range($0.range, in: self)!])
            }
        } catch {
            return []
        }
    }
    
    /// Returns the first match for a regex pattern
    func firstMatch(for pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            if let match = regex.firstMatch(in: self, range: NSRange(self.startIndex..., in: self)) {
                return String(self[Range(match.range, in: self)!])
            }
            return nil
        } catch {
            return nil
        }
    }
    
    /// Returns all ranges matching a regex pattern
    func ranges(of pattern: String, options: NSRegularExpression.Options = []) -> [Range<String.Index>]? {
        do {
            let regexOptions = options.union([.dotMatchesLineSeparators])
            let regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
            let matches = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            
            let result = matches.compactMap { match in
                Range(match.range, in: self)
            }
            
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }
    
    /// Get substring matching a range
    func substring(with range: Range<String.Index>) -> String? {
        return String(self[range])
    }
    
    /// Remove all HTML tags from a string
    func removingHTMLTags() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}