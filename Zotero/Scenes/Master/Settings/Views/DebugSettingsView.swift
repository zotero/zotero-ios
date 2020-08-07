//
//  DebugSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 04/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct DebugSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            Section {
                if self.viewModel.state.isLogging {
                    Button(action: {
                        self.viewModel.process(action: .stopLogging)
                    }) {
                        Text("Stop logging").foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Text(L10n.Settings.loggingDesc1)
                    Text(L10n.Settings.loggingDesc2)
                } else {
                    Button(action: {
                        self.viewModel.process(action: .startImmediateLogging)
                    }) {
                        Text(L10n.Settings.startLogging).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                }
            }
        }
    }
}

struct DebugSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        DebugSettingsView()
    }
}
