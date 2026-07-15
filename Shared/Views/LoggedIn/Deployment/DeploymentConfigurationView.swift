//
//  DeploymentConfigurationView.swift
//  nRF-Edge-Impulse (iOS)
//
//  Created by Dinesh Harjani on 27/9/21.
//

import SwiftUI
import iOS_Common_Libraries

// MARK: - DeploymentConfigurationView

struct DeploymentConfigurationView: View {
    
    // MARK: Private Properties
    
    @EnvironmentObject var deviceData: DeviceData
    @EnvironmentObject var viewState: DeploymentViewState
    
    // MARK: View
    
    var body: some View {
        Section("Device") {
            ConnectedDevicePicker($viewState.selectedDevice)
                .onAppear(perform: selectFirstAvailableDeviceHandler)
        }
        
        Section("Optimizations") {
            Toggle(isOn: $viewState.enableEONCompiler, label: {
                Text("Enable EON™ Compiler")
            })
            .toggleStyle(SwitchToggleStyle(tint: .nordicBlue))
            
            Text("Same accuracy, up to 50% less memory. Open source.")
                .font(.caption)
                .foregroundColor(.nordicMiddleGrey)
        }
        
        Section("Classifier") {
            InlinePicker(title: "Classifier", selectedValue: $viewState.optimization)
            
            Text(DeploymentViewState.Classifier.attributedUserCaption)
                .font(.caption)
                .foregroundColor(.nordicMiddleGrey)
        }
        
        Section("Build") {
            Toggle(isOn: $viewState.enableCachedServerBuilds, label: {
                Text("Enable Cached Builds")
            })
            .toggleStyle(SwitchToggleStyle(tint: .nordicBlue))
            
            Text("When enabled, we will check if there's an existing build in the Server matching your configuration.")
                .font(.caption)
                .foregroundColor(.nordicMiddleGrey)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DeploymentConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            DeploymentConfigurationView()
        }
        .environmentObject(Preview.mockRegisteredDevices)
        .environmentObject(DeploymentViewState())
    }
}
#endif
