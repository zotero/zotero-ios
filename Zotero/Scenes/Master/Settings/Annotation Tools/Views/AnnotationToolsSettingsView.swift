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
                        Image(uiImage: image(for: tool))
                        Text(name(for: tool))
                        Spacer()
                        Toggle(isOn: .init(get: { tools[tool] ?? false }, set: { viewModel.process(action: .setVisible($0, tool, section)) }), label: {})
                        Spacer()
                            .frame(width: 18)
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .opacity(0.5)
                    }
                    .accessibilityLabel(accessibilityLabel(for: tool))
                }
                .onMove(perform: { fromIndices, toIndex in viewModel.process(action: .move(fromIndices, toIndex, section)) })
            } header: {
                VStack {
                    Picker("", selection: $section) {
                        Text("PDF").tag(AnnotationToolsSettingsState.Section.pdf)
                        Text("HTML / EPUB").tag(AnnotationToolsSettingsState.Section.htmlEpub)
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

    func image(for tool: AnnotationTool) -> UIImage {
        switch tool {
        case .highlight:
            return Asset.Images.Annotations.highlightLarge.image
            
        case .note:
            return Asset.Images.Annotations.noteLarge.image
            
        case .image:
            return Asset.Images.Annotations.areaLarge.image
            
        case .ink:
            return Asset.Images.Annotations.inkLarge.image
            
        case .eraser:
            return Asset.Images.Annotations.eraserLarge.image
            
        case .underline:
            return Asset.Images.Annotations.underlineLarge.image
            
        case .freeText:
            return Asset.Images.Annotations.textLarge.image
        }
    }

    func name(for tool: AnnotationTool) -> String {
        switch tool {
        case .eraser:
            return L10n.Pdf.AnnotationToolbar.eraser
            
        case .freeText:
            return L10n.Pdf.AnnotationToolbar.text
            
        case .highlight:
            return L10n.Pdf.AnnotationToolbar.highlight
            
        case .image:
            return L10n.Pdf.AnnotationToolbar.image
            
        case .ink:
            return L10n.Pdf.AnnotationToolbar.ink
            
        case .note:
            return L10n.Pdf.AnnotationToolbar.note
            
        case .underline:
            return L10n.Pdf.AnnotationToolbar.underline
        }
    }
    
    func accessibilityLabel(for tool: AnnotationTool) -> String {
        switch tool {
        case .eraser:
            return L10n.Accessibility.Pdf.eraserAnnotationTool
            
        case .freeText:
            return L10n.Accessibility.Pdf.textAnnotationTool
            
        case .highlight:
            return L10n.Accessibility.Pdf.highlightAnnotationTool
            
        case .image:
            return L10n.Accessibility.Pdf.imageAnnotationTool
            
        case .ink:
            return L10n.Accessibility.Pdf.inkAnnotationTool
            
        case .note:
            return L10n.Accessibility.Pdf.noteAnnotationTool
            
        case .underline:
            return L10n.Accessibility.Pdf.underlineAnnotationTool
        }
    }
}

extension AnnotationTool: Identifiable {
    var id: AnnotationTool {
        return self
    }
}
