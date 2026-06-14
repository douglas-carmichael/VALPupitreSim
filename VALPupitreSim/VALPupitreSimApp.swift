//
//  VALPupitreSimApp.swift
//  VALPupitreSim
//
//  Created by Douglas Carmichael on 6/14/26.
//

import SwiftUI

@main
struct VALPupitreSimApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1180, minHeight: 800)
        }
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
    }
}
