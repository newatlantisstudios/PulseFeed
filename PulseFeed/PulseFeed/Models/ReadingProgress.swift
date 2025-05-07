import Foundation

struct ReadingProgress: Codable {
    let link: String
    let progress: Float // 0.0 to 1.0 representing percentage read
    let lastReadDate: Date
    
    init(link: String, progress: Float) {
        self.link = link
        self.progress = min(1.0, max(0.0, progress)) // Clamp between 0 and 1
        self.lastReadDate = Date()
    }
}