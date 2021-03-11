//
//  SettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<SettingsActionHandler>

    weak var coordinatorDelegate: MasterSettingsCoordinatorDelegate?

    var body: some View {
        NavigationView {
            self.settingsList
                .navigationBarTitle(Text(L10n.Settings.title), displayMode: .inline)
                .navigationBarItems(leading: Button(action: { self.coordinatorDelegate?.dismiss() },
                                                    label: { Text("Close").padding(.vertical, 10).padding(.trailing, 10) }))
            ProfileView()
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
        .onAppear {
            self.viewModel.process(action: .startObserving)
        }
    }

    private var settingsList: some View {
        var view = SettingsListView()
        view.coordinatorDelegate = self.coordinatorDelegate
        return view
    }
}

struct SettingsView_Previews: PreviewProvider {
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
                                            translatorsController: controllers.translatorsController)
        return SettingsView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
