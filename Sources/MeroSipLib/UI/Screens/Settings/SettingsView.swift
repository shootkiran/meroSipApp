import SwiftUI

/// Settings and user profile screen.
public struct SettingsView: View {
    @ObservedObject var callManager: CallManager
    private let authService = AuthService.shared
    
    @State private var showingLogoutConfirmation = false
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Profile Section
                if let user = callManager.currentUser {
                    Section("User Account") {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 54, height: 54)
                                Text(user.fullName.prefix(1).uppercased())
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.fullName)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("PBX: \(user.organization)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // SIP Connection Info
                Section("FreePBX Server Status") {
                    HStack {
                        Text("Registration Status")
                        Spacer()
                        StatusBadge(state: callManager.registrationState)
                    }
                    
                    if let account = callManager.provisionedAccount {
                        LabeledContent("SIP Extension", value: account.username)
                        LabeledContent("PBX Server", value: account.domain)
                        LabeledContent("Outbound Proxy", value: account.proxy ?? account.domain)
                        LabeledContent("Transport", value: "\(account.transport.rawValue) (Port \(account.port))")
                        LabeledContent("SRTP Encryption", value: account.srtpEnabled ? "Enabled" : "Disabled (UDP Standard)")
                        if let stun = account.stunServer {
                            LabeledContent("STUN Server", value: stun)
                        }
                    }
                }
                
                // Audio & Devices
                Section("Audio Output Device") {
                    Picker("Device", selection: Binding(
                        get: { callManager.audioRouteManager.currentRoute },
                        set: { callManager.audioRouteManager.setRoute($0) }
                    )) {
                        ForEach(callManager.audioRouteManager.availableRoutes) { route in
                            Text(route.rawValue).tag(route)
                        }
                    }
                }
                
                // Software Updates
                Section("Software Updates") {
                    LabeledContent("Installed Version", value: "v\(AppUpdateManager.shared.currentVersion) (Build \(AppUpdateManager.shared.currentBuild))")
                    
                    HStack {
                        Button(action: {
                            Task {
                                await AppUpdateManager.shared.checkForUpdates(manual: true)
                            }
                        }) {
                            if AppUpdateManager.shared.isChecking {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Checking for updates...")
                                }
                            } else {
                                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(AppUpdateManager.shared.isChecking)
                        
                        Spacer()
                        
                        if AppUpdateManager.shared.isUpToDate {
                            Text("Up to date")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if AppUpdateManager.shared.updateAvailable {
                            Button("Update Available") {
                                AppUpdateManager.shared.showUpdateModal = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    if let err = AppUpdateManager.shared.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // Codecs & Telephony Info
                Section("Telephony Engine & Codecs") {
                    LabeledContent("SIP Stack", value: "RFC 3261 Native UDP Engine")
                    LabeledContent("Supported Codecs", value: "PCMU (G.711u), PCMA (G.711a), Opus")
                    LabeledContent("DTMF Mode", value: "RFC 2833 / SIP INFO")
                }
                
                // Logout Action
                Section {
                    Button(role: .destructive, action: {
                        showingLogoutConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign Out of MeroSip?", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authService.logout()
                        await callManager.unregister()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Signing out will disconnect extension \(callManager.provisionedAccount?.username ?? "") from the FreePBX server.")
            }
        }
    }
}
