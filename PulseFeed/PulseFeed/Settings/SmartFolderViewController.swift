import UIKit

class SmartFolderViewController: UIViewController {
    
    // MARK: - Properties
    
    private var tableView: UITableView!
    private var smartFolders: [SmartFolder] = []
    private var isEditMode = false
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Smart Folders"
        setupUI()
        loadSmartFolders()
        
        // Set up observers for changes to smart folders
        NotificationCenter.default.addObserver(self, selector: #selector(smartFoldersUpdated), name: Notification.Name("smartFoldersUpdated"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSmartFolders()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SmartFolderCell")
        view.addSubview(tableView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Add right bar button items
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addSmartFolder)),
            UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(toggleEditMode))
        ]
    }
    
    // MARK: - Data Loading
    
    private func loadSmartFolders() {
        StorageManager.shared.getSmartFolders { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let folders):
                    self.smartFolders = folders.sorted { $0.sortIndex < $1.sortIndex }
                    self.tableView.reloadData()
                case .failure(let error):
                    print("Error loading smart folders: \(error.localizedDescription)")
                    self.showAlert(title: "Error", message: "Could not load smart folders.")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func smartFoldersUpdated() {
        loadSmartFolders()
    }
    
    @objc private func addSmartFolder() {
        let ruleEditorVC = SmartFolderEditorViewController(smartFolder: nil)
        ruleEditorVC.delegate = self
        let navController = UINavigationController(rootViewController: ruleEditorVC)
        present(navController, animated: true)
    }
    
    @objc private func toggleEditMode() {
        isEditMode = !isEditMode
        tableView.setEditing(isEditMode, animated: true)
        
        // Update bar button item
        if isEditMode {
            // Use checkmark.circle icon for Done state
            navigationItem.rightBarButtonItems?[1] = UIBarButtonItem(
                image: UIImage(systemName: "checkmark.circle"),
                style: .plain,
                target: self,
                action: #selector(toggleEditMode)
            )
        } else {
            // Use the edit system item for Edit state
            navigationItem.rightBarButtonItems?[1] = UIBarButtonItem(
                barButtonSystemItem: .edit,
                target: self,
                action: #selector(toggleEditMode)
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func deleteSmartFolder(at indexPath: IndexPath) {
        let folder = smartFolders[indexPath.row]
        
        StorageManager.shared.deleteSmartFolder(id: folder.id) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.smartFolders.remove(at: indexPath.row)
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                case .failure(let error):
                    print("Error deleting smart folder: \(error.localizedDescription)")
                    self.showAlert(title: "Error", message: "Could not delete smart folder.")
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension SmartFolderViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return smartFolders.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SmartFolderCell", for: indexPath)
        let folder = smartFolders[indexPath.row]
        
        cell.textLabel?.text = folder.name
        
        // Configure cell details and appearance
        if !folder.description.isEmpty {
            cell.detailTextLabel?.text = folder.description
        } else {
            // Show the rule count if no description is available
            let ruleCount = folder.rules.count
            cell.detailTextLabel?.text = "\(ruleCount) rule\(ruleCount == 1 ? "" : "s")"
        }
        
        // Add a disclosure indicator
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Smart folders automatically filter content based on rules you define."
    }
}

// MARK: - UITableViewDelegate

extension SmartFolderViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let folder = smartFolders[indexPath.row]
        let editorVC = SmartFolderEditorViewController(smartFolder: folder)
        editorVC.delegate = self
        navigationController?.pushViewController(editorVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            deleteSmartFolder(at: indexPath)
        }
    }
}

// MARK: - SmartFolderEditorDelegate

extension SmartFolderViewController: SmartFolderEditorDelegate {
    func didSaveSmartFolder(_ folder: SmartFolder) {
        loadSmartFolders()
    }
}

// MARK: - Smart Folder Editor View Controller

protocol SmartFolderEditorDelegate: AnyObject {
    func didSaveSmartFolder(_ folder: SmartFolder)
}

class SmartFolderEditorViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: SmartFolderEditorDelegate?
    
    private var smartFolder: SmartFolder?
    private var tableView: UITableView!
    private var nameTextField: UITextField!
    private var descriptionTextField: UITextField!
    private var matchModeControl: UISegmentedControl!
    private var includesArticlesSwitch: UISwitch!
    private var rules: [SmartFolderRule] = []
    
    // MARK: - Initialization
    
    init(smartFolder: SmartFolder?) {
        self.smartFolder = smartFolder
        if let folder = smartFolder {
            self.rules = folder.rules
        }
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = smartFolder == nil ? "New Smart Folder" : "Edit Smart Folder"
        setupUI()
        
        // Setup navigation bar buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        // Register with value1 style to show detail text
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "RuleCell")
        view.addSubview(tableView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        if navigationController?.viewControllers.first == self {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func saveTapped() {
        guard let name = nameTextField.text, !name.isEmpty else {
            showAlert(title: "Error", message: "Please enter a name for the smart folder.")
            return
        }
        
        let description = descriptionTextField.text ?? ""
        let matchMode: SmartFolderMatchMode = matchModeControl.selectedSegmentIndex == 0 ? .all : .any
        let includesArticles = includesArticlesSwitch.isOn
        
        if rules.isEmpty {
            showAlert(title: "Error", message: "Please add at least one rule.")
            return
        }
        
        if let existingFolder = smartFolder {
            // Update existing folder
            var updatedFolder = existingFolder
            updatedFolder.name = name
            updatedFolder.description = description
            updatedFolder.rules = rules
            updatedFolder.matchMode = matchMode
            updatedFolder.includesArticles = includesArticles
            
            StorageManager.shared.updateSmartFolder(updatedFolder) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.delegate?.didSaveSmartFolder(updatedFolder)
                        self.navigationController?.popViewController(animated: true)
                    case .failure(let error):
                        print("Error updating smart folder: \(error.localizedDescription)")
                        self.showAlert(title: "Error", message: "Could not update smart folder.")
                    }
                }
            }
        } else {
            // Create new folder - we'll use the StorageManager.createSmartFolder method
            
            StorageManager.shared.createSmartFolder(
                name: name,
                description: description,
                rules: rules,
                matchMode: matchMode,
                includesArticles: includesArticles
            ) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success(let folder):
                        self.delegate?.didSaveSmartFolder(folder)
                        if self.navigationController?.viewControllers.first == self {
                            self.dismiss(animated: true)
                        } else {
                            self.navigationController?.popViewController(animated: true)
                        }
                    case .failure(let error):
                        print("Error creating smart folder: \(error.localizedDescription)")
                        self.showAlert(title: "Error", message: "Could not create smart folder.")
                    }
                }
            }
        }
    }
    
    @objc private func addRule() {
        let ruleVC = RuleEditorViewController(rule: nil)
        ruleVC.delegate = self
        navigationController?.pushViewController(ruleVC, animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SmartFolderEditorViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 2 // Name and description fields
        case 1:
            return 2 // Match mode and includes articles switch
        case 2:
            return rules.count + 1 // Rules + "Add Rule" cell
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RuleCell", for: indexPath)
        
        // Reset cell properties
        cell.textLabel?.text = ""
        cell.textLabel?.textColor = .label // Reset text color to default
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        
        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                // Name field
                cell.textLabel?.text = "Name"
                nameTextField = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
                nameTextField.placeholder = "Enter a name"
                nameTextField.text = smartFolder?.name
                cell.accessoryView = nameTextField
                cell.selectionStyle = .none
            } else {
                // Description field
                cell.textLabel?.text = "Description"
                descriptionTextField = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
                descriptionTextField.placeholder = "Optional description"
                descriptionTextField.text = smartFolder?.description
                cell.accessoryView = descriptionTextField
                cell.selectionStyle = .none
            }
            
        case 1:
            if indexPath.row == 0 {
                // Match mode control
                cell.textLabel?.text = "Match"
                matchModeControl = UISegmentedControl(items: ["All Rules", "Any Rule"])
                matchModeControl.selectedSegmentIndex = smartFolder?.matchMode == .all ? 0 : 1
                cell.accessoryView = matchModeControl
                cell.selectionStyle = .none
            } else {
                // Includes articles switch
                cell.textLabel?.text = "Include Articles"
                includesArticlesSwitch = UISwitch()
                includesArticlesSwitch.isOn = smartFolder?.includesArticles ?? true
                cell.accessoryView = includesArticlesSwitch
                cell.selectionStyle = .none
            }
            
        case 2:
            if indexPath.row < rules.count {
                // Rule cell
                let rule = rules[indexPath.row]
                cell.textLabel?.text = formatRuleText(rule)
                cell.accessoryType = .disclosureIndicator
            } else {
                // "Add Rule" cell
                cell.textLabel?.text = "Add Rule"
                cell.textLabel?.textColor = .systemBlue
                cell.accessoryType = .none
            }
            
        default:
            break
        }
        
        return cell
    }
    
    private func formatRuleText(_ rule: SmartFolderRule) -> String {
        let fieldText = formatFieldText(rule.field)
        let operationText = formatOperationText(rule.operation)
        let valueText = rule.value
        
        return "\(fieldText) \(operationText) \"\(valueText)\""
    }
    
    private func formatFieldText(_ field: SmartFolderField) -> String {
        switch field {
        case .tag:
            return "Tag"
        case .title:
            return "Title"
        case .content:
            return "Content"
        case .feedURL:
            return "Feed URL"
        case .feedTitle:
            return "Feed Title"
        case .isRead:
            return "Is Read"
        case .pubDate:
            return "Publication Date"
        case .regex:
            return "Regex Pattern"
        }
    }
    
    private func formatOperationText(_ operation: SmartFolderOperation) -> String {
        switch operation {
        case .contains:
            return "contains"
        case .notContains:
            return "does not contain"
        case .equals:
            return "equals"
        case .notEquals:
            return "does not equal"
        case .beginsWith:
            return "begins with"
        case .endsWith:
            return "ends with"
        case .isTagged:
            return "is tagged with"
        case .isNotTagged:
            return "is not tagged with"
        case .isTrue:
            return "is true"
        case .isFalse:
            return "is false"
        case .after:
            return "is after"
        case .before:
            return "is before"
        case .matches:
            return "matches pattern"
        case .notMatches:
            return "does not match pattern"
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Folder Details"
        case 1:
            return "Matching Behavior"
        case 2:
            return "Rules"
        default:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1:
            return "Choose whether all rules must match (AND) or any rule can match (OR)."
        case 2:
            return "Rules determine which feeds and articles appear in this smart folder."
        default:
            return nil
        }
    }
}

