import Foundation

/// Defines fields that can be used for filtering RSS items
enum FilterFieldOption: String, Codable, CaseIterable {
    case readStatus = "Read Status"
    case tag = "Tag"
    case source = "Source"
    case dateRange = "Date Range"
    case author = "Author"
    case content = "Content"
    
    var displayName: String {
        return self.rawValue
    }
}

/// Defines operations that can be used with filters
enum FilterOperationType: String, Codable, CaseIterable {
    case equals = "Equals"
    case notEquals = "Not Equals"
    case contains = "Contains"
    case notContains = "Not Contains"
    case beginsWith = "Begins With"
    case endsWith = "Ends With"
    case before = "Before"
    case after = "After"
    case between = "Between"
    case isTrue = "Is True"
    case isFalse = "Is False"
    
    var displayName: String {
        return self.rawValue
    }
    
    /// Returns the valid operations for a specific field
    static func validOperations(for field: FilterFieldOption) -> [FilterOperationType] {
        switch field {
        case .readStatus:
            return [.isTrue, .isFalse]
        case .tag:
            return [.equals, .notEquals]
        case .source:
            return [.equals, .notEquals, .contains, .notContains, .beginsWith, .endsWith]
        case .dateRange:
            return [.before, .after, .between]
        case .author:
            return [.equals, .notEquals, .contains, .notContains, .beginsWith, .endsWith]
        case .content:
            return [.contains, .notContains]
        }
    }
}

/// Enum defining the logic for combining multiple filters
enum FilterCombinationType: String, Codable, CaseIterable {
    case all = "Match All (AND)"
    case any = "Match Any (OR)"
    
    var displayName: String {
        return self.rawValue
    }
}

/// Represents a single filter condition
struct FilterRuleOption: Codable, Equatable, Identifiable {
    let id: String
    var field: FilterFieldOption
    var operation: FilterOperationType
    var value: String
    
    init(field: FilterFieldOption, operation: FilterOperationType, value: String) {
        self.id = UUID().uuidString
        self.field = field
        self.operation = operation
        self.value = value
    }
    
    init(id: String = UUID().uuidString, field: FilterFieldOption, operation: FilterOperationType, value: String) {
        self.id = id
        self.field = field
        self.operation = operation
        self.value = value
    }
}

/// Represents a complete filtering configuration
struct FilterOptionSet: Codable, Equatable {
    var rules: [FilterRuleOption]
    var combination: FilterCombinationType
    
    init(rules: [FilterRuleOption] = [], combination: FilterCombinationType = .all) {
        self.rules = rules
        self.combination = combination
    }
    
    /// Adds a new rule to the filter
    mutating func addRule(_ rule: FilterRuleOption) {
        rules.append(rule)
    }
    
    /// Removes a rule from the filter
    mutating func removeRule(at index: Int) {
        if index < rules.count {
            rules.remove(at: index)
        }
    }
    
    /// Checks if an RSS item passes this filter
    func matchesItem(_ item: RSSItem, tagManager: TagManager) -> Bool {
        // If there are no rules, everything passes
        if rules.isEmpty {
            return true
        }
        
        var ruleResults = [Bool]()
        
        for rule in rules {
            let result = evaluateRule(rule, for: item, tagManager: tagManager)
            ruleResults.append(result)
        }
        
        // Apply the combination logic
        switch combination {
        case .all:
            // All rules must match (AND logic)
            return !ruleResults.contains(false)
        case .any:
            // Any rule can match (OR logic)
            return ruleResults.contains(true)
        }
    }
    
    private func evaluateRule(_ rule: FilterRuleOption, for item: RSSItem, tagManager: TagManager) -> Bool {
        switch rule.field {
        case .readStatus:
            return evaluateReadStatusRule(rule, for: item)
        case .tag:
            return evaluateTagRule(rule, for: item, tagManager: tagManager)
        case .source:
            return evaluateSourceRule(rule, for: item)
        case .dateRange:
            return evaluateDateRule(rule, for: item)
        case .author:
            return evaluateAuthorRule(rule, for: item)
        case .content:
            return evaluateContentRule(rule, for: item)
        }
    }
    
