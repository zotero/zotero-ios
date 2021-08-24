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
                Overlay(type: .loading)
            } else if let error = self.viewModel.state.error, let message = self.message(for: error, mode: self.viewModel.state.mode) {
                Overlay(type: .error(message))
            }
        }
        .navigationBarItems(leading: self.leadingItem, trailing: self.trailingItem)
    }

    private func message(for error: Error, mode: CitationBibliographyExportState.OutputMode) -> String? {
        if let error = error as? CitationController.Error {
            switch error {
            case .invalidItemTypes:
                return L10n.Errors.Citation.invalidTypes
            case .styleOrLocaleMissing:
                return nil
            default: break
            }
        }

        switch mode {
        case .bibliography:
            return L10n.Errors.Citation.generateBibliography
        case .citation:
            return L10n.Errors.Citation.generateCitation
        }
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
        .disabled(self.viewModel.state.isLoading || self.viewModel.state.error != nil)
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

fileprivate struct Overlay: View {
    enum Kind {
        case loading
        case error(String)
    }

    let type: Kind

    var body: some View {
        Rectangle()
            .foregroundColor(Color.black.opacity(0.15))

        switch self.type {
        case .loading:
            ActivityIndicatorView(style: .large, color: .white, isAnimating: .constant(true))
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .imageScale(.large)
                    .foregroundColor(.red)

                Text(message)
                    .font(.system(.body))
                    .foregroundColor(.white)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).foregroundColor(Color.black.opacity(0.5)))
        }
    }
}

fileprivate struct CiteView: View {
    @EnvironmentObject var viewModel: ViewModel<CitationBibliographyExportActionHandler>

    weak var coordinatorDelegate: CitationBibliographyExportCoordinatorDelegate?

    var body: some View {
        Section(header: Text(L10n.Citation.style)) {
            RowView(title: self.viewModel.state.style.title, enabled: true)
                .contentShape(Rectangle())
                .onTapGesture {
                    self.coordinatorDelegate?.showStylePicker(picked: { style in
                        self.viewModel.process(action: .setStyle(style))
                    })
                }
        }

        Section(header: Text(L10n.Citation.language)) {
            RowView(title: self.viewModel.state.localeName, enabled: self.viewModel.state.languagePickerEnabled)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard self.viewModel.state.languagePickerEnabled else { return }
                    self.coordinatorDelegate?.showLanguagePicker(picked: { locale in
                        self.viewModel.process(action: .setLocale(id: locale.id, name: locale.name))
                    })
                }
        }

        Section(header: Text(L10n.Citation.outputMode)) {
            VStack {
                OutputMethodRow(title: L10n.Citation.citations, isSelected: self.viewModel.state.mode == .citation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.viewModel.process(action: .setMode(.citation))
                    }

                OutputMethodRow(title: L10n.Citation.bibliography, isSelected: self.viewModel.state.mode == .bibliography)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.viewModel.process(action: .setMode(.bibliography))
                    }
            }
        }

        Section(header: Text(L10n.Citation.outputMethod)) {
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
            return L10n.Citation.saveHtml
        case .copy:
            return L10n.Citation.copy
        }
    }
}

fileprivate struct RowView: View {
    let title: String
    let enabled: Bool

    var body: some View {
        HStack {
            Text(self.title)
                .foregroundColor(Color(self.textColor))

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(Color(.systemGray2))
        }
    }

    private var textColor: UIColor {
        if !self.enabled {
            return .systemGray
        }
        return UIColor { $0.userInterfaceStyle == .light ? .black : .white }
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
        let style = Style(identifier: "http://www.zotero.org/styles/nature", dependencyId: nil, title: "Nature", updated: Date(), href: URL(string: "")!, filename: "", supportsBibliography: true, defaultLocale: nil)
        let state = CitationBibliographyExportState(itemIds: [], libraryId: .custom(.myLibrary), selectedStyle: style, selectedLocaleId: "en_US", languagePickerEnabled: true, selectedMode: .bibliography, selectedMethod: .copy)
        let handler = CitationBibliographyExportActionHandler(citationController: controllers.userControllers!.citationController, fileStorage: controllers.fileStorage, webView: WKWebView())
        let viewModel = ViewModel(initialState: state, handler: handler)
        return CitationBibliographyExportView().environmentObject(viewModel)
    }
}
