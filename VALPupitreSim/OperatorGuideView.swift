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
                    section("11. Commande PCC", body: pccBody)
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

    Ce simulateur reproduit le **pupitre de conduite manuelle** d'une rame VAL 206, sur un tronçon de 1,5 km comportant trois stations — ou, en commande PCC, sur la ligne que le PCC lui prête, parmi les autres rames de cette ligne (§11). La nomenclature et les contacteurs suivent ceux de la réplique de pupitre présentée par **La Patate Douce** dans la vidéo [*Pupitre VAL 206 : Simulation de conduite manuelle*](https://www.youtube.com/watch?v=U4T-fxTc7go), qui a inspiré le projet.
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

    **Point d'arrêt du PCC.** Quand le PCC a fixé un point d'arrêt (§11) avant la prochaine station, le PA freine dessus exactement comme sur une marque de quai, et y attend que le PCC le déplace.

    **Boucles.** Sur la boucle d'un PCC, il n'y a pas de terminus : le PA dessert les stations tour après tour, et NAV n'a rien à faire.

    **Terminus.** La dernière station du sens de marche *est* le terminus : la rame y reste garée, frein maintenu, sans rejoindre la fin de voie. Inverser le reverseur libère le quai et le PA repart en sens inverse. PA engagé sans aucune station devant maintient simplement le frein. La **veille KACOP est bypassée** en PA.

    **Navette (NAV).** Avec **NAV** activé, le PA effectue lui-même le retournement : à la fin du stationnement au terminus (10 s, ou immédiatement après un cycle de portes **FP**), il inverse le reverseur — celui du pupitre suit — et repart en sens inverse, d'un terminus à l'autre, indéfiniment. Engagé au-delà du dernier quai, il s'arrête, se retourne et dessert d'abord ce quai. Couper NAV en route laisse la rame finir son trajet et se garer au terminus suivant. NAV n'a pas de bouton HID.
    """ }

    private var stationsBody: String { """
    Trois stations sur la voie d'essai :
    - **P25 — QUATRE-CANTONS** (250 m)
    - **P75 — RÉPUBLIQUE** (750 m)
    - **P125 — GRAND-PLACE** (1 250 m)

    La position s'affiche sous la forme `P000 / 150` (une unité = 10 m). Elle repère le centre de la voiture de tête (voiture 1, côté AV) : c'est ce point que le PA arrête sur la marque du quai. Sur la ligne d'un PCC (§11), les stations sont celles du PCC et la position se lit sur la longueur de sa ligne — `P085 / 100` sur une boucle de 1 km.

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

    Déclenché aussi automatiquement par expiration du KACOP (> 20 s) en mode manuel et, en commande PCC, par la perte de liaison avec le PCC ou le franchissement du point d'arrêt fixé par le PCC (§11). Tout PCC connecté peut aussi le serrer. Quand ce n'est pas l'ARRÊT qui l'a serré, la barre des stations en indique la cause. Comme le frein service, il n'agit que **KG** fermé.
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

    En commande PCC (§11), le pupitre USB est verrouillé comme le pupitre à l'écran : seul le bouton 12 agit encore. Les interrupteurs à accrochage des boutons 1, 3 et 4 peuvent alors ne plus correspondre à ce que le PCC a commandé : rebasculez-les après la reprise en local.

    Le nom du périphérique connecté s'affiche dans la barre d'état (« PUPITRE USB : … »). Sans pupitre, le pilotage à la souris reste possible sur tous les contrôles virtuels.
    """ }

    private var pccBody: String { """
    Un **PCC** (*Poste de Commande Centralisé*) — par exemple le dispatcher de metroSystem — peut trouver le pupitre sur le réseau local, le suivre et le commander. Le protocole est décrit dans `PCC_API.md`.

    **Découverte.** Le pupitre s'annonce en Bonjour (`_valpupitre._tcp`) sous le nom « Rame *numéro* — *nom de l'ordinateur* » et écoute sur le port TCP 5206 (un autre port libre si 5206 est pris). Au premier lancement, macOS demande si l'application peut accéder au réseau local : acceptez, sinon les PCC ne trouveront pas le pupitre.

    **Sélecteur COMMANDE** (barre d'état) :
    - **LOCALE** (par défaut) : le pupitre conduit. Les PCC peuvent suivre la rame et serrer son frein d'urgence, rien de plus.
    - **PCC** : le PCC en commande conduit. Le pupitre et le pupitre USB sont verrouillés — ils affichent ce que le PCC commande sans y répondre — sauf l'**ARRÊT**, qui reste actif.

    Seul le pupitre peut manœuvrer le sélecteur, qui garde sa position d'un lancement à l'autre.

    **Un seul PCC en commande.** Plusieurs PCC peuvent être connectés ; un seul prend la commande, et seules ses commandes sont appliquées : KG, KIBS, KPH, PA, NAV, reverseur (à l'arrêt seulement), manipulateur T/F, KACOP, portes et frein d'urgence. Tout PCC connecté peut serrer le frein d'urgence, quelle que soit la position du sélecteur.

    **Surveillance de liaison.** En commande PCC, le pupitre doit entendre son PCC en permanence. Après **3 s** de silence — liaison perdue, PCC muet ou aucun PCC en commande — il serre le frein d'urgence : sécurité par manque. Le frein reste serré au retour de la liaison ; le PCC ou l'ARRÊT le desserre. Un pupitre passé en commande PCC avant qu'un PCC ne se connecte attend donc, freiné, qu'un PCC en prenne la commande.

    **Mêmes règles qu'au pupitre.** Le PCC conduit sous les verrouillages de la cabine : la traction est coupée par KG, le reverseur, le frein d'urgence et les portes, et en PM le PCC doit acquitter le KACOP comme un conducteur.

    **La ligne du PCC.** Un PCC peut prêter sa propre ligne à la rame — metroSystem prête sa boucle de 1 km. Dès que le pupitre est en commande PCC et à l'arrêt, la rame passe sur cette ligne à l'endroit choisi par le PCC (metroSystem prend la station la plus éloignée de ses rames), et toutes les vues se redessinent : les vues poursuite et cabine suivent la boucle, et le plan la montre en piste de course, avec ses cantons et son nom. La barre des stations et l'affichage tête haute comptent alors vers les stations de cette ligne.

    **Point d'arrêt.** Le PCC peut imposer à la rame un point à ne pas franchir — metroSystem le place 8 m avant le premier canton occupé devant elle, comme son block fixe le fait pour ses propres rames. La pastille **POINT D'ARRÊT** indique la distance restante (en rouge à moins de 30 m), reprise dans l'affichage tête haute de la vue cabine. Le PA s'y arrête ; le franchir (de plus d'1 m, en mouvement) serre le frein d'urgence — **POINT D'ARRÊT FRANCHI**.

    **Autres rames.** Le PCC peut aussi indiquer au pupitre où se trouvent les autres rames de la ligne. Elles apparaissent dans les vues poursuite et cabine comme des rames semblables à celle-ci, numérotées, feux blancs à l'avant dans leur sens de marche et feux rouges à l'arrière, et sur le plan comme des repères bleus portant leur numéro. Comme elles sont le plus souvent à plusieurs centaines de mètres sur la boucle, au-delà de 60 m un mât orange se dresse sur leur toit, et mât et numéro grandissent avec la distance pour rester lisibles. Les courbes, les murs et les stations les cachent malgré tout : la vue poursuite et l'affichage tête haute de la vue cabine portent donc un encadré **RAMES SUR LA LIGNE**, avec la rame la plus proche **DEVANT** (dans le sens de marche) et **DERRIÈRE**, chacune avec son numéro, la distance libre entre les extrémités en regard des deux rames — orange sous 150 m, rouge sous 50 m — et sa vitesse, ou ARRÊT. Sur une boucle, une rame seule est à la fois devant et derrière. Entre deux comptes rendus du PCC, elles avancent à leur dernière vitesse connue ; sans nouvelles pendant 2 s, elles disparaissent. Elles ne servent qu'à l'affichage : c'est le point d'arrêt du PCC qui tient la rame à distance.

    **Télémesures.** Le pupitre transmet à chaque PCC connecté, avec son état, les mesures de la rame : chaîne de traction (tension et courant ligne, courants d'induit et d'excitation, taux de modulation du hacheur, couple, récupération) et auxiliaires (convertisseur, batterie, éclairage, compresseur et réservoir principal, température du coffre-frein). Elles sont déduites de ce que fait la simulation, avec les caractéristiques de la chaîne de traction du VAL 206 : le synoptique de rame de metroSystem affiche ainsi des valeurs réelles. Elles n'influent pas sur la conduite.

    **Reprise en local.** Repassez le sélecteur sur **LOCALE** à tout moment : les commandes du PCC sont alors refusées. Une rame sur la ligne du PCC revient sur la voie d'essai, arrêtée là où elle l'avait quittée ; le point d'arrêt et les autres rames disparaissent avec le PCC.

    **Pastille PCC** (barre des stations) : grise en commande locale sans PCC connecté, jaune en commande locale avec des PCC connectés, verte avec le nom du PCC en commande, rouge en commande PCC sans PCC (« EN ATTENTE DU PCC ») ou si la liaison est en défaut. Un clic ouvre le détail : nom Bonjour, port, PCC connectés et **numéro de rame** présenté aux PCC — de 301 à 399 par défaut, propre à chaque Mac. Modifiez-le puis appuyez sur Entrée ; donnez un numéro distinct à chaque pupitre d'un même réseau.

    **Passer la main au PCC :**
    1. Lancez le PCC (metroSystem) sur le même réseau local : la pastille PCC passe au jaune dès qu'il est connecté.
    2. Passez le sélecteur **COMMANDE** sur **PCC** : le pupitre se verrouille, et la pastille passe au vert avec le nom du PCC quand celui-ci a pris la commande.
    3. Le PCC conduit. Si aucun PCC ne prend la commande dans les 3 s, le frein d'urgence se serre (PERTE DE LIAISON PCC) jusqu'à ce qu'un PCC le desserre.
    4. metroSystem fait passer la rame sur sa boucle, en station, et les vues montrent ses rames. L'exploitant de metroSystem met ensuite la rame en service.
    5. En cas d'urgence, frappez l'**ARRÊT** : il agit toujours.
    6. Pour reprendre la main, repassez le sélecteur sur **LOCALE** : la rame revient sur la voie d'essai.
    """ }

    private var glossaryBody: String { """
    - **Acquittement** — acknowledgment
    - **AVA** — *AVertisseur Acoustique* (horn)
    - **Boucle de Sécurité (BS)** — safety interlock loop
    - **Canton** — block : section fixe de ligne qu'une seule rame occupe à la fois
    - **Coupure** — cutoff / isolation
    - **FP** — *Fermeture Portes*
    - **K-** — préfixe des contacteurs (*contactor*) en symbologie électrique
    - **Manipulateur** — controller / handle
    - **Navette (NAV)** — service navette entre les deux terminus
    - **PA / PM** — *Pilotage Automatique / Manuel*
    - **PCC** — *Poste de Commande Centralisé* : le poste central qui supervise les rames de la ligne
    - **PO G / PO D** — *Porte Ouverture Gauche / Droite*
    - **Point d'arrêt** — stopping point : où le PCC impose l'arrêt de la rame
    - **Pupitre** — cab control desk
    - **Rame** — trainset
    - **Veille** — vigilance device / dead-man
    - **Voyant** — indicator light
    """ }
}

#Preview {
    OperatorGuideView()
}
