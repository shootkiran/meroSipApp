import SwiftUI

/// macOS NavigationSplitView full desktop window sidebar and detail container.
public struct MainSidebarView: View {
    @ObservedObject var callManager: CallManager
    private let authService = AuthService.shared
    
    public enum SidebarSection: String, CaseIterable, Identifiable {
        case keypad = "Keypad"
        case recents = "Recents"
        case contacts = "Contacts"
        case settings = "Settings"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .keypad: return "circle.grid.3x3.fill"
            case .recents: return "clock.fill"
            case .contacts: return "person.crop.circle.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    @State private var selectedSection: SidebarSection? = .keypad
    @State private var showLogoutConfirmation = false
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Navigation items
                List(SidebarSection.allCases, selection: $selectedSection) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .listStyle(.sidebar)
                
                Divider()
                
                // Sidebar Footer with logged-in user profile & quick Logout
                if let user = callManager.currentUser {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 36, height: 36)
                                Text(user.fullName.prefix(1).uppercased())
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.fullName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                
                                if let ext = callManager.provisionedAccount?.username {
                                    Text("Ext: \(ext) • \(callManager.provisionedAccount?.domain ?? "")")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        // Status and Logout row
                        HStack {
                            StatusBadge(state: callManager.registrationState)
                            
                            Spacer()
                            
                            Button(action: {
                                showLogoutConfirmation = true
                            }) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Sign Out")
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06))
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .navigationTitle("MeroSip")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    StatusBadge(state: callManager.registrationState)
                }
            }
        } detail: {
            switch selectedSection ?? .keypad {
            case .keypad:
                KeypadView(callManager: callManager)
            case .recents:
                RecentsView(callManager: callManager)
            case .contacts:
                ContactsView(callManager: callManager)
            case .settings:
                SettingsView(callManager: callManager)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .confirmationDialog("Sign out of MeroSip?", isPresented: $showLogoutConfirmation) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await authService.logout()
                    await callManager.unregister()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
