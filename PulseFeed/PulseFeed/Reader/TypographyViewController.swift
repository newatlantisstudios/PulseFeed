import UIKit

class TypographyViewController: UIViewController {
    
    // MARK: - Properties
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var typographySettings: TypographySettings
    
    // Table sections
    private enum Section: Int, CaseIterable {
        case preview
        case fontFamily
        case fontSize
        case lineSpacing
    }
    
    weak var delegate: TypographyChangeDelegate?
    
    // MARK: - Initialization
    
    init() {
        self.typographySettings = TypographySettings.loadFromUserDefaults()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupTableView()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        title = "Typography"
        view.backgroundColor = .systemBackground
        
        // Setup navigation bar
        navigationItem.largeTitleDisplayMode = .never
        
        // Add Done button
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissView))
        navigationItem.leftBarButtonItem = doneButton
        
        // Add reset button
        let resetButton = UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(resetToDefaults))
        navigationItem.rightBarButtonItem = resetButton
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(FontSizeSliderCell.self, forCellReuseIdentifier: "SliderCell")
        tableView.register(LineSpacingSliderCell.self, forCellReuseIdentifier: "LineSpacingCell")
        tableView.register(TypographyPreviewCell.self, forCellReuseIdentifier: "PreviewCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func resetToDefaults() {
        let alertController = UIAlertController(
            title: "Reset Typography Settings",
            message: "Are you sure you want to reset all typography settings to defaults?",
            preferredStyle: .alert
        )
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        let resetAction = UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            // Reset to default settings
            self.typographySettings = TypographySettings.defaultSettings()
            self.typographySettings.saveToUserDefaults()
            
            // Reload table to update UI
            self.tableView.reloadData()
            
            // Notify delegate
            self.delegate?.typographyDidChange()
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(resetAction)
        
        present(alertController, animated: true)
    }
    
    private func updateFontSize(_ size: CGFloat) {
        typographySettings.fontSize = size
        typographySettings.saveToUserDefaults()
        
        // Reload the preview cell
        if let previewIndexPath = IndexPath(row: 0, section: Section.preview.rawValue) as IndexPath? {
            tableView.reloadRows(at: [previewIndexPath], with: .none)
        }
        
        // Notify delegate
        delegate?.typographyDidChange()
    }
    
    private func updateLineSpacing(_ spacing: CGFloat) {
        typographySettings.lineHeight = spacing
        typographySettings.saveToUserDefaults()
        
        // Reload the preview cell
        if let previewIndexPath = IndexPath(row: 0, section: Section.preview.rawValue) as IndexPath? {
            tableView.reloadRows(at: [previewIndexPath], with: .none)
        }
        
        // Notify delegate
        delegate?.typographyDidChange()
    }
    
    private func selectFontFamily(_ fontFamily: TypographySettings.FontFamily) {
        typographySettings.fontFamily = fontFamily
        typographySettings.saveToUserDefaults()
        
        // Reload the font family section
        tableView.reloadSections(IndexSet(integer: Section.fontFamily.rawValue), with: .none)
        
        // Reload the preview cell
        if let previewIndexPath = IndexPath(row: 0, section: Section.preview.rawValue) as IndexPath? {
            tableView.reloadRows(at: [previewIndexPath], with: .none)
        }
        
        // Notify delegate
        delegate?.typographyDidChange()
    }
}

// MARK: - UITableViewDataSource

