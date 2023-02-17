//
//  DebuggingView.swift
//  Zotero
//
//  Created by Michal Rentka on 04/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct DebuggingView: View {
    @EnvironmentObject var viewModel: ViewModel<DebuggingActionHandler>

    var body: some View {
        Form {
            Section {
                if self.viewModel.state.isLogging {
                    Button(action: {
                        self.viewModel.process(action: .cancelLogging)
                    }) {
                        Text(L10n.Settings.cancelLogging).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Button(action: {
                        self.viewModel.process(action: .stopLogging)
                    }) {
                        Text(L10n.Settings.stopLogging).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Text(L10n.Settings.loggingDesc1)
                    Text(L10n.Settings.loggingDesc2)
                } else {
                    Button(action: {
                        self.viewModel.process(action: .startImmediateLogging)
                    }) {
                        Text(L10n.Settings.startLogging).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Button(action: {
                        self.viewModel.process(action: .startLoggingOnNextLaunch)
                    }) {
                        Text(L10n.Settings.startLoggingOnLaunch).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                }
            }

            if self.viewModel.state.isLogging {
                Section {
                    Button(action: {
                        self.viewModel.process(action: .showLogs)
                    }) {
                        Text(L10n.Settings.viewOutput).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Button(action: {
                        self.viewModel.process(action: .clearLogs)
                    }) {
                        Text(L10n.Settings.clearOutput).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Text(L10n.Settings.linesLogged(self.viewModel.state.numberOfLines))
                }
            }

            Section {
                Button {
                    self.viewModel.process(action: .exportDb)
                } label: {
                    Text(L10n.Settings.exportDb).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                }

            }
        }
        .navigationBarTitle(L10n.Settings.debug)
    }
}

struct DebuggingView_Previews: PreviewProvider {
    static var previews: some View {
        DebuggingView()
    }
}
