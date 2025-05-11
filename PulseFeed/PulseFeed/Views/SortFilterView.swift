import UIKit
import Foundation

protocol SortFilterViewDelegate: AnyObject {
    func sortOptionSelected(_ option: SortOptionConfig)
    func filterOptionSelected(_ option: FilterOptionSet)
    func clearFiltersSelected()
}

class SortFilterView: UIView {
    
    // MARK: - Properties
    
    weak var delegate: SortFilterViewDelegate?
    
    private var currentSortOption: SortOptionConfig = SortOptionConfig.default
    private var currentFilterOption: FilterOptionSet = FilterOptionSet()
    
    private let sortButton = UIButton(type: .system)
    private let filterButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    
    private let stackView = UIStackView()
    private let statusLabel = UILabel()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        // Configure stack view
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        // Configure status label
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = UIFont.systemFont(ofSize: 12)
        statusLabel.textColor = AppColors.secondary
        statusLabel.textAlignment = .center
        statusLabel.text = "No filters applied"
        statusLabel.isHidden = true // Initially hidden
        addSubview(statusLabel)
        
        // Configure buttons
        setupSortButton()
        setupFilterButton()
        setupClearButton()
        
        // Add buttons to stack view
        stackView.addArrangedSubview(sortButton)
        stackView.addArrangedSubview(filterButton)
        stackView.addArrangedSubview(clearButton)
        
