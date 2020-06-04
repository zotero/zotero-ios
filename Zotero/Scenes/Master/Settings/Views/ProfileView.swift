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
                    Text(L10n.Settings.logout)
                        .foregroundColor(.red)
                }
            }
        }
        .alert(isPresented: self.viewModel.binding(keyPath: \.logoutAlertVisible, action: { .setLogoutAlertVisible($0) })) {
            Alert(title: Text(L10n.warning),
                  message: Text(L10n.Settings.logoutWarning),
                  primaryButton: .default(Text(L10n.yes), action: {
                      self.viewModel.process(action: .logout)
                  }),
                  secondaryButton: .cancel(Text(L10n.no)))
        }
    }

    private var username: String {
        return Defaults.shared.username
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
