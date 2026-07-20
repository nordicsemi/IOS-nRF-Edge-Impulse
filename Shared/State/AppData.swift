//
//  AppData.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 1/3/21.
//

import Foundation
import KeychainSwift
import Combine
import os
import iOS_Common_Libraries

// MARK: - AppData

final class AppData: ObservableObject {
    
    // MARK: Public Properties
    
    @Published var apiToken: String? {
        didSet {
            if let newToken = apiToken {
                keychain.write(newToken)
            } else {
                keychain.remove()
            }
        }
    }
    
    @Published var loginState: AppData.LoginState = .empty
    
    @Published var selectedProject: Project? = Project.Unselected {
        didSet {
            appLog.debug("selectedProject.didSet {}")
            selectedProjectDidChange()
        }
    }
    @Published var selectedTab: Tabs? = .Devices
    
    @Published var projectDevelopmentKeys: [Project: ProjectDevelopmentKeysResponse]
    @Published var projectSocketTokens: [Project: Token]
    @Published var projects: [Project] = []
    @Published var user: User?
    
    @Published var samplesForCategory: [DataSample.Category: [DataSample]]
    @Published var selectedCategory: DataSample.Category = .training
    @Published internal var dataAquisitionViewState = DataAcquisitionViewState()
    @Published internal var inferencingViewState = InferencingViewState()
    @Published internal var deploymentViewState = DeploymentViewState()
    
    // MARK: Private Properties
    
    private lazy var keychain = KeychainSwift(keyPrefix: Constant.appName)
    internal var cancellables = Set<AnyCancellable>()
    
    internal lazy var appLog = NordicLog(self, subsystem: Logger.EdgeImpulseSubsystem)
    
    // MARK: init
    
    init() {
        self.projectDevelopmentKeys = [Project: ProjectDevelopmentKeysResponse]()
        self.projectSocketTokens = [Project: Token]()
        self.samplesForCategory = [DataSample.Category: [DataSample]]()
        self.apiToken = keychain.get("apiToken")
        
        // If inferencingViewState changes, make sure appData 'fires' as if a change has happened,
        // to alert InferencingView.
        inferencingViewState.objectWillChange
            .receive(on: RunLoop.main)
            .sink(receiveValue: { self.objectWillChange.send() })
            .store(in: &cancellables)
    }
    
    // MARK: API
    
    var isLoggedIn: Bool { apiToken != nil }
    
    func logout() {
        selectedProject = Project.Unselected
        projects = []
        user = nil
        projectSocketTokens = [Project: Token]()
        apiToken = nil
        loginState = .empty
        selectedProjectDidChange()
    }
}

// MARK: - AppData

fileprivate extension AppData {
    
    func selectedProjectDidChange() {
        projectDevelopmentKeys = [Project: ProjectDevelopmentKeysResponse]()
        samplesForCategory = [:]
        requestDataSamples()
        requestSelectedProjectSocketToken()
    }
}

// MARK: - KeychainSwift Helpers

fileprivate extension KeychainSwift {
    
    func read(key: String = #function) -> String? {
        get(key)
    }
    
    func write(_ value: String, key: String = #function) {
        guard !Constant.isRunningInPreviewMode() else { return }
        set(value, forKey: key)
    }
    
    func remove(key: String = #function) {
        delete(key)
    }
}
