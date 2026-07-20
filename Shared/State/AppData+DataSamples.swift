//
//  AppData+DataSamples.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 4/5/21.
//

import Foundation
import Combine
import iOS_Common_Libraries

// MARK: - Public API

extension AppData {
    
    func requestDataSamples() {
        appLog.debug(#function)
        guard let selectedProject, selectedProject != Project.Unselected else { return }
        
        guard haveProjectKeys(for: selectedProject) else {
            requestProjectDevelopmentKeys()
            return
        }
        
        for category in DataSample.Category.allCases {
            requestDataSamples(for: category)
        }
    }
    
    func requestNewSampleID(deliveryBlock: @escaping (StartSamplingResponse?, Error?) -> Void) {
        guard let sampleMessage = dataAquisitionViewState.newSampleMessage(category: selectedCategory),
              let selectedProject, let apiToken,
              let startRequest = HTTPRequest.startSampling(sampleMessage, project: selectedProject, device: dataAquisitionViewState.selectedDevice, using: apiToken) else { return }
        
        Network.shared.perform(startRequest, responseType: StartSamplingResponse.self)
            .onUnauthorisedUserError(logout)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { result in
                switch result {
                case .failure(let error):
                    deliveryBlock(nil, error)
                default:
                    break
                }
            }, receiveValue: { response in
                deliveryBlock(response, nil)
            })
            .store(in: &cancellables)
    }
    
    func uploadSample<AnySubject: Subject>(
        headers: SamplingRequestFinishedResponse.Headers, body: Data,
        named sampleName: String, for category: DataSample.Category, subject: AnySubject) where AnySubject.Output == String, AnySubject.Failure == DeviceRemoteHandler.Error {
            
        guard let uploadRequest = HTTPRequest.uploadSample(headers, body: body, name: sampleName, category: category) else { return }
        Network.shared.perform(uploadRequest)
            .onUnauthorisedUserError(logout)
            .tryMap { (response: NetworkResponse) -> String in
                // If we get NetworkResponse it's usually "OK" HTTP StatusCode.
                // See Network.shared.perform() implementation.
                guard let stringResponse = String(data: response.data, encoding: .utf8) else {
                    throw DeviceRemoteHandler.Error.stringError("Unable to parse String response from Upload Sample API.")
                }
                return stringResponse
            }
            .sinkReceivingError(onError: { error in
                subject.send(completion: .failure(DeviceRemoteHandler.Error.stringError(error.localizedDescription)))
            }, receiveValue: { stringResponse in
                subject.send(stringResponse)
                subject.send(completion: .finished)
            })
            .store(in: &cancellables)
    }
}

// MARK: - Private

private extension AppData {
    
    // MARK: haveProjectKeys(for:)
    
    private func haveProjectKeys(for project: Project) -> Bool {
        projectDevelopmentKeys[project] != nil
    }
    
    // MARK: requestDataSamples(for:)
    
    private func requestDataSamples(for category: DataSample.Category) {
        guard let selectedProject,
              let projectApiKey = projectDevelopmentKeys[selectedProject]?.apiKey,
              let httpRequest = HTTPRequest.getSamples(for: selectedProject, in: category, using: projectApiKey) else {
            if let selectedProject {
                appLog.error("Project Development Keys for \(selectedProject.name) are missing.")
            }
            return
        }
        
        Network.shared.perform(httpRequest, responseType: GetSamplesResponse.self)
            .receive(on: RunLoop.main)
            .onUnauthorisedUserError(logout)
            .sinkOrRaiseAppEventError { [weak self] samplesResponse in
                self?.samplesForCategory[category] = samplesResponse.samples
            }
            .store(in: &cancellables)
    }
    
    // MARK: requestProjectDevelopmentKeys()
    
    private func requestProjectDevelopmentKeys() {
        guard let selectedProject, let apiToken,
              let httpRequest = HTTPRequest.getProjectDevelopmentKeys(for: selectedProject, using: apiToken) else {
            // TODO: Error
            return
        }
        
        Network.shared.perform(httpRequest, responseType: ProjectDevelopmentKeysResponse.self)
            .receive(on: RunLoop.main)
            .onUnauthorisedUserError(logout)
            .sink(receiveCompletion: { [weak self] completion in
                switch completion {
                case .finished:
                    break // No-op.
                case .failure:
                    self?.apiKeyMissing()
                }
            }, receiveValue: { [weak self] projectKeysResponse in
                self?.obtainedKeys(projectKeysResponse, for: selectedProject)
            })
            .store(in: &cancellables)
    }
    
    // MARK: apiKeyMissing
    
    private func apiKeyMissing() {
        guard let selectedProject, let apiToken,
              let addApiKeyRequest = HTTPRequest.addAPIKey(for: selectedProject, using: apiToken),
              let devKeysRequest = HTTPRequest.getProjectDevelopmentKeys(for: selectedProject, using: apiToken) else {
            // TODO: Error
            return
        }
        
        appLog.debug(#function)
        Network.shared.perform(addApiKeyRequest, responseType: AddAPIKeyResponse.self)
            .receive(on: RunLoop.main)
            .onUnauthorisedUserError(logout)
            .tryMap({ addApiKeyResponse in
                guard addApiKeyResponse.success else {
                    throw ErrorEvent(title: "Unable to Add Development Key", localizedDescription: "We tried to add a new Development Key because none was present, but this attempt failed.")
                }
            })
            .flatMap({ _ in
                return Network.shared.perform(devKeysRequest, responseType: ProjectDevelopmentKeysResponse.self)
            })
            .receive(on: RunLoop.main)
            .sinkOrRaiseAppEventError(receiveValue: { [weak self] projectKeysResponse in
                self?.obtainedKeys(projectKeysResponse, for: selectedProject)
            })
            .store(in: &cancellables)
    }
    
    // MARK: obtainedKeys(_:for:)
    
    private func obtainedKeys(_ keys: ProjectDevelopmentKeysResponse, for project: Project) {
        projectDevelopmentKeys[project] = keys
        requestDataSamples()
        requestSelectedProjectSocketToken()
    }
}
