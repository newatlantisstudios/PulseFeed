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

// MARK: - Setting Models

enum SettingSectionType {
    case general
    case reader
    case feeds
    case filters
    case dataManagement
    case advanced
    case support
    
    var title: String {
        switch self {
        case .general: return "General"
        case .reader: return "Reader"
        case .feeds: return "RSS Feeds"
        case .filters: return "Content Filters"
        case .dataManagement: return "Data Management"
        case .advanced: return "Advanced"
        case .support: return "Support"
        }
    }
}

enum SettingItemType {
    case toggle(title: String, isOn: Bool, action: ((Bool) -> Void))
    case slider(title: String, value: Float, range: ClosedRange<Float>, action: ((Float) -> Void))
    case button(title: String, action: (() -> Void), style: UIButton.Configuration)
    case info(title: String, detail: String)
    case navigation(title: String, action: (() -> Void), icon: UIImage?)
}

struct SettingSection {
    let type: SettingSectionType
    var items: [SettingItemType]
}

// MARK: - Custom TableView Cells

class SwitchTableViewCell: UITableViewCell {
    static let identifier = "SwitchTableViewCell"
    
    private let iconContainer: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.layer.masksToBounds = true
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let label: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        return label
    }()
    
    private let switchControl: UISwitch = {
        let switchControl = UISwitch()
        return switchControl
    }()
    
    var switchToggleHandler: ((Bool) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(label)
        contentView.addSubview(switchControl)
        contentView.addSubview(iconContainer)
        iconContainer.addSubview(iconImageView)
        
        switchControl.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        
        contentView.clipsToBounds = true
        accessoryType = .none
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func switchChanged(_ sender: UISwitch) {
        switchToggleHandler?(sender.isOn)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let size: CGFloat = contentView.frame.size.height - 12
        
        // Layout for icon if present
        if !iconContainer.isHidden {
            iconContainer.frame = CGRect(
                x: 15, 
                y: 6,
                width: size, 
                height: size
            )
            
            let imageSize: CGFloat = size/1.5
            iconImageView.frame = CGRect(
                x: (size - imageSize)/2,
                y: (size - imageSize)/2,
                width: imageSize,
                height: imageSize
            )
            
            label.frame = CGRect(
                x: 25 + iconContainer.frame.size.width,
                y: 0,
                width: contentView.frame.size.width - 20 - iconContainer.frame.size.width - switchControl.frame.size.width,
                height: contentView.frame.size.height
            )
        } else {
            label.frame = CGRect(
                x: 15,
                y: 0,
                width: contentView.frame.size.width - 20 - switchControl.frame.size.width,
                height: contentView.frame.size.height
            )
        }
        
        switchControl.sizeToFit()
        switchControl.frame = CGRect(
            x: contentView.frame.size.width - switchControl.frame.size.width - 15,
            y: (contentView.frame.size.height - switchControl.frame.size.height) / 2,
            width: switchControl.frame.size.width,
            height: switchControl.frame.size.height
        )
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        iconContainer.backgroundColor = nil
        iconImageView.image = nil
        label.text = nil
        switchControl.isOn = false
        iconContainer.isHidden = true
    }
    
    public func configure(with title: String, isOn: Bool, iconName: String? = nil, iconBgColor: UIColor? = nil) {
        label.text = title
        switchControl.isOn = isOn
        
        if let iconName = iconName, let image = UIImage(systemName: iconName) {
            iconContainer.isHidden = false
            iconContainer.backgroundColor = iconBgColor
            iconImageView.image = image
        } else {
            iconContainer.isHidden = true
        }
    }
}

class SliderTableViewCell: UITableViewCell {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        return label
    }()
    
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .right
        return label
    }()
    
    private let slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = .systemBlue
        
        if let thumbImage = UIImage(systemName: "circle.fill") {
            let tintedThumb = thumbImage.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            slider.setThumbImage(tintedThumb, for: .normal)
            slider.setThumbImage(tintedThumb, for: .highlighted)
        }
        
        return slider
    }()
    
    var sliderValueChanged: ((Float) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)
        contentView.addSubview(slider)
        
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -8),
            
            valueLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLabel.widthAnchor.constraint(equalToConstant: 50),
            
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            slider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func sliderChanged(_ sender: UISlider) {
        valueLabel.text = "\(Int(sender.value))"
        sliderValueChanged?(sender.value)
    }
    
    public func configure(with title: String, value: Float, range: ClosedRange<Float>) {
        titleLabel.text = title
        valueLabel.text = "\(Int(value))"
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.value = value
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        valueLabel.text = nil
        slider.value = 0
    }
}

