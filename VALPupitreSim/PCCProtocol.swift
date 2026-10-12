//
//  PCCProtocol.swift
//  VALPupitreSim
//

import Foundation

/// The PCC link wire format: everything that crosses the socket between this
/// cab and a PCC (Poste de Commande Centralisé) such as metroSystem.
/// `PCC_API.md` at the repo root is the specification — change the two
/// together.
///
/// Newline-delimited JSON over TCP, advertised over Bonjour. One object per
/// line, each led by its `type`. Optional fields are omitted rather than sent
/// as null, and receivers ignore fields they don't know, so additive changes
/// keep the protocol version.
nonisolated enum PCCProtocol {
    /// Wire version, also published as the `proto` TXT key. Bumped only for a
    /// change a v1 client could misread.
    static let version = 1
    static let serviceType = "_valpupitre._tcp"
    /// Preferred listening port ("VAL 206"). A cab that finds it taken takes
    /// any free port instead; clients learn the real one from Bonjour.
    static let defaultPort: UInt16 = 5206
    static let defaultStateRateHz: Double = 10
    static let stateRateRange: ClosedRange<Double> = 1...60
    /// How often a controlling PCC should send something, if only a ping.
    static let heartbeatInterval: Double = 1
    static let maxLineBytes = 64 * 1024
    static let maxSessions = 8
    /// Most rames one `traffic` message may report.
    static let maxTrafficTrains = 64
}

/// A JSON scalar exactly as the client sent it: request ids are echoed back
/// verbatim, command values are read according to the command.
nonisolated enum PCCValue: Codable, Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "expected a string, number or boolean")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let b):   try container.encode(b)
        case .number(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        }
    }

    /// A switch position: true/false, or a number read the way metroSystem
    /// sends its commands (above 0.5 is on).
    var asBool: Bool? {
        switch self {
        case .bool(let b):   return b
        case .number(let n): return n.isFinite ? n > 0.5 : nil
        case .string:        return nil
        }
    }

    var asNumber: Double? {
        if case .number(let n) = self, n.isFinite { return n }
        return nil
    }

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// MARK: - Client → cab

/// Every message a client sends, as one flat envelope: `type` names the
/// message and the remaining fields are that message's own.
nonisolated struct PCCInbound: Decodable {
    let type: String
    var id: PCCValue?
    // hello
    var `protocol`: Int?
    var name: String?
    var stateRateHz: Double?
    // acquire
    var force: Bool?
    // command
    var command: String?
    var value: PCCValue?
    // line
    var line: PCCLineBody?
    var positionM: Double?
    // traffic
    var trains: [PCCTrafficTrain]?
}

/// One of the other rames on the PCC's line, in a `traffic` message.
nonisolated struct PCCTrafficTrain: Decodable {
    var rame: String
    var positionM: Double
    var speedMS: Double?
    var sense: String?
}

/// A line description: sent by the cab (in `hello` and the `line` event) for
/// the line it is on, and by a PCC (in a `line` message) to lend the cab its
/// own. `index`, `marker` and `stationToleranceM` are the cab's additions and
/// are ignored on the way in.
nonisolated struct PCCLineBody: Codable {
    var id: String
    var name: String?
    var lengthM: Double
    var loop: Bool
    var stationToleranceM: Double?
    var stations: [Station]
    var blocks: [Block]?

    struct Station: Codable {
        var index: Int?
        var name: String
        var marker: String?
        var positionM: Double
    }

    struct Block: Codable {
        var id: Int
        var startM: Double
        var lengthM: Double
    }
}

/// The commands a PCC may send. Raw values are the wire names.
nonisolated enum PCCCommand: String, CaseIterable {
    case kg
    case kibs
    case kph
    case pa
    case nav
    case reverser
    case masterController
    case kacop
    case doorsOpen
    case doorsClose
    case emergencyBrake
    case limit
}

/// Why a request was refused. Raw values are the wire codes.
nonisolated enum PCCErrorCode: String {
    case badMessage
    case unknownType
    case unsupportedProtocol
    case unknownCommand
    case badValue
    case localAuthority
    case notController
    case controlHeld
    case notStopped
    case doorsInterlocked
    case tooManySessions
    case lineTooLong
}

// MARK: - Cab → client
//
// Outbound bodies leave out `type`: `PCCLink` writes it first on the line,
// ahead of the sorted keys, so a capture reads well in a terminal.

