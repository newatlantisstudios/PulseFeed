import UIKit

class ThemeSelectionViewController: UIViewController {
    
    // MARK: - Properties
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let themeManager = ArticleThemeManager.shared
    
    private var themes: [ArticleTheme] {
        return themeManager.themes
    }
    
    private var selectedThemeName: String {
        return themeManager.selectedTheme.name
    }
    
    weak var delegate: ThemeSelectionDelegate?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupTableView()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        title = "Theme"
        view.backgroundColor = .systemBackground
        
        // Setup navigation bar
        navigationItem.largeTitleDisplayMode = .never
        
        // Add Done button
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissView))
        navigationItem.leftBarButtonItem = doneButton
        
        // Add Create New Theme button
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createNewTheme))
        navigationItem.rightBarButtonItem = addButton
    }
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ThemeSelectionCell.self, forCellReuseIdentifier: "ThemeSelectionCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func createNewTheme() {
        let alertController = UIAlertController(title: "New Theme", message: "Enter a name for your custom theme", preferredStyle: .alert)
        
        alertController.addTextField { textField in
            textField.placeholder = "Theme Name"
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self, let nameTextField = alertController.textFields?.first, let themeName = nameTextField.text, !themeName.isEmpty else { return }
            
            // Create a new theme based on the current selected theme
            let currentTheme = self.themeManager.selectedTheme
            let newTheme = ArticleTheme(
                name: themeName,
                textColor: currentTheme.textColor,
                backgroundColor: currentTheme.backgroundColor,
                accentColor: currentTheme.accentColor,
                isCustom: true
            )
            
            if self.themeManager.addCustomTheme(newTheme) {
                self.tableView.reloadData()
                
                // Navigate to theme editor
                self.editTheme(newTheme)
            } else {
                self.showAlert(title: "Error", message: "A theme with this name already exists.")
            }
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(createAction)
        
        present(alertController, animated: true)
    }
    
    private func editTheme(_ theme: ArticleTheme) {
        let themeEditorVC = ThemeEditorViewController(theme: theme)
        themeEditorVC.delegate = self
        navigationController?.pushViewController(themeEditorVC, animated: true)
    }
    
    private func deleteTheme(at indexPath: IndexPath) {
        let theme = themes[indexPath.row]
        
        // Only allow deleting custom themes
        guard theme.isCustom else { return }
        
        let alertController = UIAlertController(title: "Delete Theme", message: "Are you sure you want to delete the theme '\(theme.name)'?", preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            if self.themeManager.deleteCustomTheme(named: theme.name) {
                self.tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(deleteAction)
        
        present(alertController, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default)
        alertController.addAction(okAction)
        present(alertController, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ThemeSelectionViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return themes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ThemeSelectionCell", for: indexPath) as! ThemeSelectionCell
        
        let theme = themes[indexPath.row]
        cell.configure(with: theme, isSelected: theme.name == selectedThemeName)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Select Theme"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "Choose a theme for your reading experience. Custom themes can be edited or deleted."
    }
}

// MARK: - UITableViewDelegate

extension ThemeSelectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let theme = themes[indexPath.row]
        
        // Apply the selected theme
        themeManager.selectTheme(named: theme.name)
        
        // Update cell selection state
        tableView.reloadData()
        
        // Notify delegate
        delegate?.themeDidChange()
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let theme = themes[indexPath.row]
        
        // Only allow editing/deleting custom themes
        guard theme.isCustom else { return nil }
        
        // Edit action
        let editAction = UIContextualAction(style: .normal, title: "Edit") { [weak self] (_, _, completion) in
            guard let self = self else { return }
            self.editTheme(theme)
            completion(true)
        }
        editAction.backgroundColor = .systemBlue
        
        // Delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (_, _, completion) in
            guard let self = self else { return }
            self.deleteTheme(at: indexPath)
            completion(true)
        }
        
        return UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// MARK: - ThemeEditorDelegate

extension ThemeSelectionViewController: ThemeEditorDelegate {
    func themeDidUpdate() {
        tableView.reloadData()
        delegate?.themeDidChange()
    }
}

// MARK: - Theme Selection Cell

class ThemeSelectionCell: UITableViewCell {
    
    // MARK: - Properties
    
    private let themeNameLabel = UILabel()
    private let previewView = UIView()
    private let textPreviewLabel = UILabel()
    
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
        // Setup theme name label
        themeNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        themeNameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup preview view
        previewView.layer.cornerRadius = 8
        previewView.clipsToBounds = true
        previewView.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup text preview label
        textPreviewLabel.text = "Aa"
        textPreviewLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        textPreviewLabel.textAlignment = .center
        textPreviewLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        previewView.addSubview(textPreviewLabel)
        contentView.addSubview(themeNameLabel)
        contentView.addSubview(previewView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            themeNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            themeNameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            previewView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 48),
            previewView.heightAnchor.constraint(equalToConstant: 48),
            
            textPreviewLabel.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            textPreviewLabel.centerYAnchor.constraint(equalTo: previewView.centerYAnchor)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with theme: ArticleTheme, isSelected: Bool) {
        themeNameLabel.text = theme.name
        
        // Setup preview colors
        previewView.backgroundColor = theme.backgroundColorUI
        textPreviewLabel.textColor = theme.textColorUI
        
        // Setup selection state
        accessoryType = isSelected ? .checkmark : .none
    }
}

