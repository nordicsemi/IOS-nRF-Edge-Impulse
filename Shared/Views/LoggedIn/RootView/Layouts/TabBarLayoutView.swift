//
//  TabBarLayoutView.swift
//  nRF-Edge-Impulse (iOS)
//
//  Created by Dinesh Harjani on 11/3/21.
//

import SwiftUI

// MARK: - TabBarLayoutView

struct TabBarLayoutView: View {
    
    @EnvironmentObject var appData: AppData
    
    // MARK: init
    
    #if os(iOS)
    init() {
        let appearance = UITabBarAppearance()
        appearance.backgroundColor = UIColor.secondarySystemGroupedBackground
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    #endif
    
    // MARK: view
    
    var body: some View {
        TabView {
            ForEach(Tabs.availableCases) { tab in
                tab.view(with: appData)
                    .setTitle(tab.description)
                    .toolbar {
                        ProjectSelectionView()
                            .toolbarItem()
                    }
                    .wrapInNavigationViewForiOS(with: Assets.navBarBackground.color)
                    .tabItem {
                        Label(tab.description, systemImage: tab.systemImageName)
                    }
                    .tag(tab.rawValue)
            }
        }
        .accentColor(.nordicBlue)
    }
}

// MARK: - Preview

#if DEBUG
import iOS_Common_Libraries

struct TabBarLayoutView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TabBarLayoutView()
                .preferredColorScheme(.light)
                .environmentObject(Preview.projectsPreviewAppData)
                .environmentObject(Preview.mockScannerData)
        }
        Group {
            TabBarLayoutView()
                .preferredColorScheme(.dark)
                .environmentObject(Preview.projectsPreviewAppData)
                .environmentObject(Preview.mockScannerData)
        }
    }
}
#endif
