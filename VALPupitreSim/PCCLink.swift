//
//  PCCLink.swift
//  VALPupitreSim
//

import Foundation
import Network
import Observation

/// The PCC link: the cab's network face towards a PCC (Poste de Commande
/// Centralisé) such as metroSystem. The wire format lives in
/// `PCCProtocol.swift` and is specified in `PCC_API.md`.
///
/// - Advertises the cab over Bonjour (`_valpupitre._tcp`) so PCCs on the
///   network find it unaided, and accepts up to `PCCProtocol.maxSessions`
///   sessions at once.
/// - Streams the cab's state to every session and reports events as they
///   happen. Monitoring needs no permission.
/// - Applies commands only under PCC command (`model.authority == .pcc`), and
///   only from the one session holding control — except applying the
///   emergency brake, which any session may do at any time.
/// - Feeds the model's link watchdog: every line from the controlling session
///   is a heartbeat, and a controller silent for `pccLinkTimeout` loses
///   control.
///
/// Network callbacks are delivered on the main queue, so all of this runs on
/// the main actor alongside the model, in arrival order.
@Observable
final class PCCLink {

    enum ListenerState: Equatable {
        case stopped
        case starting
        case listening
        case waiting(String)    // can't listen yet; Network.framework retries
        case failed(String)
    }

    struct SessionSummary: Identifiable, Equatable {
        let id: Int
        let name: String
        let address: String
        let controlling: Bool
    }

    // MARK: Observed (HUD)
    private(set) var listenerState: ListenerState = .stopped
    private(set) var port: UInt16?
    /// Bonjour name as registered — the system renames on a clash.
    private(set) var serviceName: String?
    private(set) var sessions: [SessionSummary] = []
    /// Rame number shown to PCCs. Change it with `rename(to:)`.
    private(set) var rame: String

    /// Stable identity of this cab, kept across launches.
    let cabID: UUID
    /// Accept connections from this Mac only.
    let loopbackOnly: Bool

    var controllerName: String? { sessions.first(where: \.controlling)?.name }

    /// The name advertised over Bonjour before any rename by the system.
    var advertisedName: String {
        Self.truncated("Rame \(rame) — \(Self.computerName)", maxBytes: 63)
    }

    private static let computerName: String = {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }()

    // MARK: Private state
    private let model: SimulationModel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferredPort: UInt16
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var live: [Session] = []
    @ObservationIgnored private var controller: Session?
    @ObservationIgnored private var nextSessionID = 0
    @ObservationIgnored private var watched: Watched?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// UserDefaults keys. Each can also be given at launch, e.g.
    /// `-pccRame 302` or `-pccAuthority pcc`.
    enum Key {
        static let cabID = "pccCabID"
        static let rame = "pccRame"
        static let authority = "pccAuthority"
        static let port = "pccPort"
        static let loopbackOnly = "pccLoopbackOnly"
    }

    init(model: SimulationModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        if let stored = defaults.string(forKey: Key.cabID).flatMap(UUID.init(uuidString:)) {
            cabID = stored
        } else {
            cabID = UUID()
            defaults.set(cabID.uuidString, forKey: Key.cabID)
        }
        let storedRame = defaults.string(forKey: Key.rame)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        rame = storedRame.flatMap { $0.isEmpty ? nil : String($0.prefix(16)) }
            ?? Self.defaultRame(for: cabID)
        loopbackOnly = defaults.bool(forKey: Key.loopbackOnly)
        preferredPort = defaults.object(forKey: Key.port) != nil
            ? UInt16(clamping: defaults.integer(forKey: Key.port))
            : PCCProtocol.defaultPort
        // The COMMANDE selector stays where it was left, like the real key.
        if let stored = defaults.string(forKey: Key.authority)
            .flatMap(SimulationModel.CommandAuthority.init(rawValue:)) {
            model.authority = stored
        }
    }

    // MARK: Lifecycle

    func start() {
        guard listener == nil else { return }
        startListener(port: preferredPort)
    }

    func stop() {
        for session in live { close(session) }
        listener?.cancel()
        listener = nil
        port = nil
        serviceName = nil
        listenerState = .stopped
    }

