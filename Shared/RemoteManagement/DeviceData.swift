//
//  DeviceData.swift
//  nRF-Edge-Impulse
//
//  Created by Nick Kibysh on 01/06/2021.
//

import Foundation
import SwiftUI
import Combine
import os
import iOS_Common_Libraries

// MARK: - DeviceData.DeviceWrapper

extension DeviceData {
    
    struct DeviceWrapper: Identifiable, Hashable {
        
        var device: Device
        var id: Int { device.id }
        fileprivate(set) var state: State = .notConnectable
        
        // MARK: State
        
        enum State: CaseIterable {
            case notConnectable, readyToConnect, connecting, connected, deleting
            var color: Color {
                switch self {
                case .notConnectable:
                    return .gray
                case .readyToConnect:
                    return .nordicBlue
                case .connected:
                    return .green
                case .connecting:
                    return .nordicFall
                case .deleting:
                    return .gray
                }
            }
        }
        
        static func ==(lhs: DeviceWrapper, rhs: DeviceWrapper) -> Bool {
            return lhs.device == rhs.device && lhs.device.name == rhs.device.name
        }
        
        static func ==(lhs: DeviceWrapper, rhs: ScanResult) -> Bool {
            return lhs.device.deviceId == rhs.id
        }
    }
    
    // MARK: ScanResultWrapper
    
    struct ScanResultWrapper: Identifiable, Hashable {
        
        enum State {
            case notConnected, connecting, connected
        }
        
        let scanResult: ScanResult
        var state: State = .notConnected
        var id: String { scanResult.id + String(scanResult.rssi.value) }
        var availableViaRegisteredDevices: Bool = false
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(state)
            hasher.combine(scanResult)
        }
        
        static func ==(lhs: ScanResultWrapper, rhs: Device) -> Bool {
            return lhs.scanResult.id == rhs.deviceId
        }
    }

    // MARK: BluetoothStateError
    
    enum BluetoothStateError: Swift.Error {
        case poweredOff
        case unsupported
        case unknownState
        case unauthorized
    }
}

// MARK: - DeviceData

class DeviceData: ObservableObject {
    
    @ObservedObject var appData: AppData
    @ObservedObject var preferences = UserPreferences.shared
    
    let scanner: Scanner
    internal lazy var logger = Logger(Self.self)
    private var deviceManager = RegisteredDevicesManager()
    private var remoteHandlers: [DeviceRemoteHandler] = []
    
    @Published fileprivate(set) var scanResults: [ScanResultWrapper] = [] {
        didSet {
            unregisteredDevices = scanResults
                .filter({ $0.state != .connected && !$0.availableViaRegisteredDevices })
        }
    }
    @Published fileprivate(set) var unregisteredDevices: [ScanResultWrapper] = []
    @Published fileprivate(set) var registeredDevices: [DeviceWrapper] = []
    
    private(set) lazy var bluetoothStates = PassthroughSubject<Result<Bool, BluetoothStateError>, Never>()
    
    internal var cancellables = Set<AnyCancellable>()
    internal var dataSamplingCancellable: AnyCancellable!
    
    init(scanner: Scanner = Scanner(), registeredDeviceManager: RegisteredDevicesManager = RegisteredDevicesManager(), appData: AppData) {
        self.scanner = scanner
        self.deviceManager = registeredDeviceManager
        self.appData = appData
        
        let scannerSettingsPublisher = preferences.$onlyScanConnectableDevices
            .removeDuplicates()
            .combineLatest(preferences.$onlyScanUARTDevices.removeDuplicates())
            .justDoIt { [weak self] _ in
                self?.scanResults.removeAll()
            }
                
        scanner.scan().combineLatest(scannerSettingsPublisher)
            .compactMap { [weak self] (scanResult, _) -> ScanResultWrapper? in
                if let w = self?.wrapper(for: scanResult), w.scanResult.rssi == scanResult.rssi {
                    return nil
                } else {
                    return ScanResultWrapper(scanResult: scanResult)
                }
            }
            .collect(.byTime(RunLoop.main, .seconds(2)))
            .sink { [weak self] wrappers in
                guard let self = self else { return }
                guard wrappers.hasItems else { return }
                var newScanResults = self.scanResults
                wrappers.forEach { w in
                    newScanResults.addOrReplaceFirst(w, where: { $0.scanResult == w.scanResult })
                }
                self.scanResults = newScanResults
                wrappers.forEach { self.updateState($0.scanResult) }
            }
            .store(in: &cancellables)
        
        refresh()
    }
    
    subscript(scanResult: ScanResult) -> DeviceRemoteHandler? {
        get {
            remoteHandlers.first(where: { $0.scanResult == scanResult })
        }
    }
    
    subscript(device: Device) -> DeviceRemoteHandler? {
        get {
            remoteHandlers.first(where: { $0.device == device })
        }
    }
    
