import UIKit

class RSSSettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FeedCell")
        table.register(SettingSwitchCell.self, forCellReuseIdentifier: "SwitchCell")
        table.translatesAutoresizingMaskIntoConstraints = false
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RSS Settings"
        view.backgroundColor = AppColors.background
        setupNavigationBar()
        setupTableView()
        setupNotifications()
        loadFeeds()
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
            switch result {
            case .success(let loadedFeeds):
                self.feeds = loadedFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }
            case .failure(let error):
                print("Error loading feeds: \(error.localizedDescription)")
                self.feeds = []
            }
            // Debug: Print the loaded feeds.
            print("Loaded RSS Feeds:")
            for feed in self.feeds {
                print("Title: \(feed.title) | URL: \(feed.url) | Last Updated: \(feed.lastUpdated)")
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
        let addButton = createBarButton(imageName: "add", action: #selector(addButtonTapped))
        navigationItem.rightBarButtonItems = [addButton]
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
    
    private func validateAndAddFeed(_ url: URL) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showError("Failed to fetch RSS feed: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data,
                      let xmlString = String(data: data, encoding: .utf8),
                      xmlString.contains("<rss") || xmlString.contains("<feed") else {
                    self?.showError("Invalid RSS feed format")
                    return
                }
                
                let title = self?.parseFeedTitle(from: xmlString) ?? url.host ?? "Untitled Feed"
                let feed = RSSFeed(url: url.absoluteString, title: title, lastUpdated: Date())
                self?.saveFeed(feed)
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
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as? SettingSwitchCell else {
                return UITableViewCell()
            }
            
            cell.configure(
                title: "Enable Full-Text Extraction",
                subtitle: "Automatically extract full content for partial feeds",
                isOn: enableFullTextExtraction
            )
            
            cell.switchToggled = { [weak self] (isOn: Bool) in
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
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // If a feed is selected, allow editing the feed title
        if indexPath.section == 1 {
            let feed = feeds[indexPath.row]
            showEditFeedDialog(feed: feed, at: indexPath)
        }
    }
    
    private func showEditFeedDialog(feed: RSSFeed, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Edit Feed",
            message: "Update the feed title",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.text = feed.title
            textField.placeholder = "Feed Title"
        }
        
        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let newTitle = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newTitle.isEmpty else {
                return
            }
            
            // Update the feed with the new title
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
        
        alert.addAction(saveAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
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
