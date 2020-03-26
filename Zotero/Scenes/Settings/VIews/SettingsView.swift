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

    // SWIFTUI BUG: - presentationMode.wrappedValule.dismiss() doesn't work when presented from UIViewController.
    weak var coordinatorDelegate: MasterSettingsCoordinatorDelegate?

    var body: some View {
        NavigationView {
            SettingsListView()
                .navigationBarTitle("Settings", displayMode: .inline)
                .navigationBarItems(leading: Button(action: { self.coordinatorDelegate?.dismiss() }, label: { Text("Close") }))
            ProfileView()
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
        .onAppear {
            self.viewModel.process(action: .startObservingSyncChanges)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let state = SettingsState(isSyncing: false,
                                  isLogging: controllers.debugLogging.isEnabled)
        let handler = SettingsActionHandler(sessionController: controllers.sessionController,
                                            syncScheduler: controllers.userControllers!.syncScheduler,
                                            debugLogging: controllers.debugLogging)
        return SettingsView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
