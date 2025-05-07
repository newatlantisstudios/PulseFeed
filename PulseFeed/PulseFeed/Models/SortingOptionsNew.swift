import Foundation

/// Defines the available fields for sorting RSS items
enum SortFieldType: String, Codable, CaseIterable {
    case date = "Date"
    case title = "Title"
    case source = "Source"
    case author = "Author"
    
    var displayName: String {
        return self.rawValue
    }
}

/// Defines the direction of sorting
enum SortOrderType: String, Codable, CaseIterable {
    case ascending = "Ascending"
    case descending = "Descending"
    
    var displayName: String {
        return self.rawValue
    }
    
    var systemImageName: String {
        switch self {
        case .ascending:
            return "arrow.up"
        case .descending:
            return "arrow.down"
        }
    }
}

/// A complete sort configuration combining field and order
struct SortOptionConfig: Codable, Equatable {
    var field: SortFieldType
    var order: SortOrderType
    
    var description: String {
        return "\(field.displayName) (\(order == .ascending ? "A to Z" : "Z to A"))"
    }
    
    static var `default`: SortOptionConfig {
        return SortOptionConfig(field: .date, order: .descending)
    }
    
    static var allOptions: [SortOptionConfig] {
        var options = [SortOptionConfig]()
        
        for field in SortFieldType.allCases {
            for order in SortOrderType.allCases {
                options.append(SortOptionConfig(field: field, order: order))
            }
        }
        
        return options
    }
}

/// Helper extension to apply sorting to RSSItem arrays
extension Array where Element == RSSItem {
    func sorted(by option: SortOptionConfig) -> [RSSItem] {
        switch option.field {
        case .date:
            return self.sorted { item1, item2 in
                let date1 = DateUtils.parseDate(item1.pubDate)
                let date2 = DateUtils.parseDate(item2.pubDate)
                
                if let d1 = date1, let d2 = date2 {
                    return option.order == .ascending ? d1 < d2 : d1 > d2
                }
                
                // Default sorting if date parsing fails
                return option.order == .ascending
            }
            
        case .title:
            return self.sorted { item1, item2 in
                option.order == .ascending ? 
                    item1.title.lowercased() < item2.title.lowercased() :
                    item1.title.lowercased() > item2.title.lowercased()
            }
            
        case .source:
            return self.sorted { item1, item2 in
                option.order == .ascending ?
                    item1.source.lowercased() < item2.source.lowercased() :
                    item1.source.lowercased() > item2.source.lowercased()
            }
            
        case .author:
            return self.sorted { item1, item2 in
                let author1 = item1.author?.lowercased() ?? ""
                let author2 = item2.author?.lowercased() ?? ""
                
                return option.order == .ascending ? author1 < author2 : author1 > author2
            }
        }
    }
}