import Foundation

/// Class for managing hierarchical folder operations
class FolderManager {
    /// Get all root folders (those without a parent)
    static func getRootFolders(from folders: [HierarchicalFolder]) -> [HierarchicalFolder] {
        print("DEBUG: FolderManager - Getting root folders from \(folders.count) folders")
        let rootFolders = folders.filter { $0.parentId == nil }
                      .sorted { $0.sortIndex < $1.sortIndex }
        print("DEBUG: FolderManager - Found \(rootFolders.count) root folders")
        return rootFolders
    }
    
    /// Get direct child folders for a specific parent folder
    static func getChildFolders(from folders: [HierarchicalFolder], forParentId parentId: String) -> [HierarchicalFolder] {
        print("DEBUG: FolderManager - Getting child folders for parent ID: \(parentId)")
        let childFolders = folders.filter { $0.parentId == parentId }
                      .sorted { $0.sortIndex < $1.sortIndex }
        print("DEBUG: FolderManager - Found \(childFolders.count) child folders for parent \(parentId)")
        return childFolders
    }
    
    /// Get all descendant folders (children, grandchildren, etc.) for a specific folder
    static func getAllDescendantFolders(from folders: [HierarchicalFolder], forFolderId folderId: String) -> [HierarchicalFolder] {
        print("DEBUG: FolderManager - Getting all descendant folders for folder ID: \(folderId)")
        var result: [HierarchicalFolder] = []
        let directChildren = getChildFolders(from: folders, forParentId: folderId)
        
        print("DEBUG: FolderManager - Found \(directChildren.count) direct children for folder \(folderId)")
        result.append(contentsOf: directChildren)
        
        for child in directChildren {
            print("DEBUG: FolderManager - Recursively getting descendants for child folder: \(child.name) (ID: \(child.id))")
            let childDescendants = getAllDescendantFolders(from: folders, forFolderId: child.id)
            result.append(contentsOf: childDescendants)
        }
        
        print("DEBUG: FolderManager - Total descendants found for folder \(folderId): \(result.count)")
        return result
    }
    
    /// Get all ancestor folders (parent, grandparent, etc.) for a specific folder
    static func getAncestorFolders(from folders: [HierarchicalFolder], forFolderId folderId: String) -> [HierarchicalFolder] {
        print("DEBUG: FolderManager - Getting all ancestor folders for folder ID: \(folderId)")
        var result: [HierarchicalFolder] = []
        var currentFolderId = folderId
        
        print("DEBUG: FolderManager - Starting ancestry lookup for folder \(folderId)")
        while let currentFolder = folders.first(where: { $0.id == currentFolderId }),
              let parentId = currentFolder.parentId,
              let parentFolder = folders.first(where: { $0.id == parentId }) {
            print("DEBUG: FolderManager - Found parent: \(parentFolder.name) (ID: \(parentId)) for folder \(currentFolder.name)")
            result.append(parentFolder)
            currentFolderId = parentId
        }
        
        print("DEBUG: FolderManager - Found \(result.count) ancestors for folder \(folderId)")
        return result
    }
    
    /// Get the full path string for a folder (e.g., "Root > Subfolder > Current")
    static func getFolderPath(from folders: [HierarchicalFolder], forFolderId folderId: String) -> String {
        print("DEBUG: FolderManager - Getting folder path for folder ID: \(folderId)")
        guard let currentFolder = folders.first(where: { $0.id == folderId }) else {
            print("DEBUG: FolderManager - Folder not found with ID: \(folderId)")
            return ""
        }
        
        let ancestors = getAncestorFolders(from: folders, forFolderId: folderId)
        let path = ancestors.reversed().map { $0.name } + [currentFolder.name]
        let fullPath = path.joined(separator: " > ")
        print("DEBUG: FolderManager - Folder path for \(currentFolder.name): \(fullPath)")
        return fullPath
    }
    
    /// Get all feeds in a folder and its subfolders
    static func getAllFeeds(from folders: [HierarchicalFolder], forFolderId folderId: String) -> [String] {
        print("DEBUG: FolderManager - Getting all feeds for folder ID: \(folderId)")
        guard let currentFolder = folders.first(where: { $0.id == folderId }) else {
            print("DEBUG: FolderManager - Folder not found with ID: \(folderId)")
            return []
        }
        
        print("DEBUG: FolderManager - Folder \(currentFolder.name) has \(currentFolder.feedURLs.count) direct feeds")
        var allFeeds = currentFolder.feedURLs
        
        // Add feeds from all descendant folders
        let descendants = getAllDescendantFolders(from: folders, forFolderId: folderId)
        print("DEBUG: FolderManager - Found \(descendants.count) descendant folders for folder \(currentFolder.name)")
        
        for descendant in descendants {
            print("DEBUG: FolderManager - Adding \(descendant.feedURLs.count) feeds from descendant folder: \(descendant.name)")
            allFeeds.append(contentsOf: descendant.feedURLs)
        }
        
        let uniqueFeeds = Array(Set(allFeeds))
        print("DEBUG: FolderManager - Total unique feeds found for folder \(currentFolder.name): \(uniqueFeeds.count) (before deduplication: \(allFeeds.count))")
        
        // Return unique feeds
        return uniqueFeeds
    }
    
    /// Dump the entire folder hierarchy for debugging purposes
    static func dumpFolderHierarchy(folders: [HierarchicalFolder]) {
        print("DEBUG: FolderManager - Starting folder hierarchy dump")
        print("DEBUG: FolderManager - Total folders: \(folders.count)")
        
        let rootFolders = getRootFolders(from: folders)
        print("DEBUG: FolderManager - Root folders: \(rootFolders.count)")
        
        if rootFolders.isEmpty {
            print("DEBUG: FolderManager - No folders found in hierarchy")
            return
        }
        
        for rootFolder in rootFolders {
            dumpFolderSubtree(folders: folders, folder: rootFolder, level: 0)
        }
        
        print("DEBUG: FolderManager - Finished folder hierarchy dump")
    }
    
    /// Helper method to recursively dump a folder subtree with proper indentation
    private static func dumpFolderSubtree(folders: [HierarchicalFolder], folder: HierarchicalFolder, level: Int) {
        let indent = String(repeating: "    ", count: level)
        let feedCount = folder.feedURLs.count
        
        print("DEBUG: FolderManager - \(indent)└─ \(folder.name) (ID: \(folder.id), Feeds: \(feedCount))")
        
        if !folder.feedURLs.isEmpty {
            print("DEBUG: FolderManager - \(indent)   └─ Feed URLs:")
            for (index, url) in folder.feedURLs.enumerated() {
                if index < 5 || folder.feedURLs.count < 10 {
                    // Print all if less than 10 feeds, or just first 5 if more
                    print("DEBUG: FolderManager - \(indent)      └─ \(url)")
                } else if index == 5 {
                    print("DEBUG: FolderManager - \(indent)      └─ ... and \(folder.feedURLs.count - 5) more feeds")
                    break
                }
            }
        }
        
        let children = getChildFolders(from: folders, forParentId: folder.id)
        if !children.isEmpty {
            for child in children {
                dumpFolderSubtree(folders: folders, folder: child, level: level + 1)
            }
        }
    }
}