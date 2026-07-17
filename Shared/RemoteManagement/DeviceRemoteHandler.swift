//
//  DeviceRemoteHandler.swift
//  nRF-Edge-Impulse
//
//  Created by Nick Kibysh on 07/04/2021.
//

import Foundation
import Combine
import os

extension DeviceRemoteHandler {
    
    enum Error: LocalizedError {
        case anyError(Swift.Error)
        case stringError(String)
        case timeout
        case connectionEstablishFailed
        
        var failureReason: String? { errorDescription }
        var errorDescription: String? {
            switch self {
            case .anyError(let e):
                return e.localizedDescription
            case .timeout:
                return "Connection timed out."
            case .stringError(let s):
                return s
            case .connectionEstablishFailed:
                return "Unable to establish connection."
            }
        }
    }
    
    enum ConnectionState: CustomDebugStringConvertible {
        case notConnected, connecting(ScanResult), connected(ScanResult, Device), disconnected(DisconnectReason)
        
        var debugDescription: String {
            switch self {
            case .connected(_, let device):
                return "Connected to \(device.id)"
            case .connecting(let device):
                return "Connecting to \(device.name)"
            case .notConnected:
                return "Not Connected"
            case .disconnected(let reason):
                return "Disconnected. Reason: \(reason)"
            }
        }
    }
    
    enum DisconnectReason: CustomDebugStringConvertible {
        case error(Swift.Error), onDemand, dfuReset
        
        var debugDescription: String {
            switch self {
            case .error(let e):
                return e.localizedDescription
            case .onDemand:
                return "On Demand"
            case .dfuReset:
                return "DFU"
            }
        }
    }
}

// MARK: - DeviceRemoteHandler

final class DeviceRemoteHandler {
    
    private static let RemoteManagementURLString = "wss://remote-mgmt.edgeimpulse.com"
    
    internal let logger = Logger(category: "DeviceRemoteHandler")
    
    private(set) var scanResult: ScanResult
    private(set) var device: Device?
    
    @Published var state: ConnectionState = .notConnected
    @Published var samplingState: SamplingState = .standby
    @Published var inferencingState: InferencingState = .stopped
    
    private(set) lazy var bluetoothManager = BluetoothManager(peripheralId: self.scanResult.uuid)
    internal var webSocketManager: WebSocketManager!
    private lazy var cancellables = Set<AnyCancellable>()
    
    private let registeredDeviceManager: RegisteredDevicesManager
    internal let appData: AppData
    
