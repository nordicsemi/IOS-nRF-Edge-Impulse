//
//  TwoPaneLayoutView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 17/3/21.
//

import SwiftUI
import iOS_Common_Libraries

// MARK: - TwoPaneLayoutView

struct TwoPaneLayoutView: View {
    
    // MARK: Environment
    
    @EnvironmentObject var appData: AppData
    
    // MARK: view
    
    var body: some View {
        HStack {
            NavigationView {
                List {
                    ForEach(Tabs.availableCases) { tab in
                        HorizontalTabView(tab: tab)
                            .withoutListRowInsets()
                    }
                }
                .listStyle(SidebarListStyle())
                .accentColor(.nordicBlue)
                .toolbarPrincipalImage(Image("Nordic"))
                .setTitle("nRF Edge Impulse")
                .padding(.top, -4)
            }
            .setSingleColumnNavigationViewStyle()
            .setupNavBarBackground(with: Assets.navBarBackground.color)
            .frame(width: 215, alignment: .leading)
            
            // Don't use appData.selectedTab?.view because SwiftUI will not switch well within them
            // if there's a DetailView pushed into the embedded NavigationView.
            VStack {
                switch appData.selectedTab {
                case .Devices?:
                    DeviceList()
                        .setAsDetailView(title: appData.selectedTab?.description)
                case .DataAcquisition?:
                    DataSamplesView()
                        .setAsDetailView(title: appData.selectedTab?.description)
                case .Deployment?:
                    DeploymentView()
                        .environmentObject(appData.deploymentViewState)
                        .setAsDetailView(title: appData.selectedTab?.description)
                case .Inferencing?:
                    InferencingView()
                        .setAsDetailView(title: appData.selectedTab?.description)
                case .Settings?:
                    SettingsContentView()
                        .setAsDetailView(title: appData.selectedTab?.description)
                default:
                    AppHeaderView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.formBackground)
                        .setAsDetailView(title: nil)
                }
            }
            .background(Color.formBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Detail View Configuration

private extension View {
    
    func setAsDetailView(title: String?) -> some View {
        self
            .setTitle(title ?? Constant.appName)
            .toolbar {
                ProjectSelectionView()
                    .toolbarItem()
            }
            .wrapInNavigationViewForiOS(with: Assets.navBarBackground.color)
    }
}

// MARK: - Preview

#if DEBUG
import iOS_Common_Libraries

struct TwoPaneLayoutView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(OSX)
        TwoPaneLayoutView()
            .environmentObject(Preview.mockScannerData)
            .environmentObject(Preview.projectsPreviewAppData)
        #elseif os(iOS)
        TwoPaneLayoutView()
            .previewDevice("iPad Pro (11-inch) (2nd generation)")
            .environmentObject(Preview.mockScannerData)
            .environmentObject(Preview.projectsPreviewAppData)
        #endif
    }
}
#endif
