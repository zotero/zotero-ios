//
//  StorageSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 04/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct StorageSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<StorageSettingsActionHandler>

    weak var coordinatorDelegate: StorageSettingsSettingsCoordinatorDelegate?

    var body: some View {
        Group {
            if self.viewModel.state.libraries.isEmpty {
                StorageSettingsEmptyView()
            } else {
                self.listView
            }
        }
        .onAppear {
            self.viewModel.process(action: .loadData)
        }
    }

    var listView: some View {
        var view = StorageSettingsListView()
        view.coordinatorDelegate = self.coordinatorDelegate
        return view
    }
}

struct StorageSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let handler = StorageSettingsActionHandler(dbStorage: controllers.userControllers!.dbStorage, fileStorage: controllers.fileStorage,
                                                   fileCleanupController: controllers.userControllers!.fileCleanupController)
        let viewModel = ViewModel(initialState: StorageSettingsState(), handler: handler)
        return StorageSettingsView().environmentObject(viewModel)
    }
}
