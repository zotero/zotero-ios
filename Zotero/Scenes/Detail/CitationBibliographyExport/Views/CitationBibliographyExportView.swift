//
//  CitationBibliographyExportView.swift
//  Zotero
//
//  Created by Michal Rentka on 28.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI
import WebKit

struct CitationBibliographyExportView: View {
    @EnvironmentObject var viewModel: ViewModel<CitationBibliographyExportActionHandler>

    weak var coordinatorDelegate: CitationBibliographyExportCoordinatorDelegate?

    var body: some View {
        ZStack {
            Form {
//                Section(header: self.picker, content: {})

//                switch self.viewModel.state.type {
//                case .cite:
                    self.citeView
//                case .export:
//                    ExportView()
//                }
            }

            if self.viewModel.state.isLoading {
                Rectangle()
                    .foregroundColor(Color.black.opacity(0.35))

                ActivityIndicatorView(style: .large, color: .white, isAnimating: .constant(true))
            }
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
            self.viewModel.process(action: .process)
        }, label: {
            Text(L10n.done)
        })
        .disabled(self.viewModel.state.isLoading)
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

    weak var coordinatorDelegate: CitationBibliographyExportCoordinatorDelegate?

    var body: some View {
        Section(header: Text("Style")) {
            RowView(title: self.viewModel.state.style.title)
                .contentShape(Rectangle())
                .onTapGesture {
                    self.coordinatorDelegate?.showStylePicker(picked: { style in
                        self.viewModel.process(action: .setStyle(style))
                    })
                }
        }

        Section(header: Text("Language")) {
            RowView(title: self.viewModel.state.localeName)
                .contentShape(Rectangle())
                .onTapGesture {
                    self.coordinatorDelegate?.showLanguagePicker(picked: { locale in
                        self.viewModel.process(action: .setLocale(id: locale.id, name: locale.name))
                    })
                }
        }

        Section(header: Text("Output Mode")) {
            VStack {
                OutputMethodRow(title: "Citations", isSelected: self.viewModel.state.mode == .citation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.viewModel.process(action: .setMode(.citation))
                    }

                if self.viewModel.state.style.supportsBibliography {
                    OutputMethodRow(title: "Bibliography", isSelected: self.viewModel.state.mode == .bibliography)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            self.viewModel.process(action: .setMode(.bibliography))
                        }
                }
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
        let style = Style(identifier: "http://www.zotero.org/styles/nature", title: "Nature", updated: Date(), href: URL(string: "")!, filename: "", supportsBibliography: true)
        let state = CitationBibliographyExportState(itemIds: [], libraryId: .custom(.myLibrary), selectedStyle: style, selectedLocaleId: "en_US")
        let handler = CitationBibliographyExportActionHandler(citationController: controllers.citationController, fileStorage: controllers.fileStorage, webView: WKWebView())
        let viewModel = ViewModel(initialState: state, handler: handler)
        return CitationBibliographyExportView().environmentObject(viewModel)
    }
}
