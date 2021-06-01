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
            Section(header: Text("")) {
                if self.viewModel.state.isLogging {
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

//            Section(header: Text(L10n.Settings.websocketTitle)) {
//                HStack(alignment: .center, spacing: 8) {
//                    Circle()
//                        .frame(width: 12, height: 12, alignment: .leading)
//                        .foregroundColor(self.webSocketColor(for: self.viewModel.state.websocketConnectionState))
//                    Text(self.webSocketTitle(for: self.viewModel.state.websocketConnectionState))
//                    Spacer()
//                }
//
//                Button(action: {
//                    self.performWebSocketAction(for: self.viewModel.state.websocketConnectionState)
//                }, label: {
//                    Text(self.webSocketButtonTitle(for: self.viewModel.state.websocketConnectionState))
//                })
//            }
        }
        .navigationBarTitle(L10n.Settings.debug)
    }

    private func webSocketTitle(for state: WebSocketController.ConnectionState) -> String {
        switch state {
        case .connected: return L10n.Settings.websocketConnected
        case .connecting, .subscribing: return L10n.Settings.websocketConnecting
        case .disconnected: return L10n.Settings.websocketDisconnected
        }
    }

    private func webSocketColor(for state: WebSocketController.ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .subscribing: return .yellow
        case .disconnected: return .red
        }
    }

    private func webSocketButtonTitle(for state: WebSocketController.ConnectionState) -> String {
        switch state {
        case .connected: return L10n.Settings.websocketDisconnect
        case .connecting, .subscribing: return L10n.cancel
        case .disconnected: return L10n.Settings.websocketConnect
        }
    }

    private func performWebSocketAction(for state: WebSocketController.ConnectionState) {
        switch state {
        case .connected, .connecting, .subscribing:
            self.viewModel.process(action: .disconnectFromWebSocket)
        case .disconnected:
            self.viewModel.process(action: .connectToWebSocket)
        }
    }
}

struct DebugSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        DebugSettingsView()
    }
}
