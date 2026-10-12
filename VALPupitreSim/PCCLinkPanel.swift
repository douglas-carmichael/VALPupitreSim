//
//  PCCLinkPanel.swift
//  VALPupitreSim
//

import SwiftUI

/// Detail of the PCC link, opened from the HUD's PCC pill: how PCCs find
/// this cab, the rame number they see, and who is connected.
struct PCCLinkPanel: View {
    let link: PCCLink
    let model: SimulationModel
    @State private var rameDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIAISON PCC")
                .font(.system(size: 13, weight: .black))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    caption("Service")
                    detail(link.serviceName ?? link.advertisedName)
                }
                GridRow {
                    caption("Bonjour")
                    detail(PCCProtocol.serviceType)
                }
                GridRow {
                    caption("Écoute")
                    detail(listenerText)
                }
                GridRow {
                    caption("Rame n°")
                    TextField("301", text: $rameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit {
                            link.rename(to: rameDraft)
                            rameDraft = link.rame
                        }
                        .help("Numéro de rame présenté aux PCC — Entrée pour appliquer")
                }
                GridRow {
                    caption("Identifiant")
                    detail(link.cabID.uuidString)
                        .textSelection(.enabled)
                }
            }

            Divider()

            Text("PCC CONNECTÉS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            if link.sessions.isEmpty {
                Text("Aucun")
                    .font(.system(size: 11))
            } else {
                ForEach(link.sessions) { session in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.controlling ? Color.green : Color.yellow)
                            .frame(width: 7, height: 7)
                        Text(session.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text(session.address)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(session.controlling ? "COMMANDE" : "SURVEILLANCE")
                            .font(.system(size: 9, weight: .black))
                    }
                }
            }

            Divider()

            Text("""
            En commande PCC, le pupitre est verrouillé : seul l'ARRÊT reste actif. \
            Si aucun PCC en commande ne se manifeste pendant \
            \(Int(model.pccLinkTimeout)) s, le frein d'urgence est serré \
            (perte de liaison PCC).
            """)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 400)
        .onAppear { rameDraft = link.rame }
    }

    private var listenerText: String {
        switch link.listenerState {
        case .stopped:
            return "arrêtée"
        case .starting:
            return "démarrage…"
        case .listening:
            let port = link.port.map(String.init) ?? "?"
            return link.loopbackOnly
                ? "port \(port) · ce Mac uniquement"
                : "port \(port) · réseau local"
        case .waiting(let reason):
            return "en attente — \(reason)"
        case .failed(let reason):
            return "en défaut — \(reason)"
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
    }
}
