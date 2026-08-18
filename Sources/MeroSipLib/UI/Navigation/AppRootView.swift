import SwiftUI

/// Root multiplatform view orchestrating authentication state, active call overlays, and main navigation.
public struct AppRootView: View {
    @ObservedObject var callManager: CallManager
    @ObservedObject var updateManager = AppUpdateManager.shared
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    public var body: some View {
        ZStack {
            if callManager.currentUser == nil {
                LoginView(callManager: callManager)
            } else {
                #if os(macOS)
                MainSidebarView(callManager: callManager)
                #else
                MainTabView(callManager: callManager)
                #endif
            }
            
            // In-Call Full Overlay when an active call is present
            if let call = callManager.activeCall {
                InCallView(callManager: callManager, call: call)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: callManager.activeCall != nil)
        .animation(.easeInOut(duration: 0.3), value: callManager.currentUser != nil)
        .sheet(isPresented: $updateManager.showUpdateModal) {
            UpdateModalView()
        }
        .task {
            // Check for updates in background on app launch
            await updateManager.checkForUpdates(manual: false)
        }
    }
}
