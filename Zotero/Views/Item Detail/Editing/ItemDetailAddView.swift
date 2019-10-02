//
//  ItemDetailAddView.swift
//  Zotero
//
//  Created by Michal Rentka on 06/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailAddView: View {
    let title: String
    let action: () -> Void

    var body: some View {
        // SWIFTUI BUG: - Button action in cell not called in EditMode.active
        Button(action: self.action, label: {
            HStack {
                Image(systemName: "plus.circle")
                    .imageScale(.large)
                Text(self.title)
            }.foregroundColor(.blue)
        }).onTapGesture(perform: self.action)
    }
}

struct ItemDetailAddView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailAddView(title: "Add creator", action: {})
    }
}
