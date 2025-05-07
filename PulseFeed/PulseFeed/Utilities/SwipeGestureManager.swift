import UIKit

/// A class to centralize the management of swipe gestures across the app
class SwipeGestureManager {
    
    // MARK: - Singleton
    static let shared = SwipeGestureManager()
    
    private init() {}
    
    // MARK: - Properties
    
    /// A threshold to determine when a swipe gesture should trigger an action
    private let swipeThreshold: CGFloat = 50.0
    
    /// Minimum velocity for a swipe to be recognized
    private let minimumVelocity: CGFloat = 300.0
    
    // MARK: - Feed Navigation Gestures
    
    /// Adds horizontal swipe gestures to navigate between feed types
    /// - Parameter viewController: The view controller to add gestures to
    /// - Parameter leftAction: Action to perform on left swipe
    /// - Parameter rightAction: Action to perform on right swipe
    func addFeedNavigationGestures(to viewController: UIViewController,
                                  leftAction: @escaping () -> Void,
                                  rightAction: @escaping () -> Void) {
        let leftSwipe = UISwipeGestureRecognizer(target: viewController, action: #selector(handleFeedSwipe(_:)))
        leftSwipe.direction = .left
        leftSwipe.nameProperty = "leftFeedSwipe"
        viewController.view.addGestureRecognizer(leftSwipe)
        
        let rightSwipe = UISwipeGestureRecognizer(target: viewController, action: #selector(handleFeedSwipe(_:)))
        rightSwipe.direction = .right
        rightSwipe.nameProperty = "rightFeedSwipe"
        viewController.view.addGestureRecognizer(rightSwipe)
        
        // Store the closures in a map associated with the view controller
        objc_setAssociatedObject(viewController, 
                               &AssociatedKeys.leftSwipeActionKey, 
                               leftAction, 
                               .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        objc_setAssociatedObject(viewController, 
                               &AssociatedKeys.rightSwipeActionKey, 
                               rightAction, 
                               .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    // MARK: - Article Reader Gestures
    
    /// Adds horizontal swipe gestures to navigate between articles in the reader
    /// - Parameter viewController: The view controller to add gestures to
    /// - Parameter previousAction: Action to perform to go to previous article
    /// - Parameter nextAction: Action to perform to go to next article
    func addArticleNavigationGestures(to viewController: UIViewController,
                                     previousAction: @escaping () -> Void,
                                     nextAction: @escaping () -> Void) {
        let leftSwipe = UISwipeGestureRecognizer(target: viewController, action: #selector(handleArticleSwipe(_:)))
        leftSwipe.direction = .left
        leftSwipe.nameProperty = "leftArticleSwipe"
        viewController.view.addGestureRecognizer(leftSwipe)
        
        let rightSwipe = UISwipeGestureRecognizer(target: viewController, action: #selector(handleArticleSwipe(_:)))
        rightSwipe.direction = .right
        rightSwipe.nameProperty = "rightArticleSwipe"
        viewController.view.addGestureRecognizer(rightSwipe)
        
        // Store the closures in a map associated with the view controller
        objc_setAssociatedObject(viewController, 
                               &AssociatedKeys.previousArticleKey, 
                               previousAction, 
                               .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        objc_setAssociatedObject(viewController, 
                               &AssociatedKeys.nextArticleKey, 
                               nextAction, 
                               .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    // MARK: - Custom Table Cell Gestures
    
    /// Adds custom swipe gestures to a table view cell that complement UITableView's built-in swipe actions
    /// - Parameter cell: The cell to add gestures to
    /// - Parameter tableView: The table view containing the cell
    /// - Parameter actions: An array of gesture directions and associated actions
    func addCustomCellGestures(to cell: UITableViewCell,
                              in tableView: UITableView,
                              actions: [(direction: UISwipeGestureRecognizer.Direction, action: () -> Void)]) {
        
        for (direction, action) in actions {
            let gesture = UISwipeGestureRecognizer(target: self, action: #selector(handleCellSwipe(_:)))
            gesture.direction = direction
            
            // Store the action with the gesture
            objc_setAssociatedObject(gesture, 
                                   &AssociatedKeys.cellSwipeActionKey, 
                                   action, 
                                   .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            // Store the table view reference with the gesture
            objc_setAssociatedObject(gesture, 
                                   &AssociatedKeys.tableViewKey, 
                                   tableView, 
                                   .OBJC_ASSOCIATION_ASSIGN)
            
            cell.contentView.addGestureRecognizer(gesture)
        }
    }
    
    // MARK: - Gesture Handlers
    
    /// Handle feed swipe gestures
    @objc func handleFeedSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard let viewController = gesture.view?.next as? UIViewController else { return }
        
        if gesture.direction == .left, 
           let action = objc_getAssociatedObject(viewController, &AssociatedKeys.leftSwipeActionKey) as? () -> Void {
            action()
        } else if gesture.direction == .right,
                  let action = objc_getAssociatedObject(viewController, &AssociatedKeys.rightSwipeActionKey) as? () -> Void {
            action()
        }
    }
    
    /// Handle article reader swipe gestures
    @objc func handleArticleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard let viewController = gesture.view?.next as? UIViewController else { return }
        
        if gesture.direction == .left, 
           let action = objc_getAssociatedObject(viewController, &AssociatedKeys.nextArticleKey) as? () -> Void {
            action()
        } else if gesture.direction == .right,
                  let action = objc_getAssociatedObject(viewController, &AssociatedKeys.previousArticleKey) as? () -> Void {
            action()
        }
    }
    
    /// Handle custom cell swipe gestures
    @objc func handleCellSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard let action = objc_getAssociatedObject(gesture, &AssociatedKeys.cellSwipeActionKey) as? () -> Void,
              let cell = gesture.view?.superview as? UITableViewCell,
              let tableView = objc_getAssociatedObject(gesture, &AssociatedKeys.tableViewKey) as? UITableView,
              let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        
        // Execute the action associated with this gesture
        action()
    }
}

// MARK: - Associated Keys

private struct AssociatedKeys {
    static var leftSwipeActionKey = "leftSwipeAction"
    static var rightSwipeActionKey = "rightSwipeAction"
    static var previousArticleKey = "previousArticle"
    static var nextArticleKey = "nextArticle"
    static var cellSwipeActionKey = "cellSwipeAction"
    static var tableViewKey = "tableView"
}

// MARK: - UISwipeGestureRecognizer Extension

private struct AssociatedObjectKeys {
    static var nameKey = "com.pulsefeed.swipegesture.name"
}

extension UISwipeGestureRecognizer {
    // Allow storing a name for gestures for easier identification
    var nameProperty: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedObjectKeys.nameKey) as? String
        }
        set {
            objc_setAssociatedObject(self, 
                                   &AssociatedObjectKeys.nameKey, 
                                   newValue, 
                                   .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}