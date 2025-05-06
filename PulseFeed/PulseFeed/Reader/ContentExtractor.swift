import Foundation

class ContentExtractor {
    
    // MARK: - Properties
    
    // Common article content class/id names used by popular websites
    private static let contentSelectors = [
        "article",
        "main",
        ".article-content",
        ".post-content",
        ".entry-content",
        ".content",
        "#content",
        ".post",
        ".article-body",
        ".story-body"
    ]
    
    // Elements to remove
    private static let removeSelectors = [
        "header",
        "footer",
        "nav",
        ".navigation",
        ".menu",
        ".sidebar",
        ".ad",
        ".advertisement",
        ".social",
        ".comments",
        ".related",
        ".share",
        ".promo",
        "script",
        "style",
        "iframe:not(.video-embed)"
    ]
    
    // MARK: - Content Extraction
    
    /// Extracts the readable content from HTML
    static func extractReadableContent(from html: String, url: URL?) -> String {
        // First try to find the content area using common selectors
        for selector in contentSelectors {
            if let content = extractContentWithSelector(html: html, selector: selector) {
                return cleanContent(content)
            }
        }
        
        // Fallback: basic article extraction using heuristics
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
    
    /// Attempts to extract content matching a CSS-like selector (simplified implementation)
    private static func extractContentWithSelector(html: String, selector: String) -> String? {
        // Handle ID selector (e.g., "#content")
        if selector.hasPrefix("#") {
            let id = selector.dropFirst()
            let pattern = "id=['\"]\\s*\(id)\\s*['\"][^>]*>(.*?)</.*?>"
            if let range = html.range(of: pattern, options: .regularExpression) {
                return String(html[range])
            }
        }
        
        // Handle class selector (e.g., ".content")
        else if selector.hasPrefix(".") {
            let className = selector.dropFirst()
            let pattern = "class=['\"].*?\\s*\(className)\\s*.*?['\"][^>]*>(.*?)</.*?>"
            if let range = html.range(of: pattern, options: .regularExpression) {
                return String(html[range])
            }
        }
        
        // Handle tag selector (e.g., "article")
        else {
            let pattern = "<\(selector)[^>]*>(.*?)</\(selector)>"
            if let range = html.range(of: pattern, options: .regularExpression) {
                return String(html[range])
            }
        }
        
        return nil
    }
    
    /// Extracts article content using basic heuristics
    private static func extractArticleUsingHeuristics(html: String) -> String? {
        // Very basic heuristic: find the <div> with the most <p> tags
        let divPattern = "<div[^>]*>(.*?)</div>"
        let pPattern = "<p[^>]*>.*?</p>"
        
        var bestDiv = ""
        var maxPCount = 0
        
        let divMatches = html.matches(for: divPattern)
        
        for div in divMatches {
            let pCount = div.matches(for: pPattern).count
            if pCount > maxPCount {
                maxPCount = pCount
                bestDiv = div
            }
        }
        
        if maxPCount > 3 {
            return bestDiv
        }
        
        return nil
    }
    
    /// Extracts the body content from HTML
    private static func extractBody(from html: String) -> String? {
        let pattern = "<body[^>]*>(.*?)</body>"
        if let range = html.range(of: pattern, options: .regularExpression) {
            return String(html[range])
        }
        return nil
    }
    
    /// Cleans the extracted content
    private static func cleanContent(_ content: String) -> String {
        var cleanedContent = content
        
        // Remove unwanted elements
        for selector in removeSelectors {
            if selector.hasPrefix(".") {
                let className = selector.dropFirst()
                let pattern = "<[^>]*class=['\"].*?\(className).*?['\"][^>]*>.*?</.*?>"
                cleanedContent = cleanedContent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            } else if selector.hasPrefix("#") {
                let id = selector.dropFirst()
                let pattern = "<[^>]*id=['\"].*?\(id).*?['\"][^>]*>.*?</.*?>"
                cleanedContent = cleanedContent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            } else {
                // Exception for iframes with video
                if selector.contains(":not") {
                    // This is a simplified approach - a real implementation would need more robust parsing
                    continue
                }
                let pattern = "<\(selector)[^>]*>.*?</\(selector)>"
                cleanedContent = cleanedContent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
        }
        
        // Remove inline scripts
        cleanedContent = cleanedContent.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: .regularExpression)
        
        // Remove style tags
        cleanedContent = cleanedContent.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: .regularExpression)
        
        // Remove comments
        cleanedContent = cleanedContent.replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression)
        
        return cleanedContent
    }
    
    // MARK: - HTML Wrapping
    
    /// Wraps the extracted content in a reader-friendly HTML document
    static func wrapInReadableHTML(content: String, fontSize: CGFloat, lineHeight: CGFloat, fontColor: String, backgroundColor: String, accentColor: String) -> String {
        let styleSheet = """
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
                font-size: \(fontSize)px;
                line-height: \(lineHeight);
                color: \(fontColor);
                background-color: \(backgroundColor);
                margin: 20px;
                padding-bottom: 40px;
            }
            img {
                max-width: 100%;
                height: auto;
                display: block;
                margin: 20px 0;
                border-radius: 8px;
            }
            h1 {
                font-size: 26px;
                line-height: 1.3;
                margin-bottom: 20px;
            }
            h2 {
                font-size: 22px;
                line-height: 1.3;
            }
            h3 {
                font-size: 20px;
            }
            p {
                margin-bottom: 20px;
            }
            a {
                color: \(accentColor);
                text-decoration: none;
            }
            pre, code {
                background-color: rgba(0,0,0,0.05);
                padding: 8px;
                overflow-x: auto;
                border-radius: 4px;
                font-family: 'Menlo', monospace;
                font-size: 0.9em;
            }
            blockquote {
                border-left: 4px solid rgba(0,0,0,0.1);
                padding-left: 16px;
                margin-left: 0;
                font-style: italic;
                color: rgba(0,0,0,0.7);
            }
            figure {
                margin: 20px 0;
            }
            figcaption {
                font-size: 0.9em;
                color: rgba(0,0,0,0.6);
                text-align: center;
                margin-top: 8px;
            }
            /* Dark mode adjustments */
            @media (prefers-color-scheme: dark) {
                blockquote {
                    border-left-color: rgba(255,255,255,0.1);
                    color: rgba(255,255,255,0.7);
                }
                pre, code {
                    background-color: rgba(255,255,255,0.1);
                }
                figcaption {
                    color: rgba(255,255,255,0.6);
                }
            }
        </style>
        """
        
        let readableHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            \(styleSheet)
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

// MARK: - String Extension

extension String {
    /// Returns all matches for a regex pattern
    func matches(for pattern: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let results = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            return results.map {
                String(self[Range($0.range, in: self)!])
            }
        } catch {
            return []
        }
    }
}