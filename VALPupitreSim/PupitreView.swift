//
//  PupitreView.swift
//  VALPupitreSim
//

import SwiftUI

/// The virtual control desk. Layout, left → right:
///   switches • reverser + master controller • VEILLE + voyants/buttons •
///   speedometer + emergency brake.
struct PupitreView: View {
    @Bindable var model: SimulationModel

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            switchPanel
            Divider().overlay(Color.white.opacity(0.15))
            controllerPanel
            Divider().overlay(Color.white.opacity(0.15))
            veillePanel
            Divider().overlay(Color.white.opacity(0.15))
            indicatorsPanel
            Divider().overlay(Color.white.opacity(0.15))
            safetyPanel
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var switchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("INTERRUPTEURS DE CAB")
            HStack(spacing: 14) {
                KeySwitch(label: "KG", helper: "Coupure Générale",
                          state: $model.kg)
                ToggleSwitch(label: "KIBS", helper: "Inhib. B.S.",
                             state: $model.kibs)
                ToggleSwitch(label: "KPH", helper: "Phares",
                             state: $model.kph)
                ToggleSwitch(label: "PA", helper: "Pilote Auto",
                             state: $model.paMode)
                ToggleSwitch(label: "NAV", helper: "Navette",
                             state: $model.paShuttle)
            }
        }
    }

    private var controllerPanel: some View {
        VStack(spacing: 14) {
            Reverser(direction: $model.direction)
            MasterController(value: $model.masterController)
        }
    }

    private var veillePanel: some View {
        VStack(spacing: 12) {
            sectionTitle("VEILLE")
            VeilleButton(pressed: $model.kacop,
                         warning: model.deadmanWarning,
                         fraction: model.deadmanFraction)
            DoorStatus(canOperate: model.canOperateDoors,
                       leftOpen: model.doorsLeftOpenness,
                       rightOpen: model.doorsRightOpenness)
        }
    }

    private var indicatorsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("VOYANTS")
            HStack(spacing: 12) {
                Voyant(label: "TRAC",  on: model.voyantTraction, color: .green)
                Voyant(label: "FREIN", on: model.voyantFreinage, color: .orange)
                Voyant(label: "HM",    on: model.voyantHomme,    color: .yellow)
                Voyant(label: "PM",    on: model.voyantPM,       color: .cyan)
                Voyant(label: "PA",    on: model.voyantPA,       color: .mint)
                Voyant(label: "PORT",  on: model.voyantPort,     color: .blue)
                Voyant(label: "URG",   on: model.voyantUrgence,  color: .red)
            }
            sectionTitle("BOUTONS")
            HStack(spacing: 12) {
                PushButton(label: "PO G", color: .green,
                           pressed: $model.doorOpenLeft)
                PushButton(label: "PO D", color: .green,
                           pressed: $model.doorOpenRight)
                PushButton(label: "FP", color: .red,
                           pressed: $model.doorClose)
                PushButton(label: "AVA", color: .yellow,
                           pressed: $model.hornPressed)
            }
        }
    }

    private var safetyPanel: some View {
        VStack(spacing: 10) {
            Speedometer(kmh: model.speedKMH)
            EmergencyBrake(active: $model.emergencyBrake)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Switches

private struct KeySwitch: View {
    let label: String
    let helper: String
    @Binding var state: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.gradient)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.gray, lineWidth: 2))
                    .frame(width: 52, height: 56)
                Capsule()
                    .fill(LinearGradient(colors: [.white, .gray],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 30)
                    .rotationEffect(.degrees(state ? 45 : -45))
                    .animation(.spring(duration: 0.2), value: state)
            }
            .contentShape(Rectangle())
            .onTapGesture { state.toggle() }
            captionLabel(label, helper: helper)
        }
    }
}

private struct ToggleSwitch: View {
    let label: String
    let helper: String
    @Binding var state: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().strokeBorder(.gray, lineWidth: 1))
                    .frame(width: 30, height: 64)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(white: 0.95), Color(white: 0.55)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 26)
                    .offset(y: state ? -16 : 16)
                    .animation(.spring(duration: 0.18), value: state)
            }
            .contentShape(Rectangle())
            .onTapGesture { state.toggle() }
            captionLabel(label, helper: helper)
        }
    }
}

private struct Reverser: View {
    @Binding var direction: SimulationModel.Direction

