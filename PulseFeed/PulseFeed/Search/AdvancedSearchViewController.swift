import UIKit

/// Protocol for handling search results
protocol AdvancedSearchDelegate: AnyObject {
    /// Called when a search is executed with results
    func didPerformSearch(with query: SearchQuery, results: [RSSItem])
    
    /// Called when a saved search is selected
    func didSelectSavedSearch(_ query: SearchQuery)
}

class AdvancedSearchViewController: UIViewController {
    
    // MARK: - Properties
    
    /// The current search query being built
    private var searchQuery = SearchQuery()
    
    /// Delegate to handle search results
    weak var delegate: AdvancedSearchDelegate?
    
    /// All articles available for searching
    private var allArticles: [RSSItem] = []
    
    /// Bookmarked items from the main view controller
    private var bookmarkedItems: Set<String> = []
    
    /// Hearted items from the main view controller
    private var heartedItems: Set<String> = []
    
    
    /// Date picker for start date selection
    private let startDatePicker = UIDatePicker()
    
    /// Date picker for end date selection
    private let endDatePicker = UIDatePicker()
    
    // MARK: - UI Components
    
    /// Search bar for text input
    private let searchBar = UISearchBar()
    
    /// Table view for options and saved searches
    private let tableView = UITableView(frame: .zero, style: .grouped)
    
    /// Activity indicator for search operations
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    /// Button to execute the search
    private let searchButton = UIButton(type: .system)
    
    /// Button to save the current search query
    private let saveSearchButton = UIButton(type: .system)
    
