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
                        Text("Stop logging")
                    }

                    Text("If you want to debug an issue on launch, kill the app and start it again.")
                    Text("If you want to debug share extension issue, open the share extension.")
                } else {
                    Button(action: {
                        self.viewModel.process(action: .startImmediateLogging)
                    }) {
                        Text("Start logging")
                    }
                }
            }

            Section {
                Button(action: {
                    var test: String? = nil
                    NSLog(test!)
                }) {
                    Text("Crash!")
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
