import Foundation

/// Links widgets and complications open the app with.
public enum StrideLink: String, CaseIterable, Sendable {
    /// The Run tab, ready to start.
    case run
    case progress
    case activities

    public static let scheme = "stride"

    public var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(), let link = StrideLink(rawValue: host) else { return nil }
        self = link
    }
}
