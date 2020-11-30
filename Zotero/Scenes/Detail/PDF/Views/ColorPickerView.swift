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
                        Rectangle().foregroundColor(Color(hex: color))
                                   .aspectRatio(1, contentMode: .fit)
                                   .border(self.borderColor(for: color), width: 2)
                                   .onTapGesture {
                                       self.selectionAction(color)
                                   }
                    }
                }
            }
        }
        .padding(12)
    }

    private func borderColor(for color: String) -> Color {
        return self.selected == color ? .blue : .clear
    }
}

struct ColorPickerView_Previews: PreviewProvider {
    static var previews: some View {
        ColorPickerView(selected: "#ff8c19", selectionAction: { _ in })
    }
}
