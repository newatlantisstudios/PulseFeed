import UIKit

class DuplicateSettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let tableView = UITableView(frame: .zero, style: .grouped)
    
    // Reference to the DuplicateManager
    private let manager = DuplicateManager.shared
    
    // Sections in the settings table
    enum Sections: Int, CaseIterable {
        case handlingMode = 0
        case primarySelection = 1
        case badgeVisibility = 2
        case preferredSources = 3
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure navigation
        title = "Duplicate Articles"
        navigationItem.largeTitleDisplayMode = .never
        
        // Set up tableView
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: "switchCell")
        
        // Set background color
        view.backgroundColor = AppColors.background
        tableView.backgroundColor = AppColors.background
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Sections(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .handlingMode:
            return DuplicateManager.DuplicateHandlingMode.allCases.count
        case .primarySelection:
            return DuplicateManager.PrimarySelectionStrategy.allCases.count
        case .badgeVisibility:
            return 1
        case .preferredSources:
            return manager.preferredSources.count + 1 // +1 for "Add Source" cell
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = Sections(rawValue: indexPath.section) else { 
            return UITableViewCell() 
        }
        
        switch sectionType {
        case .handlingMode:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let mode = DuplicateManager.DuplicateHandlingMode.allCases[indexPath.row]
            
            var config = cell.defaultContentConfiguration()
            config.text = mode.rawValue
            cell.contentConfiguration = config
            
            // Set checkmark for selected mode
            if manager.handlingMode == mode {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            
            return cell
            
        case .primarySelection:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let strategy = DuplicateManager.PrimarySelectionStrategy.allCases[indexPath.row]
            
            var config = cell.defaultContentConfiguration()
            config.text = strategy.rawValue
            cell.contentConfiguration = config
            
            // Set checkmark for selected strategy
            if manager.primarySelectionStrategy == strategy {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            
            return cell
            
        case .badgeVisibility:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "switchCell", for: indexPath) as? SwitchTableViewCell else {
                return UITableViewCell()
            }
            
            cell.textLabel?.text = "Show Duplicate Count Badge"
            cell.switchControl.isOn = manager.showDuplicateCountBadge
            cell.onSwitchChanged = { [weak self] isOn in
                self?.manager.showDuplicateCountBadge = isOn
            }
            
            return cell
            
        case .preferredSources:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            
            if indexPath.row < manager.preferredSources.count {
                // Existing source
                let source = manager.preferredSources[indexPath.row]
                
                var config = cell.defaultContentConfiguration()
                config.text = source
                config.secondaryText = "Priority \(indexPath.row + 1)"
                cell.contentConfiguration = config
                
                // Set accessory type to indicate swipe availability
                cell.accessoryType = .detailButton
            } else {
                // "Add Source" cell
                var config = cell.defaultContentConfiguration()
                config.text = "Add Preferred Source"
                config.image = UIImage(systemName: "plus.circle.fill")
                config.imageProperties.tintColor = AppColors.accent
                cell.contentConfiguration = config
            }
            
            return cell
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let sectionType = Sections(rawValue: indexPath.section) else { return }
        
        switch sectionType {
        case .handlingMode:
            let selectedMode = DuplicateManager.DuplicateHandlingMode.allCases[indexPath.row]
            manager.handlingMode = selectedMode
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            
        case .primarySelection:
            let selectedStrategy = DuplicateManager.PrimarySelectionStrategy.allCases[indexPath.row]
            manager.primarySelectionStrategy = selectedStrategy
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            
        case .badgeVisibility:
            // Handled by switch
            break
            
        case .preferredSources:
            if indexPath.row == manager.preferredSources.count {
                // "Add Source" cell tapped
                showAddSourceAlert()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionType = Sections(rawValue: section) else { return nil }
        
        switch sectionType {
        case .handlingMode:
            return "Duplicate Handling"
        case .primarySelection:
            return "Primary Article Selection"
        case .badgeVisibility:
            return "Visual Indicators"
        case .preferredSources:
            return "Preferred Sources (Higher Priority First)"
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Sections(rawValue: section) else { return nil }
        
        switch sectionType {
        case .handlingMode:
            return "Choose how duplicate articles should be handled in your feed."
        case .primarySelection:
            return "When duplicate articles are detected, this setting determines which one is considered the primary version."
        case .badgeVisibility:
            return "Show a badge with a count of duplicate articles."
        case .preferredSources:
            return "Choose which sources you prefer when selecting the primary article. Sources not listed here will be ranked by date."
        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let sectionType = Sections(rawValue: indexPath.section),
              sectionType == .preferredSources,
              indexPath.row < manager.preferredSources.count else {
            return nil
        }
        
        let source = manager.preferredSources[indexPath.row]
        
        // Create delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.manager.removePreferredSource(source)
            tableView.reloadSections(IndexSet(integer: Sections.preferredSources.rawValue), with: .automatic)
            completion(true)
        }
        
        // Create move up action
        let moveUpAction = UIContextualAction(style: .normal, title: "Up") { [weak self] _, _, completion in
            self?.manager.movePreferredSourceUp(source)
            tableView.reloadSections(IndexSet(integer: Sections.preferredSources.rawValue), with: .automatic)
            completion(true)
        }
        moveUpAction.backgroundColor = .systemBlue
        
        // Create move down action
        let moveDownAction = UIContextualAction(style: .normal, title: "Down") { [weak self] _, _, completion in
            self?.manager.movePreferredSourceDown(source)
            tableView.reloadSections(IndexSet(integer: Sections.preferredSources.rawValue), with: .automatic)
            completion(true)
        }
        moveDownAction.backgroundColor = .systemGreen
        
        // Create an array of applicable actions
        var actions = [UIContextualAction]()
        actions.append(deleteAction)
        
        // Only add down action if not the last item
        if indexPath.row < manager.preferredSources.count - 1 {
            actions.append(moveDownAction)
        }
        
        // Only add up action if not the first item
        if indexPath.row > 0 {
            actions.append(moveUpAction)
        }
        
        return UISwipeActionsConfiguration(actions: actions)
    }
    
    // MARK: - Private Methods
    
    private func showAddSourceAlert() {
        let alert = UIAlertController(title: "Add Preferred Source", message: "Enter the name of a news source to prioritize", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Source name"
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let textField = alert?.textFields?.first, let sourceName = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceName.isEmpty else {
                return
            }
            
            // Add the source to the preferred list
            self.manager.addPreferredSource(sourceName)
            
            // Reload the preferred sources section
            self.tableView.reloadSections(IndexSet(integer: Sections.preferredSources.rawValue), with: .automatic)
        })
        
        present(alert, animated: true)
    }
}