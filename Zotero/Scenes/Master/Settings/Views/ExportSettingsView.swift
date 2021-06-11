//
//  ExportSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 11.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ExportSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<ExportActionHandler>

    var body: some View {
        Form {
            Section(header: Text(L10n.Settings.Export.quickCopy)) {
                Button {

                } label: {
                    TextRow(title: L10n.Settings.Export.defaultFormat, value: self.viewModel.state.selectedStyle)
                }

                Button {
                    
                } label: {
                    TextRow(title: L10n.Settings.Export.language, value: self.viewModel.state.selectedLanguage)
                }

                ToggleRow(title: L10n.Settings.Export.copyAsHtml, isOn: self.viewModel.binding(keyPath: \.copyAsHtml, action: { .setCopyAsHtml($0) }))
            }
        }
    }
}

fileprivate struct TextRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(self.title)

            Spacer()

            Text(self.value)
        }
    }
}

fileprivate struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(self.title)

            Spacer()

            Toggle("", isOn: self.$isOn)
        }
    }
}

struct ExportSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ExportSettingsView()
    }
}
