//
//  ContentView.swift
//  VALPupitreSim
//

import SwiftUI

struct ContentView: View {
    let model: SimulationModel
    @State private var audio = AudioEngine()
    @State private var hid: HIDInputManager?
    @State private var pcc: PCCLink?
    @State private var audioMuted: Bool = false
    @State private var showGuide: Bool = false
    @State private var showPCCPanel: Bool = false
    @Environment(\.openWindow) private var openWindow

    init(model: SimulationModel = SimulationModel()) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            stationBar
            TrackOverview3DView(model: model)
                .frame(height: 90)
                .background(Color.black)
            Train3DView(model: model)
                .frame(minHeight: 320)
                .background(Color.black)
            PupitreView(model: model)
        }
        .background(Color.black)
        .sheet(isPresented: $showGuide) { OperatorGuideView() }
        .onAppear {
            audio.start()
            model.onDoorChime = { [audio] in audio.triggerDoorChime() }
            let h = HIDInputManager(model: model)
            h.start()
            hid = h
            let link = PCCLink(model: model)
            link.start()
            pcc = link
        }
        .task { await runPhysicsLoop() }
    }

    // MARK: HUD

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label("VAL 206 SIMULATEUR", systemImage: "tram.fill")
                .font(.system(size: 13, weight: .bold))
            guideButton
            cabViewButton
            Spacer()
            metric("POSITION", value: model.positionLabel)
            metric("VITESSE", value: String(format: "%5.1f km/h", model.speedKMH))
            metric("MAN. T/F", value: String(format: "%+0.2f", model.masterController))
            if model.voyantPA {
                Text(model.paActive ? "PA" : "PA STBY")
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(model.paActive ? Color.mint : Color.mint.opacity(0.35))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            authoritySelector
            soundToggle
            directionBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.95))
        .foregroundStyle(.white)
    }

    private var stationBar: some View {
        HStack(spacing: 18) {
            if let here = model.currentStationName {
                pill("STATION", value: here, tint: .green)
            } else if let next = model.nextStation {
                pill("PROCHAIN ARRÊT",
                     value: String(format: "%@  ·  %.0f m", next.name, next.distanceM),
                     tint: .cyan)
            } else {
                pill("LIGNE", value: "FIN DE PARCOURS", tint: .gray)
            }
            if let limit = model.stopLimitDistance {
                pill("POINT D'ARRÊT", value: String(format: "%.0f m", max(0, limit)),
                     tint: limit < 30 ? .red : .orange)
            }
            if model.emergencyBrake, let cause = model.emergencyBrakeCause, cause != .cab {
                pill("FREIN D'URGENCE", value: emergencyCauseText(cause), tint: .red)
            }
            Spacer()
            pill("PUPITRE USB",
                 value: hid?.connectedDeviceName ?? "non détecté",
                 tint: hid?.connectedDeviceName == nil ? .gray : .yellow)
            pccPill
            if model.deadmanWarning {
                pill("VIGILANCE", value: "APPUYEZ SUR KACOP", tint: .red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color(white: 0.08))
        .foregroundStyle(.white)
        .font(.system(size: 11, weight: .semibold))
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.semibold))
        }
    }

    private func pill(_ title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.85))
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private var guideButton: some View {
        Button {
            showGuide = true
        } label: {
            Image(systemName: "book.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 22)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Guide d'exploitation")
    }

    private var cabViewButton: some View {
        Button {
            openWindow(id: "cab-view")
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "video.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("VUE CABINE")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.cyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Ouvrir la vue cabine dans une autre fenêtre")
    }

    private var soundToggle: some View {
        Button {
            audioMuted.toggle()
            audio.setMuted(audioMuted)
        } label: {
            Image(systemName: audioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(audioMuted ? Color.red : Color.white)
                .frame(width: 28, height: 22)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(audioMuted ? "Réactiver l'audio" : "Couper l'audio")
    }

    private var directionBadge: some View {
        Text(model.direction.rawValue)
            .font(.system(size: 12, weight: .black))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(model.direction == .neutral ? Color.gray : Color.orange)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: PCC link

    /// The COMMANDE selector: who drives the cab, the pupitre or the PCC.
    private var authoritySelector: some View {
        HStack(spacing: 6) {
            Text("COMMANDE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 0) {
                ForEach(SimulationModel.CommandAuthority.allCases, id: \.self) { authority in
                    let selected = model.authority == authority
                    Button {
                        model.authority = authority
                    } label: {
                        Text(authority == .local ? "LOCALE" : "PCC")
                            .font(.system(size: 10, weight: .black))
                            .frame(width: 52, height: 20)
                            .background(selected
                                        ? (authority == .pcc ? Color.green : Color.orange)
                                        : Color.black)
                            .foregroundStyle(selected ? .black : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.gray, lineWidth: 1))
        }
        .help("Commande locale au pupitre, ou commande par le PCC via le réseau")
    }

    private var pccPill: some View {
        Button {
            showPCCPanel.toggle()
        } label: {
            pill("PCC", value: pccSummary, tint: pccTint)
                .lineLimit(1)
                .frame(maxWidth: 300, alignment: .leading)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPCCPanel, arrowEdge: .bottom) {
            if let pcc { PCCLinkPanel(link: pcc, model: model) }
        }
        .help("Liaison PCC — cliquer pour le détail")
    }

    private var pccSummary: String {
        guard let pcc else { return "inactive" }
        switch pcc.listenerState {
        case .failed, .waiting: return "liaison en défaut"
        default: break
        }
        if let holder = pcc.controllerName {
            return model.authority == .pcc ? "\(holder) · commande" : "\(holder) · prêt"
        }
        if model.authority == .pcc { return "EN ATTENTE DU PCC" }
        switch pcc.sessions.count {
        case 0:  return "aucun PCC connecté"
        case 1:  return "\(pcc.sessions[0].name) · surveillance"
        default: return "\(pcc.sessions.count) PCC en surveillance"
        }
    }

    private var pccTint: Color {
        guard let pcc else { return .gray }
        switch pcc.listenerState {
        case .failed, .waiting: return .red
        default: break
        }
        if model.authority == .pcc {
            return pcc.controllerName == nil ? .red : .green
        }
        return pcc.sessions.isEmpty ? .gray : .yellow
    }

    private func emergencyCauseText(_ cause: SimulationModel.EmergencyCause) -> String {
        switch cause {
        case .cab:     return "PUPITRE"
        case .pcc:     return "COMMANDÉ PAR LE PCC"
        case .deadman: return "VEILLE (KACOP)"
        case .pccLink: return "PERTE DE LIAISON PCC"
        case .limit:   return "POINT D'ARRÊT FRANCHI"
        }
    }

    // MARK: Physics + audio loop

    private func runPhysicsLoop() async {
        var lastTick = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            let dt = now.timeIntervalSince(lastTick)
            lastTick = now
            model.update(dt: min(dt, 0.1))
            audio.update(model: model)
            pcc?.tick()
        }
    }
}

#Preview {
    ContentView()
        .frame(minWidth: 1180, minHeight: 800)
}
