//
//  ProfileView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private(set) var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            Section {
                Text(self.username)
            }

            Section {
                Button(action: {
                    self.viewModel.process(action: .logout)
                }) {
                    Text("Log out")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var username: String {
        let username = Defaults.shared.username
        return username.isEmpty ? "Missing username" : username
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let state = SettingsState(isSyncing: false)
        let handler = SettingsActionHandler(sessionController: controllers.sessionController,
                                            syncScheduler: controllers.userControllers!.syncScheduler)
        return ProfileView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
