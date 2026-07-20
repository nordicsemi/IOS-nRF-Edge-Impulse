//
//  UserContentView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 22/4/21.
//

import SwiftUI
import iOS_Common_Libraries

// MARK: - UserContentView

struct UserContentView: View {
    
    // MARK: Environment
    
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var deviceData: DeviceData
    
    // MARK: Private
    
    @State internal var deleteUserPassword = ""
    @State internal var deleteUserTotpToken = ""
    @State internal var showingDeleteUserAccountAlert = false
    
    // MARK: view
    
    var body: some View {
        if let user = appData.user {
            List {
                UserView(user)
                
                Section(header: Text("Projects")) {
                    if appData.projects.isEmpty {
                        VStack(alignment: .center, spacing: 16) {
                            Image(systemName: "moon.stars.fill")
                                .resizable()
                                .frame(width: 60, height: 60, alignment: .center)
                                .foregroundColor(.nordicBlueslate)
                            Text("Your Project List is empty.")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    ForEach(appData.projects) { project in
                        NavigationLink(destination: ProjectView(project)) {
                            ProjectRow(project)
                        }
                    }
                }
                
                Section("Account") {
                    Button("Logout", action: logout)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.positiveActionButtonColor)
                }
                
                Section(content: {
                    Button("Delete", action: showDeleteUserAccountAlert)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.red)
                }, footer: {
                    Text(Strings.accountDeletionFooter)
                        .font(.caption)
                })
            }
            .setTitle("User")
            .modifier(alertViewModifier(for: user))
        } else {
            EmptyView()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct UserContentView_Previews: PreviewProvider {
    
    static let loggedInWithoutUser: AppData = {
        let appData = AppData()
        appData.apiToken = "A"
        appData.loginState = .empty
        return appData
    }()
    
    static var previews: some View {
        Group {
            UserContentView()
                .environmentObject(Preview.noProjectsAppData)
            UserContentView()
                .environmentObject(Preview.projectsPreviewAppData)
        }
    }
}
#endif
