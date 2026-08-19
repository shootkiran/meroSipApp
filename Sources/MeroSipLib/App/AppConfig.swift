import Foundation

/// Application-wide configuration defaults.
public enum AppConfig {
    /// Primary production backend API base URL for MeroSip.
    public static var defaultBaseURL: URL {
        return URL(string: "https://sipbackend.mims.top/api/v1")!
    }
}
