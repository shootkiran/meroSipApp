import Foundation
import SwiftUI
#if os(macOS)
import AppKit

public final class MeroSipAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.windows.first(where: { !($0.className.contains("NSStatusBarWindow")) }) {
                window.title = "MeroSip Softphone"
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}
#endif
