import Foundation

/// Manager class to handle sorting and filtering of RSS items
class FeedFilterManagerNew {
    /// Singleton instance
    static let shared = FeedFilterManagerNew()
    
    /// Current sorting option
    private var currentSortOption: SortOptionConfig
    
    /// Current filter option
    private var currentFilterOption: FilterOptionSet
    
    /// Default initializer with defaults from UserDefaults if available
    private init() {
        if let sortData = UserDefaults.standard.data(forKey: "currentSortOptionNew"),
           let sortOption = try? JSONDecoder().decode(SortOptionConfig.self, from: sortData) {
            self.currentSortOption = sortOption
        } else {
            // Default to sorting by date descending
            self.currentSortOption = SortOptionConfig.default
        }
        
        if let filterData = UserDefaults.standard.data(forKey: "currentFilterOptionNew"),
           let filterOption = try? JSONDecoder().decode(FilterOptionSet.self, from: filterData) {
            self.currentFilterOption = filterOption
        } else {
            // Default to no filters
            self.currentFilterOption = FilterOptionSet()
        }
    }
    
    /// Apply current sort and filter settings to an array of RSS items
    /// - Parameter items: The items to sort and filter
    /// - Returns: The sorted and filtered items
    func applySortAndFilter(to items: [RSSItem]) -> [RSSItem] {
        let filteredItems = applyFilter(to: items)
        return applySort(to: filteredItems)
    }
    
    /// Apply just the current sort settings to an array of RSS items
    /// - Parameter items: The items to sort
    /// - Returns: The sorted items
    func applySort(to items: [RSSItem]) -> [RSSItem] {
        return items.sorted(by: currentSortOption)
    }
    
    /// Apply just the current filter settings to an array of RSS items
    /// - Parameter items: The items to filter
    /// - Returns: The filtered items
    func applyFilter(to items: [RSSItem]) -> [RSSItem] {
        // If there are no filter rules, return all items
        if currentFilterOption.rules.isEmpty {
            return items
        }
        
        return items.filter { item in
            return currentFilterOption.matchesItem(item)
        }
    }
    
    /// Set a new sort option
    /// - Parameter option: The new sort option to use
    func setSortOption(_ option: SortOptionConfig) {
        currentSortOption = option
        saveSortOption()
    }
    
    /// Set a new filter option
    /// - Parameter option: The new filter option to use
    func setFilterOption(_ option: FilterOptionSet) {
        currentFilterOption = option
        saveFilterOption()
    }
    
    /// Get the current sort option
    /// - Returns: The current sort option
    func getSortOption() -> SortOptionConfig {
        return currentSortOption
    }
    
    /// Get the current filter option
    /// - Returns: The current filter option
    func getFilterOption() -> FilterOptionSet {
        return currentFilterOption
    }
    
    /// Create a new sort option config
    /// - Parameters:
    ///   - field: The field to sort by
    ///   - order: The sort order (ascending or descending)
    /// - Returns: A new SortOptionConfig
    func createSortOption(field: SortFieldType, order: SortOrderType) -> SortOptionConfig {
        return SortOptionConfig(field: field, order: order)
    }
    
    /// Add a new filter rule to the current filter
    /// - Parameter rule: The rule to add
    func addFilterRule(_ rule: FilterRuleOption) {
        currentFilterOption.addRule(rule)
        saveFilterOption()
    }
    
    /// Remove a filter rule
    /// - Parameter index: The index of the rule to remove
    func removeFilterRule(at index: Int) {
        currentFilterOption.removeRule(at: index)
        saveFilterOption()
    }
    
    /// Change the filter combination logic
    /// - Parameter combination: The new combination logic to use
    func setFilterCombination(_ combination: FilterCombinationType) {
        currentFilterOption.combination = combination
        saveFilterOption()
    }
    
    /// Clear all filter rules
    func clearAllFilters() {
        currentFilterOption = FilterOptionSet()
        saveFilterOption()
    }
    
    /// Save the current sort option to UserDefaults
    private func saveSortOption() {
        if let data = try? JSONEncoder().encode(currentSortOption) {
            UserDefaults.standard.set(data, forKey: "currentSortOptionNew")
        }
    }
    
    /// Save the current filter option to UserDefaults
    private func saveFilterOption() {
        if let data = try? JSONEncoder().encode(currentFilterOption) {
            UserDefaults.standard.set(data, forKey: "currentFilterOptionNew")
        }
    }
}

// Tag functionality has been removed