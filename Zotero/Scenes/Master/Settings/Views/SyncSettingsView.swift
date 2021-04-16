//
//  SyncSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            Section {
                if self.viewModel.state.isSyncing {
                    Button(action: {
                        self.viewModel.process(action: .cancelSync)
                    }) {
                        Text(L10n.Settings.syncCancel).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                } else {
                    Button(action: {
                        self.viewModel.process(action: .startSync)
                    }) {
                        Text(L10n.Settings.sync).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                }
            }
            Section {
                SettingsToggleRow(title: L10n.Settings.permission,
                                  subtitle: L10n.Settings.permissionSubtitle,
                                  value: self.viewModel.binding(keyPath: \.askForSyncPermission, action: { .setAskForSyncPermission($0) }))
            }
        }
        .navigationBarTitle(L10n.Settings.sync)
    }
}

struct SyncSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let state = SettingsState(isSyncing: false,
                                  isLogging: controllers.debugLogging.isEnabled,
                                  isUpdatingTranslators: controllers.translatorsController.isLoading.value,
                                  lastTranslatorUpdate: controllers.translatorsController.lastUpdate,
                                  websocketConnectionState: .disconnected)
        let handler = SettingsActionHandler(dbStorage: controllers.userControllers!.dbStorage,
                                            fileStorage: controllers.fileStorage,
                                            sessionController: controllers.sessionController,
                                            webSocketController: controllers.userControllers!.webSocketController,
                                            syncScheduler: controllers.userControllers!.syncScheduler,
                                            debugLogging: controllers.debugLogging,
                                            translatorsController: controllers.translatorsController,
                                            fileCleanupController: controllers.userControllers!.fileCleanupController)
        return SyncSettingsView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
