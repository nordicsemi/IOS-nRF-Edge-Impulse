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
            NativeLoginView()
            #if os(OSX)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
