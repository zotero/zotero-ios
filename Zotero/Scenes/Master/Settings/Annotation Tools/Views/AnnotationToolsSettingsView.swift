//
//  AnnotationToolsSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 12.12.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import OrderedCollections

struct AnnotationToolsSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<AnnotationToolsSettingsViewModel>
    @State var section: AnnotationToolsSettingsState.Section = .pdf

    var body: some View {
        Form {
            Section {
                ForEach(tools.keys) { tool in
                    HStack {
                        Image(uiImage: tool.image)
                        Text(tool.name)
                        Spacer()
                        Toggle(isOn: .init(get: { tools[tool] ?? false }, set: { viewModel.process(action: .setVisible($0, tool, section)) }), label: {})
                        Spacer()
                            .frame(width: 18)
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .opacity(0.5)
                    }
                    .accessibilityLabel(tool.accessibilityLabel)
                }
                .onMove(perform: { fromIndices, toIndex in viewModel.process(action: .move(fromIndices, toIndex, section)) })
            } header: {
                VStack {
                    Picker("", selection: $section) {
                        Text(L10n.Settings.AnnotationTools.pdf).tag(AnnotationToolsSettingsState.Section.pdf)
                        Text(L10n.Settings.AnnotationTools.htmlEpub).tag(AnnotationToolsSettingsState.Section.htmlEpub)
                    }
                    .pickerStyle(.segmented)
                    Spacer()
                        .frame(height: 14)
                }
            }
        }
        .listStyle(GroupedListStyle())
        .onDisappear {
            viewModel.process(action: .save)
        }
    }

    var tools: OrderedDictionary<AnnotationTool, Bool> {
        switch section {
        case .pdf:
            return viewModel.state.pdfTools
            
        case .htmlEpub:
            return viewModel.state.htmlEpubTools
        }
    }
}

extension AnnotationTool: Identifiable {
    var id: AnnotationTool {
        return self
    }
}
