//
//  nRF_Edge_ImpulseApp.swift
//  Shared
//
//  Created by Dinesh Harjani on 22/02/2021.
//

import SwiftUI

// MARK: - App

@main
struct nRF_Edge_ImpulseApp: App {
    
    // MARK: @StateObject
    
    @StateObject var dataContainer = DataContainer()
    @StateObject var hudState = HUDState()
    
    // MARK: Scene
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(OSX)
                .containerBackground(.thinMaterial, for: .window)
                #endif
                .hud(isPresented: $hudState.isPresented) {
                    Label(hudState.title, systemImage: hudState.systemImage)
                }
                .environmentObject(dataContainer.appData)
                .environmentObject(dataContainer.deviceData)
                .environmentObject(hudState)
        }
    }
}