    var body: some View {
        VStack(spacing: 4) {
            Text("MANIPULATEUR D'INVERSION")
                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 4) {
                ForEach(SimulationModel.Direction.allCases, id: \.self) { d in
                    Button {
                        direction = d
                    } label: {
                        Text(d.rawValue)
                            .font(.system(size: 13, weight: .black))
                            .frame(width: 42, height: 32)
                            .background(direction == d ? Color.orange : Color.black)
                            .foregroundStyle(direction == d ? .black : .white)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.gray, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Master controller (vertical slider with detents)

private struct MasterController: View {
    @Binding var value: Double

    @State private var startValue: Double = 0
    @State private var isDragging: Bool = false

    private let slotHeight: CGFloat = 200
    private let handleHeight: CGFloat = 38
    private var travel: CGFloat { slotHeight - handleHeight }
    private var halfTravel: CGFloat { travel / 2 }

    var body: some View {
        VStack(spacing: 6) {
            Text("MANIPULATEUR T/F")
                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .center, spacing: 8) {
                VStack {
                    Text("TRAC").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text("0").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("FREIN").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .frame(height: slotHeight)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.gray, lineWidth: 1))
                        .frame(width: 36, height: slotHeight)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(
                            colors: [Color(white: 0.55), Color(white: 0.18)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: 52, height: handleHeight)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.gray, lineWidth: 1))
                        .overlay(Rectangle().fill(.white.opacity(0.4))
                            .frame(width: 36, height: 2))
                        .offset(y: handleOffset)
                        .gesture(dragGesture)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                withAnimation(.spring(duration: 0.25)) {
                                    value = 0
                                }
                            }
                        )
                }
                .frame(width: 52, height: slotHeight)
            }
            Text(String(format: "%+0.2f", value))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var handleOffset: CGFloat {
        halfTravel - CGFloat(value) * halfTravel
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !isDragging {
                    startValue = value
                    isDragging = true
                }
                let startOffset = halfTravel - CGFloat(startValue) * halfTravel
                let newOffset = max(0, min(travel, startOffset + g.translation.height))
                value = Double((halfTravel - newOffset) / halfTravel)
            }
            .onEnded { _ in isDragging = false }
    }
}

// MARK: - Voyants & buttons

private struct Voyant: View {
    let label: String
    let on: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(on ? color : Color.black)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.gray, lineWidth: 1.2))
                .shadow(color: on ? color : .clear, radius: 8)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct PushButton: View {
    let label: String
    let color: Color
    @Binding var pressed: Bool

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(pressed ? color : color.opacity(0.35))
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(.gray, lineWidth: 2))
                .shadow(color: pressed ? color : .clear, radius: 8)
                .scaleEffect(pressed ? 0.9 : 1)
                .animation(.spring(duration: 0.12), value: pressed)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in pressed = true }
                        .onEnded { _ in pressed = false }
                )
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct VeilleButton: View {
    @Binding var pressed: Bool
    let warning: Bool
    let fraction: Double

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 1 - fraction)
                    .stroke(warning ? Color.red : Color.yellow,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(buttonColor)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().strokeBorder(.gray, lineWidth: 2))
                    .shadow(color: warning ? .red : (pressed ? .yellow : .clear),
                            radius: warning ? 14 : 6)
                    .scaleEffect(pressed ? 0.9 : 1)
                Text("ACK")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.black)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
            Text("KACOP / VEILLE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var buttonColor: Color {
        warning ? Color.red : (pressed ? .yellow : Color.yellow.opacity(0.55))
    }
}

private struct DoorStatus: View {
    let canOperate: Bool
    let leftOpen: Double
    let rightOpen: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(canOperate ? "DOORS OK" : "DOORS LOCKED")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(canOperate ? Color.green : Color.white.opacity(0.55))
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 6) {
                doorPip("L", openness: leftOpen)
                doorPip("R", openness: rightOpen)
            }
        }
    }

    private func doorPip(_ label: String, openness: Double) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.gray, lineWidth: 1))
                    .frame(width: 26, height: 12)
                RoundedRectangle(cornerRadius: 1)
                    .fill(openness > 0.5 ? Color.green : Color.orange)
                    .frame(width: CGFloat(openness) * 22, height: 8)
                    .offset(x: -11 + CGFloat(openness) * 11)
            }
        }
    }
}

private struct EmergencyBrake: View {
    @Binding var active: Bool

    var body: some View {
        VStack(spacing: 4) {
            Button {
                active.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [.red, Color(red: 0.5, green: 0, blue: 0)],
                            center: .center, startRadius: 4, endRadius: 50))
                        .frame(width: 72, height: 72)
                        .overlay(Circle().strokeBorder(.yellow, lineWidth: 4))
                        .shadow(color: active ? .red : .clear, radius: 14)
                        .scaleEffect(active ? 0.88 : 1)
                    Text("ARRÊT")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(duration: 0.15), value: active)
            Text("FREIN D'URGENCE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct Speedometer: View {
    let kmh: Double

    private let maxKMH: Double = 80
    private let sweep: Double = 270

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(white: 0.18), .black],
                        center: .center, startRadius: 6, endRadius: 70))
                    .frame(width: 130, height: 130)
                    .overlay(Circle().strokeBorder(.gray, lineWidth: 2))

                ForEach(0...8, id: \.self) { i in
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2, height: 8)
                        .offset(y: -55)
                        .rotationEffect(.degrees(-135 + Double(i) * (sweep / 8)))
                }
                ForEach(0...8, id: \.self) { i in
                    Text("\(i * 10)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .offset(y: -42)
                        .rotationEffect(.degrees(-135 + Double(i) * (sweep / 8)))
                }
                Rectangle()
                    .fill(.red)
                    .frame(width: 2.5, height: 52)
                    .offset(y: -22)
                    .rotationEffect(.degrees(-135 + min(kmh / maxKMH, 1) * sweep))
                    .animation(.easeOut(duration: 0.12), value: kmh)
                Circle().fill(.gray).frame(width: 10, height: 10)
                Text(String(format: "%.0f", kmh))
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .offset(y: 32)
            }
            Text("km/h")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Shared helpers

private func captionLabel(_ label: String, helper: String) -> some View {
    VStack(spacing: 1) {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: false)
        Text(helper)
            .font(.system(size: 8))
            .foregroundStyle(.gray)
            .fixedSize(horizontal: true, vertical: false)
    }
}
