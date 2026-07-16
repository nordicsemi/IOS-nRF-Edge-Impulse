//
//  BluetoothManager.swift
//  nRF-Edge-Impulse
//
//  Created by Nick Kibysh on 24/03/2021.
//

import Foundation
import CoreBluetooth
import os
import Combine
import iOSMcuManagerLibrary
import Algorithms

/// Static methods and nested structures
extension BluetoothManager {
    
    struct Error: LocalizedError {
        static let cantRetreivePeripheral = Error(localizedDescription: "Can't retreive the peripheral.")
        static let deviceDoesNotAdvertiseEIService = Error(localizedDescription: "This device does not advertise the expected Edge Impulse Remote Management Service.")
        static let failedToConnect = Error(localizedDescription: "Failed to connect to the peripheral.")
        
        let localizedDescription: String
        
        var errorDescription: String? { localizedDescription }
        var failureReason: String? { localizedDescription }
    }
    
    enum State {
        case notConnected, connecting, connected, disconnected, readyToUse
    }
    
    static let uartServiceId = CBUUID(string: "E2A00001-EC31-4EC3-A97A-1C34D87E9878")
    static let txCharacteristicId = CBUUID(string: "E2A00003-EC31-4EC3-A97A-1C34D87E9878")
    static let rxCharacteristicId = CBUUID(string: "E2A00002-EC31-4EC3-A97A-1C34D87E9878")
}

