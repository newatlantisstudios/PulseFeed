import UIKit

class SyncStatusBarButtonItem: UIBarButtonItem {
    private let statusButton = UIButton(type: .system)
    private var currentState: SyncState = .synced
    private var lastSyncTime: Date?
    private var pendingCount: Int = 0
    private var animationTimer: Timer?
    
    override init() {
        super.init()
        setupButton()
        // Set initial state to synced
        statusButton.setImage(UIImage(systemName: "checkmark.icloud.fill"), for: .normal)
        statusButton.tintColor = .systemGreen
        startObserving()
        updateStatus()
        
        // Periodically refresh status to prevent stuck states
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
        // Set initial state to synced
        statusButton.setImage(UIImage(systemName: "checkmark.icloud.fill"), for: .normal)
        statusButton.tintColor = .systemGreen
        startObserving()
        updateStatus()
        
        // Periodically refresh status to prevent stuck states
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }
    
    deinit {
        animationTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupButton() {
        statusButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        // Configure button size
        statusButton.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        
        // Configure image rendering
        statusButton.imageView?.contentMode = .scaleAspectFit
        statusButton.contentMode = .center
        statusButton.adjustsImageSizeForAccessibilityContentSizeCategory = false
        
        // Configure image configuration to ensure proper sizing
        statusButton.configuration = UIButton.Configuration.plain()
        statusButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        
        customView = statusButton
    }
    
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
    
    private func updateStatus() {
        // Refresh sync manager status first to ensure we have the latest state
        SyncManager.shared.refreshSyncStatus()
        
        let (state, lastSync, pending) = SyncManager.shared.getSyncStatus()
        
        currentState = state
        lastSyncTime = lastSync
        pendingCount = pending
        
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    private func updateUI() {
        // Stop any existing animation
        animationTimer?.invalidate()
        animationTimer = nil
        statusButton.imageView?.layer.removeAllAnimations()
        statusButton.transform = .identity
        
        switch currentState {
        case .synced:
            statusButton.setImage(UIImage(systemName: "checkmark.icloud.fill"), for: .normal)
            statusButton.tintColor = .systemGreen
            
        case .syncing:
            statusButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
            statusButton.tintColor = AppColors.accent
            
            // Animate rotation on the imageView, not the button
            if let imageView = statusButton.imageView {
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.toValue = NSNumber(value: Double.pi * 2)
                rotation.duration = 2.0
                rotation.isCumulative = true
                rotation.repeatCount = .infinity
                imageView.layer.add(rotation, forKey: "rotationAnimation")
            }
            
        case .failed:
            statusButton.setImage(UIImage(systemName: "exclamationmark.icloud.fill"), for: .normal)
            statusButton.tintColor = .systemRed
            
        case .offline:
            statusButton.setImage(UIImage(systemName: "icloud.slash.fill"), for: .normal)
            statusButton.tintColor = .systemGray
            
        case .pending:
            statusButton.setImage(UIImage(systemName: "clock.fill"), for: .normal)
            statusButton.tintColor = .systemOrange
        }
        
        // Add badge for pending count
        if pendingCount > 0 && currentState != .syncing {
            addBadge(count: pendingCount)
        } else {
            removeBadge()
        }
    }
    
    private func addBadge(count: Int) {
        removeBadge()
        
        let badgeLabel = UILabel(frame: CGRect(x: 16, y: 0, width: 14, height: 14))
        badgeLabel.tag = 999 // Tag to identify badge
        badgeLabel.text = "\(min(count, 9))"
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .systemRed
        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 7
        badgeLabel.clipsToBounds = true
        
        statusButton.addSubview(badgeLabel)
    }
    
    private func removeBadge() {
        statusButton.viewWithTag(999)?.removeFromSuperview()
    }
    
    @objc private func buttonTapped() {
        let alert = UIAlertController(title: "Sync Status", message: nil, preferredStyle: .alert)
        
        // Build status message
        var message = ""
        
        switch currentState {
        case .synced:
            message = "✅ Synced"
        case .syncing:
            message = "🔄 Syncing..."
        case .failed(let error):
            message = "❌ Sync Failed\n\(error.localizedDescription)"
        case .offline:
            message = "📴 Offline"
        case .pending:
            message = "⏳ Pending"
        }
        
        if let lastSyncTime = lastSyncTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let dateString = formatter.string(from: lastSyncTime)
            let timeAgo = DateUtils.getTimeAgo(from: dateString)
            message += "\n\nLast sync: \(timeAgo)"
        } else {
            message += "\n\nNever synced"
        }
        
        if pendingCount > 0 {
            message += "\nPending operations: \(pendingCount)"
        }
        
        alert.message = message
        
        // Add actions
        alert.addAction(UIAlertAction(title: "View History", style: .default) { _ in
            self.showSyncHistory()
        })
        
        if currentState != .syncing {
            alert.addAction(UIAlertAction(title: "Force Sync", style: .default) { _ in
                self.forceSync()
            })
        }
        
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        
        // Present from the current view controller
        if let viewController = self.findViewController() {
            viewController.present(alert, animated: true)
        }
    }
    
    private func showSyncHistory() {
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
    
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = customView
        while responder != nil {
            if let viewController = responder as? UIViewController {
                return viewController
            }
            responder = responder?.next
        }
        return nil
    }
}