// MARK: - Protocols

protocol ThemeSelectionDelegate: AnyObject {
    func themeDidChange()
}

protocol ThemeEditorDelegate: AnyObject {
    func themeDidUpdate()
}

// MARK: - Theme Editor View Controller

class ThemeEditorViewController: UIViewController {
    
    // MARK: - Properties
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let themeManager = ArticleThemeManager.shared
    
    private var theme: ArticleTheme
    private var currentTextColor: UIColor
    private var currentBackgroundColor: UIColor
    private var currentAccentColor: UIColor
    
    weak var delegate: ThemeEditorDelegate?
    
    // Table sections
    private enum Section: Int, CaseIterable {
        case preview
        case colors
    }
    
    // Color rows
    private enum ColorRow: Int, CaseIterable {
        case text
        case background
        case accent
    }
    
    // MARK: - Initialization
    
    init(theme: ArticleTheme) {
        self.theme = theme
        self.currentTextColor = theme.textColorUI
        self.currentBackgroundColor = theme.backgroundColorUI
        self.currentAccentColor = theme.accentColorUI
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
        let updatedTheme = ArticleTheme(
            name: theme.name,
            textColor: currentTextColor.hexString,
            backgroundColor: currentBackgroundColor.hexString,
            accentColor: currentAccentColor.hexString,
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
        case .text:
            colorPickerVC.selectedColor = currentTextColor
            colorPickerVC.title = "Text Color"
        case .background:
            colorPickerVC.selectedColor = currentBackgroundColor
            colorPickerVC.title = "Background Color"
        case .accent:
            colorPickerVC.selectedColor = currentAccentColor
            colorPickerVC.title = "Accent Color"
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

extension ThemeEditorViewController: UITableViewDataSource {
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
            let cell = tableView.dequeueReusableCell(withIdentifier: "PreviewCell", for: indexPath) as! ThemePreviewCell
            cell.configure(
                backgroundColor: currentBackgroundColor,
                textColor: currentTextColor,
                accentColor: currentAccentColor
            )
            return cell
            
        case .colors:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ColorCell", for: indexPath)
            
            guard let colorRow = ColorRow(rawValue: indexPath.row) else {
                return cell
            }
            
            // Configure cell based on color row
            switch colorRow {
            case .text:
                cell.textLabel?.text = "Text Color"
                let colorView = createColorPreviewView(color: currentTextColor)
                cell.accessoryView = colorView
            case .background:
                cell.textLabel?.text = "Background Color"
                let colorView = createColorPreviewView(color: currentBackgroundColor)
                cell.accessoryView = colorView
            case .accent:
                cell.textLabel?.text = "Accent Color"
                let colorView = createColorPreviewView(color: currentAccentColor)
                cell.accessoryView = colorView
            }
            
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

extension ThemeEditorViewController: UITableViewDelegate {
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

extension ThemeEditorViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        let selectedColor = viewController.selectedColor
        
        // Get the row being edited from the tag
        if let colorRow = ColorRow(rawValue: viewController.view.tag) {
            switch colorRow {
            case .text:
                currentTextColor = selectedColor
            case .background:
                currentBackgroundColor = selectedColor
            case .accent:
                currentAccentColor = selectedColor
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
                case .text:
                    currentTextColor = color
                case .background:
                    currentBackgroundColor = color
                case .accent:
                    currentAccentColor = color
                }
                
                // Reload only the preview section for better performance
                if let previewIndexPath = IndexPath(row: 0, section: Section.preview.rawValue) as IndexPath? {
                    tableView.reloadRows(at: [previewIndexPath], with: .none)
                }
            }
        }
    }
}

// MARK: - Theme Preview Cell

class ThemePreviewCell: UITableViewCell {
    
    // MARK: - Properties
    
    private let previewContainerView = UIView()
    private let titleLabel = UILabel()
    private let bodyTextLabel = UILabel()
    private let linkTextLabel = UILabel()
    
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
        previewContainerView.clipsToBounds = true
        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup title label
        titleLabel.text = "Theme Preview"
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup body text label
        bodyTextLabel.text = "This is how your article text will appear with this theme. The readability and contrast are important for comfortable reading."
        bodyTextLabel.font = UIFont.systemFont(ofSize: 16)
        bodyTextLabel.numberOfLines = 0
        bodyTextLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup link text label
        linkTextLabel.text = "Links will use the accent color"
        linkTextLabel.font = UIFont.systemFont(ofSize: 16)
        linkTextLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        previewContainerView.addSubview(titleLabel)
        previewContainerView.addSubview(bodyTextLabel)
        previewContainerView.addSubview(linkTextLabel)
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
            
            bodyTextLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            bodyTextLabel.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 16),
            bodyTextLabel.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -16),
            
            linkTextLabel.topAnchor.constraint(equalTo: bodyTextLabel.bottomAnchor, constant: 12),
            linkTextLabel.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 16),
            linkTextLabel.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -16),
            linkTextLabel.bottomAnchor.constraint(lessThanOrEqualTo: previewContainerView.bottomAnchor, constant: -16)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(backgroundColor: UIColor, textColor: UIColor, accentColor: UIColor) {
        previewContainerView.backgroundColor = backgroundColor
        titleLabel.textColor = textColor
        bodyTextLabel.textColor = textColor
        linkTextLabel.textColor = accentColor
    }
}