//
//  ItemDetailTagView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailTagView: View {
    let color: Color?
    let name: String

    var body: some View {
        HStack {
            self.color.flatMap { Circle().foregroundColor($0) }
            Text(self.name)
            Spacer()
        }
    }
}

struct ItemDetailTagView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailTagView(color: .red, name: "Books")
    }
}
