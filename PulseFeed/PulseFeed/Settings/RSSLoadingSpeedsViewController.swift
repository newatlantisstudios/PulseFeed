import UIKit

class RSSLoadingSpeedsViewController: UITableViewController {
    
    // Data source: list of (feed title, load time)
    var feedLoadTimes: [(title: String, time: TimeInterval)] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RSS Feed Loading Speeds"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FeedSpeedCell")
        loadFeedTimes()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data in case new times have been recorded
        loadFeedTimes()
    }
    
    private func loadFeedTimes() {
        feedLoadTimes = FeedLoadTimeManager.shared.loadTimes
            .map { (title: $0.key, time: $0.value) }
            .sorted { $0.time > $1.time } // Sort descending: slowest (highest time) first
        tableView.reloadData()
    }
    
    // MARK: - Table View Data Source Methods
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return feedLoadTimes.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FeedSpeedCell", for: indexPath)
        let feed = feedLoadTimes[indexPath.row]
        let formattedTime: String
        if feed.time < 0 {
            formattedTime = "skipped"
        } else if feed.time < 60 {
            formattedTime = String(format: "%.2f seconds", feed.time)
        } else {
            let minutes = Int(feed.time) / 60
            let seconds = Int(feed.time) % 60
            formattedTime = "\(minutes)m \(seconds)s"
        }
        cell.textLabel?.text = "\(feed.title): \(formattedTime)"
        return cell
    }
    
}
