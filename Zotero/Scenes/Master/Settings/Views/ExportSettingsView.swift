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

    weak var coordinatorDelegate: ExportSettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section {
                Button {
                    self.coordinatorDelegate?.showStylePicker(picked: { style in
                        self.viewModel.process(action: .updateStyle(style))
                    })
                } label: {
                    SettingsListButtonRow(text: L10n.Settings.Export.defaultFormat, detailText: self.viewModel.state.selectedStyle, enabled: true)
                }

                Button {
                    self.coordinatorDelegate?.showLocalePicker(picked: { locale in
                        self.viewModel.process(action: .updateLocale(locale))
                    })
                } label: {
                    SettingsListButtonRow(text: L10n.Settings.Export.language, detailText: self.viewModel.state.selectedLanguage, enabled: self.viewModel.state.languagePickerEnabled)
                }
                .disabled(!self.viewModel.state.languagePickerEnabled)

                ToggleRow(title: L10n.Settings.Export.copyAsHtml, isOn: self.viewModel.binding(keyPath: \.copyAsHtml, action: { .setCopyAsHtml($0) }))
            }
        }
        .navigationBarTitle(Text(L10n.Settings.Export.title))
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
