//
//  CitationBibliographyExportView.swift
//  Zotero
//
//  Created by Michal Rentka on 28.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CitationBibliographyExportView: View {
    @EnvironmentObject var viewModel: ViewModel<CitationBibliographyExportActionHandler>

    weak var coordinatorDelegate: DetailCitationBibliographyExportCoordinatorDelegate?

    var body: some View {
        Form {
//            Section(header: self.picker, content: {})
//
//            switch self.viewModel.state.type {
//            case .cite:
                self.citeView
//            case .export:
//                ExportView()
//            }
        }
        .navigationBarItems(leading: self.leadingItem, trailing: self.trailingItem)
    }

    private var leadingItem: some View {
        Button(action: {
            self.coordinatorDelegate?.cancel()
        }, label: {
            Text(L10n.cancel)
        })
    }

    private var trailingItem: some View {
        Button(action: {
            self.coordinatorDelegate?.cancel()
        }, label: {
            Text(L10n.done)
        })
    }

    private var citeView: some View {
        var view = CiteView()
        view.coordinatorDelegate = self.coordinatorDelegate
        return view
    }

    private var picker: some View {
        Picker(selection: self.viewModel.binding(get: \.type, action: { .setType($0) }), label: Text(""), content: {
            Text("Cite").tag(CitationBibliographyExportState.Kind.cite)
            Text("Export").tag(CitationBibliographyExportState.Kind.export)
        }).pickerStyle(SegmentedPickerStyle())
    }
}

fileprivate struct CiteView: View {
    @EnvironmentObject var viewModel: ViewModel<CitationBibliographyExportActionHandler>

    weak var coordinatorDelegate: DetailCitationBibliographyExportCoordinatorDelegate?

    var body: some View {
        Section(header: Text("")) {
            HStack {
                Text("Output Mode")

                Spacer()

                Picker(selection: self.viewModel.binding(get: \.mode, action: { .setMode($0) }), label: Text("Output Mode"), content: {
                    Text("Citations")
                        .tag(CitationBibliographyExportState.OutputMode.citation)
                    Text("Bibliography")
                        .tag(CitationBibliographyExportState.OutputMode.bibliography)
                })
                .pickerStyle(SegmentedPickerStyle())
                .fixedSize()
            }
        }

        Section(header: Text("Style")) {
            RowView(title: self.viewModel.state.style.title)
                .contentShape(Rectangle())
                .onTapGesture {

                }
        }

        Section(header: Text("Language")) {
            RowView(title: self.language)
                .contentShape(Rectangle())
                .onTapGesture {

                }
        }

        Section(header: Text("Output Method")) {
            VStack {
                ForEach(CitationBibliographyExportState.methods) { method in
                    OutputMethodRow(title: self.name(for: method), isSelected: self.viewModel.state.method == method)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            self.viewModel.process(action: .setMethod(method))
                        }
                }
            }
        }
    }

    private func name(for method: CitationBibliographyExportState.OutputMethod) -> String {
        switch method {
        case .html:
            return "Save as HTML"
        case .copy:
            return "Copy to Clipboard"
        }
    }

    private var language: String {
        return Locale.current.localizedString(forIdentifier: self.viewModel.state.localeId) ?? self.viewModel.state.localeId
    }
}

fileprivate struct RowView: View {
    let title: String

    var body: some View {
        HStack {
            Text(self.title)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(Color(.systemGray2))
        }
    }
}

fileprivate struct OutputMethodRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(self.title)

            Spacer()

            if self.isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
            }
        }
        .padding(.vertical, 8)
    }
}

fileprivate struct ExportView: View {
    var body: some View {
        Text("Export")
    }
}

struct CitationBibliographyExportView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let style = Style(identifier: "http://www.zotero.org/styles/nature", title: "Nature", updated: Date(), href: URL(string: "")!, filename: "")
        let state = CitationBibliographyExportState(selectedStyle: style, selectedLocaleId: "en_US")
        let handler = CitationBibliographyExportActionHandler(citationController: controllers.citationController)
        let viewModel = ViewModel(initialState: state, handler: handler)
        return CitationBibliographyExportView().environmentObject(viewModel)
    }
}
