import SwiftUI
import MeroSipLib

@main
struct MeroSipApp: App {
    @StateObject private var environment = AppEnvironment.shared
    
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MeroSipAppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            AppRootView(callManager: environment.callManager)
                .task {
                    await environment.bootstrap()
                }
                .frame(minWidth: 860, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        #else
        WindowGroup {
            AppRootView(callManager: environment.callManager)
                .task {
                    await environment.bootstrap()
                }
        }
        #endif
    }
}
