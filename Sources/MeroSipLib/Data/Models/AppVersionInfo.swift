import Foundation

public struct AppVersionResponse: Codable {
    public let status: String
    public let platform: String
    public let latestVersion: String
    public let latestBuild: Int
    public let minimumSupportedVersion: String
    public let mandatory: Bool
    public let downloadUrl: String
    public let releaseNotes: String
    public let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case platform
        case latestVersion = "latest_version"
        case latestBuild = "latest_build"
        case minimumSupportedVersion = "minimum_supported_version"
        case mandatory
        case downloadUrl = "download_url"
        case releaseNotes = "release_notes"
        case publishedAt = "published_at"
    }
}
