extension Notification.Name {
    static let feedsUpdated = Notification.Name("feedsUpdated")
}

class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var feeds: [RSSFeed] = []
    var currentTitle: String?
    var currentUrl: String?
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "outline" {
            currentTitle = attributeDict["text"]
            currentUrl = attributeDict["xmlUrl"]
            
            if let title = currentTitle, let url = currentUrl {
                feeds.append(RSSFeed(url: url, title: title, lastUpdated: Date()))
            }
        }
    }
}

import Foundation
import UIKit
import CloudKit

class SettingsViewController: UIViewController, UIDocumentPickerDelegate{
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
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.xml"], in: .import)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        guard let xmlData = try? Data(contentsOf: url) else {
            showError("Failed to read OPML file")
            return
        }
        
        let parser = XMLParser(data: xmlData)
        let opmlDelegate = OPMLParserDelegate()
        parser.delegate = opmlDelegate
        
        if parser.parse() {
            let importedFeeds = opmlDelegate.feeds
            var existingFeeds = loadLocalFeeds()
            existingFeeds.append(contentsOf: importedFeeds)
            
            let uniqueFeeds = Array(Set(existingFeeds))
            
            if let encodedData = try? JSONEncoder().encode(uniqueFeeds) {
                UserDefaults.standard.set(encodedData, forKey: "rssFeeds")
            }
            
            if UserDefaults.standard.bool(forKey: "useICloud") {
                for feed in importedFeeds {
                    saveToICloud(feed)
                }
            }
            
            let alert = UIAlertController(title: "Import Successful", message: "Feeds have been imported", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            
            NotificationCenter.default.post(name: .feedsUpdated, object: nil)
        } else {
            showError("Invalid OPML format")
        }
    }
    
    private func saveToICloud(_ feed: RSSFeed) {
        let record = CKRecord(recordType: "RSSFeed")
        record.setValue(feed.url, forKey: "url")
        record.setValue(feed.title, forKey: "title")
        record.setValue(feed.lastUpdated, forKey: "lastUpdated")
        
        CKContainer.default().privateCloudDatabase.save(record) { [weak self] _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.showError("Failed to save to iCloud: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func exportOPML() {
        let feeds = loadLocalFeeds() // Using your existing function
        
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
            <head>
                <title>PulseFeed Subscriptions</title>
            </head>
            <body>
                \(feeds.map { feed in
                    """
                    <outline type="rss" text="\(feed.title)" xmlUrl="\(feed.url)"/>
                    """
                }.joined(separator: "\n"))
            </body>
        </opml>
        """
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "PulseFeed_\(Date().ISO8601Format()).opml"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try opml.write(to: fileURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            present(activityVC, animated: true)
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    private func loadLocalFeeds() -> [RSSFeed] {
        guard let data = UserDefaults.standard.data(forKey: "rssFeeds"),
              let feeds = try? JSONDecoder().decode([RSSFeed].self, from: data) else {
            return []
        }
        return feeds
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
