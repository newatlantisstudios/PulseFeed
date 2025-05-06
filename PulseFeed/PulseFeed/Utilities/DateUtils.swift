import Foundation

class DateUtils {
    
    // Helper function to get time ago string from a date string
    static func getTimeAgo(from dateString: String) -> String {
        // Create multiple date formatters to handle different RSS date formats
        let primaryFormatter = DateFormatter()
        primaryFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        primaryFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Use parseDate to handle various date formats
        guard let date = parseDate(dateString) else {
            return dateString
        }
        
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.minute, .hour, .day], from: date, to: now)

        if let days = components.day, days > 0 {
            return "\(days)d ago"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m ago"
        }
        return "just now"
    }
    
    // Helper function to parse dates with multiple formatters
    static func parseDate(_ dateString: String) -> Date? {
        // Skip empty strings
        if dateString.isEmpty {
            return nil
        }
        
        // First try ISO8601DateFormatter which handles Atom dates well
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Create formatters for RSS and other formats
        let primaryFormatter = DateFormatter()
        primaryFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        primaryFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Try standard RSS format
        if let date = primaryFormatter.date(from: dateString) {
            return date
        }
        
        // Try local timezone format (like PDT)
        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Common RSS format with different timezone (PDT/PST/EDT etc)
        localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = localFormatter.date(from: dateString) {
            return date
        }
        
        // Try with timezone without seconds
        localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm zzz"
        if let date = localFormatter.date(from: dateString) {
            return date
        }
        
        // Try with offset timezone like -0700
        localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = localFormatter.date(from: dateString) {
            return date
        }
        
        // Try more formats common in RSS and Atom feeds
        let formats = [
            // ISO 8601 variations
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            
            // RSS variations
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "EEE, dd MMM yyyy",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm zzz",
            
            // RFC 822/1123 format
            "EEE, d MMM yyyy HH:mm:ss zzz",
            
            // Atom common format
            "yyyy-MM-dd'T'HH:mm:ssxxxxx" // ISO8601 with timezone
        ]
        
        for format in formats {
            localFormatter.dateFormat = format
            if let date = localFormatter.date(from: dateString) {
                return date
            }
        }
        
        // Special handling for Atom dates that might have milliseconds
        // Try to parse something like: 2023-05-07T15:34:56.789Z
        if dateString.contains("T") && dateString.contains(".") && (dateString.hasSuffix("Z") || dateString.contains("+")) {
            // Extract the parts before the milliseconds
            var components = dateString.components(separatedBy: ".")
            if components.count >= 2 {
                // Remove fractional seconds
                let firstPart = components[0]
                let lastPart = components[1].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                
                // Try to reconstruct without fractional seconds
                let reconstructed = firstPart + "Z"
                localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                if let date = localFormatter.date(from: reconstructed) {
                    return date
                }
            }
        }
        
        return nil
    }
}