extension TypographyViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let tableSection = Section(rawValue: section) else { return 0 }
        
        switch tableSection {
        case .preview:
            return 1
        case .fontFamily:
            return TypographySettings.FontFamily.allCases.count
        case .fontSize, .lineSpacing:
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .preview:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PreviewCell", for: indexPath) as! TypographyPreviewCell
            cell.configure(with: typographySettings)
            return cell
            
        case .fontFamily:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            
            let fontFamily = TypographySettings.FontFamily.allCases[indexPath.row]
            cell.textLabel?.text = fontFamily.displayName
            cell.textLabel?.font = fontFamily.font(withSize: 17)
            
            // Show checkmark for selected font family
            cell.accessoryType = (fontFamily == typographySettings.fontFamily) ? .checkmark : .none
            
            return cell
            
        case .fontSize:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as! FontSizeSliderCell
            cell.delegate = self
            cell.configure(with: typographySettings.fontSize)
            return cell
            
        case .lineSpacing:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LineSpacingCell", for: indexPath) as! LineSpacingSliderCell
            cell.delegate = self
            cell.configure(with: typographySettings.lineHeight)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let tableSection = Section(rawValue: section) else { return nil }
        
        switch tableSection {
        case .preview:
            return "Preview"
        case .fontFamily:
            return "Font Family"
        case .fontSize:
            return "Font Size"
        case .lineSpacing:
            return "Line Spacing"
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let tableSection = Section(rawValue: section) else { return nil }
        
        switch tableSection {
        case .preview:
            return nil
        case .fontFamily:
            return "Select a font family for reading articles"
        case .fontSize:
            return "Adjust the size of the text (12-32pt)"
        case .lineSpacing:
            return "Adjust the spacing between lines (1.0-2.0)"
        }
    }
}

// MARK: - UITableViewDelegate

extension TypographyViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section), section == .fontFamily else { return }
        
        // Handle font family selection
        let selectedFontFamily = TypographySettings.FontFamily.allCases[indexPath.row]
        selectFontFamily(selectedFontFamily)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 44 }
        
        switch section {
        case .preview:
            return 150
        case .fontSize, .lineSpacing:
            return 80
        default:
            return 44
        }
    }
}

// MARK: - FontSizeSliderDelegate

extension TypographyViewController: FontSizeSliderDelegate {
    func fontSizeDidChange(_ size: CGFloat) {
        updateFontSize(size)
    }
}

// MARK: - LineSpacingSliderDelegate

extension TypographyViewController: LineSpacingSliderDelegate {
    func lineSpacingDidChange(_ spacing: CGFloat) {
        updateLineSpacing(spacing)
    }
}

// MARK: - Font Size Slider Cell

class FontSizeSliderCell: UITableViewCell {
    
    // MARK: - Properties
    
    private let slider = UISlider()
    private let valueLabel = UILabel()
    private let minLabel = UILabel()
    private let maxLabel = UILabel()
    
    weak var delegate: FontSizeSliderDelegate?
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        selectionStyle = .none
        
        // Setup slider
        slider.minimumValue = 12
        slider.maximumValue = 32
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup value label
        valueLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup min/max labels
        minLabel.text = "A"
        minLabel.font = UIFont.systemFont(ofSize: 12)
        minLabel.textColor = .secondaryLabel
        minLabel.translatesAutoresizingMaskIntoConstraints = false
        
        maxLabel.text = "A"
        maxLabel.font = UIFont.systemFont(ofSize: 24)
        maxLabel.textColor = .secondaryLabel
        maxLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        contentView.addSubview(minLabel)
        contentView.addSubview(slider)
        contentView.addSubview(maxLabel)
        contentView.addSubview(valueLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            minLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            minLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            
            slider.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: minLabel.trailingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: maxLabel.leadingAnchor, constant: -12),
            
            maxLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            maxLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            
            valueLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 4),
            valueLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with fontSize: CGFloat) {
        slider.value = Float(fontSize)
        updateValueLabel()
    }
    
    // MARK: - Actions
    
    @objc private func sliderValueChanged() {
        updateValueLabel()
        delegate?.fontSizeDidChange(CGFloat(slider.value))
    }
    
    private func updateValueLabel() {
        valueLabel.text = "\(Int(slider.value))pt"
    }
}

// MARK: - Line Spacing Slider Cell

class LineSpacingSliderCell: UITableViewCell {
    
    // MARK: - Properties
    
