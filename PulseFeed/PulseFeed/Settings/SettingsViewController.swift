import CloudKit
import UIKit

extension Notification.Name {
    static let feedsUpdated = Notification.Name("feedsUpdated")
}

class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var feeds: [RSSFeed] = []
    var currentTitle: String?
    var currentUrl: String?

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "outline" {
            currentTitle = attributeDict["text"]
            currentUrl = attributeDict["xmlUrl"]

            if let title = currentTitle, let url = currentUrl {
                feeds.append(
                    RSSFeed(url: url, title: title, lastUpdated: Date()))
            }
        }
    }
}

class SettingsViewController: UIViewController, UIDocumentPickerDelegate {

    // MARK: - UI Elements

    private lazy var storageSwitch: UISwitch = {
        let uiSwitch = UISwitch()
        // Default to local if not set; otherwise, use the saved value.
        uiSwitch.isOn = UserDefaults.standard.bool(forKey: "useICloud")
        uiSwitch.addTarget(
            self, action: #selector(storageSwitchChanged(_:)),
            for: .valueChanged)
        uiSwitch.translatesAutoresizingMaskIntoConstraints = false
        return uiSwitch
    }()

    private lazy var tipJarButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Tip Jar"
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemOrange
        configuration.buttonSize = .medium

        let button = UIButton(configuration: configuration)
        button.addTarget(
            self, action: #selector(openTipJar), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var storageLabel: UILabel = {
        let label = UILabel()
        label.text = "iCloud Syncing"
        label.font = .systemFont(ofSize: 16)
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
        button.addTarget(
            self, action: #selector(importOPML), for: .touchUpInside)
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
        button.addTarget(
            self, action: #selector(exportOPML), for: .touchUpInside)
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
        button.addTarget(
            self, action: #selector(resetReadItems), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var forceSyncButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Force Sync"
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemGreen
        configuration.buttonSize = .medium
        let button = UIButton(configuration: configuration)
        button.addTarget(
            self, action: #selector(forceSyncData), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var rssLoadingSpeedsButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "RSS Feed Loading Speeds"
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemBlue
        configuration.buttonSize = .medium
        let button = UIButton(configuration: configuration)
        button.addTarget(
            self, action: #selector(openRSSLoadingSpeeds), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var fontSizeLabel: UILabel = {
        let label = UILabel()
        // If you’d like to show the current value
        let currentSize = UserDefaults.standard.float(forKey: "fontSize")
        label.text =
            currentSize != 0
            ? "Font Size: \(Int(currentSize))" : "Font Size: 16"
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var fontSizeSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 12
        slider.maximumValue = 32

        // Load previously saved value or default to 16
        let savedValue = UserDefaults.standard.float(forKey: "fontSize")
        slider.value = savedValue != 0 ? savedValue : 16

        // Make the track colors more obvious
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .lightGray

        // Use a larger “circle.fill” symbol for the thumb
        if let thumbImage = UIImage(systemName: "circle.fill") {
            // Tint the thumb to match minimumTrackTintColor
            let tintedThumb = thumbImage.withTintColor(
                .systemBlue, renderingMode: .alwaysOriginal)
            slider.setThumbImage(tintedThumb, for: .normal)
            slider.setThumbImage(tintedThumb, for: .highlighted)
        }

        // Scale the slider to make it taller
        slider.transform = CGAffineTransform(scaleX: 1.0, y: 1.2)

        // Handle value changes
        slider.addTarget(
            self, action: #selector(fontSizeSliderChanged(_:)),
            for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        setupViews()
    }

    // MARK: - Setup Views

    private func setupViews() {
        // Create a horizontal stack view for the storage switch and label.
        let storageStack = UIStackView(arrangedSubviews: [
            storageLabel, storageSwitch,
        ])
        storageStack.axis = .horizontal
        storageStack.alignment = .center
        storageStack.spacing = 8
        storageStack.translatesAutoresizingMaskIntoConstraints = false

        let fontSizeStack = UIStackView(arrangedSubviews: [
            fontSizeLabel, fontSizeSlider,
        ])
        fontSizeStack.axis = .horizontal
        fontSizeStack.spacing = 8
        fontSizeStack.alignment = .center
        fontSizeStack.translatesAutoresizingMaskIntoConstraints = false

        fontSizeSlider.widthAnchor.constraint(equalToConstant: 200).isActive =
            true

        // Create a main vertical stack view for all settings.
        let mainStack = UIStackView(arrangedSubviews: [
            storageStack, fontSizeStack, importButton, exportButton,
            resetButton,
            forceSyncButton, rssLoadingSpeedsButton, tipJarButton,
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 16
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mainStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            importButton.widthAnchor.constraint(equalToConstant: 140),
            exportButton.widthAnchor.constraint(equalToConstant: 140),
            resetButton.widthAnchor.constraint(equalToConstant: 140),
            forceSyncButton.widthAnchor.constraint(equalToConstant: 140),
            rssLoadingSpeedsButton.widthAnchor.constraint(equalToConstant: 200),

        ])
    }

    @objc private func fontSizeSliderChanged(_ sender: UISlider) {
        let fontSize = CGFloat(sender.value)
        // Update the label to reflect the new font size
        fontSizeLabel.text = "Font Size: \(Int(fontSize))"
        // Store the value
        UserDefaults.standard.set(Float(fontSize), forKey: "fontSize")
        // Notify HomeFeedViewController to reload (so users see immediate changes)
        NotificationCenter.default.post(
            name: Notification.Name("fontSizeChanged"), object: nil)
    }

    @objc private func openRSSLoadingSpeeds() {
        let rssLoadingVC = RSSLoadingSpeedsViewController(style: .plain)
        navigationController?.pushViewController(rssLoadingVC, animated: true)
    }

    @objc private func openTipJar() {
        let tipJarVC = TipJarViewController()
        navigationController?.pushViewController(tipJarVC, animated: true)
    }

    // MARK: - Updated Storage Switch Action and Migration Helpers
    @objc private func forceSyncData() {
        let iCloudEnabled = UserDefaults.standard.bool(forKey: "useICloud")
        guard iCloudEnabled else {
            let alert = UIAlertController(
                title: "iCloud Disabled",
                message: "Force Sync is only available when iCloud syncing is enabled.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let warningMessage = """
            This action will force a two-way merge between local data and iCloud. 
            Feeds, favorites, bookmarks, and read items will be combined.

            If there are discrepancies between iCloud and local storage, 
            those entries will be joined so both remain in sync.

            Do you want to proceed with the Force Sync?
            """
        let warningAlert = UIAlertController(
            title: "Force Sync",
            message: warningMessage,
            preferredStyle: .alert
        )
        warningAlert.addAction(
            UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        )
        warningAlert.addAction(
            UIAlertAction(title: "Proceed", style: .default) { _ in
                self.performForceSync()
            }
        )
        present(warningAlert, animated: true)
    }


    private func performForceSync() {
        // Use a dispatch group to load all data concurrently.
        let dispatchGroup = DispatchGroup()

        // Load RSS Feeds from CloudKit and local storage.
        var cloudRSSFeeds: [RSSFeed] = []
        var localRSSFeeds: [RSSFeed] = []
        dispatchGroup.enter()
        CloudKitStorage().load(forKey: "rssFeeds") {
            (result: Result<[RSSFeed], Error>) in
            if case .success(let feeds) = result {
                cloudRSSFeeds = feeds
            }
            dispatchGroup.leave()
        }
        dispatchGroup.enter()
        UserDefaultsStorage().load(forKey: "rssFeeds") {
            (result: Result<[RSSFeed], Error>) in
            if case .success(let feeds) = result {
                localRSSFeeds = feeds
            }
            dispatchGroup.leave()
        }

        // Load Hearted Items.
        var cloudHearted: [String] = []
        var localHearted: [String] = []
        dispatchGroup.enter()
        CloudKitStorage().load(forKey: "heartedItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                cloudHearted = items
            }
            dispatchGroup.leave()
        }
        dispatchGroup.enter()
        UserDefaultsStorage().load(forKey: "heartedItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                localHearted = items
            }
            dispatchGroup.leave()
        }

        // Load Bookmarked Items.
        var cloudBookmarks: [String] = []
        var localBookmarks: [String] = []
        dispatchGroup.enter()
        CloudKitStorage().load(forKey: "bookmarkedItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                cloudBookmarks = items
            }
            dispatchGroup.leave()
        }
        dispatchGroup.enter()
        UserDefaultsStorage().load(forKey: "bookmarkedItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                localBookmarks = items
            }
            dispatchGroup.leave()
        }

        // Load Read Items.
        var cloudReadItems: [String] = []
        var localReadItems: [String] = []
        dispatchGroup.enter()
        CloudKitStorage().load(forKey: "readItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                cloudReadItems = items
            }
            dispatchGroup.leave()
        }
        dispatchGroup.enter()
        UserDefaultsStorage().load(forKey: "readItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                localReadItems = items
            }
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            // Merge the data from CloudKit and local storage.
            let mergedRSSFeeds = self.mergeRSSFeeds(
                cloudFeeds: cloudRSSFeeds, localFeeds: localRSSFeeds)
            let mergedHearted = Array(
                Set(cloudHearted).union(Set(localHearted)))
            let mergedBookmarks = Array(
                Set(cloudBookmarks).union(Set(localBookmarks)))
            let mergedReadItems = Array(
                Set(cloudReadItems).union(Set(localReadItems)))

            let saveGroup = DispatchGroup()
            var migrationSuccess = true

            // Consolidate all CloudKit updates into a single update call.
            let updates: [String: Data] = [
                "rssFeeds": (try? JSONEncoder().encode(mergedRSSFeeds))
                    ?? Data(),
                "heartedItems": (try? JSONEncoder().encode(mergedHearted))
                    ?? Data(),
                "bookmarkedItems": (try? JSONEncoder().encode(mergedBookmarks))
                    ?? Data(),
                "readItems": (try? JSONEncoder().encode(mergedReadItems))
                    ?? Data(),
            ]
            saveGroup.enter()
            CloudKitStorage().updateRecord(with: updates) { error in
                if let error = error {
                    print(
                        "Error saving merged data to CloudKit: \(error.localizedDescription)"
                    )
                    migrationSuccess = false
                }
                saveGroup.leave()
            }

            // Also save merged data to local storage.
            saveGroup.enter()
            UserDefaultsStorage().save(mergedRSSFeeds, forKey: "rssFeeds") {
                error in
                if let error = error {
                    print(
                        "Error saving merged RSS feeds locally: \(error.localizedDescription)"
                    )
                    migrationSuccess = false
                }
                saveGroup.leave()
            }
            saveGroup.enter()
            UserDefaultsStorage().save(mergedHearted, forKey: "heartedItems") {
                error in
                if let error = error {
                    print(
                        "Error saving merged hearted items locally: \(error.localizedDescription)"
                    )
                    migrationSuccess = false
                }
                saveGroup.leave()
            }
            saveGroup.enter()
            UserDefaultsStorage().save(
                mergedBookmarks, forKey: "bookmarkedItems"
            ) { error in
                if let error = error {
                    print(
                        "Error saving merged bookmarks locally: \(error.localizedDescription)"
                    )
                    migrationSuccess = false
                }
                saveGroup.leave()
            }
            saveGroup.enter()
            UserDefaultsStorage().save(mergedReadItems, forKey: "readItems") {
                error in
                if let error = error {
                    print(
                        "Error saving merged read items locally: \(error.localizedDescription)"
                    )
                    migrationSuccess = false
                }
                saveGroup.leave()
            }

            saveGroup.notify(queue: .main) {
                let alertTitle =
                    migrationSuccess
                    ? "Force Sync Succeeded"
                    : "Force Sync Completed with Errors"
                let alertMessage = "Data has been merged and synchronized."
                let finalAlert = UIAlertController(
                    title: alertTitle, message: alertMessage,
                    preferredStyle: .alert)
                finalAlert.addAction(
                    UIAlertAction(title: "OK", style: .default))
                self.present(finalAlert, animated: true)
            }
        }
    }

    /// Helper to merge two arrays of RSSFeed based on their unique URL.
    /// Assumes that RSSFeed conforms to Hashable (using URL as the unique identifier).
    private func mergeRSSFeeds(cloudFeeds: [RSSFeed], localFeeds: [RSSFeed])
        -> [RSSFeed]
    {
        let mergedSet = Set(cloudFeeds).union(Set(localFeeds))
        return Array(mergedSet).sorted {
            $0.title.lowercased() < $1.title.lowercased()
        }
    }

    @objc private func storageSwitchChanged(_ sender: UISwitch) {
        if sender.isOn {
            // User is turning ON iCloud Sync
            let alert = UIAlertController(
                title: "Enable iCloud Sync?",
                message: """
                    Enabling iCloud will merge the local data on this device 
                    with any existing iCloud data.

                    After the merge, all your devices using iCloud 
                    will share the same feeds, favorites, bookmarks, and read items.

                    Do you want to enable iCloud syncing now?
                    """,
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    // Revert the switch if the user cancels
                    sender.setOn(false, animated: true)
                }
            )
            alert.addAction(
                UIAlertAction(title: "Enable", style: .default) { _ in
                    // 1) Set the UserDefaults flag
                    UserDefaults.standard.set(true, forKey: "useICloud")
                    // 2) Switch StorageManager to CloudKit
                    StorageManager.shared.method = .cloudKit
                    // 3) Immediately merge/force sync data (pull + push)
                    self.performForceSync()
                }
            )
            present(alert, animated: true)

        } else {
            // User is turning OFF iCloud Sync
            let alert = UIAlertController(
                title: "Disable iCloud Sync?",
                message: """
                    Disabling iCloud sync will stop data from 
                    synchronizing across your devices. 
                    
                    Only local storage will be used on this device.

                    Do you want to disable iCloud syncing?
                    """,
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    // Revert the switch if user cancels
                    sender.setOn(true, animated: true)
                }
            )
            alert.addAction(
                UIAlertAction(title: "Disable", style: .destructive) { _ in
                    // 1) Turn off iCloud in UserDefaults
                    UserDefaults.standard.set(false, forKey: "useICloud")
                    // 2) Switch to local storage only
                    StorageManager.shared.method = .userDefaults
                    // (Optional) If you want to pull down iCloud data before going local,
                    // you can call a “migrateICloudDataToLocal” method here.
                }
            )
            present(alert, animated: true)
        }
    }


    /// Gathers a summary of iCloud data to be transferred locally.
    private func fetchICloudDataSummary(completion: @escaping (String) -> Void)
    {
        let group = DispatchGroup()
        var rssFeedsCount = 0
        var heartedCount = 0
        var bookmarkedCount = 0
        var readItemsCount = 0
        let cloudStorage = CloudKitStorage()

        group.enter()
        cloudStorage.load(forKey: "rssFeeds") {
            (result: Result<[RSSFeed], Error>) in
            if case .success(let feeds) = result {
                rssFeedsCount = feeds.count
            }
            group.leave()
        }

        group.enter()
        cloudStorage.load(forKey: "heartedItems") {
            (result: Result<[String], Error>) in
            if case .success(let hearted) = result {
                heartedCount = hearted.count
            }
            group.leave()
        }

        group.enter()
        cloudStorage.load(forKey: "bookmarkedItems") {
            (result: Result<[String], Error>) in
            if case .success(let bookmarks) = result {
                bookmarkedCount = bookmarks.count
            }
            group.leave()
        }

        group.enter()
        cloudStorage.load(forKey: "readItems") {
            (result: Result<[String], Error>) in
            if case .success(let readItems) = result {
                readItemsCount = readItems.count
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let summary = """
                - RSS Feeds: \(rssFeedsCount)
                - Favorites: \(heartedCount)
                - Bookmarks: \(bookmarkedCount)
                - Read Articles: \(readItemsCount)
                """
            completion(summary)
        }
    }

    /// Migrates data from iCloud to local storage using UserDefaults.
    private func migrateICloudDataToLocal(completion: @escaping (Bool) -> Void)
    {
        // Define the keys and their expected types.
        let keysAndTypes: [(key: String, type: Any)] = [
            ("rssFeeds", [RSSFeed].self),
            ("heartedItems", [String].self),
            ("bookmarkedItems", [String].self),
            ("readItems", [String].self),
        ]

        let cloudStorage = CloudKitStorage()
        let ud = UserDefaults.standard
        let group = DispatchGroup()
        var migrationSuccess = true

        for (key, type) in keysAndTypes {
            group.enter()
            if type as? [RSSFeed].Type != nil {
                cloudStorage.load(forKey: key) {
                    (result: Result<[RSSFeed], Error>) in
                    switch result {
                    case .success(let feeds):
                        if let encodedData = try? JSONEncoder().encode(feeds) {
                            ud.set(encodedData, forKey: key)
                        } else {
                            print("Error encoding data for key \(key)")
                            migrationSuccess = false
                        }
                    case .failure(let error):
                        print("Error loading \(key) from CloudKit: \(error)")
                        migrationSuccess = false
                    }
                    group.leave()
                }
            } else if type as? [String].Type != nil {
                cloudStorage.load(forKey: key) {
                    (result: Result<[String], Error>) in
                    switch result {
                    case .success(let items):
                        if let encodedData = try? JSONEncoder().encode(items) {
                            ud.set(encodedData, forKey: key)
                        } else {
                            print("Error encoding data for key \(key)")
                            migrationSuccess = false
                        }
                    case .failure(let error):
                        print("Error loading \(key) from CloudKit: \(error)")
                        migrationSuccess = false
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(migrationSuccess)
        }
    }

    // MARK: - OPML Import/Export and Reset Actions

    @objc private func importOPML() {
        let documentPicker = UIDocumentPickerViewController(
            documentTypes: [
                "org.opml.opml", "public.xml", "public.data", "public.content",
                "public.plain-text", ".opml", "com.apple.opml",
            ],
            in: .import
        )
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
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
            // Load existing feeds asynchronously
            loadFeeds { existingFeeds in
                var updatedFeeds = existingFeeds
                updatedFeeds.append(contentsOf: importedFeeds)
                let uniqueFeeds = Array(Set(updatedFeeds))

                // Save the merged feeds using the StorageManager
                StorageManager.shared.save(uniqueFeeds, forKey: "rssFeeds") {
                    error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.showError(
                                "Failed to save imported feeds: \(error.localizedDescription)"
                            )
                        } else {
                            let alert = UIAlertController(
                                title: "Import Successful",
                                message: "Feeds have been imported",
                                preferredStyle: .alert)
                            alert.addAction(
                                UIAlertAction(title: "OK", style: .default))
                            self.present(alert, animated: true)
                            NotificationCenter.default.post(
                                name: .feedsUpdated, object: nil)
                        }
                    }
                }
            }
        } else {
            showError("Invalid OPML format")
        }
    }

    @objc private func exportOPML() {
        // Load feeds via StorageManager instead of directly from UserDefaults.
        StorageManager.shared.load(forKey: "rssFeeds") {
            (result: Result<[RSSFeed], Error>) in
            DispatchQueue.main.async {
                var feeds: [RSSFeed] = []
                switch result {
                case .success(let loadedFeeds):
                    feeds = loadedFeeds
                case .failure(let error):
                    self.showError(
                        "Failed to load feeds for export: \(error.localizedDescription)"
                    )
                    return
                }

                // Create the OPML string.
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
                    try opml.write(
                        to: fileURL, atomically: true, encoding: .utf8)
                    let activityVC = UIActivityViewController(
                        activityItems: [fileURL], applicationActivities: nil)
                    self.present(activityVC, animated: true)
                } catch {
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    /// Asynchronously loads the RSS feeds using StorageManager.
    private func loadFeeds(completion: @escaping ([RSSFeed]) -> Void) {
        StorageManager.shared.load(forKey: "rssFeeds") {
            (result: Result<[RSSFeed], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let feeds):
                    completion(feeds)
                case .failure(let error):
                    print("Error loading feeds: \(error.localizedDescription)")
                    completion([])
                }
            }
        }
    }

    @objc private func resetReadItems() {
        let alert = UIAlertController(
            title: "Reset Read Items",
            message:
                "Are you sure you want to reset all read items? This cannot be undone.",
            preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Reset", style: .destructive) { _ in
                // Reset local storage.
                UserDefaults.standard.removeObject(forKey: "readItems")

                // If iCloud syncing is enabled, reset iCloud storage as well.
                if UserDefaults.standard.bool(forKey: "useICloud") {
                    CloudKitStorage().save([] as [String], forKey: "readItems")
                    { error in
                        if let error = error {
                            print(
                                "Error resetting read items in iCloud: \(error.localizedDescription)"
                            )
                        } else {
                            print("Successfully reset read items in iCloud.")
                        }
                    }
                }

                // Notify other parts of the app.
                NotificationCenter.default.post(
                    name: Notification.Name("readItemsReset"), object: nil)
            })

        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
