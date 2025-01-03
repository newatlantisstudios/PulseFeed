import UIKit
import CloudKit

class SettingsViewController: UIViewController {
    private lazy var iCloudSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = UserDefaults.standard.bool(forKey: "useICloud")
        toggle.addTarget(self, action: #selector(iCloudSwitchChanged), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    
    private lazy var iCloudLabel: UILabel = {
        let label = UILabel()
        label.text = "Sync with iCloud"
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var importButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Import OPML"
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemBlue
        configuration.buttonSize = .medium
        
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(importOPML), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var exportButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Export OPML"
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemBlue
        configuration.buttonSize = .medium
        
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(exportOPML), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var resetButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Reset Read Items"
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemRed
        configuration.buttonSize = .medium
        
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(resetReadItems), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        setupViews()
    }
    
    private func setupViews() {
        view.addSubview(iCloudLabel)
        view.addSubview(iCloudSwitch)
        view.addSubview(importButton)
        view.addSubview(exportButton)
        view.addSubview(resetButton)
        
        NSLayoutConstraint.activate([
            iCloudLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            iCloudLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            iCloudSwitch.centerYAnchor.constraint(equalTo: iCloudLabel.centerYAnchor),
            iCloudSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            importButton.topAnchor.constraint(equalTo: iCloudLabel.bottomAnchor, constant: 30),
            importButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            importButton.widthAnchor.constraint(equalToConstant: 140),
            
            exportButton.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 16),
            exportButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            exportButton.widthAnchor.constraint(equalToConstant: 140),
            
            resetButton.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 16),
                    resetButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                    resetButton.widthAnchor.constraint(equalToConstant: 140)
        ])
    }
    
    @objc private func iCloudSwitchChanged(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: "useICloud")
        if sender.isOn {
            checkICloudAvailability()
        }
        NotificationCenter.default.post(name: Notification.Name("iCloudSyncPreferenceChanged"), object: nil)
    }
    
    @objc private func importOPML() {
        // TODO: Implement OPML import functionality
    }
    
    @objc private func exportOPML() {
        // TODO: Implement OPML export functionality
    }
    
    @objc private func resetReadItems() {
        let alert = UIAlertController(
            title: "Reset Read Items",
            message: "Are you sure you want to reset all read items? This cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
            UserDefaults.standard.removeObject(forKey: "readItems")
            NotificationCenter.default.post(name: Notification.Name("readItemsReset"), object: nil)
        })
        
        present(alert, animated: true)
    }
    
    private func checkICloudAvailability() {
        CKContainer.default().accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                if status != .available {
                    self?.iCloudSwitch.setOn(false, animated: true)
                    UserDefaults.standard.set(false, forKey: "useICloud")
                    self?.showError("iCloud is not available. Please sign in to your iCloud account in Settings.")
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