    /// Renumber the rame: re-advertised at once and announced to every
    /// session.
    func rename(to newLabel: String) {
        let label = String(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !label.isEmpty, label != rame else { return }
        rame = label
        defaults.set(label, forKey: Key.rame)
        listener?.service = makeService()
        broadcast(PCCEventBody(event: "cab", rame: label))
    }

    /// Once per physics frame, after `model.update(dt:)`: drop a silent
    /// controller, report what changed, and stream state to whoever is due.
    func tick() {
        let now = Self.now
        if let holder = controller, now - holder.lastHeard > model.pccLinkTimeout {
            controller = nil
            announceControl(reason: "timeout")
        }
        emitEvents()
        publishState(now: now)
    }

    // MARK: Listener

    private func startListener(port requested: UInt16) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if loopbackOnly { parameters.requiredInterfaceType = .loopback }

        let listener: NWListener
        do {
            if requested == 0 {
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters,
                                          on: NWEndpoint.Port(rawValue: requested) ?? .any)
            }
        } catch {
            listenerState = .failed(String(describing: error))
            return
        }
        listener.service = makeService()
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, let listener, listener === self.listener else { return }
                self.listener(listener, changedTo: state, requestedPort: requested)
            }
        }
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            MainActor.assumeIsolated {
                if case .add(let endpoint) = change,
                   case .service(let name, _, _, _) = endpoint {
                    self?.serviceName = name
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                self.accept(connection)
            }
        }
        self.listener = listener
        listenerState = .starting
        listener.start(queue: .main)
    }

    private func listener(_ listener: NWListener, changedTo state: NWListener.State,
                          requestedPort: UInt16) {
        switch state {
        case .ready:
            port = listener.port?.rawValue
            listenerState = .listening
        case .waiting(let error):
            listenerState = .waiting(String(describing: error))
        case .failed(let error):
            listener.cancel()
            self.listener = nil
            port = nil
            if requestedPort != 0, case .posix(.EADDRINUSE) = error {
                // Another cab on this Mac has the preferred port: take any
                // free one. PCCs find the cab by Bonjour, not by port number.
                startListener(port: 0)
            } else {
                listenerState = .failed(String(describing: error))
            }
        default:
            break
        }
    }

    private func makeService() -> NWListener.Service {
        var txt = NWTXTRecord()
        txt["proto"] = String(PCCProtocol.version)
        txt["id"] = cabID.uuidString
        txt["rame"] = rame
        txt["app"] = "VALPupitreSim"
        return NWListener.Service(name: advertisedName, type: PCCProtocol.serviceType,
                                  domain: nil, txtRecord: txt)
    }

    // MARK: Sessions

    /// One client connection.
    private final class Session {
        let id: Int
        let connection: NWConnection
        let address: String
        var name: String
        var stateInterval: Double = 1 / PCCProtocol.defaultStateRateHz
        var nextStateAt: Double = 0
        var seq = 0
        var lastHeard: Double
        var inbound = Data()
        var inFlight = 0
        var ready = false
        var closed = false

        init(id: Int, connection: NWConnection, now: Double) {
            self.id = id
            self.connection = connection
            if case .hostPort(let host, _) = connection.endpoint {
                address = "\(host)"
            } else {
                address = "\(connection.endpoint)"
            }
            name = address
            lastHeard = now
        }
    }

    private func accept(_ connection: NWConnection) {
        guard live.count < PCCProtocol.maxSessions else {
            refuse(connection)
            return
        }
        nextSessionID += 1
        let session = Session(id: nextSessionID, connection: connection, now: Self.now)
        live.append(session)
        connection.stateUpdateHandler = { [weak self, weak session] state in
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                self.session(session, changedTo: state)
            }
        }
        connection.start(queue: .main)
        publishSessions()
    }

    /// Turn away a connection beyond the session limit, saying why.
    private func refuse(_ connection: NWConnection) {
        let message = frame("error", PCCErrorBody(
            error: PCCErrorCode.tooManySessions.rawValue,
            message: "this cab already has \(PCCProtocol.maxSessions) sessions"))
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: message, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            case .failed, .cancelled:
                connection.stateUpdateHandler = nil
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func session(_ session: Session, changedTo state: NWConnection.State) {
        switch state {
        case .ready:
            session.ready = true
            session.lastHeard = Self.now
            session.nextStateAt = Self.now
            send("hello", helloBody(), to: session)
            receive(on: session)
        case .failed, .cancelled, .waiting:
            close(session)
        default:
            break
        }
    }

    private func receive(on session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self, weak session] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let session, !session.closed else { return }
                if let data, !data.isEmpty { self.consume(data, from: session) }
                guard !session.closed else { return }
                if error != nil {
                    self.close(session)
                } else if isComplete {
                    // The client has finished sending; answer what it sent.
                    self.close(session, flushing: true)
                } else {
                    self.receive(on: session)
                }
            }
        }
    }

    /// Split inbound bytes into lines; LF ends a line, a CR before it is
    /// dropped, blank lines are skipped.
    private func consume(_ data: Data, from session: Session) {
        session.inbound.append(data)
        while let newline = session.inbound.firstIndex(of: 0x0A) {
            var line = session.inbound[session.inbound.startIndex..<newline]
            session.inbound.removeSubrange(session.inbound.startIndex...newline)
            if line.last == 0x0D { line = line.dropLast() }
            guard !line.isEmpty else { continue }
            handle(Data(line), from: session)
            if session.closed { return }
        }
        if session.inbound.count > PCCProtocol.maxLineBytes {
            send("error", PCCErrorBody(error: PCCErrorCode.lineTooLong.rawValue,
                                       message: "lines are limited to \(PCCProtocol.maxLineBytes) bytes"),
                 to: session)
            close(session, flushing: true)
        }
    }

    /// Drop a session. `cancel()` discards anything still queued, so a
    /// session that is owed a reply is closed `flushing`: a FIN goes out
    /// behind the queued lines and the connection is torn down once it has
    /// been sent — or after a few seconds, if the client has stopped reading.
    private func close(_ session: Session, flushing: Bool = false) {
        guard !session.closed else { return }
        session.closed = true
        let connection = session.connection
        connection.stateUpdateHandler = nil
        if flushing {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        } else {
            connection.cancel()
        }
        live.removeAll { $0 === session }
        if controller === session {
            controller = nil
            announceControl(reason: "disconnected")
        } else {
            publishSessions()
        }
    }

    // MARK: Requests

    private func handle(_ bytes: Data, from session: Session) {
        // Any line at all proves the session is alive.
        session.lastHeard = Self.now
        if session === controller { model.pccHeartbeat() }

        guard let message = try? decoder.decode(PCCInbound.self, from: bytes) else {
            send("error", PCCErrorBody(error: PCCErrorCode.badMessage.rawValue,
                                       message: "expected one JSON object with a \"type\" per line"),
                 to: session)
            return
        }
        switch message.type {
        case "hello":   hello(message, from: session)
        case "acquire": acquire(message, from: session)
        case "release": release(message, from: session)
        case "command": command(message, from: session)
        case "line":    line(message, from: session)
        case "traffic": traffic(message, from: session)
        case "ping":    send("pong", PCCPongBody(id: message.id), to: session)
        default:
            reply(message.id, to: session, refusal: Refusal(
                .unknownType, "unknown message type \"\(message.type)\""))
        }
    }

    private func hello(_ message: PCCInbound, from session: Session) {
        if let version = message.protocol, version != PCCProtocol.version {
            reply(message.id, to: session, refusal: Refusal(
                .unsupportedProtocol, "this cab speaks protocol \(PCCProtocol.version)"))
            close(session, flushing: true)
            return
        }
        if let name = message.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            session.name = String(name.prefix(64))
        }
        if let rate = message.stateRateHz, rate.isFinite {
            let range = PCCProtocol.stateRateRange
            session.stateInterval = 1 / min(max(rate, range.lowerBound), range.upperBound)
        }
        reply(message.id, to: session)
        publishSessions()
    }

    private func acquire(_ message: PCCInbound, from session: Session) {
        if controller === session {
            reply(message.id, to: session)
            return
        }
        if let holder = controller, message.force != true {
            reply(message.id, to: session, refusal: Refusal(
                .controlHeld, "control is held by \(holder.name)", holder: holder.name))
            return
        }
        let preempting = controller != nil
        controller = session
        model.pccHeartbeat()
        reply(message.id, to: session)
        announceControl(reason: preempting ? "preempted" : "acquired")
    }

    private func release(_ message: PCCInbound, from session: Session) {
        guard controller === session else {
            reply(message.id, to: session, refusal: Refusal(
                .notController, "this session does not hold control"))
            return
        }
        controller = nil
        reply(message.id, to: session)
        announceControl(reason: "released")
    }

    private func command(_ message: PCCInbound, from session: Session) {
        guard let name = message.command, let command = PCCCommand(rawValue: name) else {
            reply(message.id, to: session, refusal: Refusal(
                .unknownCommand, "unknown command \"\(message.command ?? "")\""))
            return
        }
        // The safety exception: any session may apply the emergency brake,
        // under either authority — a PCC can always stop the train.
        let applyingBrake = command == .emergencyBrake && message.value?.asBool == true
        if !applyingBrake, let refusal = commandRefusal(for: session) {
            reply(message.id, to: session, refusal: refusal)
            return
        }
        reply(message.id, to: session, refusal: execute(command, value: message.value))
    }

    /// Why `session` may not command the cab right now, or nil if it may:
    /// commands need PCC authority and control.
    private func commandRefusal(for session: Session) -> Refusal? {
        guard model.authority == .pcc else {
            return Refusal(.localAuthority, "the cab is under local command")
        }
        guard controller === session else {
            return Refusal(.notController,
                           controller.map { "control is held by \($0.name)" } ?? "acquire control first",
                           holder: controller?.name)
        }
        return nil
    }

    /// A PCC lends the cab its line: the rame joins it at `positionM`, from a
    /// stand, and runs on it for as long as the cab stays under PCC command.
    /// Sending the line the rame is already on changes nothing, so a PCC can
    /// send its line whenever it takes control.
    private func line(_ message: PCCInbound, from session: Session) {
        if let refusal = commandRefusal(for: session) {
            reply(message.id, to: session, refusal: refusal)
            return
        }
        guard let body = message.line else {
            reply(message.id, to: session, refusal: Refusal(.badValue, "line is missing"))
            return
        }
        if let problem = Self.problem(with: body) {
            reply(message.id, to: session, refusal: Refusal(.badValue, problem))
            return
        }
        let line = Self.layout(from: body)
        if line.id == model.layout.id {
            reply(message.id, to: session)
            return
        }
        guard let start = message.positionM, start.isFinite, start >= 0,
              line.isLoop ? start < line.lengthM : start <= line.lengthM else {
            reply(message.id, to: session, refusal: Refusal(
                .badValue, "positionM must lie on the line"))
            return
        }
        guard model.speedMS < 0.1 else {
            reply(message.id, to: session, refusal: Refusal(
                .notStopped, "the rame joins a line from a stand"))
            return
        }
        model.joinLine(line, at: start)
        reply(message.id, to: session)
    }

    /// The PCC reports the other rames on its line, for the cab to show on
    /// its 3D views. Each report replaces the last; the whole report is
    /// refused if any rame in it is malformed.
    private func traffic(_ message: PCCInbound, from session: Session) {
        if let refusal = commandRefusal(for: session) {
            reply(message.id, to: session, refusal: refusal)
            return
        }
        guard let trains = message.trains else {
            reply(message.id, to: session, refusal: Refusal(.badValue, "trains is missing"))
            return
        }
        guard trains.count <= PCCProtocol.maxTrafficTrains else {
            reply(message.id, to: session, refusal: Refusal(
                .badValue, "at most \(PCCProtocol.maxTrafficTrains) trains"))
            return
        }
        let line = model.layout
        var rames: [OtherRame] = []
        for train in trains {
            let label = train.rame.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.count <= 16 else {
                reply(message.id, to: session, refusal: Refusal(
                    .badValue, "rame must be 1–16 characters"))
                return
            }
            let position = train.positionM
            guard position.isFinite, position >= 0,
                  line.isLoop ? position < line.lengthM : position <= line.lengthM else {
                reply(message.id, to: session, refusal: Refusal(
                    .badValue, "rame \(label) lies off the line"))
                return
            }
            let speed = train.speedMS ?? 0
            guard speed.isFinite, (0...100).contains(speed) else {
                reply(message.id, to: session, refusal: Refusal(
                    .badValue, "speedMS of rame \(label) must be between 0 and 100"))
                return
            }
            let sense: SimulationModel.Direction
            switch train.sense?.uppercased() {
            case nil, "AV": sense = .forward
            case "AR":      sense = .reverse
            default:
                reply(message.id, to: session, refusal: Refusal(
                    .badValue, "sense of rame \(label) must be \"AV\" or \"AR\""))
                return
            }
            rames.append(OtherRame(rame: label, positionM: position, speedMS: speed, sense: sense))
        }
        // In rame order, so each keeps its place on the views from one
        // report to the next whatever order the PCC lists them in.
        rames.sort { $0.rame.localizedStandardCompare($1.rame) == .orderedAscending }
        model.setTraffic(rames)
        reply(message.id, to: session)
    }

    /// What is wrong with a PCC's line description, or nil when it is usable.
    private static func problem(with body: PCCLineBody) -> String? {
        let id = body.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 64, id != TrackLayout.testTrack.id else {
            return "line id must be 1–64 characters and not \"\(TrackLayout.testTrack.id)\""
        }
        guard body.lengthM.isFinite, (50...100_000).contains(body.lengthM) else {
            return "lengthM must be between 50 and 100000"
        }
        func onLine(_ m: Double) -> Bool {
            m.isFinite && m >= 0 && (body.loop ? m < body.lengthM : m <= body.lengthM)
        }
        guard body.stations.count <= 64 else { return "at most 64 stations" }
        for station in body.stations {
            let name = station.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 64 else {
                return "station names must be 1–64 characters"
            }
            guard onLine(station.positionM) else {
                return "station \"\(name)\" lies off the line"
            }
        }
        let blocks = body.blocks ?? []
        guard blocks.count <= 512 else { return "at most 512 blocks" }
        for block in blocks where !onLine(block.startM) || !(block.lengthM > 0 && block.lengthM.isFinite) {
            return "block \(block.id) lies off the line"
        }
        return nil
    }

    private static func layout(from body: PCCLineBody) -> TrackLayout {
        let id = body.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = body.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TrackLayout(
            id: id,
            name: name.isEmpty ? id : String(name.prefix(64)),
            lengthM: body.lengthM,
            isLoop: body.loop,
            stations: body.stations
                .map { TrackLayout.Station(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                           positionM: $0.positionM) }
                .sorted { $0.positionM < $1.positionM },
            blocks: (body.blocks ?? []).map {
                TrackLayout.Block(id: $0.id, startM: $0.startM, lengthM: $0.lengthM)
            })
    }

    private func lineBody(_ layout: TrackLayout) -> PCCLineBody {
        PCCLineBody(
            id: layout.id,
            name: layout.name,
            lengthM: layout.lengthM,
            loop: layout.isLoop,
            stationToleranceM: model.stationTolerance,
            stations: layout.stations.enumerated().map { i, station in
                PCCLineBody.Station(index: i, name: station.name,
                                    marker: String(format: "P%.0f", station.positionM / 10),
                                    positionM: station.positionM)
            },
            blocks: layout.blocks.isEmpty ? nil : layout.blocks.map {
                PCCLineBody.Block(id: $0.id, startM: $0.startM, lengthM: $0.lengthM)
            })
    }

    private struct Refusal {
        let code: PCCErrorCode
        let message: String
        var holder: String? = nil

        init(_ code: PCCErrorCode, _ message: String, holder: String? = nil) {
            self.code = code
            self.message = message
            self.holder = holder
        }
    }

    /// Apply one command to the model. Returns why it was refused, or nil.
    private func execute(_ command: PCCCommand, value: PCCValue?) -> Refusal? {
        switch command {
        case .kg:   return setSwitch(command, value) { model.kg = $0 }
        case .kibs: return setSwitch(command, value) { model.kibs = $0 }
        case .kph:  return setSwitch(command, value) { model.kph = $0 }
        case .pa:   return setSwitch(command, value) { model.paMode = $0 }
        case .nav:  return setSwitch(command, value) { model.paShuttle = $0 }
        case .emergencyBrake:
            return setSwitch(command, value) { on in
                if on { model.applyEmergencyBrake(.pcc) } else { model.emergencyBrake = false }
            }
        case .reverser:
            guard let value, let position = Self.reverserPosition(value) else {
                return Refusal(.badValue, "reverser takes \"AV\", \"0\" or \"AR\" (or 1, 0, -1)")
            }
            // A remote reverser only moves at a stand: the PCC can't feel
            // the train, and the simulator reverses a rolling train outright.
            if position != model.direction && model.speedMS >= 0.1 {
                return Refusal(.notStopped, "the reverser only moves at a stand")
            }
            model.direction = position
        case .masterController:
            guard let demand = value?.asNumber else {
                return Refusal(.badValue, "masterController takes a number from -1 to 1")
            }
            model.masterController = max(-1, min(1, demand))
        case .kacop:
            model.pressKacop()
        case .doorsOpen:
            guard let name = value?.asString, let side = Self.doorSides(name) else {
                return Refusal(.badValue, "doorsOpen takes \"left\", \"right\" or \"both\"")
            }
            guard model.canOperateDoors else { return Self.doorsInterlocked }
            model.pressDoorOpen(left: side.left, right: side.right)
        case .doorsClose:
            guard model.canOperateDoors else { return Self.doorsInterlocked }
            model.pressDoorClose()
        case .limit:
            // No value clears the stopping point.
            guard let value else {
                model.stopLimitM = nil
                return nil
            }
            let line = model.layout
            guard let position = value.asNumber, position >= 0,
                  line.isLoop ? position < line.lengthM : position <= line.lengthM else {
                return Refusal(.badValue, "limit takes a position on the line, or no value to clear it")
            }
            model.stopLimitM = position
        }
        return nil
    }

    private func setSwitch(_ command: PCCCommand, _ value: PCCValue?,
                           _ apply: (Bool) -> Void) -> Refusal? {
        guard let on = value?.asBool else {
            return Refusal(.badValue, "\(command.rawValue) takes true or false")
        }
        apply(on)
        return nil
    }

    private static let doorsInterlocked = Refusal(
        .doorsInterlocked, "doors only work stopped at a platform with KG on")

    private static func reverserPosition(_ value: PCCValue) -> SimulationModel.Direction? {
        switch value {
        case .string(let s):
            return SimulationModel.Direction(rawValue: s.uppercased())
        case .number(let n):
            switch n {
            case 1:  return .forward
            case 0:  return .neutral
            case -1: return .reverse
            default: return nil
            }
        case .bool:
            return nil
        }
    }

    private static func doorSides(_ side: String) -> (left: Bool, right: Bool)? {
        switch side.lowercased() {
        case "left":  return (true, false)
        case "right": return (false, true)
        case "both":  return (true, true)
        default:      return nil
        }
    }

    // MARK: Outbound

    private func reply(_ id: PCCValue?, to session: Session, refusal: Refusal? = nil) {
        send("result", PCCResultBody(id: id, ok: refusal == nil,
                                     error: refusal?.code.rawValue,
                                     message: refusal?.message,
                                     holder: refusal?.holder),
             to: session)
    }

    /// Tell every session who holds control now, and why it changed.
    private func announceControl(reason: String) {
        // The other rames were the outgoing controller's picture.
        model.clearTraffic()
        for session in live where session.ready {
            send("event", PCCEventBody(event: "control", holder: controller?.name,
                                       you: controller === session, reason: reason),
                 to: session)
        }
        publishSessions()
    }

    private func broadcast(_ event: PCCEventBody) {
        for session in live where session.ready {
            send("event", event, to: session)
        }
    }

    private func send<Body: Encodable>(_ type: String, _ body: Body, to session: Session) {
        guard session.ready, !session.closed else { return }
        session.inFlight += 1
        session.connection.send(content: frame(type, body), completion: .contentProcessed {
            [weak self, weak session] error in
            MainActor.assumeIsolated {
                guard let session else { return }
                session.inFlight -= 1
                if error != nil { self?.close(session) }
            }
        })
    }

    /// One wire line: `type` first, then the body's fields in sorted order.
    private func frame<Body: Encodable>(_ type: String, _ body: Body) -> Data {
        var line = Data(#"{"type":""#.utf8)
        line.append(Data(type.utf8))
        line.append(UInt8(ascii: "\""))
        let encoded = (try? encoder.encode(body)) ?? Data("{}".utf8)
        if encoded.count > 2 {
            line.append(UInt8(ascii: ","))
            line.append(encoded.dropFirst())
        } else {
            line.append(UInt8(ascii: "}"))
        }
        line.append(0x0A)
        return line
    }

    // MARK: Events

    /// What the event stream watches, as of the previous tick.
    private struct Watched: Equatable {
        var authority: SimulationModel.CommandAuthority
        var lineID: String
        var emergencyBrake: Bool
        var emergencyCause: SimulationModel.EmergencyCause?
        var vigilanceWarning: Bool
        var berthedStation: Int?
        var doorsOpen: Bool
    }

    private func emitEvents() {
        let now = Watched(authority: model.authority,
                          lineID: model.layout.id,
                          emergencyBrake: model.emergencyBrake,
                          emergencyCause: model.emergencyBrakeCause,
                          vigilanceWarning: model.deadmanWarning,
                          berthedStation: model.paBerthedStation,
                          doorsOpen: model.voyantPort)
        defer { watched = now }
        guard let before = watched, before != now else { return }

        if now.authority != before.authority {
            defaults.set(now.authority.rawValue, forKey: Key.authority)
            broadcast(PCCEventBody(event: "authority", authority: now.authority.rawValue))
        }
        if now.lineID != before.lineID {
            broadcast(PCCEventBody(event: "line", line: lineBody(model.layout)))
        }
        if now.emergencyBrake != before.emergencyBrake {
            broadcast(PCCEventBody(event: "emergencyBrake", applied: now.emergencyBrake,
                                   cause: now.emergencyCause?.rawValue))
        }
        if now.vigilanceWarning != before.vigilanceWarning {
            broadcast(PCCEventBody(event: "vigilance", warning: now.vigilanceWarning))
        }
        if now.berthedStation != before.berthedStation {
            if let left = before.berthedStation {
                broadcast(PCCEventBody(event: "paBerth", station: left, berthed: false))
            }
            if let arrived = now.berthedStation {
                broadcast(PCCEventBody(event: "paBerth", station: arrived, berthed: true))
            }
        }
        if now.doorsOpen != before.doorsOpen {
            broadcast(PCCEventBody(event: "doors", open: now.doorsOpen))
        }
    }

    // MARK: State stream

    private func publishState(now: Double) {
        for session in live where session.ready && now >= session.nextStateAt {
            // Stay on the rate's grid; resynchronise after a long stall
            // instead of bursting to catch up.
            session.nextStateAt = now - session.nextStateAt > session.stateInterval
                ? now + session.stateInterval
                : session.nextStateAt + session.stateInterval
            // A client that stops reading misses samples (a gap in `seq`)
            // instead of growing the send queue without bound.
            session.seq += 1
            guard session.inFlight < 32 else { continue }
            send("state", stateBody(for: session), to: session)
        }
    }

    private func stateBody(for session: Session) -> PCCStateBody {
        let m = model
        let next = m.nextStationAhead
        return PCCStateBody(
            seq: session.seq,
            simTimeS: Self.rounded(m.simTime, 3),
            control: .init(authority: m.authority.rawValue,
                           holder: controller?.name,
                           you: controller === session,
                           silenceS: Self.rounded(m.pccLinkSilence, 1)),
            line: .init(id: m.layout.id, loop: m.layout.isLoop),
            motion: .init(positionM: Self.rounded(m.positionM, 3),
                          speedMS: Self.rounded(m.speedMS, 3),
                          accelerationMS2: Self.rounded(m.accelerationMS2, 3),
                          sense: m.runningSense.rawValue),
            cab: .init(kg: m.kg, kibs: m.kibs, kph: m.kph, pa: m.paMode, nav: m.paShuttle,
                       reverser: m.direction.rawValue,
                       masterController: Self.rounded(m.masterController, 3)),
            drive: .init(paActive: m.paActive,
                         demand: Self.rounded(m.effectiveController, 3)),
            voyants: .init(trac: m.voyantTraction, frein: m.voyantFreinage, hm: m.voyantHomme,
                           pm: m.voyantPM, pa: m.voyantPA, port: m.voyantPort,
                           urg: m.voyantUrgence),
            doors: .init(left: Self.rounded(m.doorsLeftOpenness, 3),
                         right: Self.rounded(m.doorsRightOpenness, 3),
                         canOperate: m.canOperateDoors),
            vigilance: .init(timerS: Self.rounded(m.deadmanTimer, 1),
                             warning: m.deadmanWarning),
            emergencyBrake: .init(applied: m.emergencyBrake,
                                  cause: m.emergencyBrakeCause?.rawValue),
            limit: m.stopLimitM.map {
                .init(positionM: Self.rounded($0, 3),
                      distanceM: Self.rounded(m.stopLimitDistance ?? 0, 2))
            },
            pa: .init(target: m.paTargetStation,
                      berthed: m.paBerthedStation,
                      dwellRemainingS: Self.rounded(max(0, m.paDwellRemaining), 1)),
            station: .init(current: m.currentStationIndex,
                           next: next?.index,
                           nextDistanceM: next.map { Self.rounded($0.distanceM, 2) }),
            telemetry: telemetryBody(m.telemetry))
    }

    private func telemetryBody(_ t: RameTelemetry) -> PCCStateBody.Telemetry {
        .init(traction: .init(lineVoltageV: Self.rounded(t.lineVoltageV, 1),
                              lineCurrentA: Self.rounded(t.lineCurrentA, 1),
                              armatureCurrentA: Self.rounded(t.armatureCurrentA, 1),
                              fieldCurrentA: Self.rounded(t.fieldCurrentA, 2),
                              chopperDuty: Self.rounded(t.chopperDuty, 3),
                              tractionCurrentA: Self.rounded(t.tractionCurrentA, 1),
                              torquePct: Self.rounded(t.torquePct, 1),
                              regenerating: t.regenerating,
                              fieldWeakened: t.fieldWeakened),
              auxiliaries: .init(converterV: Self.rounded(t.converterV, 1),
                                 batteryV: Self.rounded(t.batteryV, 2),
                                 lightingA: Self.rounded(t.lightingA, 1),
                                 compressor: t.compressorRunning,
                                 mainReservoirBar: Self.rounded(t.mainReservoirBar, 2),
                                 brakeBoxC: Self.rounded(t.brakeBoxC, 1)))
    }

    private func helloBody() -> PCCHelloBody {
        let m = model
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        return PCCHelloBody(
            protocol: PCCProtocol.version,
            app: "VALPupitreSim",
            appVersion: version as? String ?? "?",
            cab: .init(id: cabID.uuidString, rame: rame, name: serviceName ?? advertisedName),
            authority: m.authority.rawValue,
            line: lineBody(m.layout),
            geometry: .init(lengthM: Self.rounded(SimulationModel.avEndM + SimulationModel.arEndM, 3),
                            avEndM: Self.rounded(SimulationModel.avEndM, 3),
                            arEndM: Self.rounded(SimulationModel.arEndM, 3)),
            limits: .init(maxSpeedMS: m.maxSpeedMS,
                          maxAccelerationMS2: m.maxAcceleration,
                          serviceBrakeMS2: m.maxServiceBrake,
                          emergencyBrakeMS2: m.emergencyBrakeRate,
                          paCruiseMS: m.paCruiseMS,
                          paDwellS: m.paDwellTime,
                          deadmanWarnS: m.deadmanWarnAt,
                          deadmanLimitS: m.deadmanLimit,
                          doorTravelS: m.doorTravelTime),
            link: .init(stateRateHz: PCCProtocol.defaultStateRateHz,
                        heartbeatS: PCCProtocol.heartbeatInterval,
                        timeoutS: m.pccLinkTimeout),
            commands: PCCCommand.allCases.map(\.rawValue))
    }

    // MARK: Helpers

    private func publishSessions() {
        sessions = live.map {
            SessionSummary(id: $0.id, name: $0.name, address: $0.address,
                           controlling: $0 === controller)
        }
        // A PCC may drive this cab while its window is hidden: keep App Nap
        // from throttling the physics loop for as long as anyone is connected.
        if live.isEmpty, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        } else if !live.isEmpty, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "A PCC is connected to the cab")
        }
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Round for the wire, folding -0 into 0.
    private static func rounded(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10, Double(places))
        let r = (value * scale).rounded() / scale
        return r == 0 ? 0 : r
    }

    /// A default rame number in 301…399, stable for this cab, so cabs left
    /// at their defaults rarely clash in a PCC's fleet.
    private static func defaultRame(for id: UUID) -> String {
        let sum = withUnsafeBytes(of: id.uuid) { $0.reduce(0) { $0 + Int($1) } }
        return String(301 + sum % 99)
    }

    /// Bonjour names are capped at 63 bytes of UTF-8.
    private static func truncated(_ text: String, maxBytes: Int) -> String {
        var out = ""
        for character in text {
            guard out.utf8.count + String(character).utf8.count <= maxBytes else { break }
            out.append(character)
        }
        return out
    }
}