    /// Container for bottom buttons
    private let buttonContainer = UIView()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Update saved searches in case they changed
        tableView.reloadData()
    }
    
    // MARK: - Setup Methods
    
    private func setupUI() {
        title = "Advanced Search"
        view.backgroundColor = AppColors.background
        
        // Add left bar button to cancel/dismiss
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        // Set up search bar
        searchBar.placeholder = "Search articles..."
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        
        // Set up table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OptionCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SavedSearchCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TagCell")
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: "SwitchCell")
        view.addSubview(tableView)
        
        // Setup button container
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.backgroundColor = AppColors.background
        // Add subtle top border
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        buttonContainer.addSubview(separator)
        view.addSubview(buttonContainer)
        
        // Setup search button
        searchButton.setTitle("Search", for: .normal)
        searchButton.backgroundColor = AppColors.primary
        searchButton.setTitleColor(.white, for: .normal)
        searchButton.layer.cornerRadius = 8
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)
        buttonContainer.addSubview(searchButton)
        
        // Setup save search button
        saveSearchButton.setTitle("Save Search", for: .normal)
        saveSearchButton.backgroundColor = AppColors.secondary
        saveSearchButton.setTitleColor(.white, for: .normal)
        saveSearchButton.layer.cornerRadius = 8
        saveSearchButton.translatesAutoresizingMaskIntoConstraints = false
        saveSearchButton.addTarget(self, action: #selector(saveSearchButtonTapped), for: .touchUpInside)
        buttonContainer.addSubview(saveSearchButton)
        
        // Setup activity indicator
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        // Configure date pickers
        startDatePicker.datePickerMode = .date
        endDatePicker.datePickerMode = .date
        if #available(iOS 13.4, *) {
            startDatePicker.preferredDatePickerStyle = .wheels
            endDatePicker.preferredDatePickerStyle = .wheels
        }
        
        // Set up constraints
        NSLayoutConstraint.activate([
            // Search bar constraints
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Button container constraints
            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: 80),
            
            // Separator constraints
            separator.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            
            // Table view constraints
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: buttonContainer.topAnchor),
            
            // Search button constraints
            searchButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            searchButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor, constant: -16),
            searchButton.widthAnchor.constraint(equalToConstant: 100),
            searchButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Save search button constraints
            saveSearchButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            saveSearchButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 16),
            saveSearchButton.widthAnchor.constraint(equalToConstant: 120),
            saveSearchButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Activity indicator constraints
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - Public Methods
    
    /// Set up the search controller with available data
    func setupWithData(articles: [RSSItem], bookmarkedItems: Set<String>, heartedItems: Set<String>) {
        self.allArticles = articles
        self.bookmarkedItems = bookmarkedItems
        self.heartedItems = heartedItems
    }
    
    // MARK: - Private Methods
    
    
    /// Show a date picker for date range selection
    private func showDatePicker(for indexPath: IndexPath) {
        let alert = UIAlertController(title: "Select Date", message: "\n\n\n\n\n\n\n\n", preferredStyle: .actionSheet)
        
        // Determine if it's for start or end date
        let isStartDate = indexPath.row == 1
        let datePicker = isStartDate ? startDatePicker : endDatePicker
        
        // Set current date if not already set
        if isStartDate && searchQuery.startDate == nil {
            let calendar = Calendar.current
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: Date())
            dateComponents.day = dateComponents.day! - 30  // Default to 30 days ago
            datePicker.date = calendar.date(from: dateComponents) ?? Date()
        } else if !isStartDate && searchQuery.endDate == nil {
            datePicker.date = Date()
        }
        
        // Add date picker to alert
        datePicker.frame = CGRect(x: 0, y: 0, width: 270, height: 200)
        alert.view.addSubview(datePicker)
        
        // Add actions
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            if isStartDate {
                self.searchQuery.startDate = datePicker.date
            } else {
                self.searchQuery.endDate = datePicker.date
            }
            
            // Enable date filtering
            self.searchQuery.filterByDate = true
            
            // Refresh the table
            self.tableView.reloadData()
        })
        
        present(alert, animated: true)
    }
    
    /// Load saved searches from storage
    private func loadSavedSearches(completion: @escaping ([SearchQuery]) -> Void) {
        SearchManager.shared.getSavedSearchQueries { result in
            switch result {
            case .success(let queries):
                completion(queries)
            case .failure:
                completion([])
            }
        }
    }
    
    /// Execute the search with current query
    private func executeSearch() {
        activityIndicator.startAnimating()
        
        searchQuery.searchText = searchBar.text ?? ""
        
        
        // Perform the search
        searchQuery.filterArticles(allArticles, in: bookmarkedItems, heartedItems: heartedItems) { [weak self] results in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                
                // Notify delegate of search results
                self.delegate?.didPerformSearch(with: self.searchQuery, results: results)
                
                // Dismiss the search view controller
                self.dismiss(animated: true)
            }
        }
    }
    
    // MARK: - Action Handlers
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func searchButtonTapped() {
        executeSearch()
    }
    
    @objc private func saveSearchButtonTapped() {
        // Show alert to name the search
        let alert = UIAlertController(title: "Save Search", message: "Enter a name for this search", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Search Name"
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let textField = alert?.textFields?.first, let name = textField.text, !name.isEmpty else {
                return
            }
            
            // Use the search text as the name if it's not empty
            var newQuery = self.searchQuery
            newQuery.searchText = self.searchBar.text ?? name
            
            // Save the search
            SearchManager.shared.saveSearchQuery(newQuery) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.showAlert(title: "Error", message: "Failed to save search: \(error.localizedDescription)")
                    } else {
                        self.showAlert(title: "Success", message: "Search saved successfully") {
                            self.tableView.reloadData()
                        }
                    }
                }
            }
        })
        
        present(alert, animated: true)
    }
    
    /// Show a simple alert with an optional completion handler
    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension AdvancedSearchViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3  // Search Options, Bookmark & Heart Status, Date Range
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:  // Search Options
            return 5  // Title, Content, Author, Feed, Read Status
        case 1:  // Bookmark & Heart Status
            return 2  // Bookmarked, Hearted
        case 2:  // Date Range
            return 3  // Enable Date Filter, Start Date, End Date
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:  // Search Options
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
            
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Search in Title"
                cell.switchControl.isOn = searchQuery.searchInTitle
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    self?.searchQuery.searchInTitle = isOn
                }
            case 1:
                cell.textLabel?.text = "Search in Content"
                cell.switchControl.isOn = searchQuery.searchInContent
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    self?.searchQuery.searchInContent = isOn
                }
            case 2:
                cell.textLabel?.text = "Search in Author"
                cell.switchControl.isOn = searchQuery.searchInAuthor
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    self?.searchQuery.searchInAuthor = isOn
                }
            case 3:
                cell.textLabel?.text = "Search in Feed Title"
                cell.switchControl.isOn = searchQuery.searchInFeedTitle
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    self?.searchQuery.searchInFeedTitle = isOn
                }
            case 4:
                cell.textLabel?.text = "Only Unread Articles"
                cell.switchControl.isOn = searchQuery.filterByReadStatus && !searchQuery.isRead
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    guard let self = self else { return }
                    self.searchQuery.filterByReadStatus = isOn
                    self.searchQuery.isRead = !isOn  // Invert logic for clarity in UI
                }
            default:
                break
            }
            
            return cell
            
        case 1:  // Bookmark & Heart Status
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
            
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Only Bookmarked Articles"
                cell.switchControl.isOn = searchQuery.filterByBookmarked && searchQuery.isBookmarked
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    guard let self = self else { return }
                    self.searchQuery.filterByBookmarked = isOn
                    self.searchQuery.isBookmarked = isOn
                }
            case 1:
                cell.textLabel?.text = "Only Favorited Articles"
                cell.switchControl.isOn = searchQuery.filterByHearted && searchQuery.isHearted
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    guard let self = self else { return }
                    self.searchQuery.filterByHearted = isOn
                    self.searchQuery.isHearted = isOn
                }
            default:
                break
            }
            
            return cell
            
            
        case 3:  // Date Range
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
                cell.textLabel?.text = "Filter by Date Range"
                cell.switchControl.isOn = searchQuery.filterByDate
                cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                    self?.searchQuery.filterByDate = isOn
                    self?.tableView.reloadSections(IndexSet(integer: 3), with: .none)
                }
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "OptionCell", for: indexPath)
                
                if indexPath.row == 1 {
                    cell.textLabel?.text = "Start Date"
                    
                    if let startDate = searchQuery.startDate {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .none
                        cell.detailTextLabel?.text = formatter.string(from: startDate)
                    } else {
                        cell.detailTextLabel?.text = "Not Set"
                    }
                } else {
                    cell.textLabel?.text = "End Date"
                    
                    if let endDate = searchQuery.endDate {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .none
                        cell.detailTextLabel?.text = formatter.string(from: endDate)
                    } else {
                        cell.detailTextLabel?.text = "Not Set"
                    }
                }
                
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = searchQuery.filterByDate ? .default : .none
                cell.textLabel?.textColor = searchQuery.filterByDate ? .label : .secondaryLabel
                
                return cell
            }
            
        default:
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Search Options"
        case 1:
            return "Article Status"
        case 2:
            return "Date Range"
        default:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Select where to search for your terms"
        case 2:
            return "Filter articles by publication date"
        default:
            return nil
        }
    }
}

// MARK: - UITableViewDelegate

extension AdvancedSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch indexPath.section {
            
        case 2:  // Date Range
            if indexPath.row > 0 && searchQuery.filterByDate {
                showDatePicker(for: indexPath)
            }
            
        default:
            break
        }
    }
}

// MARK: - UISearchBarDelegate

extension AdvancedSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        executeSearch()
    }
}

// MARK: - UIColor Extension for Hex

extension UIColor {
    convenience init?(hexString: String) {
        let r, g, b: CGFloat
        
        let hexColor = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = hexColor.index(hexColor.startIndex, offsetBy: hexColor.hasPrefix("#") ? 1 : 0)
        let hexValue = String(hexColor[start...])
        let scanner = Scanner(string: hexValue)
        var hexNumber: UInt64 = 0
        
        if scanner.scanHexInt64(&hexNumber) {
            r = CGFloat((hexNumber & 0xFF0000) >> 16) / 255
            g = CGFloat((hexNumber & 0x00FF00) >> 8) / 255
            b = CGFloat(hexNumber & 0x0000FF) / 255
            
            self.init(red: r, green: g, blue: b, alpha: 1.0)
            return
        }
        
        return nil
    }
}