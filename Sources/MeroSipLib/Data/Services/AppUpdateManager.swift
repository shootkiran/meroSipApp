import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class AppUpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = AppUpdateManager()
    
    @Published public var isChecking: Bool = false
    @Published public var updateAvailable: Bool = false
    @Published public var latestRelease: AppVersionResponse?
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadComplete: Bool = false
    @Published public var statusMessage: String?
    @Published public var isUpToDate: Bool = false
    @Published public var errorMessage: String?
    @Published public var showUpdateModal: Bool = false
    
    public private(set) var savedUpdateZipUrl: URL?
    
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.5"
    }
    
    public var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "6") ?? 6
    }
    
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    
    private var backendUrl: String {
        AuthService.shared.baseURL.absoluteString
    }
    
    override public init() {
        super.init()
    }
    
    // MARK: - Check for Updates
    
    public func checkForUpdates(manual: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        isUpToDate = false
        
        let endpoint = "\(backendUrl)/app/version?platform=macos"
        guard let url = URL(string: endpoint) else {
            isChecking = false
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let release = try JSONDecoder().decode(AppVersionResponse.self, from: data)
            self.latestRelease = release
            
            let isNewer = isVersionNewer(release.latestVersion, comparedTo: currentVersion) || release.latestBuild > currentBuild
            
            if isNewer {
                self.updateAvailable = true
                self.showUpdateModal = true
                print("[Auto-Update] New update available: v\(release.latestVersion) (Build \(release.latestBuild))")
            } else {
                self.updateAvailable = false
                if manual {
                    self.isUpToDate = true
                }
                print("[Auto-Update] App is up to date (v\(currentVersion)).")
            }
        } catch {
            print("[Auto-Update] Version check error: \(error)")
            if manual {
                self.errorMessage = "Unable to check for updates. Check server connection."
            }
        }
        
        isChecking = false
    }
    
    // MARK: - Download & Install
    
    public func startDownload() {
        guard let release = latestRelease, let url = URL(string: release.downloadUrl) else { return }
        
        isDownloading = true
        downloadProgress = 0.0
        downloadComplete = false
        errorMessage = nil
        statusMessage = "Downloading MeroSip v\(release.latestVersion)..."
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
    
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        statusMessage = nil
    }
    
    public func dismissModal() {
        showUpdateModal = false
        errorMessage = nil
    }
    
    public func applyUpdateAndRelaunch() {
        guard let zipUrl = savedUpdateZipUrl else {
            // Dismiss if no package is present
            dismissModal()
            return
        }
        
        print("[Auto-Update] Applying update from \(zipUrl.path)...")
        statusMessage = "Installing update and restarting MeroSip..."
        
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        // Unzip and relaunch script
        let appBundlePath = Bundle.main.bundlePath
        let script = """
        sleep 2
        mkdir -p /tmp/MeroSipExtracted
        rm -rf /tmp/MeroSipExtracted/*
        unzip -o "\(zipUrl.path)" -d /tmp/MeroSipExtracted
        if [ -d "/tmp/MeroSipExtracted/MeroSip.app" ]; then
            xattr -cr /tmp/MeroSipExtracted/MeroSip.app 2>/dev/null || true
            TARGET_APP="\(appBundlePath)"
            if [ -n "$TARGET_APP" ] && [ -d "$TARGET_APP/Contents" ]; then
                cp -Rf /tmp/MeroSipExtracted/MeroSip.app/Contents/* "$TARGET_APP/Contents/"
                xattr -cr "$TARGET_APP" 2>/dev/null || true
                open -n "$TARGET_APP"
            else
                rm -rf /Applications/MeroSip.app
                cp -R /tmp/MeroSipExtracted/MeroSip.app /Applications/MeroSip.app
                xattr -cr /Applications/MeroSip.app 2>/dev/null || true
                open -n /Applications/MeroSip.app
            fi
        fi
        """
        process.arguments = ["-c", script]
        
        do {
            try process.run()
            dismissModal()
            NSApplication.shared.terminate(nil)
        } catch {
            print("[Auto-Update] Failed to run update script: \(error)")
            dismissModal()
        }
        #else
        dismissModal()
        #endif
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0
        
        Task { @MainActor in
            self.downloadProgress = progress
            self.statusMessage = "Downloading update... \(Int(progress * 100))%"
        }
    }
    
    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fileManager = FileManager.default
        let updateDir = fileManager.temporaryDirectory.appendingPathComponent("MeroSipUpdates", isDirectory: true)
        let savedFileUrl = updateDir.appendingPathComponent("MeroSip-update-\(UUID().uuidString).zip")
        
        do {
            try fileManager.createDirectory(at: updateDir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: savedFileUrl.path) {
                try fileManager.removeItem(at: savedFileUrl)
            }
            try fileManager.copyItem(at: location, to: savedFileUrl)
            
            Task { @MainActor in
                self.isDownloading = false
                self.downloadComplete = true
                self.savedUpdateZipUrl = savedFileUrl
                self.statusMessage = "Update downloaded successfully. Click Restart & Update to finish."
                print("[Auto-Update] Update package safely saved to: \(savedFileUrl.path)")
            }
        } catch {
            print("[Auto-Update] Error copying update file: \(error)")
            Task { @MainActor in
                self.isDownloading = false
                self.errorMessage = "Failed to process update: \(error.localizedDescription)"
            }
        }
    }
    
    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            Task { @MainActor in
                self.isDownloading = false
                self.errorMessage = "Download failed: \(error.localizedDescription)"
                self.statusMessage = nil
            }
        }
    }
    
    // MARK: - Semantic Version Comparison
    
    private func isVersionNewer(_ remote: String, comparedTo local: String) -> Bool {
        let cleanRemote = remote.components(separatedBy: "-").first ?? remote
        let cleanLocal = local.components(separatedBy: "-").first ?? local
        
        let remoteParts = cleanRemote.split(separator: ".").compactMap { Int($0.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) }
        let localParts = cleanLocal.split(separator: ".").compactMap { Int($0.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) }
        
        let maxLen = max(remoteParts.count, localParts.count)
        for i in 0..<maxLen {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
