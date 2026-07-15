//
//  ConnectedDevicePicker.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 21/7/21.
//

import SwiftUI
import iOS_Common_Libraries

// MARK: - ConnectedDevicePicker

struct ConnectedDevicePicker<SelectionValue: Hashable>: View {
    
    // MARK: Environment
    
    @EnvironmentObject var deviceData: DeviceData
    
    // MARK: Properties
    
    private var selectionBinding: Binding<SelectionValue>
    
    // MARK: init
    
    init(_ selectionBinding: Binding<SelectionValue>) {
        self.selectionBinding = selectionBinding
    }
}

// MARK: - iOS

#if os(iOS)
extension ConnectedDevicePicker {
    
    @ViewBuilder
    var body: some View {
        let connectedDevices = deviceData
            .allConnectedAndReadyToUseDevices()
            .compactMap(\.device)
        
        Picker("Selected", selection: selectionBinding) {
            Text("--")
                .tag(Constant.unselectedDevice)
            
            ForEach(connectedDevices, id: \.self) { device in
                Text(deviceData.name(for: device))
                    .lineLimit(1)
                    .tag(device)
            }
        }
        .accentColor(.universalAccentColor)
        .pickerStyle(.menu)
    }
}
#endif

// MARK: - macOS

#if os(OSX)
extension ConnectedDevicePicker {
    
    @ViewBuilder
    var body: some View {
        MultiColumnView {
            Text("Connected Device")
            
            let connectedDevices = deviceData
                .allConnectedAndReadyToUseDevices()
                .compactMap(\.device)
            
            Picker(selection: selectionBinding, label: EmptyView()) {
                Text("--")
                    .tag(Constant.unselectedDevice)
                
                ForEach(connectedDevices, id: \.self) { device in
                    Text(deviceData.name(for: device))
                        .lineLimit(1)
                        .tag(device)
                }
            }
        }
    }
}
#endif
