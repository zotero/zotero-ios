//
//  LibraryRow.swift
//  Zotero
//
//  Created by Michal Rentka on 18/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct LibraryRow: View {
    let title: String

    var body: some View {
        HStack {
            Image("icon_cell_library")
                .renderingMode(.template)
                .foregroundColor(.blue)
            Text(self.title)
        }
    }
}

struct LibraryRow_Previews: PreviewProvider {
    static var previews: some View {
        LibraryRow(title: "My library")
    }
}
