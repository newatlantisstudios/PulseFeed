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
        let stackView = UIStackView(arrangedSubviews: [importButton, exportButton, resetButton])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            importButton.widthAnchor.constraint(equalToConstant: 140),
            exportButton.widthAnchor.constraint(equalToConstant: 140),
            resetButton.widthAnchor.constraint(equalToConstant: 140)
        ])
    }
    
    @objc private func importOPML() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["org.opml.opml", "public.xml", "public.data", "public.content", "public.plain-text", ".opml", "com.apple.opml"], in: .import)
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
            
            let alert = UIAlertController(title: "Import Successful", message: "Feeds have been imported", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            
            NotificationCenter.default.post(name: .feedsUpdated, object: nil)
        } else {
            showError("Invalid OPML format")
        }
    }
    
    @objc private func exportOPML() {
        let feeds = loadLocalFeeds()
        
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
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
