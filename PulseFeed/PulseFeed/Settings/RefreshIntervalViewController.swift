import UIKit

class RefreshIntervalViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    // MARK: - Properties
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var feeds: [RSSFeed] = []
    
    // Sections in the table view
    private enum Section: Int, CaseIterable {
        case settings
        case feeds
        
        var title: String {
            switch self {
            case .settings: return "Global Settings"
            case .feeds: return "Feed-Specific Intervals"
            }
        }
    }
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Refresh Intervals"
        view.backgroundColor = AppColors.background
        
        setupTableView()
        loadFeeds()
    }
    
    // MARK: - Setup Methods
    
    private func setupTableView() {
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
    }
    
    private func loadFeeds() {
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let feeds):
                    self.feeds = feeds.sorted { $0.title.lowercased() < $1.title.lowercased() }
                    self.tableView.reloadData()
                case .failure(let error):
                    print("Error loading feeds: \(error.localizedDescription)")
                    self.showAlert(title: "Error", message: "Could not load feeds: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .settings:
            return 2
        case .feeds:
            return feeds.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .settings:
            if indexPath.row == 0 {
                // Global interval cell
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                var config = cell.defaultContentConfiguration()
                config.text = "Global Refresh Interval"
                
                let interval = RefreshIntervalManager.shared.currentGlobalInterval
                config.secondaryText = interval.description
                
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
                return cell
            } else {
                // Use custom intervals toggle
                let cell = tableView.dequeueReusableCell(withIdentifier: "switchCell", for: indexPath) as! SwitchTableViewCell
                
                cell.configure(
                    with: "Use Per-Feed Refresh Intervals",
                    isOn: RefreshIntervalManager.shared.areCustomIntervalsEnabled
                )
                
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    RefreshIntervalManager.shared.areCustomIntervalsEnabled = isOn
                    self?.tableView.reloadSections(IndexSet(integer: Section.feeds.rawValue), with: .automatic)
                }
                
                return cell
            }
            
        case .feeds:
            let feed = feeds[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            
            config.text = feed.title
            
            // Show interval if custom intervals are enabled
            if RefreshIntervalManager.shared.areCustomIntervalsEnabled {
                let interval = RefreshIntervalManager.shared.getInterval(forFeed: feed.url)
                config.secondaryText = interval.description
                cell.accessoryType = .disclosureIndicator
            } else {
                config.secondaryText = "Using global setting"
                cell.accessoryType = .none
            }
            
            cell.contentConfiguration = config
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        return sectionType.title
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        
        switch sectionType {
        case .settings:
            return "Set how often feeds should refresh automatically. Enable per-feed intervals to customize refresh timing for individual feeds."
        case .feeds:
            return RefreshIntervalManager.shared.areCustomIntervalsEnabled ? 
                "Configure custom refresh intervals for each feed." : 
                "Enable per-feed intervals above to customize refresh timing for individual feeds."
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .settings:
            if indexPath.row == 0 {
                // Global interval setting
                showIntervalPicker(for: nil)
            }
        case .feeds:
            // Only allow selection if custom intervals are enabled
            if RefreshIntervalManager.shared.areCustomIntervalsEnabled {
                let feed = feeds[indexPath.row]
                showIntervalPicker(for: feed)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func showIntervalPicker(for feed: RSSFeed?) {
        let alertController = UIAlertController(
            title: feed == nil ? "Global Refresh Interval" : "Refresh Interval for \(feed!.title)",
            message: "Select how often this feed should refresh",
            preferredStyle: .actionSheet
        )
        
        // Get current interval
        let currentInterval: RefreshInterval
        if let feed = feed {
            currentInterval = RefreshIntervalManager.shared.getInterval(forFeed: feed.url)
        } else {
            currentInterval = RefreshIntervalManager.shared.currentGlobalInterval
        }
        
        // Add actions for each interval option
        for interval in RefreshInterval.allCases {
            let action = UIAlertAction(title: interval.description, style: .default) { [weak self] _ in
                if let feed = feed {
                    RefreshIntervalManager.shared.setInterval(interval, forFeed: feed.url)
                } else {
                    RefreshIntervalManager.shared.currentGlobalInterval = interval
                }
                self?.tableView.reloadData()
            }
            
            // Add checkmark to current selection
            if interval == currentInterval {
                action.setValue(true, forKey: "checked")
            }
            
            alertController.addAction(action)
        }
        
        // Add cancel action
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Configure for iPad
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alertController, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}