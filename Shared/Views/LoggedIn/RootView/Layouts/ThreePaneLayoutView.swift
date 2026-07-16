//
//  ThreePaneLayoutView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 13/4/21.
//

import SwiftUI

// MARK: - ThreePaneLayoutView

struct ThreePaneLayoutView: View {
    
    // MARK: Properties
    
    @EnvironmentObject var appData: AppData
    
    // MARK: view
    
    var body: some View {
        NavigationSplitView(sidebar: {
            VStack(alignment: .leading) {
                List {
                    Section("Tabs") {
                        ForEach(Tabs.availableCases) { tab in
                            NavigationLink(destination: tab.view(with: appData)) {
                                Label(tab.description, systemImage: tab.systemImageName)
                                    .tag(tab)
                            }
                        }
                    }

                    if let user = appData.user {
                        let userTab = Tabs.User
                        Section(userTab.description) {
                            NavigationLink(destination: userTab.view(with: appData)) {
                                Label(user.formattedName, systemImage: userTab.systemImageName)
                                    .tag(userTab)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                SmallAppIconAndVersionView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: .sidebarWidth, ideal: 215.0)
        }, content: {
            AppHeaderView()
                .navigationSplitViewColumnWidth(min: .minTabWidth, ideal: 1.25 * .minTabWidth)
        }, detail: {
            AppHeaderView()
                .navigationSplitViewColumnWidth(min: .minTabWidth, ideal: 1.25 * .minTabWidth)
        })
        .toolbar {
            ProjectSelectionView()
                .toolbarItem()
        }
        .frame(
            minHeight: 720,
            maxHeight: .infinity,
//            alignment: .leading
        )
//        .frame(width: 1280, height: 748) // Frame for 1280x800 screenshots.
    }
}

// MARK: - Preview

#if DEBUG
import iOS_Common_Libraries

struct ThreePaneLayoutView_Previews: PreviewProvider {
    static var previews: some View {
        ThreePaneLayoutView()
            .environmentObject(Preview.projectsPreviewAppData)
    }
}
#endif