    private let slider = UISlider()
    private let valueLabel = UILabel()
    private let minLabel = UILabel()
    private let maxLabel = UILabel()
    
    weak var delegate: LineSpacingSliderDelegate?
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        selectionStyle = .none
        
        // Setup slider
        slider.minimumValue = 1.0
        slider.maximumValue = 2.0
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup value label
        valueLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup min/max labels
        minLabel.text = "Dense"
        minLabel.font = UIFont.systemFont(ofSize: 13)
        minLabel.textColor = .secondaryLabel
        minLabel.translatesAutoresizingMaskIntoConstraints = false
        
        maxLabel.text = "Airy"
        maxLabel.font = UIFont.systemFont(ofSize: 13)
        maxLabel.textColor = .secondaryLabel
        maxLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        contentView.addSubview(minLabel)
        contentView.addSubview(slider)
        contentView.addSubview(maxLabel)
        contentView.addSubview(valueLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            minLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            minLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            
            slider.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: minLabel.trailingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: maxLabel.leadingAnchor, constant: -12),
            
            maxLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            maxLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            
            valueLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 4),
            valueLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with lineHeight: CGFloat) {
        slider.value = Float(lineHeight)
        updateValueLabel()
    }
    
    // MARK: - Actions
    
    @objc private func sliderValueChanged() {
        updateValueLabel()
        delegate?.lineSpacingDidChange(CGFloat(slider.value))
    }
    
    private func updateValueLabel() {
        valueLabel.text = String(format: "%.1fx", slider.value)
    }
}

// MARK: - Typography Preview Cell

class TypographyPreviewCell: UITableViewCell {
    
    // MARK: - Properties
    
    private let previewContainerView = UIView()
    private let titleLabel = UILabel()
    private let bodyTextLabel = UILabel()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        selectionStyle = .none
        
        // Setup preview container
        previewContainerView.layer.cornerRadius = 12
        previewContainerView.layer.borderWidth = 1
        previewContainerView.layer.borderColor = UIColor.separator.cgColor
        previewContainerView.backgroundColor = .systemBackground
        previewContainerView.clipsToBounds = true
        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup title label
        titleLabel.text = "Typography Preview"
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup body text label
        bodyTextLabel.text = "This is a preview of how your articles will look with the selected typography settings. Good typography improves readability and reduces eye strain during extended reading sessions."
        bodyTextLabel.numberOfLines = 0
        bodyTextLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        previewContainerView.addSubview(titleLabel)
        previewContainerView.addSubview(bodyTextLabel)
        contentView.addSubview(previewContainerView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            previewContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            previewContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            previewContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            previewContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            titleLabel.topAnchor.constraint(equalTo: previewContainerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -16),
            
            bodyTextLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            bodyTextLabel.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 16),
            bodyTextLabel.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -16),
            bodyTextLabel.bottomAnchor.constraint(lessThanOrEqualTo: previewContainerView.bottomAnchor, constant: -16)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with settings: TypographySettings) {
        // Apply font family
        titleLabel.font = settings.fontFamily.font(withSize: settings.fontSize + 4, weight: .bold)
        bodyTextLabel.font = settings.fontFamily.font(withSize: settings.fontSize)
        
        // Apply line height
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = (settings.fontSize * settings.lineHeight) - settings.fontSize
        
        let attributes = [NSAttributedString.Key.paragraphStyle: paragraphStyle]
        
        let bodyText = NSMutableAttributedString(string: bodyTextLabel.text ?? "")
        bodyText.addAttributes(attributes, range: NSRange(location: 0, length: bodyText.length))
        bodyTextLabel.attributedText = bodyText
    }
}

// MARK: - Protocols

protocol FontSizeSliderDelegate: AnyObject {
    func fontSizeDidChange(_ size: CGFloat)
}

protocol LineSpacingSliderDelegate: AnyObject {
    func lineSpacingDidChange(_ spacing: CGFloat)
}

protocol TypographyChangeDelegate: AnyObject {
    func typographyDidChange()
}