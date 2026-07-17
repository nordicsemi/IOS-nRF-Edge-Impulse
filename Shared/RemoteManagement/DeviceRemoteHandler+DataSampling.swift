//
//  DeviceRemoteHandler+DataSampling.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 16/6/21.
//

import Foundation
import Combine

extension DeviceRemoteHandler {
    
    func samplingRequestPublisher(_ request: BLESampleRequestWrapper) -> AnyPublisher<Void, Swift.Error>? {
        let requestReceptionResponse = bluetoothManager.receptionSubject
            .onlyDecode(type: SamplingRequestReceivedResponse.self)
            .tryMap { [weak self] response in
                try self?.webSocketManager.send(response.message)
                guard response.message.sample else {
                    throw DeviceRemoteHandler.Error.stringError("Returned Not Successful")
                }
                self?.samplingState = .requestStarted // Why is this not 'requestReceived' ??
            }
            .eraseToAnyPublisher()
        
        let samplingStartedResponse = bluetoothManager.receptionSubject
            .drop(while: { [unowned self] _ in self.samplingState != .requestReceived })
            .onlyDecode(type: SamplingRequestStartedResponse.self)
            .tryMap { [weak self] response in
                try self?.webSocketManager.send(response.message)
                guard response.message.sampleStarted else {
                    throw DeviceRemoteHandler.Error.stringError("Sampling failed to start")
                }
                self?.samplingState = .requestStarted
            }
            .eraseToAnyPublisher()
        
        let uploadingStartedResponse = bluetoothManager.receptionSubject
            .drop(while: { [unowned self] _ in self.samplingState != .requestStarted })
            .onlyDecode(type: SamplingRequestUploadingResponse.self)
            .tryMap { [weak self] response in
                try self?.webSocketManager.send(response.message)
                guard response.message.sampleUploading else {
                    throw DeviceRemoteHandler.Error.stringError("Failed to obtain Sample from the Firmware")
                }
                self?.samplingState = .receivingFromFirmware
            }
            .eraseToAnyPublisher()
        
        let uploadSampleResponseSubject = PassthroughSubject<String, DeviceRemoteHandler.Error>()
        
        let uploadPublisher = uploadSampleResponseSubject
            .tryMap { [weak self] serverResponse in
                print(serverResponse)
                self?.samplingState = .completed
            }
            .eraseToAnyPublisher()
        
        let samplingResultResponse = bluetoothManager.receptionSubject
            .drop(while: { [unowned self] _ in self.samplingState != .receivingFromFirmware })
            .compactMap {
                // Filter-out the data from this JSON, because they are received too fast from each other.
                if let _ = try? JSONDecoder().decode(SamplingRequestUploadingResponse.self, from: $0) {
                    return nil
                } else {
                    return $0
                }
            }
            .gatherData(ofType: SamplingRequestFinishedResponse.self)
            .tryMap { [weak self] response in
                #if DEBUG
                let encoder = JSONEncoder()
                encoder.outputFormatting = .withoutEscapingSlashes
                if let jsonData = try? encoder.encode(response), let jsonText = String(data: jsonData, encoding: .utf8) {
                    self?.logger.debug("Full Response: \(jsonText)")
                }
                #endif
                
                guard let decodedBody = Data(base64Encoded: response.body) else {
                    throw DeviceRemoteHandler.Error.stringError("Response does not contain valid base64 Data.")
                }
                self?.samplingState = .uploadingSample
                self?.appData.uploadSample(headers: response.headers, body: decodedBody, named: request.message.sample.label, for: request.dataSampleCategory(), subject: uploadSampleResponseSubject)
            }
            .eraseToAnyPublisher()
        
        return Publishers.MergeMany([requestReceptionResponse, samplingStartedResponse,
                                     uploadingStartedResponse, samplingResultResponse, uploadPublisher])
            .eraseToAnyPublisher()
    }
    
    func sendSampleRequestToBLEFirmware(_ request: BLESampleRequestWrapper) throws {
        try bluetoothManager.write(request)
    }
}
