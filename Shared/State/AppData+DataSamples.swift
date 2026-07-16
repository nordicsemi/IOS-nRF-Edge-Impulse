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
        guard let selectedProject = selectedProject, selectedProject != Project.Unselected else { return }
        for category in DataSample.Category.allCases {
            requestDataSamples(for: category)
        }
    }
    
    func requestNewSampleID(deliveryBlock: @escaping (StartSamplingResponse?, Error?) -> Void) {
        guard let sampleMessage = dataAquisitionViewState.newSampleMessage(category: selectedCategory),
              let currentProject = selectedProject, let apiKey = apiToken,
              let startRequest = HTTPRequest.startSampling(sampleMessage, project: currentProject, device: dataAquisitionViewState.selectedDevice, using: apiKey) else { return }
        
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
    
    func uploadSample<AnySubject: Subject>(headers: SamplingRequestFinishedResponse.Headers, body: Data,
                                           named sampleName: String, for category: DataSample.Category, subject: AnySubject) where AnySubject.Output == String, AnySubject.Failure == DeviceRemoteHandler.Error {
        guard let uploadRequest = HTTPRequest.uploadSample(headers, body: body, name: sampleName, category: category) else { return }
        Network.shared.perform(uploadRequest)
            .onUnauthorisedUserError(logout)
            .compactMap { String(data: $0, encoding: .utf8) }
            .sinkReceivingError(onError: { error in
                subject.send(completion: .failure(DeviceRemoteHandler.Error.stringError(error.localizedDescription)))
            }, receiveValue: { response in
                subject.send(response)
                subject.send(completion: .finished)
            })
            .store(in: &cancellables)
    }
}

// MARK: - Private

private extension AppData {
    
    // MARK: requestDataSamples(for:)
    
    private func requestDataSamples(for category: DataSample.Category) {
        guard let currentProject = selectedProject,
              let projectApiKey = projectDevelopmentKeys[currentProject]?.apiKey,
              let httpRequest = HTTPRequest.getSamples(for: currentProject, in: category, using: projectApiKey) else {
            requestProjectDevelopmentKeys()
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
        guard let selectedProject, let token = apiToken,
              let httpRequest = HTTPRequest.getProjectDevelopmentKeys(for: selectedProject, using: token) else {
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
        guard let selectedProject, let token = apiToken,
              let addApiKeyRequest = HTTPRequest.addAPIKey(for: selectedProject, using: token),
              let devKeysRequest = HTTPRequest.getProjectDevelopmentKeys(for: selectedProject, using: token) else {
            // TODO: Error
            return
        }
        
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
