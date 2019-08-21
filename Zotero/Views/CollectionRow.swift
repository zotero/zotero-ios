//
//  CollectionRow.swift
//  Zotero
//
//  Created by Michal Rentka on 20/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionRow: View {
    private static let levelOffset: CGFloat = 20.0
    let data: CollectionCellData

    var body: some View {
        HStack {
            Image(self.data.iconName)
            Text(self.data.name)
        }.padding(.leading, CGFloat(self.data.level) * CollectionRow.levelOffset)
    }
}

struct CollectionRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CollectionRow(data: CollectionCellData(custom: .all))
            CollectionRow(data: CollectionCellData(custom: .publications))
            CollectionRow(data: CollectionCellData(custom: .trash))
        }.previewLayout(.fixed(width: 320, height: 44))
    }
}
