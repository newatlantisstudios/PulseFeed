import UIKit

class RSSSettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FeedCell")
        table.register(SwitchTableViewCell.self, forCellReuseIdentifier: "SwitchCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.allowsMultipleSelectionDuringEditing = true
        return table
    }()

    private var feeds: [RSSFeed] = [] {
        didSet {
            tableView.reloadData()
        }
    }

    private var useICloud: Bool {
        // The switch flag stored in UserDefaults.
        return UserDefaults.standard.bool(forKey: "useICloud")
    }

    private var enableFullTextExtraction: Bool {
        return UserDefaults.standard.bool(forKey: "enableFullTextExtraction")
    }

    private var isEditingMode = false {
        didSet {
            tableView.setEditing(isEditingMode, animated: true)
            updateNavigationBar()
        }
    }

    private var selectedFeeds: [RSSFeed] {
        guard let selectedRows = tableView.indexPathsForSelectedRows else { return [] }
        return selectedRows.compactMap { indexPath in
            guard indexPath.section == 1 && indexPath.row < feeds.count else { return nil }
            return feeds[indexPath.row]
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RSS Settings"
        view.backgroundColor = AppColors.background
        setupTableView()
        setupNotifications()
        loadFeeds()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupNavigationBar()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(iCloudPreferenceChanged),
                                               name: Notification.Name("iCloudSyncPreferenceChanged"),
                                               object: nil)
    }
    
    @objc private func iCloudPreferenceChanged() {
        loadFeeds()
    }
    
    private func saveFeed(_ feed: RSSFeed) {
        // First, load the current feeds.
        loadLocalFeeds { currentFeeds in
            var updatedFeeds = currentFeeds
            updatedFeeds.append(feed)
            // Save the updated array using the StorageManager.
            StorageManager.shared.save(updatedFeeds, forKey: "rssFeeds") { error in
                if let error = error {
                    self.showError("Failed to save feeds: \(error.localizedDescription)")
                } else {
                    self.loadFeeds() // Reload after saving.
                }
            }
        }
    }
    
    private func loadFeeds() {
        StorageManager.shared.load(forKey: "rssFeeds") { (result: Result<[RSSFeed], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let loadedFeeds):
                    self.feeds = loadedFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }
                case .failure(let error):
                    print("Error loading feeds: \(error.localizedDescription)")
                    self.feeds = []
                }
                // Debug: Print the loaded feeds.
                //print("Loaded RSS Feeds:")
                for feed in self.feeds {
                    print("Title: \(feed.title) | URL: \(feed.url) | Last Updated: \(feed.lastUpdated)")
                }

                // Make sure the navigation bar is updated after feeds are loaded
                self.updateNavigationBar()
            }
        }
    }
    
    private func loadLocalFeeds(completion: @escaping ([RSSFeed]) -> Void) {
        StorageManager.shared.load(forKey: "rssFeeds") { (result: Result<[RSSFeed], Error>) in
            switch result {
            case .success(let feeds):
                completion(feeds)
            case .failure(_):
                completion([])
            }
        }
    }
    
    private func setupNavigationBar() {
        updateNavigationBar()
    }

    private func updateNavigationBar() {
        // Create the add button
        let plusImage = UIImage(systemName: "plus")
        let addButton = UIBarButtonItem(
            image: plusImage,
            style: .plain,
            target: self,
            action: #selector(addButtonTapped)
        )

        if isEditingMode {
            // In editing mode - show Done and Delete buttons
            let doneButton = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(doneButtonTapped)
            )

            let deleteButton = UIBarButtonItem(
                barButtonSystemItem: .trash,
                target: self,
                action: #selector(deleteSelectedButtonTapped)
            )
            deleteButton.isEnabled = !selectedFeeds.isEmpty

            navigationItem.rightBarButtonItems = [doneButton, deleteButton]
            // Don't modify the left bar button item to preserve the back button
        } else {
            // In normal mode - show Edit and Add buttons
            // Only show edit button if there are feeds to edit
            if feeds.isEmpty {
                // If no feeds, only show add button
                navigationItem.rightBarButtonItems = [addButton]
            } else {
                // Create edit button and add it to the right bar with add button
                let editButton = UIBarButtonItem(
                    barButtonSystemItem: .edit,
                    target: self,
                    action: #selector(editButtonTapped)
                )

                navigationItem.rightBarButtonItems = [addButton, editButton]
            }
            // Don't modify the left bar button item to preserve the back button
        }

        // Force the navigation bar to update
        navigationController?.navigationBar.setNeedsLayout()
    }
    
    private func createBarButton(imageName: String, action: Selector) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            image: resizeImage(UIImage(named: imageName), targetSize: CGSize(width: 24, height: 24))?
                .withRenderingMode(.alwaysTemplate),
            style: .plain,
            target: self,
            action: action
        )
        return button
    }
    
    private func resizeImage(_ image: UIImage?, targetSize: CGSize) -> UIImage? {
        guard let image = image else { return nil }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    private func setupTableView() {
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Add a refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    @objc private func refreshFeeds() {
        loadFeeds()
        tableView.refreshControl?.endRefreshing()
    }
    
    @objc private func addButtonTapped() {
        let alert = UIAlertController(
            title: "Add RSS Feed",
            message: "Enter the RSS feed URL",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "https://example.com/feed.xml"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
        }

        let addAction = UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let urlString = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: urlString) else {
                self?.showError("Please enter a valid URL")
                return
            }

            self?.validateAndAddFeed(url)
        }

        alert.addAction(addAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func editButtonTapped() {
        isEditingMode = true
    }

    @objc private func doneButtonTapped() {
        isEditingMode = false
    }

    @objc private func deleteSelectedButtonTapped() {
        guard !selectedFeeds.isEmpty else { return }

        let feedCount = selectedFeeds.count
        let message = feedCount == 1
            ? "Are you sure you want to delete this RSS feed?"
            : "Are you sure you want to delete these \(feedCount) RSS feeds?"

        let alert = UIAlertController(
            title: "Delete RSS Feeds",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteSelectedFeeds()
        })

        present(alert, animated: true)
    }
    
    private func validateAndAddFeed(_ url: URL) {
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.center = view.center
        view.addSubview(activityIndicator)

        // Disable user interaction while validating
        view.isUserInteractionEnabled = false

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Remove loading indicator
                activityIndicator.removeFromSuperview()

                // Re-enable user interaction
                self.view.isUserInteractionEnabled = true

                if let error = error {
                    self.showError("Failed to fetch RSS feed: \(error.localizedDescription)")
                    return
                }

                guard let data = data,
                      let xmlString = String(data: data, encoding: .utf8),
                      xmlString.contains("<rss") || xmlString.contains("<feed") else {
                    self.showError("Invalid RSS feed format")
                    return
                }

                let title = self.parseFeedTitle(from: xmlString) ?? url.host ?? "Untitled Feed"
                let feed = RSSFeed(url: url.absoluteString, title: title, lastUpdated: Date())
                self.saveFeed(feed)
            }
        }
        task.resume()
    }

    private func validateAndUpdateFeed(oldFeed: RSSFeed, newTitle: String, newURL: URL, at indexPath: IndexPath) {
        // Check if this URL already exists in another feed
        let urlExists = feeds.contains { $0.url == newURL.absoluteString && $0.url != oldFeed.url }
        if urlExists {
            showError("This RSS feed URL already exists in your feed list")
            return
        }

        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.center = view.center
        view.addSubview(activityIndicator)

        // Disable user interaction while validating
        view.isUserInteractionEnabled = false

        // Validate the new URL is a valid RSS feed
        let task = URLSession.shared.dataTask(with: newURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Remove loading indicator
                activityIndicator.removeFromSuperview()

                // Re-enable user interaction
                self.view.isUserInteractionEnabled = true

                if let error = error {
                    self.showError("Failed to fetch RSS feed: \(error.localizedDescription)")
                    return
                }

                guard let data = data,
                      let xmlString = String(data: data, encoding: .utf8),
                      xmlString.contains("<rss") || xmlString.contains("<feed") else {
                    self.showError("Invalid RSS feed format")
                    return
                }

                // Create the updated feed with the new URL
                var updatedFeed = oldFeed
                updatedFeed.title = newTitle

                // Need to create a new feed with the new URL since URL is immutable
                let newFeed = RSSFeed(url: newURL.absoluteString, title: newTitle, lastUpdated: Date())

                // Remove the old feed and add the new one
                self.feeds.remove(at: indexPath.row)
                self.feeds.append(newFeed)

                // Re-sort the feeds by title
                self.feeds.sort { $0.title.lowercased() < $1.title.lowercased() }

                // Save the updated feeds array
                StorageManager.shared.save(self.feeds, forKey: "rssFeeds") { error in
                    if let error = error {
                        self.showError("Failed to update feed: \(error.localizedDescription)")
                    } else {
                        // Post notification that feeds have been updated
                        NotificationCenter.default.post(name: NSNotification.Name("feedsUpdated"), object: nil)
                    }
                }
            }
        }
        task.resume()
    }
    
    private func parseFeedTitle(from xmlString: String) -> String? {
        if let titleRange = xmlString.range(of: "<title>"),
           let titleEndRange = xmlString.range(of: "</title>") {
            let startIndex = titleRange.upperBound
            let endIndex = titleEndRange.lowerBound
            return String(xmlString[startIndex..<endIndex])
        }
        return nil
    }
    
    // MARK: - UITableViewDataSource Methods
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Settings section
            return 1
        case 1: // Feeds section
            return feeds.count
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0: // Settings section
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as? SwitchTableViewCell else {
                return UITableViewCell()
            }
            
            cell.configure(
                with: "Enable Full-Text Extraction",
                subtitle: "Automatically extract full content for partial feeds",
                isOn: enableFullTextExtraction
            )
            
            cell.switchToggleHandler = { [weak self] (isOn: Bool) in
                UserDefaults.standard.set(isOn, forKey: "enableFullTextExtraction")
                // Post notification so other parts of the app can respond
                NotificationCenter.default.post(name: Notification.Name("fullTextExtractionChanged"), object: nil)
            }
            
            return cell
            
        case 1: // Feeds section
            let cell = tableView.dequeueReusableCell(withIdentifier: "FeedCell", for: indexPath)
            let feed = feeds[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = feed.title
            config.secondaryText = feed.url
            cell.contentConfiguration = config

            // Configure for editing mode
            if isEditingMode {
                cell.selectionStyle = .default
            } else {
                cell.selectionStyle = .gray
            }

            return cell
            
        default:
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Feed Settings"
        case 1:
            return "Your RSS Feeds"
        default:
            return nil
        }
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        // Only allow deletion in the feeds section
        guard indexPath.section == 1, editingStyle == .delete else { return }
        
        let _ = feeds[indexPath.row]
        feeds.remove(at: indexPath.row)
        // Save the updated feeds array.
        StorageManager.shared.save(feeds, forKey: "rssFeeds") { error in
            if let error = error {
                self.showError("Failed to update feeds: \(error.localizedDescription)")
            }
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Only allow editing in the feeds section
        return indexPath.section == 1
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == 0 {
            // Don't allow editing for the settings section
            return .none
        }

        // If we're in our custom editing mode, disable swipe-to-delete
        if isEditingMode {
            return .none
        }

        // When not in editing mode, allow swipe-to-delete
        return .delete
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            // When in editing mode, selection is handled by the table view
            // Update the delete button state
            DispatchQueue.main.async {
                self.updateNavigationBar()
            }
        } else {
            tableView.deselectRow(at: indexPath, animated: true)

            // If a feed is selected, allow editing the feed title
            if indexPath.section == 1 {
                let feed = feeds[indexPath.row]
                showEditFeedDialog(feed: feed, at: indexPath)
            }
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            // Update the delete button state when deselecting
            DispatchQueue.main.async {
                self.updateNavigationBar()
            }
        }
    }
    
    private func showEditFeedDialog(feed: RSSFeed, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Edit Feed",
            message: "Update the feed title and URL",
            preferredStyle: .alert
        )

        // Add title field
        alert.addTextField { textField in
            textField.text = feed.title
            textField.placeholder = "Feed Title"
        }

        // Add URL field
        alert.addTextField { textField in
            textField.text = feed.url
            textField.placeholder = "Feed URL"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let newTitle = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newTitle.isEmpty,
                  let newURLString = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let newURL = URL(string: newURLString) else {
                self?.showError("Please enter a valid title and URL")
                return
            }

            // Check if the URL was changed and if so, validate it
            if newURLString != feed.url {
                self.validateAndUpdateFeed(oldFeed: feed, newTitle: newTitle, newURL: newURL, at: indexPath)
            } else {
                // Only title changed, update immediately
                var updatedFeed = feed
                updatedFeed.title = newTitle

                // Update the feeds array
                self.feeds[indexPath.row] = updatedFeed

                // Save the updated feeds array
                StorageManager.shared.save(self.feeds, forKey: "rssFeeds") { error in
                    if let error = error {
                        self.showError("Failed to update feed: \(error.localizedDescription)")
                    }
                }
            }
        }

        alert.addAction(saveAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func deleteSelectedFeeds() {
        // Get the feeds to delete
        let feedsToDelete = selectedFeeds

        // Remove the selected feeds from the feeds array
        feeds.removeAll { feedsToDelete.contains($0) }

        // Save the updated feeds array
        StorageManager.shared.save(feeds, forKey: "rssFeeds") { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.showError("Failed to delete feeds: \(error.localizedDescription)")
                // Reload feeds to restore the previous state
                self.loadFeeds()
            } else {
                // Exit editing mode after successful deletion
                self.isEditingMode = false

                // Post notification to update other parts of the app
                NotificationCenter.default.post(name: NSNotification.Name("feedsUpdated"), object: nil)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
