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

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section {
                Text(self.username)
            }

            Section {
                Button(action: {
                    self.coordinatorDelegate?.showLogoutAlert(viewModel: self.viewModel)
                }) {
                    Text(L10n.Settings.logout)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationBarTitle(L10n.Settings.account)
    }

    private var username: String {
        return Defaults.shared.username
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let state = SettingsState()
        let handler = SettingsActionHandler(sessionController: SessionController(secureStorage: KeychainSecureStorage(), defaults: Defaults.shared))
        return ProfileView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
