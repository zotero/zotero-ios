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
    let data: Collection
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(self.data.iconName)
            Text(self.data.name)
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(self.data.level) * CollectionRow.levelOffset)
        .listRowBackground(self.isSelected ? Color.gray.opacity(0.4) : Color.white)
    }
}

#if DEBUG

struct CollectionRow_Previews: PreviewProvider {
    static var previews: some View {
        List {
            CollectionRow(data: Collection(custom: .all), isSelected: true)
            CollectionRow(data: Collection(custom: .publications), isSelected: false)
            CollectionRow(data: Collection(custom: .trash), isSelected: false)
        }
    }
}

#endif
