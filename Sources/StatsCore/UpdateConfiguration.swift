import Foundation

/// An unconfigured development build must never start the network updater.
public struct UpdateConfiguration: Equatable {
    public let feedURL: URL
    public let publicKey: String

    public init?(feedURL: String?, publicKey: String?) {
        guard let feedURL, let url = URL(string: feedURL),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              let publicKey, Data(base64Encoded: publicKey)?.count == 32 else { return nil }
        self.feedURL = url
        self.publicKey = publicKey
    }
}
