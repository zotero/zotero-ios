//
//  StorageSettingsListView.swift
//  Zotero
//
//  Created by Michal Rentka on 04/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct StorageSettingsListView: View {
    @EnvironmentObject var viewModel: ViewModel<StorageSettingsActionHandler>

    weak var coordinatorDelegate: StorageSettingsSettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section(header: Text("Attachment storage")) {
                Picker("Attachment storage", selection: Binding(get: {
                    self.viewModel.state.storagePreference
                }, set: { newValue in
                    self.viewModel.process(action: .setStoragePreference(newValue))
                })) {
                    Text("On this device").tag(AttachmentStoragePreference.appGroup)
                    Text("iCloud").tag(AttachmentStoragePreference.iCloud).disabled(!self.viewModel.state.iCloudAvailable)
                }
                .pickerStyle(SegmentedPickerStyle())

                if !self.viewModel.state.iCloudAvailable {
                    Text("iCloud is unavailable for this account/device.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                ForEach(self.viewModel.state.libraries) { library in
                    StorageSettingsRow(title: library.name, data: self.viewModel.state.storageData[library.identifier], deleteAction: {
                        self.coordinatorDelegate?.showDeleteLibraryStorageAlert(for: library, viewModel: self.viewModel)
                    })
                }

                StorageSettingsRow(title: L10n.total.uppercased(), data: self.viewModel.state.totalStorageData, deleteAction: nil)
            }

            if self.viewModel.state.totalStorageData.fileCount > 0 {
                Section {
                    Button {
                        self.coordinatorDelegate?.showDeleteAllStorageAlert(viewModel: self.viewModel)
                    } label: {
                        Text(L10n.Settings.Storage.deleteAll).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                }
            }
        }
    }
}

struct StorageSettingsListView_Previews: PreviewProvider {
    static var previews: some View {
        StorageSettingsListView()
    }
}
