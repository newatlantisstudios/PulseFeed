import UIKit
import Foundation

extension HomeFeedViewController {
    
    // Special handling for smart folders in the sort and filter process
    func applyCurrentSortAndFilterForSmartFolders() {
        // Step 1: Hide the UI during processing
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        loadingLabel.text = "Applying sort and filters..."
        loadingLabel.isHidden = false
        
        // Step 2: For smart folders, we need to potentially reapply the smart folder logic
        switch currentFeedType {
        case .smartFolder(let folderId):
            // If we're viewing a smart folder, reload it to ensure rules are applied
            if let folder = currentSmartFolder, folder.id == folderId {
                // Load smart folder contents which will also apply sorting
                loadSmartFolderContents(folder: folder)
                return
            }
        default:
            // For other feed types, proceed with normal sort/filter
            break
        }
        
        // Step 3: Finish UI update
        tableView.isHidden = false
        loadingIndicator.stopAnimating()
        loadingLabel.isHidden = true
    }
}