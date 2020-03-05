//
//  SettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private(set) var viewModel: ViewModel<SettingsActionHandler>

    // SWIFTUI BUG: - presentationMode.wrappedValule.dismiss() didn't work when presented from UIViewController, so I pass a closure
    // This view is presented by UIKit, because modals in SwiftUI are currently buggy
//    @Environment(\.presentationMode) private var presentationMode: Binding<PresentationMode>
    let closeAction: () -> Void

    var body: some View {
        NavigationView {
            SettingsListView()
                .navigationBarTitle("Settings", displayMode: .inline)
                .navigationBarItems(leading: Button(action: self.closeAction, label: { Text("Close") }))

            ProfileView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
        return SettingsView(closeAction: {}).environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