// MARK: - UITableViewDelegate

extension SmartFolderEditorViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 2 {
            if indexPath.row < rules.count {
                // Edit existing rule
                let rule = rules[indexPath.row]
                let ruleVC = RuleEditorViewController(rule: rule)
                ruleVC.delegate = self
                ruleVC.ruleIndex = indexPath.row
                navigationController?.pushViewController(ruleVC, animated: true)
            } else {
                // Add new rule
                addRule()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 2 && indexPath.row < rules.count
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && indexPath.section == 2 && indexPath.row < rules.count {
            rules.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}

// MARK: - RuleEditorDelegate

extension SmartFolderEditorViewController: RuleEditorDelegate {
    func didSaveRule(_ rule: SmartFolderRule, at index: Int?) {
        if let index = index, index < rules.count {
            // Update existing rule
            rules[index] = rule
        } else {
            // Add new rule
            rules.append(rule)
        }
        tableView.reloadSections(IndexSet(integer: 2), with: .automatic)
    }
}

// MARK: - Rule Editor View Controller

protocol RuleEditorDelegate: AnyObject {
    func didSaveRule(_ rule: SmartFolderRule, at index: Int?)
}

class RuleEditorViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIPickerViewDelegate, UIPickerViewDataSource {
    
    // MARK: - Properties
    
    weak var delegate: RuleEditorDelegate?
    var ruleIndex: Int?
    
    private var rule: SmartFolderRule?
    private var tableView: UITableView!
    
    private var fields: [SmartFolderField] = [.tag, .title, .content, .feedURL, .feedTitle, .isRead, .pubDate, .regex]
    private var operations: [SmartFolderOperation] = []
    
    private var selectedField: SmartFolderField = .title
    private var selectedOperation: SmartFolderOperation = .contains
    private var valueText: String = ""
    
    private var valueTextField: UITextField!
    private var fieldPickerView: UIPickerView!
    private var operationPickerView: UIPickerView!
    
    // MARK: - Initialization
    
    init(rule: SmartFolderRule?) {
        self.rule = rule
        super.init(nibName: nil, bundle: nil)
        
        if let rule = rule {
            // Use existing rule values
            selectedField = rule.field
            selectedOperation = rule.operation
            valueText = rule.value
        } else {
            // Set default values for a new rule
            selectedField = .title
            selectedOperation = .contains
            valueText = ""
        }
        
        // Update available operations based on selected field
        updateOperationsForField(selectedField)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = rule == nil ? "New Rule" : "Edit Rule"
        setupUI()
        
        // Setup navigation bar buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        // Register with value1 style to show detail text
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "RuleCell")
        view.addSubview(tableView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Create pickers
        fieldPickerView = UIPickerView()
        fieldPickerView.delegate = self
        fieldPickerView.dataSource = self
        
        operationPickerView = UIPickerView()
        operationPickerView.delegate = self
        operationPickerView.dataSource = self
        
        // Set initial selected values for pickers
        if let index = fields.firstIndex(of: selectedField) {
            fieldPickerView.selectRow(index, inComponent: 0, animated: false)
        }
        
        if let index = operations.firstIndex(of: selectedOperation) {
            operationPickerView.selectRow(index, inComponent: 0, animated: false)
        }
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func saveTapped() {
        guard isValidRule() else {
            showAlert(title: "Error", message: "Please make sure all fields are filled correctly.")
            return
        }
        
        let newRule = SmartFolderRule(
            field: selectedField,
            operation: selectedOperation,
            value: valueText
        )
        
        delegate?.didSaveRule(newRule, at: ruleIndex)
        navigationController?.popViewController(animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func isValidRule() -> Bool {
        // Check if value is required for this operation
        let requiresValue = selectedOperation != .isTrue && selectedOperation != .isFalse
        
        return !requiresValue || !valueText.isEmpty
    }
    
    private func updateOperationsForField(_ field: SmartFolderField) {
        switch field {
        case .tag:
            operations = [.isTagged, .isNotTagged, .contains, .notContains, .equals, .notEquals]
        case .title, .content, .feedURL, .feedTitle:
            operations = [.contains, .notContains, .equals, .notEquals, .beginsWith, .endsWith]
        case .isRead:
            operations = [.isTrue, .isFalse]
        case .pubDate:
            operations = [.after, .before]
        case .regex:
            operations = [.matches, .notMatches]
        }
        
        // Ensure selected operation is valid for this field
        if !operations.contains(selectedOperation) {
            selectedOperation = operations.first ?? .contains
        }
        
        // Update picker if it exists
        if let picker = operationPickerView {
            picker.reloadAllComponents()
            if let index = operations.firstIndex(of: selectedOperation) {
                picker.selectRow(index, inComponent: 0, animated: false)
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3 // Field, operation, value
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Always create a new cell with the right style to ensure consistent display
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "RuleCell")
        
        switch indexPath.row {
        case 0:
            // Field picker
            cell.textLabel?.text = "Field"
            cell.detailTextLabel?.text = formatFieldText(selectedField)
            cell.accessoryType = .disclosureIndicator
            
        case 1:
            // Operation picker
            cell.textLabel?.text = "Operation"
            cell.detailTextLabel?.text = formatOperationText(selectedOperation)
            cell.accessoryType = .disclosureIndicator
            
        case 2:
            // Value text field
            cell.textLabel?.text = "Value"
            valueTextField = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
            valueTextField.placeholder = "Enter value"
            valueTextField.text = valueText
            valueTextField.clearButtonMode = .whileEditing
            valueTextField.addTarget(self, action: #selector(valueTextChanged(_:)), for: .editingChanged)
            
            // Disable text field for operations that don't need values
            valueTextField.isEnabled = selectedOperation != .isTrue && selectedOperation != .isFalse
            
            cell.accessoryView = valueTextField
            cell.selectionStyle = .none
            
        default:
            // This should never happen as we only have 3 rows, but Swift requires exhaustive switches
            cell.textLabel?.text = "Unknown Row"
        }
        
        return cell
    }
    
    private func formatFieldText(_ field: SmartFolderField) -> String {
        switch field {
        case .tag:
            return "Tag"
        case .title:
            return "Title"
        case .content:
            return "Content"
        case .feedURL:
            return "Feed URL"
        case .feedTitle:
            return "Feed Title"
        case .isRead:
            return "Is Read"
        case .pubDate:
            return "Publication Date"
        case .regex:
            return "Regex Pattern"
        }
    }
    
    private func formatOperationText(_ operation: SmartFolderOperation) -> String {
        switch operation {
        case .contains:
            return "contains"
        case .notContains:
            return "does not contain"
        case .equals:
            return "equals"
        case .notEquals:
            return "does not equal"
        case .beginsWith:
            return "begins with"
        case .endsWith:
            return "ends with"
        case .isTagged:
            return "is tagged with"
        case .isNotTagged:
            return "is not tagged with"
        case .isTrue:
            return "is true"
        case .isFalse:
            return "is false"
        case .after:
            return "is after"
        case .before:
            return "is before"
        case .matches:
            return "matches pattern"
        case .notMatches:
            return "does not match pattern"
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch indexPath.row {
        case 0:
            // Show field picker
            showFieldPicker()
        case 1:
            // Show operation picker
            showOperationPicker()
        default:
            break
        }
    }
    
    // MARK: - UIPickerViewDataSource
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView == fieldPickerView {
            return fields.count
        } else {
            return operations.count
        }
    }
    
    // MARK: - UIPickerViewDelegate
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView == fieldPickerView {
            return formatFieldText(fields[row])
        } else {
            return formatOperationText(operations[row])
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView == fieldPickerView {
            let field = fields[row]
            selectedField = field
            updateOperationsForField(field)
            tableView.reloadRows(at: [IndexPath(row: 0, section: 0), IndexPath(row: 1, section: 0)], with: .none)
        } else {
            selectedOperation = operations[row]
            tableView.reloadRows(at: [IndexPath(row: 1, section: 0), IndexPath(row: 2, section: 0)], with: .none)
        }
    }
    
    // MARK: - Picker Presentation
    
    private func showFieldPicker() {
        // Create a simple action sheet with a list of options instead of a picker
        let alert = UIAlertController(title: "Select Field", message: nil, preferredStyle: .actionSheet)
        
        // Add an action for each available field
        for field in fields {
            let action = UIAlertAction(title: formatFieldText(field), style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.selectedField = field
                self.updateOperationsForField(field)
                
                // Ensure table gets updated on main thread
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
            alert.addAction(action)
        }
        
        // Add cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPads, set source view for popover
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = tableView
            popoverController.sourceRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
        }
        
        present(alert, animated: true)
    }
    
    private func showOperationPicker() {
        // Create a simple action sheet with a list of options instead of a picker
        let alert = UIAlertController(title: "Select Operation", message: nil, preferredStyle: .actionSheet)
        
        // Add an action for each available operation
        for operation in operations {
            let action = UIAlertAction(title: formatOperationText(operation), style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.selectedOperation = operation
                
                // Ensure table gets updated on main thread
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
            alert.addAction(action)
        }
        
        // Add cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPads, set source view for popover
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = tableView
            popoverController.sourceRect = tableView.rectForRow(at: IndexPath(row: 1, section: 0))
        }
        
        present(alert, animated: true)
    }
    
    // MARK: - Text Field Events
    
    @objc private func valueTextChanged(_ textField: UITextField) {
        valueText = textField.text ?? ""
    }
}