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
                    Button {
                        self.viewModel.process(action: .cancelLogging)
                    } label: {
                        Text(L10n.Settings.cancelLogging).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Button {
                        self.viewModel.process(action: .stopLogging)
                    } label: {
                        Text(L10n.Settings.stopLogging).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Text(L10n.Settings.loggingDesc1)
                    Text(L10n.Settings.loggingDesc2)
                } else {
                    Button {
                        self.viewModel.process(action: .startImmediateLogging)
                    } label: {
                        Text(L10n.Settings.startLogging).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Button {
                        self.viewModel.process(action: .startLoggingOnNextLaunch)
                    } label: {
                        Text(L10n.Settings.startLoggingOnLaunch).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }
                }
            }

            if self.viewModel.state.isLogging {
                Section {
                    Button {
                        self.viewModel.process(action: .showLogs)
                    } label: {
                        Text(L10n.Settings.viewOutput).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                    }

                    Button {
                        self.viewModel.process(action: .clearLogs)
                    } label: {
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
