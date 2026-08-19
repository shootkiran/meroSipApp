import Foundation

/// Application-wide configuration defaults.
public enum AppConfig {
    /// Default backend API base URL based on build configuration and bundle ID.
    public static var defaultBaseURL: URL {
        let isDevBundle = Bundle.main.bundleIdentifier == "com.merosip.app.dev" ||
                          Bundle.main.bundleIdentifier?.contains("dev") == true
        #if DEBUG
        return URL(string: "https://merosipbackend.test/api/v1")!
        #else
        if isDevBundle {
            return URL(string: "https://merosipbackend.test/api/v1")!
        } else {
            return URL(string: "https://sipbackend.mims.top/api/v1")!
        }
        #endif
    }
}
