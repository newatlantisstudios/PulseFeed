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
        
        // Create formatters
        let primaryFormatter = DateFormatter()
        primaryFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        primaryFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Try standard RSS format first
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
        
        // Try ISO 8601 format
        localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = localFormatter.date(from: dateString) {
            return date
        }
        
        // Try more fallback formats
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "EEE, dd MMM yyyy",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm zzz"  // No seconds
        ]
        
        for format in formats {
            localFormatter.dateFormat = format
            if let date = localFormatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
}