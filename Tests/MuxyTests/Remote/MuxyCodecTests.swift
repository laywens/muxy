import Foundation
import MuxyShared
import Testing

@Suite("MuxyCodec")
struct MuxyCodecTests {
    @Test("legacy envelope without protocolVersion decodes as v1")
    func legacyEnvelopeDefaultsToProtocolV1() throws {
        let json = #"{"type":"request","payload":{"id":"legacy","method":"listProjects"}}"#

        let decoded = try MuxyCodec.decode(Data(json.utf8))

        #expect(decoded.protocolVersion == 1)
        guard case let .request(request, protocolVersion) = decoded else {
            Issue.record("expected request")
            return
        }
        #expect(protocolVersion == 1)
        #expect(request.id == "legacy")
    }

    @Test("encoded envelope includes protocolVersion")
    func encodedEnvelopeIncludesProtocolVersion() throws {
        let data = try MuxyCodec.encode(.request(MuxyRequest(id: "v", method: .listProjects)))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["protocolVersion"] as? Int == 2)
    }

    @Test("current protocol is v2 and accepts v1 during deprecation")
    func currentProtocolIsV2() {
        #expect(MuxyProtocolVersion.current == 2)
        #expect(MuxyProtocolVersion.accepted == [1, 2])
    }

    @Test("auth challenge result round trips")
    func authChallengeRoundTrip() throws {
        let challenge = AuthChallengeDTO(
            challengeID: "challenge",
            nonce: "00112233445566778899aabbccddeeff",
            serverTimestamp: 1_774_000_000_000,
            acceptedVersions: [1, 2]
        )

        let data = try MuxyCodec.encode(.response(MuxyResponse(id: "auth", result: .authChallenge(challenge))))
        let decoded = try MuxyCodec.decode(data)

        guard case let .response(response, protocolVersion) = decoded,
              case let .authChallenge(roundTripped) = response.result
        else {
            Issue.record("expected auth challenge response")
            return
        }
        #expect(protocolVersion == 2)
        #expect(roundTripped.challengeID == "challenge")
        #expect(roundTripped.nonce == "00112233445566778899aabbccddeeff")
        #expect(roundTripped.serverTimestamp == 1_774_000_000_000)
        #expect(roundTripped.acceptedVersions == [1, 2])
    }

    @Test("explicit future protocolVersion round trips")
    func explicitFutureProtocolVersionRoundTrips() throws {
        let json = #"{"protocolVersion":2,"type":"request","payload":{"id":"future","method":"listProjects"}}"#

        let decoded = try MuxyCodec.decode(Data(json.utf8))
        let reencoded = try MuxyCodec.encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])

        #expect(decoded.protocolVersion == 2)
        #expect(object["protocolVersion"] as? Int == 2)
    }

    @Test("pairing result defaults acceptedVersions for legacy payloads")
    func pairingResultDefaultsAcceptedVersions() throws {
        let json = #"{"clientID":"00000000-0000-0000-0000-000000000001","deviceName":"iPhone"}"#

        let result = try JSONDecoder().decode(PairingResultDTO.self, from: Data(json.utf8))

        #expect(result.acceptedVersions == [1, 2])
    }

    @Test("pairing result session token defaults nil for legacy payloads")
    func pairingResultSessionTokenDefaultsNil() throws {
        let json = #"{"clientID":"00000000-0000-0000-0000-000000000001","deviceName":"iPhone"}"#

        let result = try JSONDecoder().decode(PairingResultDTO.self, from: Data(json.utf8))

        #expect(result.sessionToken == nil)
    }

    @Test("device info defaults acceptedVersions for legacy payloads")
    func deviceInfoDefaultsAcceptedVersions() throws {
        let json = #"{"clientID":"00000000-0000-0000-0000-000000000001","deviceName":"iPhone"}"#

        let result = try JSONDecoder().decode(DeviceInfoDTO.self, from: Data(json.utf8))

        #expect(result.acceptedVersions == [1, 2])
    }

    @Test("request round-trip preserves id, method and params")
    func requestRoundTrip() throws {
        let projectID = UUID()
        let original = MuxyMessage.request(
            MuxyRequest(
                id: "req-1",
                method: .selectProject,
                params: .selectProject(SelectProjectParams(projectID: projectID))
            )
        )

        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .request(request, _) = decoded else {
            Issue.record("expected .request case, got \(decoded)")
            return
        }
        #expect(request.id == "req-1")
        #expect(request.method == .selectProject)
        guard case let .selectProject(params) = request.params else {
            Issue.record("expected selectProject params")
            return
        }
        #expect(params.projectID == projectID)
    }

    @Test("response round-trip preserves ok result")
    func responseRoundTripOk() throws {
        let original = MuxyMessage.response(MuxyResponse(id: "r1", result: .ok))
        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .response(response, _) = decoded else {
            Issue.record("expected .response case")
            return
        }
        #expect(response.id == "r1")
        #expect(response.error == nil)
        guard case .ok = response.result else {
            Issue.record("expected .ok result")
            return
        }
    }

    @Test("response round-trip preserves error")
    func responseRoundTripError() throws {
        let original = MuxyMessage.response(
            MuxyResponse(id: "r2", error: .invalidParams)
        )
        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .response(response, _) = decoded,
              let error = response.error
        else {
            Issue.record("expected response with error")
            return
        }
        #expect(error.code == 400)
        #expect(response.result == nil)
    }

    @Test("event round-trip preserves payload")
    func eventRoundTrip() throws {
        let paneID = UUID()
        let deviceID = UUID()
        let original = MuxyMessage.event(
            MuxyEvent(
                event: .paneOwnershipChanged,
                data: .paneOwnership(
                    PaneOwnershipEventDTO(
                        paneID: paneID,
                        owner: .remote(deviceID: deviceID, deviceName: "iPhone")
                    )
                )
            )
        )

        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .event(event, _) = decoded,
              case let .paneOwnership(dto) = event.data
        else {
            Issue.record("expected pane ownership event")
            return
        }
        #expect(event.event == .paneOwnershipChanged)
        #expect(dto.paneID == paneID)
        #expect(dto.owner == .remote(deviceID: deviceID, deviceName: "iPhone"))
    }

    @Test("unknown param type rejects decoding")
    func unknownParamTypeFails() {
        let json = #"{"type":"request","payload":{"id":"x","method":"selectProject","params":{"type":"bogus","value":{}}}}"#
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            _ = try MuxyCodec.decode(data)
        }
    }

    @Test("terminal cells payload preserves cells array")
    func terminalCellsRoundTrip() throws {
        let paneID = UUID()
        let cells = (0 ..< 4).map {
            TerminalCellDTO(codepoint: UInt32($0) + 65, fg: 0xFF_FFFF, bg: 0, flags: 0)
        }
        let payload = TerminalCellsDTO(
            paneID: paneID,
            cols: 2,
            rows: 2,
            cursorX: 1,
            cursorY: 1,
            cursorVisible: true,
            defaultFg: 0xFF_FFFF,
            defaultBg: 0,
            cells: cells
        )

        let data = try MuxyCodec.encode(.response(MuxyResponse(id: "c1", result: .terminalCells(payload))))
        let decoded = try MuxyCodec.decode(data)

        guard case let .response(response, _) = decoded,
              case let .terminalCells(roundTripped) = response.result
        else {
            Issue.record("expected terminalCells response")
            return
        }
        #expect(roundTripped.paneID == paneID)
        #expect(roundTripped.cells.count == 4)
        #expect(roundTripped.cells.first?.codepoint == 65)
    }
}
