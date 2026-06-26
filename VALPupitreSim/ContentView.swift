//
//  ContentView.swift
//  VALPupitreSim
//

import SwiftUI

struct ContentView: View {
    @State private var model = SimulationModel()
    @State private var audio = AudioEngine()
    @State private var hid: HIDInputManager?
    @State private var audioMuted: Bool = false
    @State private var showGuide: Bool = false

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
        }
        .task { await runPhysicsLoop() }
    }

    // MARK: HUD

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label("VAL 206 SIMULATEUR", systemImage: "tram.fill")
                .font(.system(size: 13, weight: .bold))
            guideButton
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
            Spacer()
            pill("PUPITRE USB",
                 value: hid?.connectedDeviceName ?? "non détecté",
                 tint: hid?.connectedDeviceName == nil ? .gray : .yellow)
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
        }
    }
}

#Preview {
    ContentView()
        .frame(minWidth: 1180, minHeight: 800)
}
