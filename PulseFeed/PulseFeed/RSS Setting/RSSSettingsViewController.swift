import UIKit
import CloudKit

struct RSSFeed: Codable, Hashable {
    let url: String
    let title: String
    var lastUpdated: Date
    
    private enum CodingKeys: String, CodingKey {
        case url, title, lastUpdated
    }
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        // Use url as unique identifier since it should be unique for each feed
        hasher.combine(url)
    }
    
    static func == (lhs: RSSFeed, rhs: RSSFeed) -> Bool {
        return lhs.url == rhs.url
    }
}

class RSSSettingsViewController : UIViewController, UITableViewDelegate, UITableViewDataSource {
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FeedCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.allowsSelection = false
        return table
    }()
    
    private var feeds: [RSSFeed] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    private var useICloud: Bool {
        UserDefaults.standard.bool(forKey: "useICloud")
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
        // Save locally first
        var feeds = loadLocalFeeds()
        feeds.append(feed)
        saveLocally(feeds)
        
        // Save to iCloud if enabled
        if useICloud {
            saveToICloud(feed)
        } else {
            self.feeds = feeds
        }
    }
    
    private func saveLocally(_ feeds: [RSSFeed]) {
        if let encodedData = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(encodedData, forKey: "rssFeeds")
        }
    }
    
    private func saveToICloud(_ feed: RSSFeed) {
        let record = CKRecord(recordType: "RSSFeed")
        record.setValue(feed.url, forKey: "url")
        record.setValue(feed.title, forKey: "title")
        record.setValue(feed.lastUpdated, forKey: "lastUpdated")
        
        CKContainer.default().privateCloudDatabase.save(record) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showError("Failed to save to iCloud: \(error.localizedDescription)")
                    return
                }
                self?.loadFeeds()
            }
        }
    }
    
    private func loadFeeds() {
        if useICloud {
            loadFromICloud()
        } else {
            feeds = loadLocalFeeds()
        }
    }
    
    private func loadFromICloud() {
        let query = CKQuery(recordType: "RSSFeed", predicate: NSPredicate(value: true))
        CKContainer.default().privateCloudDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                guard let records = records, error == nil else {
                    self?.feeds = self?.loadLocalFeeds() ?? []
                    return
                }
                
                let cloudFeeds = records.compactMap { record -> RSSFeed? in
                    guard let url = record["url"] as? String,
                          let title = record["title"] as? String,
                          let lastUpdated = record["lastUpdated"] as? Date else { return nil }
                    return RSSFeed(url: url, title: title, lastUpdated: lastUpdated)
                }
                self?.feeds = cloudFeeds
                self?.saveLocally(cloudFeeds) // Keep local copy in sync
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
        button.tintColor = .white
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
    
    @objc private func importButtonTapped() {
        // Handle import button tap
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
    
    private func syncWithiCloud() {
        let query = CKQuery(recordType: "RSSFeed", predicate: NSPredicate(value: true))
        CKContainer.default().privateCloudDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                guard let records = records, error == nil else { return }
                let cloudFeeds = records.compactMap { record -> RSSFeed? in
                    guard let url = record["url"] as? String,
                          let title = record["title"] as? String,
                          let lastUpdated = record["lastUpdated"] as? Date else { return nil }
                    return RSSFeed(url: url, title: title, lastUpdated: lastUpdated)
                }
                self?.feeds = Array(Set(self?.feeds ?? []).union(cloudFeeds))
            }
        }
    }
    
    private func loadLocalFeeds() -> [RSSFeed] {
        guard let data = UserDefaults.standard.data(forKey: "rssFeeds"),
              let feeds = try? JSONDecoder().decode([RSSFeed].self, from: data) else {
            return []
        }
        return feeds
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
    
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return feeds.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FeedCell", for: indexPath)
        let feed = feeds[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        config.secondaryText = feed.url
        cell.contentConfiguration = config
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let feed = feeds[indexPath.row]
        deleteFeed(feed, at: indexPath)
    }
    
    private func deleteFeed(_ feed: RSSFeed, at indexPath: IndexPath) {
        feeds.remove(at: indexPath.row)
        
        if let encodedData = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(encodedData, forKey: "rssFeeds")
        }
        
        let predicate = NSPredicate(format: "url == %@", feed.url)
        let query = CKQuery(recordType: "RSSFeed", predicate: predicate)
        
        CKContainer.default().privateCloudDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            guard let record = records?.first else { return }
            CKContainer.default().privateCloudDatabase.delete(withRecordID: record.recordID) { _, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.showError("Failed to delete from iCloud: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