    init(scanResult: ScanResult, device: Device? = nil, registeredDeviceManager: RegisteredDevicesManager = RegisteredDevicesManager(),
         appData: AppData) {
        self.registeredDeviceManager = registeredDeviceManager
        self.scanResult = scanResult
        self.appData = appData
        self.device = device
        
        webSocketManager = WebSocketManager()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    func rename(to newName: String) {
        device?.name = newName
    }
    
    func connect(apiKey: String) -> AnyPublisher<ConnectionState, Never> {
        state = .connecting(scanResult)
        
        newBLEDisconnectionCancellable()
            .store(in: &cancellables)
        
        let pingConfiguration = WebSocketManager.PingConfiguration()
        return bluetoothManager.connect()
            .drop(while: { $0 != .readyToUse })
            .first()
            .flatMap { _ in self.bluetoothManager.receptionSubject.gatherData(ofType: ResponseRootObject.self) }
            .combineLatest(
                webSocketManager.connect(to: Self.RemoteManagementURLString, using: pingConfiguration)
                    .drop(while: { $0 != .connected })
            )
            .flatMap { [weak self] (data, _) -> AnyPublisher<Data, Swift.Error> in
                guard var webSocketHello = data.message, let self = self else {
                    return Fail(error: Error.connectionEstablishFailed)
                        .eraseToAnyPublisher()
                }
                
                webSocketHello.hello?.apiKey = apiKey
                webSocketHello.hello?.deviceId = self.scanResult.id
                do {
                    try self.webSocketManager.send(webSocketHello)
                } catch let e {
                    return Fail(error: e).eraseToAnyPublisher()
                }
                
                return self.newWebSocketDataPublisher()
            }
            .decode(type: WSHelloResponse.self, decoder: JSONDecoder())
            .flatMap { [registeredDeviceManager] response -> AnyPublisher<Device, Swift.Error> in
                if let e = response.err {
                    return Fail(error: Error.stringError(e))
                        .eraseToAnyPublisher()
                } else {
                    return registeredDeviceManager.fetchDevice(deviceId: self.scanResult.id, appData: self.appData)
                }
            }
            .justDoIt { [weak self] device in
                guard let self = self else { return }
                if let d = self.device, d.deviceId == device.deviceId {
                    return
                } else {
                    self.device = device
                    self.state = .connected(self.scanResult, device)
                }
            }
            .tryMap { [weak self] registeredDevice in
                guard let self = self else {
                    throw DeviceRemoteHandler.Error.connectionEstablishFailed
                }
                let bleHello = BLEHelloMessageContainer(message: BLEHelloMessage(hello: true))
                try self.bluetoothManager.write(bleHello)
                
                if let currentProject = self.appData.selectedProject,
                   let projectApiKey = self.appData.projectDevelopmentKeys[currentProject]?.apiKey {
                    let bleConfigure = BLEConfigureMessageContainer(message: BLEConfigureMessage(apiKey: projectApiKey))
                    try self.bluetoothManager.write(bleConfigure)
                }
                
                return ConnectionState.connected(self.scanResult, registeredDevice)
            }
            .prefix(1)
            .timeout(25, scheduler: DispatchQueue.main, customError: { Error.timeout })
            .catch { [weak self] error -> Just<ConnectionState> in
                self?.disconnect(reason: .error(error))
                return Just(ConnectionState.disconnected(.error(error)))
            }
            .eraseToAnyPublisher()
    }
    
    internal func disconnect(reason: DisconnectReason) {
        bluetoothManager.disconnect()
        webSocketManager.disconnect()
        
        self.state = .disconnected(reason)
        let deviceName = scanResult.name
        logger.info("\(deviceName) Disconnected.")
    }
    
    func disconnect() {
        disconnect(reason: .onDemand)
    }
}

// MARK: - Private

fileprivate extension DeviceRemoteHandler {
    
    func newBLEDisconnectionCancellable() -> AnyCancellable {
        return bluetoothManager.btStateSubject
            .drop(while: { $0 != .poweredOn })
            .filter { [weak self] _ in
                switch self?.state {
                case .connected(_, _):
                    return true
                default:
                    return false
                }
            }
            .sinkReceivingError(onError: { [weak self] error in
                self?.disconnect(reason: .error(error))
            }, receiveValue: { [weak self] a in
                switch self?.bluetoothManager.state {
                case .notConnected, .disconnected:
                    self?.disconnect()
                default:
                    break
                }
            })
    }
    
    func newWebSocketDataPublisher() -> AnyPublisher<Data, Swift.Error> {
        return webSocketManager.dataSubject
            .tryMap { (result) -> Data in
                switch result {
                case .success(let data):
                    return data
                case .failure(let error):
                    throw error
                }
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - DeviceRemoteHandler.SamplingState

extension DeviceRemoteHandler {
    
    enum SamplingState {
        case standby
        case requestReceived, requestStarted
        case receivingFromFirmware
        case uploadingSample, completed
        
        var userDescription: String {
            switch self {
            case .standby:
                return ""
            case .requestReceived:
                return "Request Received"
            case .requestStarted:
                return "Sampling Started"
            case .receivingFromFirmware:
                return "Sampling Complete. Receiving Data..."
            case .uploadingSample:
                return "Uploading Firmware to Edge Impulse..."
            case .completed:
                return "Success!"
            }
        }
    }
}

// MARK: - Hashable, Equatable

extension DeviceRemoteHandler: Hashable, Identifiable {
    
    var id: String {
        scanResult.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(scanResult)
    }
    
    static func == (lhs: DeviceRemoteHandler, rhs: DeviceRemoteHandler) -> Bool {
        lhs.scanResult == rhs.scanResult
    }
    
    static func == (lhs: DeviceRemoteHandler, rhs: ScanResult) -> Bool {
        lhs.scanResult == rhs
    }
}

#if DEBUG
extension DeviceRemoteHandler {
    static let connectableMock = DeviceRemoteHandler(scanResult: ScanResult.sample, registeredDeviceManager: RegisteredDevicesManager(), appData: AppData())
}
#endif
