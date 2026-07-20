//
//  DeploymentView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 22/3/21.
//

import SwiftUI
import Combine
import iOS_Common_Libraries

// MARK: - DeploymentView

struct DeploymentView: View {
    
    // MARK: Environment
    
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var deviceData: DeviceData
    @EnvironmentObject var viewState: DeploymentViewState
    
    // MARK: view
    
    var body: some View {
        FormIniOSListInMacOS {
            if viewState.pipelineManager.started {
                DeploymentProgressView()
                    .environmentObject(viewState)
            } else {
                DeploymentConfigurationView()
                    .environmentObject(viewState)
                    .environmentObject(deviceData)
            }
            
            if let error = viewState.pipelineManager.error {
                DeploymentErrorView(error)
            }
            
            Section {
                Button(viewState.buildButtonText, action: buttonAction)
                    .centerTextInsideForm()
                    .disabled(!viewState.buildButtonEnable)
                #if os(iOS)
                    .foregroundColor(viewState.buildButtonEnable
                                     ? .positiveActionButtonColor : .disabledTextColor)
                #endif
            }
        }
        .background(Color.formBackground)
    }
}

// MARK: - Preview

#if DEBUG
import iOS_Common_Libraries

struct DeploymentView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            DeploymentView()
                .setTitle(Tabs.Deployment.description)
                .wrapInNavigationViewForiOS(with: Assets.navBarBackground.color)
                .environmentObject(DeploymentViewState())
                .environmentObject(Preview.noDevicesAppData)
                .environmentObject(Preview.noDevicesScannerData)
        }
    }
}
#endif
