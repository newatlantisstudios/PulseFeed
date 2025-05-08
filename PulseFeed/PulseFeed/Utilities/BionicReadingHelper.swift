import UIKit

/// Helper class for converting regular text to Bionic Reading format
class BionicReadingHelper {
    
    struct Configuration {
        /// Percentage of the word to bold (0.0 - 1.0)
        var fixationStrength: Double = 0.5
        
        /// Fonts to use
        var regularFont: UIFont
        var boldFont: UIFont
        
        /// Optional colors
        var regularColor: UIColor?
        var boldColor: UIColor?
        
        /// Minimum word length to apply bionic format
        var minWordLength: Int = 1
        
        init(regularFont: UIFont, boldFont: UIFont) {
            self.regularFont = regularFont
            self.boldFont = boldFont
        }
    }
    
    /// Converts text to bionic reading format with custom configuration
    static func convertToBionic(text: String, config: Configuration) -> NSAttributedString {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let attributedString = NSMutableAttributedString()
        
        for (index, word) in words.enumerated() {
            if word.count >= config.minWordLength {
                let numCharsToBold = calculateCharsToEmbolden(word: word, fixationStrength: config.fixationStrength)
                
                if numCharsToBold > 0 && numCharsToBold < word.count {
                    // Bold part attributes
                    var boldAttributes: [NSAttributedString.Key: Any] = [.font: config.boldFont]
                    if let boldColor = config.boldColor {
                        boldAttributes[.foregroundColor] = boldColor
                    }
                    
                    // Regular part attributes
                    var regularAttributes: [NSAttributedString.Key: Any] = [.font: config.regularFont]
                    if let regularColor = config.regularColor {
                        regularAttributes[.foregroundColor] = regularColor
                    }
                    
                    // Create the parts
                    let boldPart = String(word.prefix(numCharsToBold))
                    let normalPart = String(word.dropFirst(numCharsToBold))
                    
                    let wordAttr = NSMutableAttributedString()
                    wordAttr.append(NSAttributedString(string: boldPart, attributes: boldAttributes))
                    wordAttr.append(NSAttributedString(string: normalPart, attributes: regularAttributes))
                    
                    attributedString.append(wordAttr)
                } else {
                    // If the word is too short or empty, just use regular font
                    var regularAttributes: [NSAttributedString.Key: Any] = [.font: config.regularFont]
                    if let regularColor = config.regularColor {
                        regularAttributes[.foregroundColor] = regularColor
                    }
                    attributedString.append(NSAttributedString(string: word, attributes: regularAttributes))
                }
            } else {
                // Word too short for bionic formatting
                var regularAttributes: [NSAttributedString.Key: Any] = [.font: config.regularFont]
                if let regularColor = config.regularColor {
                    regularAttributes[.foregroundColor] = regularColor
                }
                attributedString.append(NSAttributedString(string: word, attributes: regularAttributes))
            }
            
            // Add space after each word except the last one
            if index < words.count - 1 {
                var regularAttributes: [NSAttributedString.Key: Any] = [.font: config.regularFont]
                if let regularColor = config.regularColor {
                    regularAttributes[.foregroundColor] = regularColor
                }
                attributedString.append(NSAttributedString(string: " ", attributes: regularAttributes))
            }
        }
        
        return attributedString
    }
    
    /// Calculate how many characters should be bolded in a word
    private static func calculateCharsToEmbolden(word: String, fixationStrength: Double) -> Int {
        let wordLength = word.count
        if wordLength <= 0 {
            return 0
        } else if wordLength <= 3 {
            return 1
        } else {
            // Use the fixation strength parameter to determine how much to bold
            return max(1, min(wordLength - 1, Int(ceil(Double(wordLength) * fixationStrength))))
        }
    }
    
    /// Converts HTML content to bionic reading format
    static func convertHTMLToBionic(html: String, config: Configuration) -> NSAttributedString {
        // First convert HTML to attributed string
        guard let data = html.data(using: .utf8) else {
            return NSAttributedString()
        }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return NSAttributedString()
        }
        
        // Extract plain text to process with bionic reading
        let plainText = attributedString.string
        
        // Apply bionic reading to the plain text
        return convertToBionic(text: plainText, config: config)
    }
}