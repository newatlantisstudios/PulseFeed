import UIKit

protocol AppThemeSelectionDelegate: AnyObject {
    func themeDidChange()
}

class AppThemeSelectionViewController: UIViewController {
    
    // MARK: - Properties
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let themeManager = AppThemeManager.shared
    
    private var themes: [AppTheme] {
        return themeManager.themes
    }
    
    private var selectedThemeName: String {
        return themeManager.selectedTheme.name
    }
    
    weak var delegate: AppThemeSelectionDelegate?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupTableView()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        title = "App Theme"
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
        if isModal {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    private var isModal: Bool {
        return presentingViewController != nil
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AppThemeSelectionCell.self, forCellReuseIdentifier: "ThemeSelectionCell")
        
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
            let newTheme = AppTheme(
                name: themeName,
                primaryColor: currentTheme.primaryColor,
                secondaryColor: currentTheme.secondaryColor,
                backgroundColor: currentTheme.backgroundColor,
                accentColor: currentTheme.accentColor,
                textColor: currentTheme.textColor,
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
    
    private func editTheme(_ theme: AppTheme) {
        let themeEditorVC = AppThemeEditorViewController(theme: theme)
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

extension AppThemeSelectionViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return themes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "ThemeSelectionCell", for: indexPath) as? AppThemeSelectionCell else {
            return UITableViewCell()
        }
        
        let theme = themes[indexPath.row]
        cell.configure(with: theme, isSelected: theme.name == selectedThemeName)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Select Theme"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "Choose a theme for your app experience. Custom themes can be edited or deleted."
    }
}

// MARK: - UITableViewDelegate

extension AppThemeSelectionViewController: UITableViewDelegate {
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
        return 80
    }
}

// MARK: - ThemeEditorDelegate

extension AppThemeSelectionViewController: AppThemeEditorDelegate {
    func themeDidUpdate() {
        tableView.reloadData()
        delegate?.themeDidChange()
    }
}

// MARK: - AppThemeSelectionCell

class AppThemeSelectionCell: UITableViewCell {
    
    // MARK: - Properties
    
    private let nameLabel = UILabel()
    private let previewView = UIView()
    private let textPreviewLabel = UILabel()
    private let colorIndicatorsStack = UIStackView()
    
    private let primaryColorIndicator = AppThemeColorIndicatorView(label: "Primary")
    private let secondaryColorIndicator = AppThemeColorIndicatorView(label: "Secondary")
    private let accentColorIndicator = AppThemeColorIndicatorView(label: "Accent")
    
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
        contentView.backgroundColor = .systemBackground
        
        // Configure name label
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure preview view
        previewView.layer.cornerRadius = 6
        previewView.clipsToBounds = true
        previewView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure text preview label
        textPreviewLabel.text = "Aa"
        textPreviewLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        textPreviewLabel.textAlignment = .center
        textPreviewLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure color indicators stack
        colorIndicatorsStack.axis = .horizontal
        colorIndicatorsStack.distribution = .fillEqually
        colorIndicatorsStack.spacing = 8
        colorIndicatorsStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        previewView.addSubview(textPreviewLabel)
        colorIndicatorsStack.addArrangedSubview(primaryColorIndicator)
        colorIndicatorsStack.addArrangedSubview(secondaryColorIndicator)
        colorIndicatorsStack.addArrangedSubview(accentColorIndicator)
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(previewView)
        contentView.addSubview(colorIndicatorsStack)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Name label
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Preview view
            previewView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            previewView.heightAnchor.constraint(equalToConstant: 28),
            previewView.widthAnchor.constraint(equalToConstant: 60),
            
            // Text preview label
            textPreviewLabel.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            textPreviewLabel.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            
            // Color indicators stack
            colorIndicatorsStack.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            colorIndicatorsStack.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 16),
            colorIndicatorsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            colorIndicatorsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with theme: AppTheme, isSelected: Bool) {
        // Configure cell with theme
        nameLabel.text = theme.name
        previewView.backgroundColor = theme.backgroundColorUI
        textPreviewLabel.textColor = theme.textColorUI
        
        // Configure color indicators
        primaryColorIndicator.setColor(theme.primaryColorUI)
        secondaryColorIndicator.setColor(theme.secondaryColorUI)
        accentColorIndicator.setColor(theme.accentColorUI)
        
        // Set selection state
        accessoryType = isSelected ? .checkmark : .none
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryType = .none
    }
}

// MARK: - App Theme Color Indicator View

class AppThemeColorIndicatorView: UIView {
    
    // MARK: - Properties
    
    private let colorCircle = UIView()
    private let nameLabel = UILabel()
    
    // MARK: - Initialization
    
    init(label: String) {
        super.init(frame: .zero)
        nameLabel.text = label
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // Configure color circle
        colorCircle.layer.cornerRadius = 8
        colorCircle.layer.borderWidth = 1
        colorCircle.layer.borderColor = UIColor.systemGray4.cgColor
        colorCircle.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure label
        nameLabel.font = UIFont.systemFont(ofSize: 10)
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        addSubview(colorCircle)
        addSubview(nameLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            colorCircle.topAnchor.constraint(equalTo: topAnchor),
            colorCircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            colorCircle.widthAnchor.constraint(equalToConstant: 16),
            colorCircle.heightAnchor.constraint(equalToConstant: 16),
            
            nameLabel.topAnchor.constraint(equalTo: colorCircle.bottomAnchor, constant: 2),
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Configuration
    
    func setColor(_ color: UIColor) {
        colorCircle.backgroundColor = color
    }
}

// MARK: - Theme Cell Configuration Helper

private extension AppThemeSelectionViewController {
    func configureThemeCell(_ cell: UITableViewCell, theme: AppTheme, isSelected: Bool) {
        if let themeCell = cell as? AppThemeSelectionCell {
            themeCell.configure(with: theme, isSelected: isSelected)
        }
    }
}

