import UIKit

protocol AppThemeEditorDelegate: AnyObject {
    func themeDidUpdate()
}

class AppThemeEditorViewController: UIViewController {
    
    // MARK: - Properties
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let themeManager = AppThemeManager.shared
    
    private var theme: AppTheme
    private var currentPrimaryColor: UIColor
    private var currentSecondaryColor: UIColor
    private var currentBackgroundColor: UIColor
    private var currentAccentColor: UIColor
    private var currentTextColor: UIColor
    
    weak var delegate: AppThemeEditorDelegate?
    
    // Table sections
    private enum Section: Int, CaseIterable {
        case preview
        case colors
    }
    
    // Color rows
    private enum ColorRow: Int, CaseIterable {
        case primary
        case secondary
        case background
        case accent
        case text
        
        var title: String {
            switch self {
            case .primary: return "Primary Color"
            case .secondary: return "Secondary Color"
            case .background: return "Background Color"
            case .accent: return "Accent Color"
            case .text: return "Text Color"
            }
        }
    }
    
    // MARK: - Initialization
    
    init(theme: AppTheme) {
        self.theme = theme
        self.currentPrimaryColor = theme.primaryColorUI
        self.currentSecondaryColor = theme.secondaryColorUI
        self.currentBackgroundColor = theme.backgroundColorUI
        self.currentAccentColor = theme.accentColorUI
        self.currentTextColor = theme.textColorUI
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
        title = "Edit Theme"
        view.backgroundColor = .systemBackground
        
        // Setup navigation bar
        navigationItem.largeTitleDisplayMode = .never
        
        // Add cancel button
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelEdit))
        navigationItem.leftBarButtonItem = cancelButton
        
        // Add save button
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTheme))
        navigationItem.rightBarButtonItem = saveButton
    }
    
    @objc private func cancelEdit() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ColorCell")
        tableView.register(ThemePreviewCell.self, forCellReuseIdentifier: "PreviewCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func saveTheme() {
        // Update theme with new colors
        let updatedTheme = AppTheme(
            name: theme.name,
            primaryColor: currentPrimaryColor.hexString,
            secondaryColor: currentSecondaryColor.hexString,
            backgroundColor: currentBackgroundColor.hexString,
            accentColor: currentAccentColor.hexString,
            textColor: currentTextColor.hexString,
            isCustom: theme.isCustom,
            supportsDarkMode: theme.supportsDarkMode
        )
        
        if themeManager.updateTheme(updatedTheme) {
            // Notify delegate that theme was updated
            delegate?.themeDidUpdate()
            
            // Navigate back
            navigationController?.popViewController(animated: true)
        } else {
            showAlert(title: "Error", message: "Failed to update theme.")
        }
    }
    
    private func showColorPicker(for row: ColorRow) {
        let colorPickerVC = UIColorPickerViewController()
        colorPickerVC.delegate = self
        
        switch row {
        case .primary:
            colorPickerVC.selectedColor = currentPrimaryColor
            colorPickerVC.title = "Primary Color"
        case .secondary:
            colorPickerVC.selectedColor = currentSecondaryColor
            colorPickerVC.title = "Secondary Color"
        case .background:
            colorPickerVC.selectedColor = currentBackgroundColor
            colorPickerVC.title = "Background Color"
        case .accent:
            colorPickerVC.selectedColor = currentAccentColor
            colorPickerVC.title = "Accent Color"
        case .text:
            colorPickerVC.selectedColor = currentTextColor
            colorPickerVC.title = "Text Color"
        }
        
        // Store the row being edited
        colorPickerVC.view.tag = row.rawValue
        
        present(colorPickerVC, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default)
        alertController.addAction(okAction)
        present(alertController, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension AppThemeEditorViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let tableSection = Section(rawValue: section) else { return 0 }
        
        switch tableSection {
        case .preview:
            return 1
        case .colors:
            return ColorRow.allCases.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .preview:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PreviewCell", for: indexPath)
            configurePreviewCell(
                cell,
                primaryColor: currentPrimaryColor,
                secondaryColor: currentSecondaryColor,
                backgroundColor: currentBackgroundColor,
                accentColor: currentAccentColor,
                textColor: currentTextColor
            )
            return cell
            
        case .colors:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ColorCell", for: indexPath)
            
            guard let colorRow = ColorRow(rawValue: indexPath.row) else {
                return cell
            }
            
            // Configure cell based on color row
            var content = cell.defaultContentConfiguration()
            content.text = colorRow.title
            cell.contentConfiguration = content
            
            // Add color preview
            let color: UIColor
            switch colorRow {
            case .primary:
                color = currentPrimaryColor
            case .secondary:
                color = currentSecondaryColor
            case .background:
                color = currentBackgroundColor
            case .accent:
                color = currentAccentColor
            case .text:
                color = currentTextColor
            }
            
            let colorView = createColorPreviewView(color: color)
            cell.accessoryView = colorView
            cell.accessoryType = .disclosureIndicator
            
            return cell
        }
    }
    
    private func createColorPreviewView(color: UIColor) -> UIView {
        let colorView = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        colorView.backgroundColor = color
        colorView.layer.cornerRadius = 14
        colorView.layer.borderWidth = 1
        colorView.layer.borderColor = UIColor.separator.cgColor
        return colorView
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let tableSection = Section(rawValue: section) else { return nil }
        
        switch tableSection {
        case .preview:
            return "Preview"
        case .colors:
            return "Theme Colors"
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let tableSection = Section(rawValue: section) else { return nil }
        
        switch tableSection {
        case .preview:
            return nil
        case .colors:
            return "Tap on any color to customize it."
        }
    }
}

// MARK: - UITableViewDelegate

extension AppThemeEditorViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section), section == .colors else { return }
        
        if let colorRow = ColorRow(rawValue: indexPath.row) {
            showColorPicker(for: colorRow)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 44 }
        
        if section == .preview {
            return 200
        }
        
        return 44
    }
}

