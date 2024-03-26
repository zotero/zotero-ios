//
//  FullSyncDebuggingView.swift
//  Zotero
//
//  Created by Michal Rentka on 26.03.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct FullSyncDebuggingView: View {
    @EnvironmentObject var viewModel: ViewModel<FullSyncDebuggingActionHandler>

    var body: some View {
        Form {
            Section {
                Button {
                    viewModel.process(action: .start)
                } label: {
                    Text(L10n.Settings.FullSync.start).foregroundColor(viewModel.state.syncTypeInProgress == nil ? Asset.Colors.zoteroBlue.swiftUiColor : Color(.systemGray))
                }
                .disabled(viewModel.state.syncTypeInProgress != nil)

                if let type = viewModel.state.syncTypeInProgress {
                    if type == .full {
                        Text(L10n.Settings.FullSync.inProgress)
                    } else {
                        Text(L10n.Settings.FullSync.otherInProgress)
                    }
                }
            }
        }
        .navigationBarTitle(L10n.Settings.fullSyncDebug)
    }
}

#Preview {
    FullSyncDebuggingView()
}
