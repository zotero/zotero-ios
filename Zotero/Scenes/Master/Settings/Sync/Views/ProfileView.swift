//
//  ProfileView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: ViewModel<SyncSettingsActionHandler>

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section(header: Text("Data Syncing")) {
                Text(self.viewModel.state.account)

                Button(action: {
                    self.coordinatorDelegate?.showLogoutAlert(viewModel: self.viewModel)
                }) {
                    Text(L10n.Settings.logout)
                        .foregroundColor(.red)
                }
            }

            Section(header: Text("File Syncing")) {
                Picker("Sync attachment files in My Library using", selection: self.viewModel.binding(get: \.fileSyncType, action: { .setFileSyncType($0) })) {
                    Text("Zotero").tag(SyncSettingsState.FileSyncType.zotero)
                    Text("WebDAV").tag(SyncSettingsState.FileSyncType.webDav)
                }

                if self.viewModel.state.fileSyncType == .webDav {
                    HStack {
                        Picker("Scheme", selection: self.viewModel.binding(get: \.scheme, action: { .setScheme($0) })) {
                            Text("http").tag(WebDavScheme.http)
                            Text("https").tag(WebDavScheme.https)
                        }

                        TextField("URL", text: self.viewModel.binding(get: \.url, action: { .setUrl($0) }))
                    }
                }
            }
        }
        .navigationBarTitle(L10n.Settings.account)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        return ProfileView()
    }
}