        // Set layout constraints for buttons
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            // Status label constraints
            statusLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            
            // Overall height
            heightAnchor.constraint(equalToConstant: 70)
        ])
        
        // Add border to the view
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.lightGray.cgColor
        backgroundColor = AppColors.background
    }
    
    private func setupSortButton() {
        configureButton(sortButton, 
                       title: "Sort",
                       iconName: "arrow.up.arrow.down",
                       action: #selector(showSortOptions))
    }
    
    private func setupFilterButton() {
        configureButton(filterButton, 
                       title: "Filter",
                       iconName: "line.horizontal.3.decrease.circle",
                       action: #selector(showFilterOptions))
    }
    
    private func setupClearButton() {
        configureButton(clearButton, 
                       title: "Clear All",
                       iconName: "xmark.circle",
                       action: #selector(clearFilters))
        clearButton.isHidden = true // Initially hidden until filters are applied
    }
    
    private func configureButton(_ button: UIButton, title: String, iconName: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: iconName), for: .normal)
        button.tintColor = AppColors.accent
        button.backgroundColor = AppColors.background
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 0.5
        button.layer.borderColor = AppColors.secondary.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        button.addTarget(self, action: action, for: .touchUpInside)
    }
    
    // MARK: - Button Actions
    
    @objc private func showSortOptions() {
        let alert = UIAlertController(title: "Sort Options", message: nil, preferredStyle: .actionSheet)
        
        for option in SortOptionConfig.allOptions {
            let isSelected = option.field == currentSortOption.field && option.order == currentSortOption.order
            
            let action = UIAlertAction(title: isSelected ? "✓ \(option.description)" : option.description, style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                self.currentSortOption = option
                self.updateSortButtonState()
                self.delegate?.sortOptionSelected(option)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present from the window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // For iPad, set source view
            if let popover = alert.popoverPresentationController {
                popover.sourceView = sortButton
                popover.sourceRect = sortButton.bounds
            }
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    @objc private func showFilterOptions() {
        let alert = UIAlertController(title: "Filter Options", message: nil, preferredStyle: .actionSheet)
        
        for field in FilterFieldOption.allCases {
            let action = UIAlertAction(title: field.displayName, style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                self.showFilterOperationOptions(for: field)
            }
            alert.addAction(action)
        }
        
        // Add option to view current filters
        if !currentFilterOption.rules.isEmpty {
            let viewFiltersAction = UIAlertAction(title: "View Current Filters", style: .default) { [weak self] _ in
                self?.showCurrentFilters()
            }
            alert.addAction(viewFiltersAction)
            
            // Add option to change filter combination logic
            let combinationAction = UIAlertAction(
                title: "Change Logic: Currently \(currentFilterOption.combination.displayName)",
                style: .default
            ) { [weak self] _ in
                self?.toggleFilterCombination()
            }
            alert.addAction(combinationAction)
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present from the window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // For iPad, set source view
            if let popover = alert.popoverPresentationController {
                popover.sourceView = filterButton
                popover.sourceRect = filterButton.bounds
            }
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showFilterOperationOptions(for field: FilterFieldOption) {
        let alert = UIAlertController(title: "Select Operation", message: nil, preferredStyle: .actionSheet)
        
        let operations = FilterOperationType.validOperations(for: field)
        
        for operation in operations {
            let action = UIAlertAction(title: operation.displayName, style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                self.showFilterValueInput(for: field, operation: operation)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present from the window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // For iPad, set source view
            if let popover = alert.popoverPresentationController {
                popover.sourceView = filterButton
                popover.sourceRect = filterButton.bounds
            }
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showFilterValueInput(for field: FilterFieldOption, operation: FilterOperationType) {
        // For boolean operations like isTrue/isFalse, no need for value input
        if operation == FilterOperationType.isTrue || operation == FilterOperationType.isFalse {
            let value = ""
            addFilterRule(field: field, operation: operation, value: value)
            return
        }
        
        // For date range operations, show date picker
        if field == FilterFieldOption.dateRange {
            showDatePicker(for: operation)
            return
        }
        
        // Tag operations have been removed
        if field == FilterFieldOption.tag {
            // Skip tag picker as functionality has been removed
            return
        }
        
        // For other operations, show text input
        let alert = UIAlertController(
            title: "Enter Value",
            message: "Enter a value for '\(field.displayName)' \(operation.displayName)",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Value"
            
            // Set keyboard type based on field
            switch field {
            case .source, .content, .author:
                textField.autocapitalizationType = .none
            default:
                textField.autocapitalizationType = .sentences
            }
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Add Filter", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let text = alert?.textFields?.first?.text,
                  !text.isEmpty
            else { return }
            
            self.addFilterRule(field: field, operation: operation, value: text)
        })
        
        // Present from the window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showDatePicker(for operation: FilterOperationType) {
        let alert = UIAlertController(
            title: "Select Date",
            message: nil,
            preferredStyle: .actionSheet
        )
        
        // Add predefined date options
        let today = UIAlertAction(title: "Today", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            let today = ISO8601DateFormatter().string(from: Date())
            self.addFilterRule(field: FilterFieldOption.dateRange, operation: operation, value: today)
        }
        
        let yesterday = UIAlertAction(title: "Yesterday", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            let yesterday = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
            self.addFilterRule(field: .dateRange, operation: operation, value: yesterday)
        }
        
        let lastWeek = UIAlertAction(title: "Last Week", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            let lastWeek = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
            self.addFilterRule(field: .dateRange, operation: operation, value: lastWeek)
        }
        
        let lastMonth = UIAlertAction(title: "Last Month", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            let lastMonth = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .month, value: -1, to: Date())!)
            self.addFilterRule(field: .dateRange, operation: operation, value: lastMonth)
        }
        
        let customDate = UIAlertAction(title: "Custom Date...", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            self.showCustomDatePicker(for: operation)
        }
        
        // Add all actions
        alert.addAction(today)
        alert.addAction(yesterday)
        alert.addAction(lastWeek)
        alert.addAction(lastMonth)
        alert.addAction(customDate)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present from the window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // For iPad, set source view
            if let popover = alert.popoverPresentationController {
                popover.sourceView = filterButton
                popover.sourceRect = filterButton.bounds
            }
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showCustomDatePicker(for operation: FilterOperationType) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // Create a view controller to host the date picker
            let vc = UIViewController()
            vc.modalPresentationStyle = .formSheet
            
            let datePicker = UIDatePicker()
            datePicker.datePickerMode = .date
            datePicker.preferredDatePickerStyle = .wheels
            datePicker.translatesAutoresizingMaskIntoConstraints = false
            
            let doneButton = UIButton(type: .system)
            doneButton.setTitle("Done", for: .normal)
            doneButton.translatesAutoresizingMaskIntoConstraints = false
            doneButton.addAction(UIAction { [weak self, weak vc, weak datePicker] _ in
                guard let self = self, let datePicker = datePicker else { return }
                
                let selectedDate = ISO8601DateFormatter().string(from: datePicker.date)
                self.addFilterRule(field: FilterFieldOption.dateRange, operation: operation, value: selectedDate)
                
                vc?.dismiss(animated: true)
            }, for: .touchUpInside)
            
            // Add views to the controller
            vc.view.addSubview(datePicker)
            vc.view.addSubview(doneButton)
            
            // Set up constraints
            NSLayoutConstraint.activate([
                datePicker.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                datePicker.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
                
                doneButton.topAnchor.constraint(equalTo: datePicker.bottomAnchor, constant: 20),
                doneButton.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor)
            ])
            
            // Present the controller
            rootViewController.present(vc, animated: true)
        }
    }
    
    // Tag picker functionality has been removed
    private func showTagPicker(for operation: FilterOperationType) {
        // Tag functionality has been removed
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {

            let alert = UIAlertController(
                title: "Feature Unavailable",
                message: "Tag filtering has been removed from the app.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showCurrentFilters() {
        let alert = UIAlertController(
            title: "Current Filters",
            message: "Logic: \(currentFilterOption.combination.displayName)",
            preferredStyle: .actionSheet
        )
        
        if currentFilterOption.rules.isEmpty {
            alert.message = "No filters applied."
        } else {
            for (index, rule) in currentFilterOption.rules.enumerated() {
                // Format the rule description
                let ruleDescription = formatRuleDescription(rule)
                
                let action = UIAlertAction(title: "\(index + 1). \(ruleDescription)", style: .default) { [weak self] _ in
                    // Show options for this filter
                    self?.showOptionsForRule(at: index)
                }
                alert.addAction(action)
            }
        }
        
        alert.addAction(UIAlertAction(title: "✕", style: .cancel))
        
        // Present from the window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // For iPad, set source view
            if let popover = alert.popoverPresentationController {
                popover.sourceView = filterButton
                popover.sourceRect = filterButton.bounds
            }
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showOptionsForRule(at index: Int) {
        guard index < currentFilterOption.rules.count else { return }
        
        let alert = UIAlertController(
            title: "Filter Options",
            message: formatRuleDescription(currentFilterOption.rules[index]),
            preferredStyle: .actionSheet
        )
        
        let removeAction = UIAlertAction(title: "Remove Filter", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            var updatedRules = self.currentFilterOption.rules
            updatedRules.remove(at: index)
            
            let newFilterOption = FilterOptionSet(
                rules: updatedRules,
                combination: self.currentFilterOption.combination
            )
            
            self.currentFilterOption = newFilterOption
            self.updateFilterButtonState()
            self.delegate?.filterOptionSelected(newFilterOption)
        }
        
        alert.addAction(removeAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present from the window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // For iPad, set source view
            if let popover = alert.popoverPresentationController {
                popover.sourceView = filterButton
                popover.sourceRect = filterButton.bounds
            }
            
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func toggleFilterCombination() {
        let newCombination: FilterCombinationType = (currentFilterOption.combination == FilterCombinationType.all) ? FilterCombinationType.any : FilterCombinationType.all
        
        let newFilterOption = FilterOptionSet(
            rules: currentFilterOption.rules,
            combination: newCombination
        )
        
        currentFilterOption = newFilterOption
        updateFilterButtonState()
        delegate?.filterOptionSelected(newFilterOption)
        
        // Show confirmation toast
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            let alert = UIAlertController(
                title: nil,
                message: "Filter logic changed to \(newCombination.displayName)",
                preferredStyle: .alert
            )
            
            rootViewController.present(alert, animated: true)
            
            // Dismiss after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                alert.dismiss(animated: true)
            }
        }
    }
    
    private func formatRuleDescription(_ rule: FilterRuleOption) -> String {
        var fieldName = rule.field.displayName
        var operationName = rule.operation.displayName
        var valueString = rule.value
        
        // Format special cases
        switch rule.field {
        case .readStatus:
            return "Read Status \(rule.operation == .isTrue ? "is Read" : "is Unread")"
            
        case .tag:
            return "Tag filtering has been removed"
            
        case .dateRange:
            // Format the date nicely
            if let date = ISO8601DateFormatter().date(from: rule.value) {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                valueString = formatter.string(from: date)
            }
            
        default:
            break
        }
        
        return "\(fieldName) \(operationName) '\(valueString)'"
    }
    
    @objc private func clearFilters() {
        // Reset filters
        currentFilterOption = FilterOptionSet()
        updateFilterButtonState()
        
        // Notify delegate
        delegate?.clearFiltersSelected()
        
        // Update UI
        clearButton.isHidden = true
    }
    
    // MARK: - Helper Methods
    
    private func addFilterRule(field: FilterFieldOption, operation: FilterOperationType, value: String) {
        // Create a new rule
        let rule = FilterRuleOption(field: field, operation: operation, value: value)
        
        // Add to current filter option
        var updatedRules = currentFilterOption.rules
        updatedRules.append(rule)
        
        let newFilterOption = FilterOptionSet(
            rules: updatedRules,
            combination: currentFilterOption.combination
        )
        
        // Update current filter option
        currentFilterOption = newFilterOption
        
        // Update UI
        updateFilterButtonState()
        
        // Notify delegate
        delegate?.filterOptionSelected(newFilterOption)
    }
    
    private func updateSortButtonState() {
        // If using default sort, show regular title
        if currentSortOption.field == SortOptionConfig.default.field && 
           currentSortOption.order == SortOptionConfig.default.order {
            sortButton.setTitle("Sort", for: .normal)
        } else {
            // Show sort field as title
            sortButton.setTitle(currentSortOption.field.displayName, for: .normal)
            
            // Update icon to show sort direction
            sortButton.setImage(
                UIImage(systemName: currentSortOption.order.systemImageName),
                for: .normal
            )
        }
        
        // Update status label
        updateStatusLabel()
    }
    
    private func updateFilterButtonState() {
        // Update filter button appearance
        if currentFilterOption.rules.isEmpty {
            filterButton.setTitle("Filter", for: .normal)
            filterButton.setImage(UIImage(systemName: "line.horizontal.3.decrease.circle"), for: .normal)
            clearButton.isHidden = true
        } else {
            // Show filter count
            filterButton.setTitle("Filters (\(currentFilterOption.rules.count))", for: .normal)
            filterButton.setImage(UIImage(systemName: "line.horizontal.3.decrease.circle.fill"), for: .normal)
            clearButton.isHidden = false
        }
        
        // Update status label
        updateStatusLabel()
    }
    
    private func updateStatusLabel() {
        let description = getCurrentStateDescription()
        if description.isEmpty {
            statusLabel.isHidden = true
        } else {
            statusLabel.text = description
            statusLabel.isHidden = false
        }
    }
    
    // MARK: - Public Methods
    
    func setSortOption(_ option: SortOptionConfig) {
        currentSortOption = option
        updateSortButtonState()
    }
    
    func setFilterOption(_ option: FilterOptionSet) {
        currentFilterOption = option
        updateFilterButtonState()
    }
    
    /// Returns a user-friendly description of the current sorting and filtering state
    func getCurrentStateDescription() -> String {
        var descriptions = [String]()
        
        // Add sort description
        if currentSortOption.field != SortOptionConfig.default.field || 
           currentSortOption.order != SortOptionConfig.default.order {
            let sortDesc = "Sorted by \(currentSortOption.field.displayName) (\(currentSortOption.order == .ascending ? "A to Z" : "Z to A"))"
            descriptions.append(sortDesc)
        }
        
        // Add filter description
        if !currentFilterOption.rules.isEmpty {
            let filterDesc = "\(currentFilterOption.rules.count) filter\(currentFilterOption.rules.count > 1 ? "s" : "") applied"
            descriptions.append(filterDesc)
        }
        
        return descriptions.joined(separator: ", ")
    }
}