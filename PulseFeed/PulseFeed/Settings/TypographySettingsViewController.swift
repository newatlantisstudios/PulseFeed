import UIKit

class TypographySettingsViewController: UIViewController {
    
    // MARK: - Properties
    
    private var tableView: UITableView!
    private var settings = TypographySettings.loadFromUserDefaults()
    private var previewText: UITextView!
    private var previewCard: UIView!
    
    // MARK: - Sections and Items
    
    enum Section: Int, CaseIterable {
        case preview
        case fontFamily
        case fontSize
        case lineHeight
        
        var title: String {
            switch self {
            case .preview: return "Preview"
            case .fontFamily: return "Font Family"
            case .fontSize: return "Font Size"
            case .lineHeight: return "Line Height"
            }
        }
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Typography Settings"
        view.backgroundColor = .systemBackground
        
        setupTableView()
        setupPreviewCard()
        updatePreviewText()
    }
    
    // MARK: - Setup UI
    
    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(SliderTableViewCell.self, forCellReuseIdentifier: "sliderCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupPreviewCard() {
        // Will be created in the table view
    }
    
    private func updatePreviewText() {
        guard previewText != nil else { return }
        
        // Update the preview text with current settings
        previewText.font = settings.fontFamily.font(withSize: settings.fontSize)
        
        // Apply line height
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = (settings.lineHeight - 1.0) * settings.fontSize
        
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: settings.fontFamily.font(withSize: settings.fontSize)
        ]
        
        let attributedText = NSAttributedString(string: previewText.text, attributes: attributes)
        previewText.attributedText = attributedText
    }
    
    // MARK: - Settings Actions
    
    private func selectFontFamily(_ fontFamily: TypographySettings.FontFamily) {
        settings.fontFamily = fontFamily
        settings.saveToUserDefaults()
        updatePreviewText()
        tableView.reloadSections(IndexSet(integer: Section.fontFamily.rawValue), with: .automatic)
    }
    
    private func updateFontSize(_ size: Float) {
        settings.fontSize = CGFloat(size)
        settings.saveToUserDefaults()
        updatePreviewText()
    }
    
    private func updateLineHeight(_ height: Float) {
        // Convert from 10-30 range to 1.0-3.0 range
        settings.lineHeight = CGFloat(height) / 10.0
        settings.saveToUserDefaults()
        updatePreviewText()
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension TypographySettingsViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        
        switch section {
        case .preview:
            return 1
        case .fontFamily:
            return TypographySettings.FontFamily.allCases.count
        case .fontSize, .lineHeight:
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .preview:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            
            // Remove any previous preview card
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            
            // Create preview card
            previewCard = UIView()
            previewCard.translatesAutoresizingMaskIntoConstraints = false
            previewCard.backgroundColor = .systemBackground
            previewCard.layer.cornerRadius = 8
            previewCard.layer.borderWidth = 1
            previewCard.layer.borderColor = UIColor.systemGray4.cgColor
            
            // Create preview text view
            previewText = UITextView()
            previewText.translatesAutoresizingMaskIntoConstraints = false
            previewText.isEditable = false
            previewText.isScrollEnabled = false
            previewText.backgroundColor = .clear
            previewText.text = """
            Typography is the art and technique of arranging type to make written language legible, readable, and appealing when displayed.
            
            Good typography enhances readability and the overall reading experience.
            """
            
            previewCard.addSubview(previewText)
            cell.contentView.addSubview(previewCard)
            
            NSLayoutConstraint.activate([
                previewCard.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                previewCard.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                previewCard.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                previewCard.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                previewCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
                
                previewText.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 12),
                previewText.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
                previewText.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
                previewText.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -12)
            ])
            
            updatePreviewText()
            
            cell.selectionStyle = .none
            return cell
            
        case .fontFamily:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            
            let fontFamily = TypographySettings.FontFamily.allCases[indexPath.row]
            
            var content = cell.defaultContentConfiguration()
            content.text = fontFamily.displayName
            
            // Use the actual font for the font name
            content.textProperties.font = fontFamily.font(withSize: 17)
            
            // Add checkmark for selected font
            if fontFamily == settings.fontFamily {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            
            cell.contentConfiguration = content
            return cell
            
        case .fontSize:
            let cell = tableView.dequeueReusableCell(withIdentifier: "sliderCell", for: indexPath) as! SliderTableViewCell
            cell.configure(with: "Font Size", value: Float(settings.fontSize), range: 12...32)
            cell.sliderValueChanged = { [weak self] value in
                self?.updateFontSize(value)
            }
            return cell
            
        case .lineHeight:
            let cell = tableView.dequeueReusableCell(withIdentifier: "sliderCell", for: indexPath) as! SliderTableViewCell
            
            // Display line height in 10-30 range but store as 1.0-3.0
            let displayValue = Float(settings.lineHeight * 10)
            cell.configure(with: "Line Spacing", value: displayValue, range: 10...30)
            cell.sliderValueChanged = { [weak self] value in
                self?.updateLineHeight(value)
            }
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        return section.title
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == Section.preview.rawValue {
            return 200 // Fixed height for preview
        }
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        if section == .fontFamily {
            let selectedFontFamily = TypographySettings.FontFamily.allCases[indexPath.row]
            selectFontFamily(selectedFontFamily)
        }
    }
}