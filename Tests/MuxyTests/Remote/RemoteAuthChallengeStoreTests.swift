import Foundation
import Testing

@testable import MuxyServer

@Suite("RemoteAuthChallengeStore")
struct RemoteAuthChallengeStoreTests {
    @Test("consuming a challenge prevents replay")
    func consumePreventsReplay() throws {
        let store = RemoteAuthChallengeStore()
        let now = Date(timeIntervalSince1970: 1)
        let challenge = try store.issue(
            deviceID: UUID(),
            deviceName: "iPhone",
            deviceFingerprint: "device-fp",
            now: now
        )

        let first = store.consume(challengeID: challenge.challengeID, now: now)
        let second = store.consume(challengeID: challenge.challengeID, now: now)

        #expect(first != nil)
        #expect(second == nil)
    }

    @Test("expired challenges cannot be consumed")
    func expiredChallengesCannotBeConsumed() throws {
        let store = RemoteAuthChallengeStore(challengeTTL: 1)
        let challenge = try store.issue(
            deviceID: UUID(),
            deviceName: "iPhone",
            deviceFingerprint: "device-fp",
            now: Date(timeIntervalSince1970: 1)
        )

        let consumed = store.consume(
            challengeID: challenge.challengeID,
            now: Date(timeIntervalSince1970: 3)
        )

        #expect(consumed == nil)
    }
}
