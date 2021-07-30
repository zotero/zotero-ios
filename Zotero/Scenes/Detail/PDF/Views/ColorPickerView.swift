//
//  ColorPickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 13/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ColorPickerView: View {
    private static let numberOfCellsInRow = 5
    private var numberOfRows: Int {
        guard AnnotationsConfig.colors.count != ColorPickerView.numberOfCellsInRow else { return 1 }
        return (AnnotationsConfig.colors.count / ColorPickerView.numberOfCellsInRow) + 1
    }

    @State var selected: String?

    var selectionAction: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<self.numberOfRows) { row in
                HStack(spacing: 12) {
                    ForEach(AnnotationsConfig.colors, id: \.self) { color in
                        Circle().foregroundColor(Color(hex: color))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(self.borderOverlay(for: color))
                                .onTapGesture {
                                    self.selectionAction(color)
                                }
                                .accessibility(label: Text(self.name(for: color)))
                    }
                }
            }
        }
        .padding(12)
    }

    private func borderOverlay(for color: String) -> some View {
        return Group {
            if self.selected == color {
                Circle().strokeBorder(Asset.Colors.defaultCellBackground.swiftUiColor, lineWidth: 3)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(4)
            }
        }
    }

    private func name(for color: String) -> String {
        let colorName = AnnotationsConfig.colorNames[color] ?? L10n.unknown
        if self.selected != color {
            return colorName
        }
        return L10n.Accessibility.Pdf.selected + ": " + colorName
    }
}

struct ColorPickerView_Previews: PreviewProvider {
    static var previews: some View {
        ColorPickerView(selected: "#ff8c19", selectionAction: { _ in })
    }
}
