//
//  SyncSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private(set) var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            Section {
                if self.viewModel.state.isSyncing {
                    Button(action: {
                        self.viewModel.process(action: .cancelSync)
                    }) {
                        Text("Cancel ongoing sync")
                    }
                } else {
                    Button(action: {
                        self.viewModel.process(action: .startSync)
                    }) {
                        Text("Sync with zotero.org")
                    }
                }
            }
            Section {
                SettingsToggleRow(title: "User Permission",
                                  subtitle: "Ask for user permission for each write action",
                                  value: self.viewModel.binding(keyPath: \.askForSyncPermission, action: { .setAskForSyncPermission($0) }))
            }
        }
    }
}

struct SyncSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let state = SettingsState(isSyncing: false)
        let handler = SettingsActionHandler(sessionController: controllers.sessionController,
                                            syncScheduler: controllers.userControllers!.syncScheduler)
        return SyncSettingsView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
