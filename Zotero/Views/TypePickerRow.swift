//
//  TypePickerRow.swift
//  Zotero
//
//  Created by Michal Rentka on 24/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TypePickerRow: View {
    let text: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(self.text)
            if self.isSelected {
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
    }
}

struct TypePickerRow_Preview: PreviewProvider {
    static var previews: some View {
        TypePickerRow(text: "Test", isSelected: true)
    }
}