    private func evaluateReadStatusRule(_ rule: FilterRuleOption, for item: RSSItem) -> Bool {
        let isRead = item.isRead || ReadStatusTracker.shared.isArticleRead(link: item.link)
        
        switch rule.operation {
        case .isTrue:
            return isRead
        case .isFalse:
            return !isRead
        default:
            return false // Other operations don't apply to boolean values
        }
    }
    
    private func evaluateTagRule(_ rule: FilterRuleOption, for item: RSSItem, tagManager: TagManager) -> Bool {
        let tagId = rule.value
        
        // Get all tagged items with this tag
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        tagManager.getItemsWithTag(tagId: tagId, itemType: TaggedItem.ItemType.article) { tagResult in
            switch tagResult {
            case .success(let itemIds):
                // Check if the current item's link is in the list of tagged items
                let isTagged = itemIds.contains(item.link)
                
                switch rule.operation {
                case .equals:
                    result = isTagged
                case .notEquals:
                    result = !isTagged
                default:
                    result = false // Other operations don't apply to tags
                }
            case .failure:
                result = false
            }
            semaphore.signal()
        }
        
        // Wait for the async operation to complete
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }
    
    private func evaluateSourceRule(_ rule: FilterRuleOption, for item: RSSItem) -> Bool {
        let sourceText = item.source.lowercased()
        let ruleValue = rule.value.lowercased()
        
        switch rule.operation {
        case .equals:
            return sourceText == ruleValue
        case .notEquals:
            return sourceText != ruleValue
        case .contains:
            return sourceText.contains(ruleValue)
        case .notContains:
            return !sourceText.contains(ruleValue)
        case .beginsWith:
            return sourceText.hasPrefix(ruleValue)
        case .endsWith:
            return sourceText.hasSuffix(ruleValue)
        default:
            return false
        }
    }
    
    private func evaluateDateRule(_ rule: FilterRuleOption, for item: RSSItem) -> Bool {
        guard let date = DateUtils.parseDate(item.pubDate) else {
            return false
        }
        
        switch rule.operation {
        case .before:
            if let beforeDate = DateUtils.parseISODate(rule.value) {
                return date < beforeDate
            }
            return false
            
        case .after:
            if let afterDate = DateUtils.parseISODate(rule.value) {
                return date > afterDate
            }
            return false
            
        case .between:
            // For between, expect a comma-separated pair of ISO dates
            let dateStrings = rule.value.split(separator: ",")
            if dateStrings.count == 2,
               let startDate = DateUtils.parseISODate(String(dateStrings[0])),
               let endDate = DateUtils.parseISODate(String(dateStrings[1])) {
                return date >= startDate && date <= endDate
            }
            return false
            
        default:
            return false
        }
    }
    
    private func evaluateAuthorRule(_ rule: FilterRuleOption, for item: RSSItem) -> Bool {
        guard let author = item.author?.lowercased() else {
            // If no author but we're checking for NOT conditions, return true
            switch rule.operation {
            case .notEquals, .notContains:
                return true
            default:
                return false
            }
        }
        
        let ruleValue = rule.value.lowercased()
        
        switch rule.operation {
        case .equals:
            return author == ruleValue
        case .notEquals:
            return author != ruleValue
        case .contains:
            return author.contains(ruleValue)
        case .notContains:
            return !author.contains(ruleValue)
        case .beginsWith:
            return author.hasPrefix(ruleValue)
        case .endsWith:
            return author.hasSuffix(ruleValue)
        default:
            return false
        }
    }
    
    private func evaluateContentRule(_ rule: FilterRuleOption, for item: RSSItem) -> Bool {
        let contentTexts = [
            item.title.lowercased(),
            item.description?.lowercased() ?? "",
            item.content?.lowercased() ?? ""
        ]
        
        let ruleValue = rule.value.lowercased()
        
        switch rule.operation {
        case .contains:
            return contentTexts.contains { $0.contains(ruleValue) }
        case .notContains:
            return !contentTexts.contains { $0.contains(ruleValue) }
        default:
            return false
        }
    }
}

/// Extension to DateUtils for ISO date parsing
extension DateUtils {
    static func parseISODate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}