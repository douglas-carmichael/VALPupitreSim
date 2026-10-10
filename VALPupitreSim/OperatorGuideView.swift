//
//  OperatorGuideView.swift
//  VALPupitreSim
//

import SwiftUI

/// Built-in operator's guide / theory of operation. Mirrors the content of
/// `OPERATOR_GUIDE.md` at the project root.
struct OperatorGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    section("1. Introduction", body: introBody)
                    section("2. Théorie de Fonctionnement", body: theoryBody)
                    kSwitchTable
                    voyantTable
                    hidTable
                    section("3. Démarrage Rapide", body: quickStartBody)
                    section("4. Mode Manuel (PM)", body: manualBody)
                    section("5. Mode Automatique (PA)", body: paBody)
                    section("6. Stations et Portes", body: stationsBody)
                    section("7. Veille (KACOP)", body: kacopBody)
                    section("8. Frein d'Urgence", body: emergencyBody)
                    section("9. Audio", body: audioBody)
                    section("10. Entrée USB HID", body: hidBody)
                    section("Glossaire", body: glossaryBody)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 780, minHeight: 640)
        .background(Color(white: 0.08))
        .foregroundStyle(.white)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.cyan)
            Text("Guide d'Exploitation — VAL 206")
                .font(.title2.bold())
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color.black)
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.cyan)
            Text(.init(body))
                .font(.system(size: 13))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tableRow(_ a: String, _ b: String, _ c: String,
                          header: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(a).frame(width: 120, alignment: .leading)
            Text(b).frame(width: 230, alignment: .leading)
            Text(c).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, weight: header ? .bold : .regular))
        .foregroundStyle(header ? Color.yellow.opacity(0.9) : Color.white)
        .padding(.vertical, 2)
    }

    // MARK: Tables

    private var kSwitchTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Interrupteurs « K » (contacteurs)")
                .font(.subheadline.bold())
                .foregroundStyle(.yellow)
            tableRow("Symbole", "Expansion", "Fonction", header: true)
            tableRow("KG", "Coupure Générale", "Alimentation maître")
            tableRow("KIBS", "Inhibition Boucle Sécurité", "Bypass BS (non simulé)")
            tableRow("KPH", "PHares", "Feux avant")
            tableRow("PA", "Pilote Automatique", "Sélection mode auto / manuel")
            tableRow("NAV", "NAVette", "Retournement auto aux terminus (écran seul)")
        }
    }

    private var voyantTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voyants")
                .font(.subheadline.bold())
                .foregroundStyle(.yellow)
            tableRow("Voyant", "Couleur", "Signification", header: true)
            tableRow("TRAC", "vert", "Traction commandée")
            tableRow("FREIN", "orange", "Freinage de service")
            tableRow("HM", "jaune", "Veille acquittée / alerte")
            tableRow("PM", "cyan", "Pilotage Manuel actif")
            tableRow("PA", "menthe", "Pilotage Automatique armé")
            tableRow("PORT", "bleu", "Au moins une porte ouverte")
            tableRow("URG", "rouge", "Frein d'urgence enclenché")
        }
    }

    private var hidTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mapping USB HID par défaut")
                .font(.subheadline.bold())
                .foregroundStyle(.yellow)
            tableRow("Entrée HID", "Fonction simulateur", "", header: true)
            tableRow("Bouton 1", "KG", "")
            tableRow("Bouton 2", "KACOP", "")
            tableRow("Bouton 3", "KIBS", "")
            tableRow("Bouton 4", "KPH", "")
            tableRow("Bouton 5", "AVA (klaxon)", "")
            tableRow("Bouton 6", "PO G", "")
            tableRow("Bouton 7", "PO D", "")
            tableRow("Bouton 8", "FP", "")
            tableRow("Bouton 9 / 10 / 11", "Reverseur AV / 0 / AR", "")
            tableRow("Bouton 12", "Frein d'urgence (bascule)", "")
            tableRow("Axe Y", "Manipulateur T/F", "")
        }
    }

    // MARK: Body strings (Markdown-aware via Text(.init:))

    private var introBody: String { """
    Le **VAL** (*Véhicule Automatique Léger*) est un métro automatique sur pneumatiques conçu par **Matra Transport** pour Lille en 1983. Le **VAL 206** doit son nom à la largeur de ses caisses : **2,06 m**.

    Ce simulateur reproduit le **pupitre de conduite manuelle** d'une rame VAL 206, sur un tronçon de 1,5 km comportant trois stations. La nomenclature et les contacteurs suivent ceux de la réplique de pupitre présentée par **La Patate Douce** dans la vidéo [*Pupitre VAL 206 : Simulation de conduite manuelle*](https://www.youtube.com/watch?v=U4T-fxTc7go), qui a inspiré le projet.
    """ }

    private var theoryBody: String { """
    **Véhicule** : rame articulée à deux voitures, 26 m de long, 2,06 m de large. Pneus de roulement sur deux bandes de béton de part et d'autre d'un **rail central jaune** de guidage. Vitesse maximale ligne : 80 km/h (60 km/h en PA).

    **Modes de conduite** — mutuellement exclusifs :
    - **PA — Pilotage Automatique** : la rame se conduit seule de station à station. Veille désactivée. Mode normal en exploitation commerciale.
    - **PM — Pilotage Manuel** : conduite au manipulateur. Veille requise. Manœuvres dépôt, récupération, formation.

    La sélection se fait par l'interrupteur **PA** du pupitre, qui inhibe le manipulateur quand activé.
    """ }

    private var quickStartBody: String { """
    1. Tournez **KG** sur **on** — le compresseur démarre.
    2. Positionnez le **reverseur** sur **AV** (Avant).
    3. Choisir le mode :
       - **Automatique** : activez **PA**, la rame démarre seule.
       - **Manuel** : tirez le **manipulateur T/F** vers le haut (TRAC).
    4. En manuel, appuyez sur **KACOP** au moins toutes les 14 s.
    5. À l'arrêt en station, **DOORS OK** s'allume.
    6. **PO G** / **PO D** pour ouvrir, **FP** pour fermer.
    """ }

    private var manualBody: String { """
    Le manipulateur **T/F** combine traction et freinage de service sur une course verticale unique :
    - **+1** : traction maximale (≈ 1,3 m/s²)
    - **0** : roue libre (résistance au roulement seule, ≈ 0,12 m/s²)
    - **−1** : frein service maximal (≈ 1,4 m/s²)

    La traction est inhibée si :
    - une porte est ouverte (> 2 %),
    - le reverseur est sur 0,
    - le frein d'urgence est enclenché,
    - ou **KG** est ouvert.

    Le freinage service n'est **pas** soumis à ces verrouillages : il reste disponible portes ouvertes, reverseur sur 0, etc.

    **KG** ouvert, la rame n'est plus alimentée : ni le frein service ni le frein d'urgence n'agissent, la rame ralentit seulement sur la résistance résiduelle (≈ 0,05 m/s²).

    **KIBS** figure au pupitre mais n'est pas encore simulé : il est sans effet.
    """ }

    private var paBody: String { """
    En PA, l'**automate de conduite** ignore le manipulateur et applique le profil suivant :
    1. Station cible **verrouillée** : la prochaine dans le sens de marche, hors station déjà desservie. Le verrou évite qu'un dépassement de quelques centimètres fasse abandonner le quai.
    2. Calcul de la décélération amenant la rame pile sur la **marque d'arrêt** : `a = v² ⁄ 2d`, `d` étant la distance restante.
    3. Si `a ≥ 1,0 m/s²` → freinage à la fraction exacte du frein service : `−a ⁄ 1,4`, borné à −1,0. Ce recalcul à chaque image fait la précision de l'arrêt : un cran fixe maintenu jusqu'à l'immobilisation laisse la rame à plusieurs mètres du quai.
    4. Sinon, si `a ≥ 0,5 m/s²` → roue libre (approche).
    5. Sinon, si `v < 60 km/h` → 70 % de traction.
    6. Sinon → roue libre (croisière).
    7. Dans ±0,05 m de la marque → frein maximal jusqu'à l'arrêt.

    L'étape 3 est **verrouillée en hystérésis** : une fois le freinage engagé, il est maintenu jusqu'à ce que `a` retombe sous 0,5 m/s². Freiner exactement à la valeur demandée maintient `a` sur le seuil : un seuil unique ferait osciller la commande — et le voyant **FREIN** — d'une image à l'autre.

    Précision d'accostage : environ **±0,02 m** du centre du quai, y compris après une perturbation (frein d'urgence en approche, cycle de portes) — le profil est simplement rejoué depuis la position atteinte.

    **Enchaînement des stations.** À l'arrêt (< 0,1 m/s) dans la boîte de ±6 m d'une station non desservie, la rame se **gare** à quai, frein maintenu, pour un **stationnement de 10 s** :
    - l'ouverture des portes **suspend** le décompte ;
    - **FP** (fermeture) y met fin immédiatement et la rame repart ;
    - sinon le départ est automatique à l'expiration des 10 s.

    La station desservie est alors exclue des cibles d'arrêt — elle le redevient dès que la rame s'en est éloignée de plus de 12 m, ce qui permet de la desservir à nouveau après inversion du reverseur.

    Le PA se **suspend** automatiquement à l'ouverture des portes ou à l'enclenchement du frein d'urgence, et **reprend** dès que les conditions reviennent, sans perdre la station en cours. Couper **PA**, **KG** ou passer le reverseur sur **0** réinitialise l'enchaînement.

    **Terminus.** La dernière station du sens de marche *est* le terminus : la rame y reste garée, frein maintenu, sans rejoindre la fin de voie. Inverser le reverseur libère le quai et le PA repart en sens inverse. PA engagé sans aucune station devant maintient simplement le frein. La **veille KACOP est bypassée** en PA.

    **Navette (NAV).** Avec **NAV** activé, le PA effectue lui-même le retournement : à la fin du stationnement au terminus (10 s, ou immédiatement après un cycle de portes **FP**), il inverse le reverseur — celui du pupitre suit — et repart en sens inverse, d'un terminus à l'autre, indéfiniment. Engagé au-delà du dernier quai, il s'arrête, se retourne et dessert d'abord ce quai. Couper NAV en route laisse la rame finir son trajet et se garer au terminus suivant. NAV n'a pas de bouton HID.
    """ }

    private var stationsBody: String { """
    Trois stations sur la ligne :
    - **P25 — QUATRE-CANTONS** (250 m)
    - **P75 — RÉPUBLIQUE** (750 m)
    - **P125 — GRAND-PLACE** (1 250 m)

    Conditions pour autoriser l'ouverture des portes :
    - **KG** sur on,
    - vitesse < 0,1 m/s,
    - à ±6 m du centre de la station.

    L'interverrouillage **interdit la traction** tant qu'une porte est ouverte. Animation d'ouverture/fermeture : ≈ 0,9 s, accompagnée d'un carillon (Audio §9). Si la rame se met tout de même en mouvement (> 0,3 m/s, p. ex. en dérive KG ouvert), les portes se referment d'elles-mêmes.
    """ }

    private var kacopBody: String { """
    **KACOP** — *Acquittement Conduite OPérateur*, dispositif d'**homme-mort** / veille.

    En PM, un appui est requis **au moins toutes les 14 secondes**. Le système ne reconnaît que le **front montant** — un bouton coincé est sans effet.

    - Appui ⇒ `deadmanTimer = 0`
    - Le décompte ne court qu'en marche en PM : KG fermé, reverseur hors 0, vitesse > 0,5 m/s (≈ 1,8 km/h). Sinon il redescend deux fois plus vite.
    - **14 s** : alerte rouge + buzzer 1500 Hz porté par carré 4 Hz
    - **20 s** : frein d'urgence automatique
    - **PA** : veille désactivée
    """ }

    private var emergencyBody: String { """
    Le **frein d'urgence** (« ARRÊT ») est un bouton-coup-de-poing à verrouillage.

    - **Appui** : application immédiate à 2,8 m/s², voyant URG allumé.
    - **Inhibe toute traction**, quel que soit le manipulateur.
    - **Nouvel appui** : déverrouillage.

    Déclenché aussi automatiquement par expiration du KACOP (> 20 s) en mode manuel. Comme le frein service, il n'agit que **KG** fermé.
    """ }

    private var audioBody: String { """
    Tous les sons sont **synthétisés en temps réel** par un unique `AVAudioSourceNode` :
    - **Moteur** : triangle bi-harmonique, fondamentale 32 → 352 Hz selon vitesse ; amplitude croissante avec la vitesse, +25 % en traction.
    - **Frein** : bruit blanc filtré passe-bas, plus fort selon la demande de freinage, maximal en urgence.
    - **Klaxon (AVA)** : 220 Hz + harmonique 1,5×.
    - **Compresseur** : sinusoïde 55 Hz tant que KG est on.
    - **Veille** : 1500 Hz porté par carré 4 Hz (alerte uniquement).
    - **Carillon portes** : sinus 660 Hz décroissant, au début de chaque ouverture ou fermeture.

    Sortie limitée doucement par `tanh`. Coupure / réactivation via le bouton haut-parleur dans la barre d'état.
    """ }

    private var hidBody: String { """
    Le simulateur ouvre automatiquement tout périphérique HID détecté par `IOHIDManager` (joystick, gamepad, contrôleur multi-axes).

    Un **pupitre matériel** comme celui de la vidéo de La Patate Douce (§1) — Raspberry Pi Pico configuré en HID gamepad à 12 boutons + 1 axe — est ainsi compatible *plug & play* avec ce mapping par défaut.

    Comportement des entrées :
    - **Boutons 1, 3, 4** (KG, KIBS, KPH) suivent le *niveau* du bouton : l'interrupteur est fermé tant que l'entrée est maintenue — à câbler sur des interrupteurs à accrochage.
    - **Boutons 2, 5 à 8** (KACOP, klaxon, portes) sont momentanés ; KACOP et les portes n'agissent que sur le front montant.
    - **Boutons 9 à 11** positionnent le reverseur à l'appui.
    - **Bouton 12** bascule le frein d'urgence à chaque appui.

    Le nom du périphérique connecté s'affiche dans la barre d'état (« PUPITRE USB : … »). Sans pupitre, le pilotage à la souris reste possible sur tous les contrôles virtuels.
    """ }

    private var glossaryBody: String { """
    - **Acquittement** — acknowledgment
    - **AVA** — *AVertisseur Acoustique* (horn)
    - **Boucle de Sécurité (BS)** — safety interlock loop
    - **Coupure** — cutoff / isolation
    - **FP** — *Fermeture Portes*
    - **K-** — préfixe des contacteurs (*contactor*) en symbologie électrique
    - **Manipulateur** — controller / handle
    - **Navette (NAV)** — service navette entre les deux terminus
    - **PA / PM** — *Pilotage Automatique / Manuel*
    - **PO G / PO D** — *Porte Ouverture Gauche / Droite*
    - **Pupitre** — cab control desk
    - **Veille** — vigilance device / dead-man
    - **Voyant** — indicator light
    """ }
}

#Preview {
    OperatorGuideView()
}
