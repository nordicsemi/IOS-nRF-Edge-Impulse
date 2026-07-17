//
//  DeviceData+Sampling.swift
//  nRF-Edge-Impulse
//
//  Created by Nick Kibysh on 21/06/2021.
//

import Foundation
import iOS_Common_Libraries

extension DeviceData {
    
    func startSampling(_ request: BLESampleRequestWrapper, for deviceHandler: DeviceRemoteHandler) {
        guard let samplingPublisher = deviceHandler.samplingRequestPublisher(request) else { return }
        
        dataSamplingCancellable = samplingPublisher
            .timeout(.seconds(TimeInterval(appData.dataAquisitionViewState.sampleLengthS) + TimeInterval.timeoutInterval), scheduler: DispatchQueue.main, customError: { DeviceRemoteHandler.Error.timeout })
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    guard deviceHandler.samplingState != .completed else { return }
                    self.appData.dataAquisitionViewState.samplingEncounteredAnError(error.localizedDescription)
                    AppEvents.shared.error = ErrorEvent(error)
                    
                    guard let cancellable = self.dataSamplingCancellable else { return }
                    self.cancellables.remove(cancellable)
                default:
                    break
                }
            }) { [unowned self] state in
                appData.dataAquisitionViewState.progressString = deviceHandler.samplingState.userDescription
                switch deviceHandler.samplingState {
                case .requestReceived:
                    logger.debug("Sampling Request received.")
                    appData.dataAquisitionViewState.indeterminateProgress = true
                case .requestStarted:
                    logger.debug("Sampling Request started.")
                    appData.dataAquisitionViewState.indeterminateProgress = false
                    appData.dataAquisitionViewState.progress = 0.0
                    appData.dataAquisitionViewState.startCountdownTimer()
                case .receivingFromFirmware:
                    logger.debug("Receiving Sampling Data...")
                    appData.dataAquisitionViewState.stopCountdownTimer()
                    appData.dataAquisitionViewState.progress = 100.0
                    appData.dataAquisitionViewState.indeterminateProgress = true
                    appData.dataAquisitionViewState.progressColor = .nordicBlue
                case .completed:
                    appData.dataAquisitionViewState.stopCountdownTimer()
                    appData.dataAquisitionViewState.progress = 100.0
                    appData.dataAquisitionViewState.indeterminateProgress = false
                    appData.dataAquisitionViewState.isSampling = false
                    appData.dataAquisitionViewState.progressColor = .green
                    
                    logger.debug("Sample Uploaded Successfully. Triggering Request for new Samples.")
                    appData.requestDataSamples()
                    
                    guard let dataSamplingCancellable else { return }
                    cancellables.remove(dataSamplingCancellable)
                default:
                    break
                }
            }
        cancellables.insert(dataSamplingCancellable)
        
        appData.dataAquisitionViewState.isSampling = true
        appData.dataAquisitionViewState.progress = 0.0
        do {
            appData.dataAquisitionViewState.progressString = "Sending Sample Request to Device..."
            try deviceHandler.sendSampleRequestToBLEFirmware(request)
        }
        catch (let error) {
            appData.dataAquisitionViewState.samplingEncounteredAnError(error.localizedDescription)
            AppEvents.shared.error = ErrorEvent(error)
        }
    }
}
