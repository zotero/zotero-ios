//
//  StorageSettingsListView.swift
//  Zotero
//
//  Created by Michal Rentka on 04/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct StorageSettingsListView: View {
    @EnvironmentObject var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        List {
            Section {
                ForEach(self.viewModel.state.libraries) { library in
                    StorageSettingsRow(title: library.name, data: self.viewModel.state.storageData[library.identifier], deleteAction: {
                        self.viewModel.process(action: .showDeleteLibraryQuestion(library))
                    })
                }

                StorageSettingsRow(title: L10n.total.uppercased(), data: self.viewModel.state.totalStorageData, deleteAction: nil)

                if self.viewModel.state.totalStorageData.fileCount > 0 {
                    Button(action: {
                        self.viewModel.process(action: .showDeleteAllQuestion(true))
                    }) {
                        Text(L10n.Settings.Storage.deleteAll).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                }
            }

            Section {
                StorageSettingsRow(title: L10n.Settings.Storage.cache, data: self.viewModel.state.cacheData, deleteAction: nil)

                if self.viewModel.state.cacheData.fileCount > 0 {
                    Button(action: {
                        self.viewModel.process(action: .showDeleteAllQuestion(true))
                    }) {
                        Text(L10n.Settings.Storage.deleteCache).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                }
            }
        }.listStyle(GroupedListStyle())
    }
}

struct StorageSettingsListView_Previews: PreviewProvider {
    static var previews: some View {
        StorageSettingsListView()
    }
}
