//
//  ManageAccountView.swift
//  Zotero
//
//  Created by Michal Rentka on 16/04/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ManageAccountView: View {
    @EnvironmentObject var viewModel: ViewModel<SyncSettingsActionHandler>

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section {
                Button {
                    coordinatorDelegate?.showWeb(url: URL(string: "https://www.zotero.org/settings")!, completion: {
                        viewModel.process(action: .recheckKeys)
                    })
                } label: {
                    Text(L10n.Settings.Sync.accountSettings)
                        .foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUiColor)
                }

                Button {
                    coordinatorDelegate?.showWeb(url: URL(string: "https://www.zotero.org/settings/security#delete")!, completion: {
                        viewModel.process(action: .recheckKeys)
                    })
                } label: {
                    Text(L10n.Settings.Sync.deleteAccount)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationBarTitle(L10n.Settings.Sync.manageAccount)
    }
}
