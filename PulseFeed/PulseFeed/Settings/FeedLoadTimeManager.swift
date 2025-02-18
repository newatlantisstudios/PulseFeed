import Foundation

class FeedLoadTimeManager {
    static let shared = FeedLoadTimeManager()
    private init() {}
    // Dictionary mapping feed title to its load time in seconds.
    var loadTimes: [String: TimeInterval] = [:]
}
