import SwiftUI

/// Clean production cloud authentication and provisioning login view.
public struct LoginView: View {
    @ObservedObject var callManager: CallManager
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let authService = AuthService.shared
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    public var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // App Branding Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                        .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 6)
                    
                    Image(systemName: "phone.bubble.left.fill")
                        .font(.system(size: 38))
                        .foregroundColor(.white)
                }
                
                Text("MeroSip")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Enterprise VoIP Softphone")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
            
            // Login Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Username or Email")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g. reception_1", text: $email)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                
                Button(action: handleLogin) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text(isLoading ? "Authenticating & Connecting..." : "Sign In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                .padding(.top, 8)
                
                Button("Fill reception_1 (FreePBX)") {
                    email = "reception_1"
                    password = "reception_1"
                }
                .font(.footnote)
                .foregroundColor(.accentColor)
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
            
            Spacer()
            
            // PBX Server status indicator
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.caption)
                Text("Connected to FreePBX • SmartLink")
                    .font(.caption2)
            }
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.bottom, 16)
        }
        .frame(minWidth: 360, minHeight: 520)
    }
    
    private func handleLogin() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let response = try await authService.login(email: email, password: password)
                await callManager.configure(with: response)
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
