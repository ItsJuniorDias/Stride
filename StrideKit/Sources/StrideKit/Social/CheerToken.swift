import Foundation
import CommonCrypto
import Synchronization

/// What a public card lists for each friend its runner cheered: not the friend's code (that would
/// let anyone holding the card read the friend's card too), but a slow one-way token only that
/// friend can recognize. Guessing a code from a token means trying ~10¹² codes at 30,000
/// PBKDF2 rounds each.
public enum CheerToken {
    static let rounds: UInt32 = 30_000

    private static let cache = Mutex<[String: String]>([:])

    /// The token `cheerer` publishes for `friend`; `friend` computes the same to see the cheer.
    public static func make(for friend: String, from cheerer: String) -> String {
        let key = "\(friend)|\(cheerer)"
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let password = Array("stride-cheer:\(friend)".utf8)
        let salt = Array("stride-runner:\(cheerer)".utf8)
        var derived = [UInt8](repeating: 0, count: 8)
        let status = password.withUnsafeBufferPointer { passwordBytes in
            passwordBytes.withMemoryRebound(to: Int8.self) { passwordChars in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordChars.baseAddress, password.count,
                                     salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     &derived, derived.count)
            }
        }
        let token = status == kCCSuccess ? derived.map { String(format: "%02x", $0) }.joined() : ""
        cache.withLock { $0[key] = token }
        return token
    }
}
