import Foundation

// MARK: - Sync Event
struct SyncEvent {
    let id: String
    let timestamp: Date
    let type: SyncType
    let status: SyncEventStatus
    let details: String
    let error: Error?
    let duration: TimeInterval?
    
    init(type: SyncType, status: SyncEventStatus, details: String, error: Error? = nil, duration: TimeInterval? = nil) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.type = type
        self.status = status
        self.details = details
        self.error = error
        self.duration = duration
    }
}

enum SyncEventStatus {
    case started
    case completed
    case failed
    case retrying
    case rateLimited
}

// MARK: - Sync History Manager
class SyncHistory {
    static let shared = SyncHistory()
    
    private var events: [SyncEvent] = []
    private let maxEvents = 100
    private let fileManager = FileManager.default
    
    private var logFileURL: URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsURL.appendingPathComponent("sync_history.log")
    }
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Public API
    
    /// Log a sync event
    func logEvent(_ event: SyncEvent) {
        events.append(event)
        
        // Limit history size
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        
        // Write to file
        writeToFile(event)
        
        // Save to UserDefaults
        saveHistory()
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: Notification.Name("SyncHistoryUpdated"),
            object: nil,
            userInfo: ["event": event]
        )
    }
    
    /// Get recent sync events
    func getRecentEvents(limit: Int = 50) -> [SyncEvent] {
        return Array(events.suffix(limit))
    }
    
    /// Get events filtered by type
    func getEvents(ofType type: SyncType) -> [SyncEvent] {
        return events.filter { $0.type == type }
    }
    
    /// Get failed events
    func getFailedEvents() -> [SyncEvent] {
        return events.filter { $0.status == .failed }
    }
    
    /// Clear history
    func clearHistory() {
        events.removeAll()
        saveHistory()
        
        // Clear log file
        if let logFileURL = logFileURL {
            try? fileManager.removeItem(at: logFileURL)
        }
    }
    
    /// Export history as JSON
    func exportHistory() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            return try encoder.encode(events)
        } catch {
            print("ERROR: Failed to export sync history: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func loadHistory() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "syncHistory") {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                events = try decoder.decode([SyncEvent].self, from: data)
            } catch {
                print("ERROR: Failed to decode sync history: \(error)")
                events = []
            }
        }
    }
    
    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(events)
            UserDefaults.standard.set(data, forKey: "syncHistory")
        } catch {
            print("ERROR: Failed to save sync history: \(error)")
        }
    }
    
    private func writeToFile(_ event: SyncEvent) {
        guard let logFileURL = logFileURL else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var logEntry = "\n[\(dateFormatter.string(from: event.timestamp))] "
        logEntry += "\(event.type.rawValue) - \(event.status) - \(event.details)"
        
        if let error = event.error {
            logEntry += " - ERROR: \(error.localizedDescription)"
        }
        
        if let duration = event.duration {
            logEntry += " - Duration: \(String(format: "%.2f", duration))s"
        }
        
        if let data = logEntry.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}

// MARK: - Codable Conformance
extension SyncEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, type, status, details, duration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        type = try container.decode(SyncType.self, forKey: .type)
        status = try container.decode(SyncEventStatus.self, forKey: .status)
        details = try container.decode(String.self, forKey: .details)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        error = nil // Don't decode errors
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(type, forKey: .type)
        try container.encode(status, forKey: .status)
        try container.encode(details, forKey: .details)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

extension SyncEventStatus: Codable {
    var stringValue: String {
        switch self {
        case .started: return "started"
        case .completed: return "completed"
        case .failed: return "failed"
        case .retrying: return "retrying"
        case .rateLimited: return "rate_limited"
        }
    }
    
    init?(stringValue: String) {
        switch stringValue {
        case "started": self = .started
        case "completed": self = .completed
        case "failed": self = .failed
        case "retrying": self = .retrying
        case "rate_limited": self = .rateLimited
        default: return nil
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        if let status = SyncEventStatus(stringValue: stringValue) {
            self = status
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid sync event status")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}