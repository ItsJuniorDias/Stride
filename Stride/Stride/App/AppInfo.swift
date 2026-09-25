import Foundation

/// Where runners reach the developer. Set before release: App Review needs a working way to
/// report names in Friends (guideline 1.2), and the App Store listing needs a support contact.
enum AppInfo {
    static let supportEmail = "support@example.com"

    /// A prefilled email reporting a friend's name.
    static func reportURL(name: String, code: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Report a runner in Stride"),
            URLQueryItem(name: "body", value: "I'd like to report the runner \"\(name)\" (code \(code)).\n\nReason:\n"),
        ]
        return components.url
    }
}