class ButtonTableViewCell: UITableViewCell {
    private let customButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    var buttonTapHandler: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        contentView.addSubview(customButton)
        customButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            customButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            customButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            customButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            customButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            customButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func buttonTapped() {
        buttonTapHandler?()
    }
    
    public func configure(with configuration: UIButton.Configuration, action: @escaping () -> Void) {
        customButton.configuration = configuration
        buttonTapHandler = action
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        var emptyConfig = UIButton.Configuration.filled()
        emptyConfig.title = nil
        customButton.configuration = emptyConfig
        buttonTapHandler = nil
    }
}

class SettingsViewController: UIViewController, UIDocumentPickerDelegate {
    
    // MARK: - Properties
    
    private var tableView: UITableView!
    private var settingSections: [SettingSection] = []
    private var isSimulatingOfflineMode = false
    private var filterKeywords: [String] = []
    
    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        
        setupTableView()
        configureSettings()
    }
    
    // MARK: - Setup UI
    
    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: "switchCell")
        tableView.register(SliderTableViewCell.self, forCellReuseIdentifier: "sliderCell")
        tableView.register(ButtonTableViewCell.self, forCellReuseIdentifier: "buttonCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Configure Settings
    
    private func configureSettings() {
        // General Section
        let generalSection = SettingSection(type: .general, items: [
            .slider(title: "Feed Font Size", 
                   value: UserDefaults.standard.float(forKey: "fontSize") != 0 ? UserDefaults.standard.float(forKey: "fontSize") : 16,
                   range: 12...32,
                   action: { [weak self] value in
                        self?.fontSizeSliderChanged(value)
                   }),
            .toggle(title: "Enhanced Article Style", 
                   isOn: UserDefaults.standard.bool(forKey: "enhancedArticleStyle"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "enhancedArticleStyle")
                        NotificationCenter.default.post(name: Notification.Name("articleStyleChanged"), object: nil)
                   }),
            .toggle(title: "Compact View", 
                   isOn: UserDefaults.standard.bool(forKey: "compactArticleView"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "compactArticleView")
                        NotificationCenter.default.post(name: Notification.Name("articleViewModeChanged"), object: nil)
                   }),
            .toggle(title: "Show Article Images", 
                   isOn: UserDefaults.standard.bool(forKey: "showArticleImages"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "showArticleImages")
                        NotificationCenter.default.post(name: Notification.Name("articleViewModeChanged"), object: nil)
                   }),
            .toggle(title: "Show Read Articles", 
                   isOn: UserDefaults.standard.bool(forKey: "showReadArticles"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "showReadArticles")
                        NotificationCenter.default.post(name: Notification.Name("showReadArticlesChanged"), object: nil)
                   }),
            .navigation(title: "Preview Text Length", 
                   action: { [weak self] in
                       self?.showPreviewLengthOptions()
                   },
                   icon: UIImage(systemName: "text.alignleft")),
            .navigation(title: "Article Sort Order", 
                   action: { [weak self] in
                       self?.showSortOptions()
                   },
                   icon: UIImage(systemName: "arrow.up.arrow.down"))
        ])
        
        // Reader Settings Section
        let readerSection = SettingSection(type: .reader, items: [
            .toggle(title: "Use In-App Reader", 
                   isOn: UserDefaults.standard.bool(forKey: "useInAppReader"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "useInAppReader")
                   }),
            .slider(title: "Reader Font Size", 
                   value: UserDefaults.standard.float(forKey: "readerFontSize") != 0 ? UserDefaults.standard.float(forKey: "readerFontSize") : 18,
                   range: 12...32,
                   action: { [weak self] value in
                        self?.readerFontSizeChanged(value)
                   }),
            .slider(title: "Line Spacing", 
                   value: UserDefaults.standard.float(forKey: "readerLineHeight") != 0 ? UserDefaults.standard.float(forKey: "readerLineHeight") * 10 : 15,
                   range: 10...30,
                   action: { [weak self] value in
                        self?.lineHeightChanged(value)
                   }),
            .toggle(title: "Sepia Mode", 
                   isOn: UserDefaults.standard.bool(forKey: "readerSepiaMode"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "readerSepiaMode")
                        NotificationCenter.default.post(name: Notification.Name("readerAppearanceChanged"), object: nil)
                   }),
            .toggle(title: "Auto-Enable Reader Mode in Safari", 
                   isOn: UserDefaults.standard.bool(forKey: "autoEnableReaderMode"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "autoEnableReaderMode")
                   })
        ])
        
        // Feed Section
        let feedSection = SettingSection(type: .feeds, items: [
            .navigation(title: "Manage RSS Feeds", 
                       action: { [weak self] in
                           self?.openRSSSettings()
                       },
                       icon: UIImage(systemName: "list.bullet")),
            .navigation(title: "Folder Organization", 
                       action: { [weak self] in
                           self?.openFolderManagement()
                       },
                       icon: UIImage(systemName: "folder")),
            .navigation(title: "RSS Feed Loading Speeds", 
                       action: { [weak self] in
                           self?.openRSSLoadingSpeeds()
                       },
                       icon: UIImage(systemName: "speedometer")),
            .slider(title: "Slow Feed Threshold (seconds)", 
                   value: UserDefaults.standard.float(forKey: "feedSlowThreshold") > 0 ? 
                          UserDefaults.standard.float(forKey: "feedSlowThreshold") : 10.0,
                   range: 3...30,
                   action: { [weak self] value in
                        self?.updateSlowFeedThreshold(value)
                   }),
            .button(title: "Import OPML", 
                   action: { [weak self] in
                       self?.importOPML()
                   },
                   style: createButtonConfiguration(title: "Import OPML", color: .systemBlue, symbolName: "square.and.arrow.down")),
            .button(title: "Export OPML", 
                   action: { [weak self] in
                       self?.exportOPML()
                   },
                   style: createButtonConfiguration(title: "Export OPML", color: .systemBlue, symbolName: "square.and.arrow.up"))
        ])
        
        // Content Filters Section
        let filtersSection = SettingSection(type: .filters, items: [
            .toggle(title: "Enable Content Filtering", 
                   isOn: UserDefaults.standard.bool(forKey: "enableContentFiltering"),
                   action: { isOn in
                        UserDefaults.standard.set(isOn, forKey: "enableContentFiltering")
                        NotificationCenter.default.post(name: Notification.Name("contentFilteringChanged"), object: nil)
                   }),
            .navigation(title: "Manage Filter Keywords", 
                   action: { [weak self] in
                       self?.manageFilterKeywords()
                   },
                   icon: UIImage(systemName: "line.horizontal.3.decrease.circle")),
            .info(title: "About Filters", detail: "Articles containing any filter keyword will be automatically hidden")
        ])
        
        // Data Management Section
        var dataItems: [SettingItemType] = [
            .toggle(title: "iCloud Syncing", 
                   isOn: UserDefaults.standard.bool(forKey: "useICloud"),
                   action: { [weak self] isOn in
                       self?.handleStorageToggle(isOn)
                   }),
            .button(title: "Force Sync", 
                   action: { [weak self] in
                       self?.forceSyncData()
                   },
                   style: createButtonConfiguration(title: "Force Sync", color: .systemGreen, symbolName: "arrow.triangle.2.circlepath")),
            .button(title: "Reset Read Items", 
                   action: { [weak self] in
                       self?.resetReadItems()
                   },
                   style: createButtonConfiguration(title: "Reset Read Items", color: .systemRed, symbolName: "trash"))
        ]
        
        #if DEBUG
        // Add a test button for folder cloud syncing in debug builds
        dataItems.append(
            .button(title: "Test Folder Sync", 
                   action: { [weak self] in
                       self?.testFolderCloudSync()
                   },
                   style: createButtonConfiguration(title: "Test Folder Sync", color: .systemPurple, symbolName: "folder.badge.gearshape"))
        )
        #endif
        
        let dataSection = SettingSection(type: .dataManagement, items: dataItems)
        
        // Advanced Section
        let advancedSection = SettingSection(type: .advanced, items: [
            .toggle(title: "Simulate Offline Mode", 
                   isOn: isSimulatingOfflineMode,
                   action: { [weak self] isOn in
                        self?.toggleOfflineMode(isOn)
                   }),
            .button(title: "Clear Article Cache", 
                   action: { [weak self] in
                       self?.clearArticleCache()
                   },
                   style: createButtonConfiguration(title: "Clear Article Cache", color: .systemRed, symbolName: "trash"))
        ])
        
        // Support Section
        let supportSection = SettingSection(type: .support, items: [
            .navigation(title: "Tip Jar", 
                       action: { [weak self] in
                           self?.openTipJar()
                       },
                       icon: UIImage(systemName: "heart.fill"))
        ])
        
        settingSections = [generalSection, readerSection, feedSection, filtersSection, dataSection, advancedSection, supportSection]
        tableView.reloadData()
    }
    
    private func createButtonConfiguration(title: String, color: UIColor, symbolName: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = color
        configuration.buttonSize = .medium
        
        if let image = UIImage(systemName: symbolName) {
            configuration.image = image
            configuration.imagePadding = 8
            configuration.imagePlacement = .leading
        }
        
        return configuration
    }
    
    // MARK: - UITableViewDelegate & DataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return settingSections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settingSections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let settingItem = settingSections[indexPath.section].items[indexPath.row]
        
        switch settingItem {
        case .toggle(let title, let isOn, let action):
            let cell = tableView.dequeueReusableCell(withIdentifier: "switchCell", for: indexPath) as! SwitchTableViewCell
            cell.configure(with: title, isOn: isOn)
            cell.switchToggleHandler = action
            return cell
            
        case .slider(let title, let value, let range, let action):
            let cell = tableView.dequeueReusableCell(withIdentifier: "sliderCell", for: indexPath) as! SliderTableViewCell
            cell.configure(with: title, value: value, range: range)
            cell.sliderValueChanged = action
            return cell
            
        case .button(_, let action, let style):
            let cell = tableView.dequeueReusableCell(withIdentifier: "buttonCell", for: indexPath) as! ButtonTableViewCell
            cell.configure(with: style, action: action)
            return cell
            
        case .navigation(let title, let action, let icon):
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = title
            
            if let icon = icon {
                content.image = icon
                content.imageProperties.tintColor = .systemBlue
            }
            
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
            
        case .info(let title, let detail):
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = title
            content.secondaryText = detail
            cell.contentConfiguration = content
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return settingSections[section].type.title
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let settingItem = settingSections[indexPath.section].items[indexPath.row]
        
        switch settingItem {
        case .navigation(_, let action, _):
            action()
        default:
            break
        }
    }
    
    // MARK: - Actions
    
    private func fontSizeSliderChanged(_ value: Float) {
        let fontSize = CGFloat(value)
        UserDefaults.standard.set(Float(fontSize), forKey: "fontSize")
        NotificationCenter.default.post(
            name: Notification.Name("fontSizeChanged"), object: nil)
    }
    
    private func readerFontSizeChanged(_ value: Float) {
        let fontSize = value
        UserDefaults.standard.set(fontSize, forKey: "readerFontSize")
        NotificationCenter.default.post(
            name: Notification.Name("readerFontSizeChanged"), object: nil)
    }
    
    private func lineHeightChanged(_ value: Float) {
        // We store line height as a decimal (1.0 - 3.0) but display it as 10-30
        let lineHeight = value / 10.0
        UserDefaults.standard.set(lineHeight, forKey: "readerLineHeight")
        NotificationCenter.default.post(
            name: Notification.Name("readerLineHeightChanged"), object: nil)
    }
    
    private func handleStorageToggle(_ isOn: Bool) {
        if isOn {
            showEnableICloudAlert()
        } else {
            showDisableICloudAlert()
        }
    }
    
    private func showEnableICloudAlert() {
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
            UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                // Revert the switch if the user cancels
                self?.updateToggleState(forSection: 2, item: 0, isOn: false)
            }
        )
        alert.addAction(
            UIAlertAction(title: "Enable", style: .default) { [weak self] _ in
                // 1) Set the UserDefaults flag
                UserDefaults.standard.set(true, forKey: "useICloud")
                // 2) Switch StorageManager to CloudKit
                StorageManager.shared.method = .cloudKit
                // 3) Immediately merge/force sync data (pull + push)
                self?.performForceSync()
            }
        )
        present(alert, animated: true)
    }
    
    private func showDisableICloudAlert() {
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
            UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                // Revert the switch if user cancels
                self?.updateToggleState(forSection: 2, item: 0, isOn: true)
            }
        )
        alert.addAction(
            UIAlertAction(title: "Disable", style: .destructive) { _ in
                // 1) Turn off iCloud in UserDefaults
                UserDefaults.standard.set(false, forKey: "useICloud")
                // 2) Switch to local storage only
                StorageManager.shared.method = .userDefaults
            }
        )
        present(alert, animated: true)
    }
    
    private func updateToggleState(forSection section: Int, item: Int, isOn: Bool) {
        if section < settingSections.count {
            let settingSection = settingSections[section]
            if item < settingSection.items.count {
                switch settingSection.items[item] {
                case .toggle(let title, _, let action):
                    settingSections[section].items[item] = .toggle(title: title, isOn: isOn, action: action)
                    tableView.reloadRows(at: [IndexPath(row: item, section: section)], with: .none)
                default:
                    break
                }
            }
        }
    }
    
    @objc private func openRSSSettings() {
        let rssSettingsVC = RSSSettingsViewController()
        navigationController?.pushViewController(rssSettingsVC, animated: true)
    }
    
    @objc private func openFolderManagement() {
        let folderManagementVC = FolderManagementViewController()
        navigationController?.pushViewController(folderManagementVC, animated: true)
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
    
    @objc private func showSortOptions() {
        let alert = UIAlertController(
            title: "Sort Articles",
            message: "Choose the default sort order for articles",
            preferredStyle: .actionSheet)
        
        let isSortedAscending = UserDefaults.standard.bool(forKey: "articleSortAscending")
        
        let newestFirstAction = UIAlertAction(title: "Newest First", style: .default) { _ in
            UserDefaults.standard.set(false, forKey: "articleSortAscending")
            // Notify other parts of the app about the change
            NotificationCenter.default.post(name: Notification.Name("articleSortOrderChanged"), object: nil)
        }
        // Add a checkmark if this is the current sort order
        if !isSortedAscending {
            newestFirstAction.setValue(true, forKey: "checked")
        }
        
        let oldestFirstAction = UIAlertAction(title: "Oldest First", style: .default) { _ in
            UserDefaults.standard.set(true, forKey: "articleSortAscending")
            // Notify other parts of the app about the change
            NotificationCenter.default.post(name: Notification.Name("articleSortOrderChanged"), object: nil)
        }
        // Add a checkmark if this is the current sort order
        if isSortedAscending {
            oldestFirstAction.setValue(true, forKey: "checked")
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(newestFirstAction)
        alert.addAction(oldestFirstAction)
        alert.addAction(cancelAction)
        
        // For iPad compatibility
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    @objc private func showPreviewLengthOptions() {
        let alert = UIAlertController(
            title: "Preview Text Length",
            message: "Choose the length of preview text to display",
            preferredStyle: .actionSheet)
        
        let currentPreviewLength = UserDefaults.standard.string(forKey: "previewTextLength") ?? "none"
        
        let previewOptions = [
            ("None", "none"),
            ("Short", "short"),
            ("Medium", "medium"),
            ("Full", "full")
        ]
        
        for (title, value) in previewOptions {
            let action = UIAlertAction(title: title, style: .default) { _ in
                UserDefaults.standard.set(value, forKey: "previewTextLength")
                // Notify other parts of the app about the change
                NotificationCenter.default.post(name: Notification.Name("articleViewModeChanged"), object: nil)
            }
            
            // Add a checkmark if this is the current option
            if currentPreviewLength == value {
                action.setValue(true, forKey: "checked")
            }
            
            alert.addAction(action)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alert.addAction(cancelAction)
        
        // For iPad compatibility
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    private func updateSlowFeedThreshold(_ value: Float) {
        // Save the threshold in seconds
        let threshold = Double(value)
        UserDefaults.standard.set(threshold, forKey: "feedSlowThreshold")
        
        // If the value has changed, post a notification that might trigger UI updates
        // in the RSS Loading Speeds view
        NotificationCenter.default.post(name: Notification.Name("feedSlowThresholdChanged"), object: nil)
        
        // Show a brief toast/alert for the user
        let thresholdText = String(format: "%.1f", threshold)
        let alert = UIAlertController(
            title: "Threshold Updated",
            message: "Feeds that take longer than \(thresholdText) seconds to load will be considered slow. Feeds that consistently fail or are slow will be skipped.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true) {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                alert.dismiss(animated: true)
            }
        }
    }
    
    #if DEBUG
    private func testFolderCloudSync() {
        // Show a message that we're testing folder syncing
        let loadingAlert = UIAlertController(
            title: "Testing Folder Sync",
            message: "Testing folder syncing with CloudKit...",
            preferredStyle: .alert
        )
        present(loadingAlert, animated: true)
        
        // Run the test
        StorageManager.shared.testFolderSyncingFromCloudKit { success in
            DispatchQueue.main.async {
                // Dismiss the loading alert
                loadingAlert.dismiss(animated: true) {
                    // Show the result
                    let resultAlert = UIAlertController(
                        title: success ? "Folder Sync Test Succeeded" : "Folder Sync Test Failed",
                        message: success ? "The test folder was successfully synced from CloudKit to local storage." : "The folder sync test failed. Check the debug logs for details.",
                        preferredStyle: .alert
                    )
                    resultAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(resultAlert, animated: true)
                }
            }
        }
    }
    #endif
    
    // MARK: - Content Filters
    
    private func manageFilterKeywords() {
        // Load existing filter keywords
        StorageManager.shared.load(forKey: "filterKeywords") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let keywords):
                    self.filterKeywords = keywords
                case .failure:
                    self.filterKeywords = []
                }
                
                self.showFilterKeywordsManagement()
            }
        }
    }
    
    private func showFilterKeywordsManagement() {
        let alertController = UIAlertController(
            title: "Filter Keywords",
            message: "Articles containing any of these keywords will be hidden",
            preferredStyle: .actionSheet
        )
        
        // Display current keywords
        let keywordsMessage = filterKeywords.isEmpty ? 
            "No filter keywords set" : 
            "Current keywords:\n" + filterKeywords.joined(separator: "\n")
        
        let keywordsAlert = UIAlertController(
            title: "Current Filter Keywords",
            message: keywordsMessage,
            preferredStyle: .alert
        )
        keywordsAlert.addAction(UIAlertAction(title: "OK", style: .default))
        
        let viewKeywordsAction = UIAlertAction(title: "View Keywords", style: .default) { [weak self] _ in
            self?.present(keywordsAlert, animated: true)
        }
        
        // Add keyword action
        let addKeywordAction = UIAlertAction(title: "Add Keyword", style: .default) { [weak self] _ in
            self?.showAddKeywordAlert()
        }
        
        // Remove keyword action
        let removeKeywordAction = UIAlertAction(title: "Remove Keyword", style: .destructive) { [weak self] _ in
            self?.showRemoveKeywordAlert()
        }
        
        // Clear all keywords action
        let clearAllAction = UIAlertAction(title: "Clear All Keywords", style: .destructive) { [weak self] _ in
            self?.showClearAllKeywordsAlert()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alertController.addAction(viewKeywordsAction)
        alertController.addAction(addKeywordAction)
        if !filterKeywords.isEmpty {
            alertController.addAction(removeKeywordAction)
            alertController.addAction(clearAllAction)
        }
        alertController.addAction(cancelAction)
        
        // For iPad compatibility
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alertController, animated: true)
    }
    
    private func showAddKeywordAlert() {
        let alertController = UIAlertController(
            title: "Add Filter Keyword",
            message: "Enter a keyword to filter. Articles containing this keyword will be hidden.",
            preferredStyle: .alert
        )
        
        alertController.addTextField { textField in
            textField.placeholder = "Enter keyword"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        let addAction = UIAlertAction(title: "Add", style: .default) { [weak self, weak alertController] _ in
            guard let keyword = alertController?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !keyword.isEmpty,
                  let self = self else { return }
            
            // Add keyword if it doesn't already exist
            if !self.filterKeywords.contains(keyword) {
                self.filterKeywords.append(keyword)
                
                // Save updated keywords
                StorageManager.shared.save(self.filterKeywords, forKey: "filterKeywords") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.showError("Failed to save filter keyword: \(error.localizedDescription)")
                        } else {
                            // Notify that content filtering has changed
                            NotificationCenter.default.post(name: Notification.Name("contentFilteringChanged"), object: nil)
                            
                            // Show success message
                            self.showAddKeywordSuccessAlert(keyword: keyword)
                        }
                    }
                }
            } else {
                // Show error for duplicate keyword
                self.showError("This keyword is already in the filter list")
            }
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(addAction)
        
        present(alertController, animated: true)
    }
    
    private func showAddKeywordSuccessAlert(keyword: String) {
        let alert = UIAlertController(
            title: "Keyword Added",
            message: "The keyword '\(keyword)' has been added to your filter list. Articles containing this keyword will now be hidden.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showRemoveKeywordAlert() {
        guard !filterKeywords.isEmpty else { return }
        
        let alertController = UIAlertController(
            title: "Remove Filter Keyword",
            message: "Select a keyword to remove from your filter list:",
            preferredStyle: .actionSheet
        )
        
        // Add an action for each keyword
        for keyword in filterKeywords {
            let action = UIAlertAction(title: keyword, style: .destructive) { [weak self] _ in
                self?.removeKeyword(keyword)
            }
            alertController.addAction(action)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alertController.addAction(cancelAction)
        
        // For iPad compatibility
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alertController, animated: true)
    }
    
    private func removeKeyword(_ keyword: String) {
        // Remove the keyword from the array
        filterKeywords.removeAll { $0 == keyword }
        
        // Save updated keywords
        StorageManager.shared.save(filterKeywords, forKey: "filterKeywords") { [weak self] error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    self.showError("Failed to remove filter keyword: \(error.localizedDescription)")
                } else {
                    // Notify that content filtering has changed
                    NotificationCenter.default.post(name: Notification.Name("contentFilteringChanged"), object: nil)
                    
                    // Show success message
                    let alert = UIAlertController(
                        title: "Keyword Removed",
                        message: "The keyword '\(keyword)' has been removed from your filter list.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    private func showClearAllKeywordsAlert() {
        let alert = UIAlertController(
            title: "Clear All Keywords",
            message: "Are you sure you want to remove all filter keywords? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            // Clear the keywords array
            self.filterKeywords.removeAll()
            
            // Save empty array
            StorageManager.shared.save(self.filterKeywords, forKey: "filterKeywords") { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.showError("Failed to clear filter keywords: \(error.localizedDescription)")
                    } else {
                        // Notify that content filtering has changed
                        NotificationCenter.default.post(name: Notification.Name("contentFilteringChanged"), object: nil)
                        
                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Keywords Cleared",
                            message: "All filter keywords have been removed.",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(successAlert, animated: true)
                    }
                }
            }
        })
        
        present(alert, animated: true)
    }
    
    // MARK: - Offline Mode & Article Cache
    
    private func toggleOfflineMode(_ isOn: Bool) {
        isSimulatingOfflineMode = isOn
        
        // Update the StorageManager's offline state
        StorageManager.shared.setOfflineState(isOn)
        
        // Show message
        let message = isOn ? 
            "Offline mode is now ON. Only cached articles will be available." : 
            "Offline mode is now OFF. Normal feed functionality restored."
            
        let alert = UIAlertController(
            title: isOn ? "Offline Mode Enabled" : "Offline Mode Disabled",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func clearArticleCache() {
        let alert = UIAlertController(
            title: "Clear Article Cache",
            message: "Are you sure you want to clear all cached articles? This cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear Cache", style: .destructive) { [weak self] _ in
            StorageManager.shared.clearArticleCache { success, error in
                DispatchQueue.main.async {
                    if success {
                        let successAlert = UIAlertController(
                            title: "Cache Cleared",
                            message: "All cached articles have been removed.",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(successAlert, animated: true)
                    } else {
                        let errorMessage = error?.localizedDescription ?? "An unknown error occurred"
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to clear article cache: \(errorMessage)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
                    }
                }
            }
        })
        
        present(alert, animated: true)
    }
}

// MARK: - UITableView Protocol Extensions
extension SettingsViewController: UITableViewDelegate, UITableViewDataSource {
    // These methods are already implemented in the class itself
}