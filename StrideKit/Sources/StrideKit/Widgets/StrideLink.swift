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

    /// The friend code in an invite link, stride://friend/ABCDEFGH.
    public static func friendCode(in url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "friend" else { return nil }
        return ShareCode.normalize(url.lastPathComponent)
    }

    public static func invite(code: String) -> URL {
        URL(string: "\(scheme)://friend/\(code)")!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(), let link = StrideLink(rawValue: host) else { return nil }
        self = link
    }
}