nonisolated struct PCCHelloBody: Encodable {
    let `protocol`: Int
    let app: String
    let appVersion: String
    let cab: Cab
    let authority: String
    let line: PCCLineBody
    let geometry: Geometry
    let limits: Limits
    let link: Link
    let commands: [String]

    struct Cab: Encodable {
        let id: String
        let rame: String
        let name: String
    }

    /// Where the rame lies around its `positionM`: its AV end `avEndM`
    /// above it, its AR end `arEndM` below.
    struct Geometry: Encodable {
        let lengthM: Double
        let avEndM: Double
        let arEndM: Double
    }

    struct Limits: Encodable {
        let maxSpeedMS: Double
        let maxAccelerationMS2: Double
        let serviceBrakeMS2: Double
        let emergencyBrakeMS2: Double
        let paCruiseMS: Double
        let paDwellS: Double
        let deadmanWarnS: Double
        let deadmanLimitS: Double
        let doorTravelS: Double
    }

    struct Link: Encodable {
        let stateRateHz: Double
        let heartbeatS: Double
        let timeoutS: Double
    }
}

nonisolated struct PCCStateBody: Encodable {
    let seq: Int
    let simTimeS: Double
    let control: Control
    let line: Line
    let motion: Motion
    let cab: Cab
    let drive: Drive
    let voyants: Voyants
    let doors: Doors
    let vigilance: Vigilance
    let emergencyBrake: EmergencyBrake
    let limit: Limit?
    let pa: PA
    let station: Station
    let telemetry: Telemetry

    struct Control: Encodable {
        let authority: String
        let holder: String?
        let you: Bool
        let silenceS: Double
    }

    /// Which line the rame is on; the full description comes in `hello` and
    /// the `line` event.
    struct Line: Encodable {
        let id: String
        let loop: Bool
    }

    struct Motion: Encodable {
        let positionM: Double
        let speedMS: Double
        let accelerationMS2: Double
        let sense: String
    }

    struct Cab: Encodable {
        let kg: Bool
        let kibs: Bool
        let kph: Bool
        let pa: Bool
        let nav: Bool
        let reverser: String
        let masterController: Double
    }

    struct Drive: Encodable {
        let paActive: Bool
        let demand: Double
    }

    struct Voyants: Encodable {
        let trac: Bool
        let frein: Bool
        let hm: Bool
        let pm: Bool
        let pa: Bool
        let port: Bool
        let urg: Bool
    }

    struct Doors: Encodable {
        let left: Double
        let right: Double
        let canOperate: Bool
    }

    struct Vigilance: Encodable {
        let timerS: Double
        let warning: Bool
    }

    struct EmergencyBrake: Encodable {
        let applied: Bool
        let cause: String?
    }

    /// The PCC's stopping point, while one is set.
    struct Limit: Encodable {
        let positionM: Double
        let distanceM: Double
    }

    struct PA: Encodable {
        let target: Int?
        let berthed: Int?
        let dwellRemainingS: Double
    }

    struct Station: Encodable {
        let current: Int?
        let next: Int?
        let nextDistanceM: Double?
    }

    /// The rame's instruments (`RameTelemetry`).
    struct Telemetry: Encodable {
        let traction: Traction
        let auxiliaries: Auxiliaries

        struct Traction: Encodable {
            let lineVoltageV: Double
            let lineCurrentA: Double
            let armatureCurrentA: Double
            let fieldCurrentA: Double
            let chopperDuty: Double
            let tractionCurrentA: Double
            let torquePct: Double
            let regenerating: Bool
            let fieldWeakened: Bool
        }

        struct Auxiliaries: Encodable {
            let converterV: Double
            let batteryV: Double
            let lightingA: Double
            let compressor: Bool
            let mainReservoirBar: Double
            let brakeBoxC: Double
        }
    }
}

/// One event; which optional fields are present depends on `event`.
nonisolated struct PCCEventBody: Encodable {
    let event: String
    var authority: String? = nil
    var holder: String? = nil
    var you: Bool? = nil
    var reason: String? = nil
    var applied: Bool? = nil
    var cause: String? = nil
    var warning: Bool? = nil
    var station: Int? = nil
    var berthed: Bool? = nil
    var open: Bool? = nil
    var rame: String? = nil
    var line: PCCLineBody? = nil
}

nonisolated struct PCCResultBody: Encodable {
    let id: PCCValue?
    let ok: Bool
    var error: String? = nil
    var message: String? = nil
    var holder: String? = nil
}

nonisolated struct PCCPongBody: Encodable {
    let id: PCCValue?
}

nonisolated struct PCCErrorBody: Encodable {
    let error: String
    let message: String
}
