//
//  DebugSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 04/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct DebugSettingsView: View {
    @EnvironmentObject private(set) var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            Section {
                if self.viewModel.state.isWaitingOnTermination {
                    Text("Please force-quit the app now. Once you start it again, debug logging will start automatically.")
                } else if self.viewModel.state.isLogging {
                    Button(action: {
                        self.viewModel.process(action: .stopLogging)
                    }) {
                        Text("Stop logging")
                    }
                } else {
                    Button(action: {
                        self.viewModel.process(action: .startImmediateLogging)
                    }) {
                        Text("Start logging now")
                    }

                    Button(action: {
                        self.viewModel.process(action: .startLoggingOnNextLaunch)
                    }) {
                        Text("Start logging on next launch")
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
