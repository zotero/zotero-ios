//
//  FileDownloadSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 30.01.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct FileDownloadSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<SyncSettingsActionHandler>

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Form {
            ForEach(viewModel.state.libraries) { library in
                Picker(library.name, selection: binding(library: library)) {
                    Text("as needed").tag(LibraryFileSyncType.asNeeded)
                    Text("at sync time").tag(LibraryFileSyncType.atSyncTime)
                }
            }
        }
    }

    private func binding(library: Library) -> Binding<LibraryFileSyncType> {
        return viewModel.binding(get: { state in
            return state.libraries.first(where: { $0.identifier == library.identifier })?.fileSyncType ?? .asNeeded
        }, action: { value in
            return .setLibraryFileSyncType(libraryId: library.identifier, syncType: value)
        })
    }
}

extension LibraryFileSyncType {
    fileprivate var title: String {
        switch self {
        case .asNeeded:
            return "as needed"

        case .atSyncTime:
            return "at sync time"
        }
    }
}

#Preview {
    FileDownloadSettingsView()
}
