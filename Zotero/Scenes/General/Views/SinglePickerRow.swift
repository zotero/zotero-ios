//
//  TypePickerRow.swift
//  Zotero
//
//  Created by Michal Rentka on 24/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SinglePickerRow: View {
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

struct SinglePickerRow_Preview: PreviewProvider {
    static var previews: some View {
        SinglePickerRow(text: "Test", isSelected: true)
    }
}