    // MARK: Connecting
    
    func tryToConnect(scanResult: ScanResult) {
        let handler = getRemoteHandler(for: scanResult)
        guard let keys = appData.selectedProject.map ({ appData.projectDevelopmentKeys[$0] }), let apiKey = keys?.apiKey else {
            return
        }
        
        if let index = scanResults.firstIndex(of: ScanResultWrapper(scanResult: scanResult)) {
            self.scanResults[index].state = .connecting
        }
        
        if let index = associatedRegisteredDevice(with: scanResult).flatMap({ registeredDevices.firstIndex(of: $0 ) }) {
            registeredDevices[index].state = .connecting
        }
        
        handler.connect(apiKey: apiKey)
            .sink { [handler, logger, weak self] completion in
                switch completion {
                case .finished:
                    logger.info("Device remote handler completed connection")
                    guard let self = self else { return }
                    self.onUnexpectedDisconnectionListener(for: handler)
                        .store(in: &self.cancellables)
                case .failure(let error):
                    logger.error("Device remote handler an error: \(error.localizedDescription).")
                }
            } receiveValue: { [handler, logger, weak self] state in
                logger.info("Device remote handler obtained new state: \(state.debugDescription)")
                self?.stateChanged(of: handler, newState: state)
            }
            .store(in: &cancellables)
    }
    
    func tryToConnect(device: Device) {
        guard let scanResult = associatedScanResult(with: device)?.scanResult else {
            return
        }
        
        tryToConnect(scanResult: scanResult)
    }
    
    // MARK: Name
    
    func name(for deviceHandler: DeviceRemoteHandler) -> String {
        guard let device = deviceHandler.device else { return "N/A" }
        return name(for: device)
    }
    
    func name(for device: Device) -> String {
        return registeredDevices.first(where: { $0.device.id == device.id })?.device.name ?? "N/A"
    }
    
    // MARK: Connection State
    
    func connectionState(of scanResult: ScanResult) -> ScanResultWrapper.State? {
        scanResults.first(where: { $0.scanResult == scanResult })?.state
    }
    
    // MARK: Disconnect
    
    func onUnexpectedDisconnectionListener(for handler: DeviceRemoteHandler) -> AnyCancellable {
        return handler.$state
            .compactMap({ (state) -> DeviceRemoteHandler.DisconnectReason? in
                guard case let .disconnected(reason) = state else { return nil }
                return reason
            })
            .sink { [weak self] reason in
                guard case let .error(error) = reason else {
                    self?.stateChanged(of: handler, newState: .disconnected(.onDemand))
                    return
                }
                self?.stateChanged(of: handler, newState: .disconnected(.error(error)))
            }
    }
    
    func disconnect(scanResult: ScanResult) {
        remoteHandlers
            .first(where: { $0.scanResult == scanResult })
            .map { self.disconnect(remoteHandler: $0) }
    }
    
    func disconnect(device: Device) {
        remoteHandlers
            .first(where: { $0.device != nil && $0.device == device })
            .map { remoteHandler in
                disconnect(remoteHandler: remoteHandler)
            }
    }
    
    func disconnect(remoteHandler: DeviceRemoteHandler) {
        remoteHandler.disconnect()
        remoteHandlers.removeAll(where: { $0.scanResult == remoteHandler.scanResult })
        registeredDevices
            .firstIndex(where: { $0.device == remoteHandler.device })
            .map { registeredDevices[$0].state = .readyToConnect }
        
        scanResults
            .firstIndex(where: { $0.scanResult == remoteHandler.scanResult })
            .map { scanResults[$0].state = .notConnected }
    }
    
    func disconnectAll() {
        allConnectedOrConnectingDevices()
            .forEach {
                disconnect(remoteHandler: $0)
            }
    }
    
    func allConnectedAndReadyToUseDevices() -> [DeviceRemoteHandler] {
        remoteHandlers.filter {
            if case .connected = $0.state {
                return true
            } else {
                return false
            }
        }
    }
    
    func allConnectedOrConnectingDevices() -> [DeviceRemoteHandler] {
        remoteHandlers.filter {
            if case .connected = $0.state {
                return true
            } else if case .connecting = $0.state {
                return true
            } else {
                return false
            }
        }
    }
    
    func refresh() {
        guard appData.isLoggedIn else {
            logger.info("\(#function): Ignoring call since User is not logged-in.")
            return
        }
        scanResults.removeAll()
        updateRegisteredDevices()
    }
    
    func renamed(_ device: Device, to newName: String) {
        if let i = registeredDevices.firstIndex(where: { $0.id == device.id }) {
            registeredDevices[i].device.name = newName
        }
        if let i = remoteHandlers.firstIndex(where: { $0.device?.id == device.id }) {
            remoteHandlers[i].rename(to: newName)
        }
        objectWillChange.send()
    }
    