/// `BluetoothManager` is responsible for connection and managing peripheral connection
/// Each `BluetoothManager` can handle only one peripheral
final class BluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Private Properties
    
    private let centralManager: CBCentralManager
    
    private let transmissionSubject = PassthroughSubject<Data, Never>()
    let receptionSubject = PassthroughSubject<Data, Never>()
    
    @Published var state: State = .notConnected
    internal lazy var btStateSubject = PassthroughSubject<CBManagerState, Swift.Error>()
    
    private let logger = Logger(category: "BluetoothManager")
    
    private var pId: UUID
    private var peripheral: CBPeripheral!
    private var txCharacteristic: CBCharacteristic!
    private var rxCharacteristic: CBCharacteristic!
    private var dfuManager: FirmwareUpgradeManager!
    private lazy var jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()
    
    private var cancellables = Set<AnyCancellable>()
    
    init(peripheralId: UUID) {
        self.centralManager = CBCentralManager()
        self.pId = peripheralId
        super.init()
        
        centralManager.delegate = self
        transmissionSubject
            .map { [weak self] data -> [Data] in
                self?.logger.debug("Write total: \(data.count) bytes")
                guard let self = self,
                      let mtuSize = self.peripheral?.maximumWriteValueLength(for: .withoutResponse) else { return [] }
                
                guard data.count > mtuSize else {
                    return [data]
                }
                return Array(data.chunks(ofCount: mtuSize))
            }
            .sink { [weak self] chunks in
                guard let self = self else { return }
                chunks.enumerated().forEach { i, chunkData in
                    self.logger.debug("Write Chunk \(i): \(chunkData.hexEncodedString()) (\(chunkData.count) bytes)")
                    self.peripheral.writeValue(chunkData, for: self.rxCharacteristic, type: .withoutResponse)
                }
            }
            .store(in: &cancellables)
    }
    
    func connect() -> AnyPublisher<State, Swift.Error> {
        return btStateSubject.drop(while: { $0 != .poweredOn })
            .flatMap { _ -> AnyPublisher<State, Swift.Error> in
                do {
                    try self.tryToConnect()
                } catch let e {
                    return Fail(error: e)
                        .eraseToAnyPublisher()
                }
                return self.$state.setFailureType(to: Swift.Error.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    func write<T: Codable>(_ data: T) throws {
        guard var encodedData = try? jsonEncoder.encode(data) else { return }
        #if DEBUG
        if let dataAsString = String(data: encodedData, encoding: .utf8) {
            print("Write JSON: \(dataAsString)")
        }
        #endif
        encodedData.appendUARTTerminator()
        transmissionSubject.send(encodedData)
    }
    
    func sendUpgradeFirmware(_ firmware: McuMgrPackage, logDelegate: McuMgrLogDelegate,
                             firmwareDelegate: FirmwareUpgradeDelegate) throws {
        guard let peripheral = peripheral else {
            throw DeviceRemoteHandler.Error.stringError("Peripheral is not available (i.e. 'nil')")
        }
        
        let bleTransport = McuMgrBleTransport(peripheral)
        bleTransport.logDelegate = logDelegate
        dfuManager = FirmwareUpgradeManager(transport: bleTransport, delegate: firmwareDelegate)
        dfuManager.logDelegate = logDelegate

        // Start the firmware upgrade with the image data
        let pipelinedConfiguration = FirmwareUpgradeConfiguration(pipelineDepth: 3, byteAlignment: .fourByte)
        dfuManager.start(package: firmware, using: pipelinedConfiguration)
    }
    
    func disconnect() {
        guard let peripheral = peripheral else {
            logger.debug("Peripheral for Device \(self.pId.uuidString) is nil.")
            return
        }
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    private func tryToConnect() throws {
        self.state = .connecting
        
        guard let p = centralManager.retrievePeripherals(withIdentifiers: [pId]).first else {
            throw Error.cantRetreivePeripheral
        }
        
        peripheral = p
        peripheral.delegate = self
        centralManager.connect(p, options: nil)
    }
    
    private func received(_ data: Data) {
        receptionSubject.send(data)
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Swift.Error?) {
        if let e = error {
            logger.error("Failed to dicover services. Error: \(e.localizedDescription)")
            return
        }
        
        guard let uartService = peripheral.services?.first(where: { $0.uuid == Self.uartServiceId }) else {
            btStateSubject.send(completion: .failure(Error.deviceDoesNotAdvertiseEIService))
            return
        }
        logger.info("Did discover service: \(uartService.uuid.uuidString)")
        peripheral.discoverCharacteristics(nil, for: uartService)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Swift.Error?) {
        
        if let e = error {
            logger.error("Failed to discover characteristic. Error: \(e.localizedDescription)")
        }
        
        service.characteristics?.forEach {
            switch $0.uuid {
            case Self.txCharacteristicId:
                txCharacteristic = $0
                logger.info("TX Characteristic discovered")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    peripheral.setNotifyValue(true, for: self.txCharacteristic)
                    self.logger.info("TX Characteristic set to Notify")
                }
            case Self.rxCharacteristicId:
                rxCharacteristic = $0
                logger.info("RX Characteristic discovered")
            default:
                break
            }
        }
        
        guard txCharacteristic != nil, rxCharacteristic != nil else { return }
        state = .readyToUse
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Swift.Error?) {
        logger.info("Notification status has been updated: \(characteristic.isNotifying) for characteristic: \(characteristic)")
        if let e = error {
            logger.error("Error: \(e.localizedDescription)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Swift.Error?) {
        if let e = error {
            logger.warning("Updating characteristic has failed")
            logger.error("\(e.localizedDescription)")
            return
        }
        
        guard let bytesReceived = characteristic.value else {
            logger.info("Notification received from: \(characteristic.uuid.uuidString), with empty value")
            logger.error("Empty packet received")
            return
        }
        
        logger.debug("Received \(ByteCountFormatter.string(fromByteCount: Int64(bytesReceived.count), countStyle: .memory))")
        received(bytesReceived)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("Central Manager state changed to \(central.state)")
        btStateSubject.send(central.state)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected the peripheral: \(peripheral.identifier.uuidString)")
        self.state = .connected
        self.peripheral = peripheral
        self.peripheral.discoverServices([Self.uartServiceId])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Swift.Error?) {
        logger.info("Did fail to connect the peripheral: \(peripheral.identifier.uuidString)")
        logger.error("Error: \(error?.localizedDescription ?? "")")
        let e: Swift.Error = error ?? Error.failedToConnect
        state = .disconnected
        disconnect()
        btStateSubject.send(completion: .failure(e))
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Swift.Error?) {
        logger.info("Did disconnect peripheral: \(peripheral)")
        error.map { logger.error("Did disconnect error: \($0.localizedDescription)") }
        self.peripheral = nil
        state = .disconnected
        disconnect()
        
        if let e = error {
            btStateSubject.send(completion: .failure(e))
        } else {
            btStateSubject.send(completion: .finished)
        }
    }
}

// MARK: - UART Terminator

fileprivate extension Data {
    
    mutating func appendUARTTerminator() {
        // append 'OA'
        append(Data(repeating: 10, count: 1))
    }
}
