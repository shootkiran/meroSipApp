import Foundation
import SwiftUI
#if os(macOS)
import AppKit

@MainActor
public final class MeroSipAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public static var mainWindow: NSWindow?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if let window = NSApp.windows.first(where: { !($0.className.contains("NSStatusBarWindow")) }) {
                window.title = "MeroSip Softphone"
                window.isReleasedWhenClosed = false
                window.delegate = self
                MeroSipAppDelegate.mainWindow = window
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let targetWindow = Self.mainWindow ?? sender.windows.first(where: { !($0.className.contains("NSStatusBarWindow")) && $0.canBecomeMain })
        if let window = targetWindow {
            window.setIsVisible(true)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(self)
            return false
        }
        return true
    }
    
    // Intercept red "X" close button to hide window instead of destroying it
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    
    public static func revealAndFloatMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let targetWindow = mainWindow ?? NSApp.windows.first(where: { !$0.className.contains("NSStatusBarWindow") })
        if let window = targetWindow {
            window.setIsVisible(true)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.level = .floating
        }
    }
    
    public static func restoreNormalWindowLevel() {
        for window in NSApp.windows where !window.className.contains("NSStatusBarWindow") {
            window.level = .normal
        }
    }
}
#endif