    func updateRegisteredDevices() {
        deviceManager.refreshDevices(appData: appData)
            .receive(on: RunLoop.main)
            .sink { [logger] completion in
                switch completion {
                case .finished:
                    logger.info("Fetch device completed")
                case .failure(let error):
                    logger.error("Fetch device failed. Error: \(error.localizedDescription)")
                    AppEvents.shared.error = ErrorEvent(error)
                }
            } receiveValue: { [weak self] devices in
                guard let self = self else { return }
                self.registeredDevices = devices
                    .map { DeviceWrapper(device: $0, state: .notConnectable) }
                
                devices.forEach(self.updateState)
            }
            .store(in: &cancellables)
    }
    
    // MARK: Delete device
    
    func tryToDelete(device: Device) {
        guard let i = registeredDevices.firstIndex(where: { $0.device == device }) else { return }
        switch registeredDevices[i].state {
        case .connected:
            disconnect(device: device)
        case .deleting:
            // Error: Operation already in-progress.
            return
        default:
            // Continue.
            break
        }
        
        let previousState = registeredDevices[i].state
        registeredDevices[i].state = .deleting
        
        deviceManager.deleteDevice(deviceId: device.deviceId, appData: appData)
            .receive(on: RunLoop.main)
            .sinkReceivingError(onError: { [weak self] error in
                self?.registeredDevices[i].state = previousState
                AppEvents.shared.error = ErrorEvent(title: "Error", localizedDescription: error.localizedDescription)
            }, receiveValue: { [weak self] response in
                if let errorMessage = response.error {
                    self?.registeredDevices[i].state = previousState
                    AppEvents.shared.error = ErrorEvent(title: "Error", localizedDescription: errorMessage)
                } else {
                    self?.registeredDevices.removeAll(where: {
                        $0.device == device
                    })
                }
            })
            .store(in: &cancellables)
    }
}

// MARK: - Private methods

extension DeviceData {
    
    private func getRemoteHandler(for scanResult: ScanResult) -> DeviceRemoteHandler {
        if let handler = remoteHandlers.first(where: { $0 == scanResult }) {
            return handler
        } else {
            let newHandler = DeviceRemoteHandler(scanResult: scanResult, registeredDeviceManager: deviceManager, appData: appData)
            remoteHandlers.append(newHandler)
            return newHandler
        }
    }
    
    @discardableResult
    private func removeHandler(_ handler: DeviceRemoteHandler) -> Bool {
        remoteHandlers.firstIndex(of: handler)
            .map { remoteHandlers.remove(at: $0) } != nil
    }
    
