import UIKit

class SyncStatusView: UIView {
    // UI Elements
    private let statusIconImageView = UIImageView()
    private let statusLabel = UILabel()
    private let lastSyncLabel = UILabel()
    private let pendingCountLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    
    // State
    private var currentState: SyncState = .synced
    private var lastSyncTime: Date?
    private var pendingCount: Int = 0
    
    // Timer for updating time ago
    private var updateTimer: Timer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        startObserving()
        updateStatus()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        startObserving()
        updateStatus()
    }
    
    deinit {
        updateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = AppColors.background
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = AppColors.secondary.cgColor
        
        // Add subviews
        addSubview(statusIconImageView)
        addSubview(statusLabel)
        addSubview(lastSyncLabel)
        addSubview(pendingCountLabel)
        addSubview(progressView)
        
        // Configure views
        statusIconImageView.contentMode = .scaleAspectFit
        statusIconImageView.tintColor = AppColors.accent
        
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = AppColors.accent
        
        lastSyncLabel.font = .systemFont(ofSize: 12)
        lastSyncLabel.textColor = AppColors.secondary
        
        pendingCountLabel.font = .systemFont(ofSize: 12)
        pendingCountLabel.textColor = AppColors.secondary
        
        progressView.progressTintColor = AppColors.accent
        progressView.isHidden = true
        
        // Setup constraints
        setupConstraints()
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
        
        // Start update timer
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateTimeAgo()
        }
    }
    
    private func setupConstraints() {
        statusIconImageView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        lastSyncLabel.translatesAutoresizingMaskIntoConstraints = false
        pendingCountLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Status icon
            statusIconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusIconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIconImageView.widthAnchor.constraint(equalToConstant: 20),
            statusIconImageView.heightAnchor.constraint(equalToConstant: 20),
            
            // Status label
            statusLabel.leadingAnchor.constraint(equalTo: statusIconImageView.trailingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            
            // Last sync label
            lastSyncLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            lastSyncLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            
            // Pending count label
            pendingCountLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pendingCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // Progress view
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),
            
            // View height
            heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Observing
    
    private func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncStateChanged(_:)),
            name: Notification.Name("SyncStateChanged"),
            object: nil
        )
    }
    
    @objc private func syncStateChanged(_ notification: Notification) {
        updateStatus()
    }
    
    // MARK: - Updates
    
    private func updateStatus() {
        let (state, lastSync, pending) = SyncManager.shared.getSyncStatus()
        
        currentState = state
        lastSyncTime = lastSync
        pendingCount = pending
        
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    private func updateUI() {
        switch currentState {
        case .synced:
            statusIconImageView.image = UIImage(systemName: "checkmark.circle.fill")
            statusIconImageView.tintColor = .systemGreen
            statusLabel.text = "Synced"
            progressView.isHidden = true
            
        case .syncing:
            statusIconImageView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            statusIconImageView.tintColor = AppColors.accent
            statusLabel.text = "Syncing..."
            progressView.isHidden = false
            progressView.setProgress(0.5, animated: true)
            
            // Animate icon rotation
            let rotation = CABasicAnimation(keyPath: "transform.rotation")
            rotation.toValue = NSNumber(value: Double.pi * 2)
            rotation.duration = 2.0
            rotation.repeatCount = .infinity
            statusIconImageView.layer.add(rotation, forKey: "rotationAnimation")
            
        case .failed:
            statusIconImageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            statusIconImageView.tintColor = .systemRed
            statusLabel.text = "Sync Failed"
            progressView.isHidden = true
            statusIconImageView.layer.removeAllAnimations()
            
        case .offline:
            statusIconImageView.image = UIImage(systemName: "wifi.slash")
            statusIconImageView.tintColor = .systemGray
            statusLabel.text = "Offline"
            progressView.isHidden = true
            statusIconImageView.layer.removeAllAnimations()
            
        case .pending:
            statusIconImageView.image = UIImage(systemName: "clock.fill")
            statusIconImageView.tintColor = .systemOrange
            statusLabel.text = "Pending"
            progressView.isHidden = true
            statusIconImageView.layer.removeAllAnimations()
        }
        
        updateTimeAgo()
        updatePendingCount()
    }
    
    private func updateTimeAgo() {
        if let lastSyncTime = lastSyncTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let dateString = formatter.string(from: lastSyncTime)
            let timeAgo = DateUtils.getTimeAgo(from: dateString)
            lastSyncLabel.text = "Last sync: \(timeAgo)"
        } else {
            lastSyncLabel.text = "Never synced"
        }
    }
    
    private func updatePendingCount() {
        if pendingCount > 0 {
            pendingCountLabel.text = "\(pendingCount) pending"
            pendingCountLabel.isHidden = false
        } else {
            pendingCountLabel.isHidden = true
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleTap() {
        // Show sync details in an alert
        let alert = UIAlertController(title: "Sync Status", message: nil, preferredStyle: .alert)
        
        // Add sync details
        var message = "Status: \(statusText)\n"
        message += "Last Sync: \(lastSyncLabel.text ?? "Never")\n"
        message += "Pending Operations: \(pendingCount)\n"
        
        if case .failed(let error) = currentState {
            message += "\nError: \(error.localizedDescription)"
        }
        
        alert.message = message
        
        // Add actions
        alert.addAction(UIAlertAction(title: "View History", style: .default) { _ in
            self.showSyncHistory()
        })
        
        alert.addAction(UIAlertAction(title: "Force Sync", style: .default) { _ in
            self.forceSync()
        })
        
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        
        // Present alert
        if let viewController = self.findViewController() {
            viewController.present(alert, animated: true)
        }
    }
    
    private var statusText: String {
        switch currentState {
        case .synced: return "Synced"
        case .syncing: return "Syncing"
        case .failed: return "Failed"
        case .offline: return "Offline"
        case .pending: return "Pending"
        }
    }
    
    private func showSyncHistory() {
        // Navigate to sync history view
        if let viewController = self.findViewController() {
            let historyVC = SyncHistoryViewController()
            viewController.navigationController?.pushViewController(historyVC, animated: true)
        }
    }
    
    private func forceSync() {
        SyncManager.shared.forceSyncAll { success, error in
            if !success {
                // Show error alert
                let alert = UIAlertController(
                    title: "Sync Failed",
                    message: error?.localizedDescription ?? "Unknown error",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                if let viewController = self.findViewController() {
                    viewController.present(alert, animated: true)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            if let viewController = responder as? UIViewController {
                return viewController
            }
            responder = responder?.next
        }
        return nil
    }
}

// MARK: - Sync History View Controller
class SyncHistoryViewController: UIViewController {
    private let tableView = UITableView()
    private var syncEvents: [SyncEvent] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Sync History"
        view.backgroundColor = AppColors.background
        
        setupTableView()
        loadHistory()
    }
    
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshHistory), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        // Add export button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Export",
            style: .plain,
            target: self,
            action: #selector(exportHistory)
        )
    }
    
    private func loadHistory() {
        syncEvents = SyncHistory.shared.getRecentEvents()
        tableView.reloadData()
    }
    
    @objc private func refreshHistory() {
        loadHistory()
        tableView.refreshControl?.endRefreshing()
    }
    
    @objc private func exportHistory() {
        guard let data = SyncHistory.shared.exportHistory() else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [data],
            applicationActivities: nil
        )
        present(activityVC, animated: true)
    }
}

