import Foundation
import Testing
@testable import StatsCore

@Test func updateConfigurationRequiresSecureFeedAndValidPublicKey() {
    let key = Data(repeating: 42, count: 32).base64EncodedString()
    #expect(UpdateConfiguration(feedURL: "https://updates.example.com/appcast.xml", publicKey: key) != nil)
    for feed in [nil, "", "http://updates.example.com/appcast.xml", "file:///tmp/appcast.xml", "https:///", "https://user:password@example.com/appcast.xml", "https://example.com/appcast.xml#fragment"] as [String?] {
        #expect(UpdateConfiguration(feedURL: feed, publicKey: key) == nil)
    }
    for invalidKey in [nil, "", "not base64", Data(repeating: 1, count: 31).base64EncodedString()] as [String?] {
        #expect(UpdateConfiguration(feedURL: "https://updates.example.com/appcast.xml", publicKey: invalidKey) == nil)
    }
}
