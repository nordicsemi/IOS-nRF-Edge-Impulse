//
//  DataAcquisitionView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 4/3/21.
//

import SwiftUI
import iOS_Common_Libraries

// MARK: - DataAcquisitionView

struct DataAcquisitionView: View {
    
    // MARK: Environment
    
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var dataAcquisitionViewState: DataAcquisitionViewState
    @EnvironmentObject var deviceData: DeviceData
    
    // MARK: Private Properties
    
    private enum Field: Int, Hashable {
        case label
    }
    
    @FocusState private var focusedField: Field?
    @State private var keyboardShownOnce = false
    
    // MARK: view (iOS Only)
    
    var body: some View {
        FormIniOSListInMacOS {
            Section("Category") {
                Picker("Selected", selection: $appData.selectedCategory) {
                    ForEach(DataSample.Category.allCases) { dataType in
                        Text(dataType.rawValue.uppercasingFirst)
                            .tag(dataType)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(dataAcquisitionViewState.isSampling)
            }
            
            Section("Device") {
                ConnectedDevicePicker($dataAcquisitionViewState.selectedDevice)
                    .disabled($dataAcquisitionViewState.isSampling.wrappedValue)
            }
            
            Section("Data Collection") {
                HStack {
                    Text("Label")
                    
                    TextField("Label", text: $dataAcquisitionViewState.label)
                        .focused($focusedField, equals: .label)
                        .multilineTextAlignment(.trailing)
                        .enabledForeground(!dataAcquisitionViewState.isSampling)
                        .onAppear {
                            guard !keyboardShownOnce,
                                  !dataAcquisitionViewState.isSampling,
                                  dataAcquisitionViewState.label.isEmpty else { return }
                            keyboardShownOnce = true
                            withAnimation {
                                focusedField = .label
                            }
                        }
                }
                
                InlinePicker(title: "Sensor", selectedValue: $dataAcquisitionViewState.selectedSensor, possibleValues: dataAcquisitionViewState.selectedDevice.sensors)
                    .accentColor(.universalAccentColor)
                
                DataAcquisitionViewSampleLengthPicker(viewState: dataAcquisitionViewState)
                
                HStack {
                    Text("Frequency")
                    
                    DataAcquisitionFrequencyPicker(viewState: dataAcquisitionViewState)
                }
            }
            .disabled(dataAcquisitionViewState.isSampling)
            
            Section("Progress") {
                ReusableProgressView(progress: $dataAcquisitionViewState.progress, isIndeterminate: $dataAcquisitionViewState.indeterminateProgress, statusText: $dataAcquisitionViewState.progressString, statusColor: $dataAcquisitionViewState.progressColor, buttonText: "Start Sampling", buttonEnabled: $dataAcquisitionViewState.samplingButtonEnable, buttonAction: startSampling)
            }
        }
        .setTitle("Record New Data")
        .onAppear(perform: setInitialSelectedDevice)
        .onReceive(dataAcquisitionViewState.countdownTimer, perform: dataAcquisitionViewState.onSampleTimerTick(_:))
        .frame(minWidth: .minTabWidth)
    }
}

// MARK: - Preview

#if DEBUG
struct DataAcquisitionView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            NavigationView {
                DataAcquisitionView()
                    .environmentObject(Preview.noDevicesAppData)
                    .environmentObject(Preview.noDevicesScannerData)
            }
            
            NavigationView {
                DataAcquisitionView()
                    .environmentObject(Preview.projectsPreviewAppData)
                    .environmentObject(Preview.mockScannerData)
            }
            .setupNavBarBackground(with: Assets.navBarBackground.color)
        }
        .previewDevice("iPhone 12 mini")
    }
}
#endif
