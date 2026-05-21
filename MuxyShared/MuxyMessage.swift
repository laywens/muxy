import Foundation

public enum MuxyMessage: Codable, Sendable {
    case request(MuxyRequest, protocolVersion: Int = MuxyProtocolVersion.current)
    case response(MuxyResponse, protocolVersion: Int = MuxyProtocolVersion.current)
    case event(MuxyEvent, protocolVersion: Int = MuxyProtocolVersion.current)

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case type
        case payload
    }

    public var protocolVersion: Int {
        switch self {
        case let .request(_, protocolVersion),
             let .response(_, protocolVersion),
             let .event(_, protocolVersion):
            protocolVersion
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? MuxyProtocolVersion.legacy
        let type = try container.decode(MuxyMessageType.self, forKey: .type)
        switch type {
        case .request: self = try .request(container.decode(MuxyRequest.self, forKey: .payload), protocolVersion: protocolVersion)
        case .response: self = try .response(container.decode(MuxyResponse.self, forKey: .payload), protocolVersion: protocolVersion)
        case .event: self = try .event(container.decode(MuxyEvent.self, forKey: .payload), protocolVersion: protocolVersion)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        switch self {
        case let .request(r, _):
            try container.encode(MuxyMessageType.request, forKey: .type)
            try container.encode(r, forKey: .payload)
        case let .response(r, _):
            try container.encode(MuxyMessageType.response, forKey: .type)
            try container.encode(r, forKey: .payload)
        case let .event(e, _):
            try container.encode(MuxyMessageType.event, forKey: .type)
            try container.encode(e, forKey: .payload)
        }
    }
}

public enum MuxyCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode(_ message: MuxyMessage) throws -> Data {
        try encoder.encode(message)
    }

    public static func decode(_ data: Data) throws -> MuxyMessage {
        try decoder.decode(MuxyMessage.self, from: data)
    }
}
