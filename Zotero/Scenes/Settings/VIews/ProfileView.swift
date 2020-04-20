//
//  ProfileView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            Section {
                Text(self.username)
            }

            Section {
                Button(action: {
                    self.viewModel.process(action: .setLogoutAlertVisible(true))
                }) {
                    Text("Log out")
                        .foregroundColor(.red)
                }
            }
        }
        .alert(isPresented: self.viewModel.binding(keyPath: \.logoutAlertVisible, action: { .setLogoutAlertVisible($0) })) {
            Alert(title: Text("Warning"),
                  message: Text("Your loca data that were not synced will be deleted. Do you really want to log out?"),
                  primaryButton: .default(Text("Yes"), action: {
                      self.viewModel.process(action: .logout)
                  }),
                  secondaryButton: .cancel(Text("No")))
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
        let state = SettingsState(isSyncing: false,
                                  isLogging: controllers.debugLogging.isEnabled,
                                  isUpdatingTranslators: controllers.translatorsController.isLoading.value,
                                  lastTranslatorUpdate: controllers.translatorsController.lastUpdate)
        let handler = SettingsActionHandler(sessionController: controllers.sessionController,
                                            syncScheduler: controllers.userControllers!.syncScheduler,
                                            debugLogging: controllers.debugLogging,
                                            translatorsController: controllers.translatorsController)
        return ProfileView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