// MARK: - UIColorPickerViewControllerDelegate

extension AppThemeEditorViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        let selectedColor = viewController.selectedColor
        
        // Get the row being edited from the tag
        if let colorRow = ColorRow(rawValue: viewController.view.tag) {
            switch colorRow {
            case .primary:
                currentPrimaryColor = selectedColor
            case .secondary:
                currentSecondaryColor = selectedColor
            case .background:
                currentBackgroundColor = selectedColor
            case .accent:
                currentAccentColor = selectedColor
            case .text:
                currentTextColor = selectedColor
            }
            
            // Reload table to update preview
            tableView.reloadData()
        }
    }
    
    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        // Only update preview during continuous selection
        if continuously {
            // Get the row being edited from the tag
            if let colorRow = ColorRow(rawValue: viewController.view.tag) {
                switch colorRow {
                case .primary:
                    currentPrimaryColor = color
                case .secondary:
                    currentSecondaryColor = color
                case .background:
                    currentBackgroundColor = color
                case .accent:
                    currentAccentColor = color
                case .text:
                    currentTextColor = color
                }
                
                // Reload only the preview section for better performance
                if let previewIndexPath = IndexPath(row: 0, section: Section.preview.rawValue) as IndexPath? {
                    tableView.reloadRows(at: [previewIndexPath], with: .none)
                }
            }
        }
    }
}

// MARK: - ThemePreviewCell Configuration Extension

// Custom extension to configure the theme preview cell
private extension AppThemeEditorViewController {
    // Helper method to configure a preview cell
    func configurePreviewCell(_ cell: UITableViewCell, primaryColor: UIColor, secondaryColor: UIColor, backgroundColor: UIColor, accentColor: UIColor, textColor: UIColor) {
        cell.contentView.backgroundColor = backgroundColor
        
        // Find the preview container view and other views by tag or looking through the subviews
        for view in cell.contentView.subviews {
            if let containerView = view as? UIView, containerView.tag == 100 {
                containerView.backgroundColor = backgroundColor
                
                // Configure subviews
                for subview in containerView.subviews {
                    if let headerView = subview as? UIView, headerView.tag == 101 {
                        headerView.backgroundColor = primaryColor
                    } else if let titleLabel = subview as? UILabel, titleLabel.tag == 102 {
                        titleLabel.textColor = textColor
                    } else if let bodyLabel = subview as? UILabel, bodyLabel.tag == 103 {
                        bodyLabel.textColor = textColor
                    } else if let linkLabel = subview as? UILabel, linkLabel.tag == 104 {
                        linkLabel.textColor = accentColor
                    } else if let buttonView = subview as? UIView, buttonView.tag == 105 {
                        buttonView.backgroundColor = accentColor
                    }
                }
            }
        }
        // Configuration already done above
    }
}