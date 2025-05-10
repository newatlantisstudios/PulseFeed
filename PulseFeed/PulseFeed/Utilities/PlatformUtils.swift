import Foundation
import UIKit

/// Utility struct for detecting platform-specific capabilities and behaviors
struct PlatformUtils {

    /// Returns whether the current device is running macOS (Catalyst)
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// Returns whether the current device supports touch input natively
    static var hasNativeTouchInput: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
    }

    /// Determines if the device likely has a trackpad
    /// Note: This is an approximation, as there's no direct API to detect a trackpad
    static var hasTrackpad: Bool {
        // Most Macs have trackpads, but this could be enhanced with more specific detection
        // Returns true for iPad/iPhone since they have direct touch gestures
        #if targetEnvironment(macCatalyst)
        return UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .phone
        #else
        return true
        #endif
    }

    /// Determines if we should enhance context menu functionality for better macOS experience
    /// True when on macOS, where right-clicking is a primary interaction pattern
    static var shouldEnhanceContextMenu: Bool {
        return isMac
    }
}