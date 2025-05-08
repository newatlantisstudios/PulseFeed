import Foundation

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
    
    /// Extracts the readable content from HTML
    static func extractReadableContent(from html: String, url: URL?) -> String {
        let domain = url?.host ?? ""
        
        // First look for schema.org metadata which often contains the full article content
        if let schemaContent = extractSchemaContent(from: html) {
            return cleanContent(schemaContent)
        }
        
        // Look for structured article content using common selectors
        for selector in contentSelectors {
            if let content = extractContentWithSelector(html: html, selector: selector) {
                if isValidArticleContent(content) {
                    return cleanContent(content)
                }
            }
        }
        
        // Try site-specific extractors for known domains
        if let content = extractContentForSpecificSite(html: html, domain: domain) {
            return cleanContent(content)
        }
        
        // Fallback: extract article using heuristics
        if let content = extractArticleUsingHeuristics(html: html) {
            return cleanContent(content)
        }
        
        // Last resort: just clean up the whole body
        if let bodyContent = extractBody(from: html) {
            return cleanContent(bodyContent)
        }
        
        // Ultimate fallback
        return cleanContent(html)
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
    
    /// Site-specific content extraction for known domains
    private static func extractContentForSpecificSite(html: String, domain: String) -> String? {
        // Medium and similar platforms
        if domain.contains("medium.com") || html.contains("data-selectable-paragraph") {
            let paragraphPattern = "<p[^>]*data-selectable-paragraph[^>]*>(.*?)</p>"
            let paragraphs = html.matches(for: paragraphPattern)
            
            if !paragraphs.isEmpty {
                return "<article>\(paragraphs.joined())</article>"
            }
        }
        
        // WordPress sites often use specific content classes
        if html.contains("wp-content") || html.contains("wordpress") {
            let wpContentPattern = "<div[^>]*class=[\"'].*?\\b(wp-content|entry-content)\\b.*?[\"'][^>]*>(.*?)</div>"
            if let wpContent = html.firstMatch(for: wpContentPattern) {
                return wpContent
            }
        }
        
        // Substack newsletters
        if domain.contains("substack.com") {
            let substackPattern = "<div[^>]*class=[\"'].*?\\bpost-content\\b.*?[\"'][^>]*>(.*?)</div>"
            if let substackContent = html.firstMatch(for: substackPattern) {
                return substackContent
            }
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
    
    /// Attempts to extract content matching a CSS-like selector (simplified implementation)
    private static func extractContentWithSelector(html: String, selector: String) -> String? {
        // Handle ID selector (e.g., "#content")
        if selector.hasPrefix("#") {
            let id = selector.dropFirst()
            let pattern = "<[^>]*\\bid=[\"\']\\s*\(id)\\s*[\"\'][^>]*>(.*?)</.*?>"
            if let match = html.firstMatch(for: pattern) {
                return match
            }
        }
        
        // Handle class selector (e.g., ".content")
        else if selector.hasPrefix(".") {
            let className = selector.dropFirst()
            let pattern = "<[^>]*\\bclass=[\"\'].*?\\b\(className)\\b.*?[\"\'][^>]*>(.*?)</.*?>"
            if let match = html.firstMatch(for: pattern) {
                return match
            }
        }
        
        // Handle tag selector (e.g., "article")
        else {
            let pattern = "<\(selector)[^>]*>(.*?)</\(selector)>"
            if let match = html.firstMatch(for: pattern) {
                return match
            }
        }
        
        return nil
    }
    
    /// Extracts article content using basic heuristics
    private static func extractArticleUsingHeuristics(html: String) -> String? {
        // Find the div with the most paragraphs and a reasonable text density
        let divPattern = "<div[^>]*>(.*?)</div>"
        let divMatches = html.matches(for: divPattern)
        
        var bestDiv = ""
        var maxScore = 0
        
        for div in divMatches {
            let paragraphs = div.matches(for: "<p[^>]*>.*?</p>")
            let paragraphCount = paragraphs.count
            
            // Skip very small divs
            if paragraphCount < 3 {
                continue
            }
            
            // Calculate the text density (ratio of text to HTML)
            let textContent = div.removingHTMLTags()
            let textLength = textContent.count
            let htmlLength = div.count
            
            guard htmlLength > 0 else { continue }
            
            let textDensity = Double(textLength) / Double(htmlLength)
            
            // Calculate a score based on paragraph count and text density
            let score = Int(Double(paragraphCount) * textDensity * 100)
            
            // Check for keywords that indicate good content
            let contentKeywords = ["article", "content", "story", "post", "text", "body"]
            var keywordBonus = 0
            
            for keyword in contentKeywords {
                if div.lowercased().contains(keyword) {
                    keywordBonus += 20
                }
            }
            
            // Apply the bonus to the score
            let finalScore = score + keywordBonus
            
            if finalScore > maxScore {
                maxScore = finalScore
                bestDiv = div
            }
        }
        
        // If we found a good candidate, return it
        if maxScore > 50 && !bestDiv.isEmpty {
            return bestDiv
        }
        
        return nil
    }
    
    /// Extracts the body content from HTML
    private static func extractBody(from html: String) -> String? {
        let pattern = "<body[^>]*>(.*?)</body>"
        if let match = html.firstMatch(for: pattern) {
            return match
        }
        return nil
    }
    
    /// Cleans the extracted content for better readability
    private static func cleanContent(_ content: String) -> String {
        var cleanedContent = content
        
        // First, preserve certain elements we want to keep
        cleanedContent = preserveImportantElements(cleanedContent)
        
        // Remove unwanted elements
        for selector in removeSelectors {
            if selector.hasPrefix(".") {
                let className = selector.dropFirst()
                let pattern = "<[^>]*\\bclass=[\"\'].*?\\b\(className)\\b.*?[\"\'][^>]*>.*?</.*?>"
                cleanedContent = cleanedContent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            } else if selector.hasPrefix("#") {
                let id = selector.dropFirst()
                let pattern = "<[^>]*\\bid=[\"\'].*?\(id).*?[\"\'][^>]*>.*?</.*?>"
                cleanedContent = cleanedContent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            } else if selector.hasPrefix("[") && selector.contains("*=") {
                // Handle attribute contains selector like [class*='ad-']
                let parts = selector.dropFirst().dropLast().components(separatedBy: "*=")
                if parts.count == 2 {
                    let attr = parts[0]
                    var value = parts[1]
                    // Remove quotes from value
                    value = value.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
                    let pattern = "<[^>]*\\b\(attr)=[\"\'].*?\(value).*?[\"\'][^>]*>.*?</.*?>"
                    cleanedContent = cleanedContent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                }
            } else if selector.contains(":not") {
                // Special handling for :not pseudo-selector
                // This is simplified - a real implementation would need more robust parsing
                continue
            } else {
                let pattern = "<\(selector)[^>]*>.*?</\(selector)>"
                cleanedContent = cleanedContent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
        }
        
        // Remove inline scripts and styles
        cleanedContent = cleanedContent.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
        cleanedContent = cleanedContent.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
        cleanedContent = cleanedContent.replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression)
        
        // Clean tracking attributes from remaining elements
        cleanedContent = cleanAttributesFromTags(cleanedContent)
        
        // Fix relative URLs for images
        cleanedContent = fixRelativeImageUrls(cleanedContent)
        
        // Remove empty paragraphs and excessive breaks
        cleanedContent = cleanedContent.replacingOccurrences(of: "<p>\\s*</p>", with: "", options: .regularExpression)
        cleanedContent = cleanedContent.replacingOccurrences(of: "<br>\\s*<br>\\s*<br>", with: "<br><br>", options: .regularExpression)
        
        // Fix unclosed tags and cleanup HTML structure
        cleanedContent = fixBrokenHtml(cleanedContent)
        
        return cleanedContent
    }
    
    /// Preserves important elements like images and embedded videos before cleaning
    private static func preserveImportantElements(_ html: String) -> String {
        var processedHtml = html
        
        // Preserve images with proper attributes
        let imgPattern = "<img[^>]*src=[\"'](.*?)[\"'][^>]*>"
        let imgMatches = html.matches(for: imgPattern)
        
        for imgTag in imgMatches {
            // Extract the source URL
            if let srcRange = imgTag.range(of: "src=[\"'](.*?)[\"']", options: .regularExpression),
               let src = imgTag.substring(with: srcRange)?.replacingOccurrences(of: "src=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) {
                
                // Extract alt text if available
                let alt = imgTag.matches(for: "alt=[\"'](.*?)[\"']").first?.replacingOccurrences(of: "alt=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? "Image"
                
                // Add data-cached attribute to enable client-side caching
                let cleanImgTag = "<img src=\"\(src)\" alt=\"\(alt)\" class=\"article-image\" data-cached=\"true\" loading=\"lazy\">"
                
                // Replace the original tag
                processedHtml = processedHtml.replacingOccurrences(of: imgTag, with: cleanImgTag, options: .literal)
            }
        }
        
        // Preserve YouTube/Vimeo embeds
        let iframePattern = "<iframe[^>]*src=[\"'](.*?youtube\\.com.*?|.*?vimeo\\.com.*?)[\"'][^>]*>.*?</iframe>"
        let iframeMatches = html.matches(for: iframePattern)
        
        for iframeTag in iframeMatches {
            // Mark as video embed to avoid removal
            let preservedTag = iframeTag.replacingOccurrences(of: "<iframe", with: "<iframe class=\"video-embed\" loading=\"lazy\"")
            processedHtml = processedHtml.replacingOccurrences(of: iframeTag, with: preservedTag, options: .literal)
        }
        
        return processedHtml
    }
    
    /// Cleans tracking and unnecessary attributes from HTML tags
    private static func cleanAttributesFromTags(_ html: String) -> String {
        var cleanedHtml = html
        
        for attr in attributesToClean {
            let pattern = "\\s\(attr)=[\"'].*?[\"']"
            cleanedHtml = cleanedHtml.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        return cleanedHtml
    }
    
    /// Fixes relative URLs in image tags to absolute URLs
    private static func fixRelativeImageUrls(_ html: String, baseUrl: URL? = nil) -> String {
        var fixedHtml = html
        
        // Extract all image tags
        let imgPattern = "<img[^>]*src=[\"'](.*?)[\"'][^>]*>"
        let imgMatches = html.matches(for: imgPattern)
        
        for imgTag in imgMatches {
            // Extract the source URL
            if let srcRange = imgTag.range(of: "src=[\"'](.*?)[\"']", options: .regularExpression),
               let srcAttr = imgTag.substring(with: srcRange),
               let src = srcAttr.range(of: "\".*?\"", options: .regularExpression).map({ String(srcAttr[$0]) }) {
                
                let cleanSrc = src.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                
                // Check if it's a relative URL
                if cleanSrc.hasPrefix("/") && !cleanSrc.hasPrefix("//"), let baseUrl = baseUrl {
                    // Convert to absolute URL
                    let absoluteUrl = baseUrl.scheme! + "://" + baseUrl.host! + cleanSrc
                    let newImgTag = imgTag.replacingOccurrences(of: srcAttr, with: "src=\"\(absoluteUrl)\"")
                    fixedHtml = fixedHtml.replacingOccurrences(of: imgTag, with: newImgTag)
                }
            }
        }
        
        return fixedHtml
    }
    
    /// Attempts to fix broken HTML structure for better rendering
    private static func fixBrokenHtml(_ html: String) -> String {
        // This is a simplified approach to fixing broken HTML
        var fixedHtml = html
        
        // Ensure we have a wrapper article tag
        if !fixedHtml.hasPrefix("<article") && !fixedHtml.contains("</article>") {
            fixedHtml = "<article>\(fixedHtml)</article>"
        }
        
        // Fix common broken tag pairs
        let brokenTagPairs = [
            ("<div", "</div>"),
            ("<p", "</p>"),
            ("<span", "</span>"),
            ("<h1", "</h1>"),
            ("<h2", "</h2>"),
            ("<h3", "</h3>"),
            ("<h4", "</h4>"),
            ("<h5", "</h5>"),
            ("<h6", "</h6>"),
            ("<section", "</section>"),
            ("<article", "</article>")
        ]
        
        for (openTag, closeTag) in brokenTagPairs {
            let openCount = fixedHtml.components(separatedBy: openTag).count - 1
            let closeCount = fixedHtml.components(separatedBy: closeTag).count - 1
            
            if openCount > closeCount {
                // Add missing closing tags
                for _ in 0..<(openCount - closeCount) {
                    fixedHtml += closeTag
                }
            }
        }
        
        return fixedHtml
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