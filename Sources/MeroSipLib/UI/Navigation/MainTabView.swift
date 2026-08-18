import SwiftUI

/// iOS Tab Bar navigation container.
public struct MainTabView: View {
    @ObservedObject var callManager: CallManager
    
    @State private var selectedTab = 0
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            KeypadView(callManager: callManager)
                .tabItem {
                    Label("Keypad", systemImage: "circle.grid.3x3.fill")
                }
                .tag(0)
            
            RecentsView(callManager: callManager)
                .tabItem {
                    Label("Recents", systemImage: "clock.fill")
                }
                .tag(1)
            
            ContactsView(callManager: callManager)
                .tabItem {
                    Label("Contacts", systemImage: "person.crop.circle.fill")
                }
                .tag(2)
            
            SettingsView(callManager: callManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
    }
}
