//
//  CitationSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 18.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CitationSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<CitationsActionHandler>

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Form {
            if let styles = self.viewModel.state.styles, !styles.isEmpty {
                Section(header: Text(L10n.Settings.Cite.stylesTitle)) {
                    ForEach(styles) { style in
                        StyleRow(style: style)
                    }
                }
            }

            Section(header: Text("")) {
                Button {
                    self.coordinatorDelegate?.showCitationStyleManagement(viewModel: self.viewModel)
                } label: {
                    HStack {
                        Text("Get additional styles")

                        Spacer()

                        Image(systemName: "chevron.right")
                            .imageScale(.medium)
                    }
                    .foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUiColor)
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle(L10n.Settings.Cite.title)
        .onAppear {
            self.viewModel.process(action: .loadStyles)
        }
    }
}

struct StyleRow: View {
    let style: RStyle

    var body: some View {
        Text(self.style.title)
    }
}

struct CitationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CitationSettingsView()
    }
}
