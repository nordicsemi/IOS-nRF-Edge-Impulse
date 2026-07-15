//
//  ContentView.swift
//  Shared
//
//  Created by Dinesh Harjani on 22/02/2021.
//

import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    
    // MARK: Environment
    
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var deviceData: DeviceData
    
    // MARK: view
    
    var body: some View {
        if appData.isLoggedIn {
            LoggedInRootView()
                .environmentObject(deviceData)
        } else {
            #if os(OSX)
            if #available(macOS 15.0, *) {
                NativeLoginView()
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            } else {
                NativeLoginView()
            }
            #else
            NativeLoginView()
            #endif
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let appData = AppData()
        ContentView()
            .environmentObject(appData)
            .environmentObject(DeviceData(scanner: Scanner(), registeredDeviceManager: RegisteredDevicesManager(), appData: appData))
    }
}
#endif
