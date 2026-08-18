import SwiftUI

public struct UpdateModalView: View {
    @ObservedObject var updateManager = AppUpdateManager.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 18) {
            // Header with App Icon
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Software Update Available")
                    .font(.title2.bold())
                
                if let release = updateManager.latestRelease {
                    Text("Version \(release.latestVersion) (Build \(release.latestBuild)) is ready to install.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Release Notes
            VStack(alignment: .leading, spacing: 6) {
                Text("What's New:")
                    .font(.headline)
                
                ScrollView {
                    Text(updateManager.latestRelease?.releaseNotes ?? "Bug fixes and performance enhancements.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxHeight: 130)
            }
            
            // Download Progress Bar & Status
            if updateManager.isDownloading {
                VStack(spacing: 6) {
                    ProgressView(value: updateManager.downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    
                    Text(updateManager.statusMessage ?? "Downloading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if updateManager.downloadComplete {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(updateManager.statusMessage ?? "Update downloaded. Ready to restart.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else if let error = updateManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                if updateManager.latestRelease?.mandatory != true {
                    Button(action: {
                        updateManager.dismissModal()
                        dismiss()
                    }) {
                        Text("Remind Me Later")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
                
                Spacer()
                
                if updateManager.isDownloading {
                    Button("Cancel") {
                        updateManager.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                } else if updateManager.downloadComplete {
                    Button(action: {
                        updateManager.applyUpdateAndRelaunch()
                        dismiss()
                    }) {
                        Text("Restart & Update")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: {
                        updateManager.startDownload()
                    }) {
                        Text("Download & Update")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 380)
    }
}
