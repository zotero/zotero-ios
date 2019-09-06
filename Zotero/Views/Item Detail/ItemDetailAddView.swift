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

    var body: some View {
        HStack {
            Image(systemName: "plus.circle")
                .imageScale(.large)
            Text(self.title)
        }.foregroundColor(.blue)
    }
}

struct ItemDetailAddView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailAddView(title: "Add creator")
    }
}
