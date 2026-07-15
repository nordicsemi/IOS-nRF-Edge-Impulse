//
//  DeviceDetails.swift
//  nRF-Edge-Impulse
//
//  Created by Nick Kibysh on 02/07/2021.
//

import SwiftUI
import iOS_Common_Libraries

struct DeviceDetails: View {
    
    @Environment(\.presentationMode) private var presentationMode: Binding<PresentationMode>
    @EnvironmentObject var deviceData: DeviceData
    
    // MARK: Private Properties
    
    @State private var showingAlert = false
    
    private let device: Device
    private let state: DeviceData.DeviceWrapper.State
    
    // MARK: init
    
    init(device: Device, state: DeviceData.DeviceWrapper.State) {
        self.device = device
        self.state = state
    }
    
    // MARK: view
    
    var body: some View {
        FormIniOSListInMacOS {
            Section("Device Information") {
                #if os(macOS)
                StringDeviceInfoRow(title: "Name", systemImage: "character", content: device.name)
                #endif
                
                StringDeviceInfoRow(title: "ID", systemImage: "person", content: device.deviceId)
                StringDeviceInfoRow(title: "Type", systemImage: "t.square", content: device.deviceType.trimmingCharacters(in: .whitespacesAndNewlines))
                StringDeviceInfoRow(title: "Created At", systemImage: "calendar", content: device.created.toDate()?.formatterString() ?? "")
                StringDeviceInfoRow(title: "Last Seen", systemImage: "eye", content: device.lastSeen.toDate()?.formatterString() ?? "")
                BoolDeviceInfoRow(title: "Supports Snapshot Streaming", systemImage: "arrow.left.and.right", enabled: device.supportsSnapshotStreaming)
            }
            
            DeviceStatusSectionView(device: device, state: state)
            
            ForEach(device.sensors) {
                SensorSection(sensor: $0)
            }
            
            deleteSection()
        }
        .background(Color.secondarySystemGroupBackground)
        .accentColor(.primary)
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Delete Device"),
                  message: Text("Are you sure you want to delete this Device?"),
                  primaryButton: .destructive(Text("Yes"), action: confirmDeleteDevice),
                  secondaryButton: .default(Text("Cancel"), action: dismissDeleteDevice))
        }
        .navigationTitle(Text(device.name))
        .toolbar {
            if case .readyToConnect = state {
                Button("Connect") {
                    deviceData.tryToConnect(device: device)
                }
            } else if case .connecting = state {
                CircularProgressView()
                    .foregroundColor(Assets.textColor.color)
            } else if case .connected = state {
                Button("Disconnect") {
                    deviceData.disconnect(device: device)
                }
            }
        }
    }
    
    @ViewBuilder
    private func deleteSection() -> some View {
        Section(header: Text("Management"),
                footer: Text("Deletes this device from the list of registered devices.")
                    .font(.caption2)
                    .foregroundColor(.nordicMiddleGrey)
                    .frame(maxWidth: .infinity, alignment: .center)) {
            
            Button("Delete") {
                showingAlert = true
            }
            .foregroundColor(.negativeActionButtonColor)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Private

private extension DeviceDetails {
    
    func confirmDeleteDevice() {
        showingAlert = false
        deviceData.tryToDelete(device: device)
        presentationMode.wrappedValue.dismiss()
    }
    
    func dismissDeleteDevice() {
        showingAlert = false
    }
}

// MARK: - SensorSection

private struct SensorSection: View {
    
    let sensor: Sensor

    var body: some View {
        Section(header: Label(sensor.name, systemImage: sensor.iconName)) {
            HStack {
                NordicLabel(title: "Max. Sample Length", systemImage: "stopwatch")
                
                Spacer()
                
                if let maxSampleLengthSeconds = sensor.maxSampleLengthS {
                    Text("\(maxSampleLengthSeconds, specifier: "%.0d")s").bold()
                        .foregroundColor(.secondary)
                } else {
                    Text("N/A")
                        .foregroundColor(.secondary)
                }
            }
            
            if let frequencies = sensor.frequencies, frequencies.hasItems == true {
                let text = ListFormatter.localizedString(
                    byJoining: frequencies.map { "\(String(format: "%.2f", $0))Hz" })
                
                StringDeviceInfoRow(title: "Frequencies", systemImage: "waveform.path.ecg", content: text)
            }
        }
    }
}

// MARK: - NordicLabel

struct NordicLabel: View {
    
    let title: String
    let systemImage: String
    
    var body: some View {
        Label(
            title: { Text(title) },
            icon: {
                Image(systemName: systemImage)
                    .renderingMode(.template)
                    .foregroundColor(.universalAccentColor)
            }
        )
    }
}

// MARK: - NordicDateLabel

struct NordicDateLabel: View {
    
    let date: Date
    let systemImage: String
    
    var body: some View {
        Label(
            title: { Text(date, style: .date) },
            icon: {
                Image(systemName: systemImage)
                    .renderingMode(.template)
                    .foregroundColor(.universalAccentColor)
            }
        )
    }
}

// MARK: - Preview

#if DEBUG
struct DeviceDetails_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(DeviceData.DeviceWrapper.State.allCases, id: \.self) { state in
                DeviceDetails(device: .connectableMock, state: state)
                    .navigationTitle("Device")
                    .environmentObject(DeviceData(appData: AppData()))
                    .previewLayout(.sizeThatFits)
                    .previewDisplayName(String(describing: state).uppercasingFirst)
            }
        }
    }
}
#endif
