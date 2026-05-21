import Testing

@testable import Muxy

@Suite("Remote authentication")
struct RemoteAuthenticationTests {
    @Test("challenge HMAC uses token hash key material")
    func challengeHMACUsesTokenHashKeyMaterial() throws {
        let token = "pair-token"
        let tokenHash = ApprovedDevicesStore.hash(token)
        let response = ApprovedDevicesStore.challengeResponse(
            tokenHash: tokenHash,
            nonce: "00112233445566778899aabbccddeeff",
            serverTimestamp: 1_774_000_000_000,
            deviceFingerprint: "device-fp"
        )

        #expect(response.count == 64)
        #expect(ApprovedDevicesStore.constantTimeHexEquals(response, response))
    }
}
