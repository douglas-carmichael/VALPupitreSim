//
//  VALPupitreSimApp.swift
//  VALPupitreSim
//
//  Created by Douglas Carmichael on 6/14/26.
//

import SwiftUI

@main
struct VALPupitreSimApp: App {
    @State private var model = SimulationModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1180, minHeight: 800)
        }
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)

        Window("Vue Cabine — VAL 206", id: "cab-view") {
            Cab3DView(model: model)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1024, height: 640)
    }
}