// MARK: - Table View Data Source
extension SyncHistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return syncEvents.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let event = syncEvents[indexPath.row]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        
        var text = "\(event.type.rawValue) - \(event.status.stringValue)"
        text += "\n\(dateFormatter.string(from: event.timestamp))"
        text += "\n\(event.details)"
        
        if let duration = event.duration {
            text += " (Duration: \(String(format: "%.2f", duration))s)"
        }
        
        cell.textLabel?.text = text
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .systemFont(ofSize: 12)
        
        // Color code by status
        switch event.status {
        case .completed:
            cell.textLabel?.textColor = .systemGreen
        case .failed:
            cell.textLabel?.textColor = .systemRed
        case .rateLimited:
            cell.textLabel?.textColor = .systemOrange
        default:
            cell.textLabel?.textColor = AppColors.accent
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let event = syncEvents[indexPath.row]
        
        // Show event details
        let alert = UIAlertController(title: "Sync Event Details", message: nil, preferredStyle: .alert)
        
        var message = "Type: \(event.type.rawValue)\n"
        message += "Status: \(event.status.stringValue)\n"
        message += "Time: \(DateFormatter.localizedString(from: event.timestamp, dateStyle: .short, timeStyle: .medium))\n"
        message += "Details: \(event.details)\n"
        
        if let duration = event.duration {
            message += "Duration: \(String(format: "%.2f", duration))s\n"
        }
        
        if let error = event.error {
            message += "\nError: \(error.localizedDescription)"
        }
        
        alert.message = message
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        present(alert, animated: true)
    }
}