    private func stateChanged(of handler: DeviceRemoteHandler, newState: DeviceRemoteHandler.ConnectionState) {
        if case .connected(let device, let registeredDevice) = newState {
            if let deviceIndex = scanResults.firstIndex(of: ScanResultWrapper(scanResult: device)) {
                scanResults[deviceIndex].state = .connected
                scanResults[deviceIndex].availableViaRegisteredDevices = true
            }
            
            if let deviceIndex = registeredDevices.firstIndex(of: DeviceWrapper(device: registeredDevice)) {
                registeredDevices[deviceIndex].state = .connected
            } else {
                registeredDevices.append(DeviceWrapper(device: registeredDevice, state: .connected))
            }
            attachDataSamplingRequestListener(to: handler)
        } else if case .disconnected(let reason) = newState {
            
            if let deviceIndex = self.scanResults.firstIndex(of: ScanResultWrapper(scanResult: handler.scanResult)) {
                scanResults[deviceIndex].state = .notConnected
            }
            
            if let wrapper = self.associatedRegisteredDevice(with: handler.scanResult),
               let deviceIndex = self.registeredDevices.firstIndex(of: wrapper) {
                registeredDevices[deviceIndex].state = .readyToConnect
            }
            
            if appData.dataAquisitionViewState.selectedDevice == handler.device {
                appData.dataAquisitionViewState.deviceDisconnected()
            }
            
            if case let .error(e) = reason {
                AppEvents.shared.error = ErrorEvent(e)
            }
            
            guard appData.inferencingViewState.isInferencing,
                  appData.inferencingViewState.selectedDevice == handler.device else {
                removeHandler(handler)
                return
            }
            
            appData.inferencingViewState.sendStopRequest(with: handler)
            appData.inferencingViewState.selectedDevice = .Unselected
            appData.inferencingViewState.isInferencing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.removeHandler(handler)
            }
        }
    }
    
    private func attachDataSamplingRequestListener(to handler: DeviceRemoteHandler) {
        handler.webSocketManager.dataSubject
            .tryMap { result -> BLESampleRequestMessage in
                switch result {
                case .success(let data):
                    return try JSONDecoder().decode(BLESampleRequestMessage.self, from: data)
                case .failure(let error):
                    throw error
                }
            }
            .receive(on: RunLoop.main)
            .sink { [weak self, logger] completion in
                switch completion {
                case .finished:
                    logger.info("Device remote handler Data funnel completed.")
                case .failure(let error):
                    logger.error("Device remote handler Data funnel encountered an error: \(error.localizedDescription).")
                    self?.stateChanged(of: handler, newState: .disconnected(.error(NordicError.deviceWebSocketDisconnectedError)))
                }
            } receiveValue: { [logger, weak self] request in
                logger.info("Device Remote Handler Received Sample Request for Sensor \(request.sample.sensor) of length \(request.sample.length)ms named \(request.sample.label).")
                self?.startSampling(BLESampleRequestWrapper(scheme: .wss, host: .EdgeImpulse, message: request),
                                    for: handler)
            }
            .store(in: &cancellables)
    }
    
    private func updateState(_ scanResult: ScanResult) {
        guard let index = scanResults.firstIndex(where: { $0.scanResult == scanResult }) else {
            return
        }
        
        if let regDeviceIndex = registeredDevices.firstIndex(where: { $0 == scanResult }) {
            if case .notConnectable = registeredDevices[regDeviceIndex].state {
                registeredDevices[regDeviceIndex].state = .readyToConnect
            }
            
            scanResults[index].availableViaRegisteredDevices = true
        }
    }
    
    internal func updateState(_ device: Device) {
        guard let regDeviceIndex = registeredDevices.firstIndex(where: { $0.device == device }) else {
            return
        }
        
        registeredDevices[regDeviceIndex].state = remoteHandlers
            .first(where: { $0.device == device })
            .flatMap { handler -> DeviceWrapper.State? in
                switch handler.state {
                case .connecting: return .connecting
                case .connected: return .connected
                default: return nil
                }
            }
            ?? associatedScanResult(with: device)
            .map { _ in DeviceWrapper.State.readyToConnect }
        ?? .notConnectable
        
        if let scanResultIndex = scanResults.firstIndex(where: { $0 == device }) {
            scanResults[scanResultIndex].availableViaRegisteredDevices = true
        }
    }
    
    private func associatedScanResult(with device: Device) -> ScanResultWrapper? {
        scanResults.first { $0 == device }
    }
    
    private func associatedRegisteredDevice(with scanResult: ScanResult) -> DeviceWrapper? {
        registeredDevices.first { $0 == scanResult }
    }
    
    private func wrapper(for device: Device) -> DeviceWrapper? {
        registeredDevices.first(where: { $0.device == device })
    }
    
    private func wrapper(for scanResult: ScanResult) -> ScanResultWrapper? {
        scanResults.first(where: { $0.scanResult == scanResult })
    }
}

#if DEBUG
import iOS_Common_Libraries

extension iOS_Common_Libraries.Preview {
    
    // MARK: - ScannerData
    
    static let noDevicesScannerData: DeviceData = {
        let deviceData = DeviceData(scanner: Scanner(), registeredDeviceManager: RegisteredDevicesManager(), appData: AppData())
        deviceData.scanResults = []
        return deviceData
    }()
    
    static let isScanningButNoDevicesScannerData: DeviceData = {
        let scanner = Scanner()
        let deviceData = DeviceData(scanner: scanner, registeredDeviceManager: RegisteredDevicesManager(), appData: AppData())
        _ = scanner.turnOnBluetoothRadio()
        deviceData.scanResults = []
        return deviceData
    }()

    static var mockScannerData: DeviceData = {
        let deviceData = DeviceData(scanner: Scanner(), registeredDeviceManager: RegisteredDevicesManager(), appData: AppData())
        deviceData.scanResults = [
            ScanResult(name: "Device 1", uuid: UUID(), rssi: .good, advertisementData: .connectableMock),
            ScanResult(name: "Device 2", uuid: UUID(), rssi: .bad, advertisementData: .connectableMock),
            ScanResult(name: "Device 3", uuid: UUID(), rssi: .ok, advertisementData: .connectableMock)
        ].map { DeviceData.ScanResultWrapper(scanResult: $0) }
        return deviceData
    }()
    
    static var mockRegisteredDevices: DeviceData = {
        let deviceData = DeviceData(scanner: Scanner(), registeredDeviceManager: RegisteredDevicesManager(), appData: AppData())
        var registeredDevices = Array<Device>(repeating: .connectableMock, count: 5)
            .map { DeviceData.DeviceWrapper(device: $0) }
        
        let states: [DeviceData.DeviceWrapper.State] = DeviceData.DeviceWrapper.State.allCases
        
        deviceData.registeredDevices = zip(registeredDevices, states).map {
            var wrapper = $0.0
            wrapper.state = $0.1
            return wrapper
        }
        
        return deviceData
    }()
}

#endif
