//
//  ItemDetailAttachmentView.swift
//  Zotero
//
//  Created by Michal Rentka on 29/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailAttachmentView: View {
    let filename: String

    var body: some View {
        HStack {
            Image("icon_cell_attachment")
            Text(self.filename)
        }
    }
}

struct ItemDetailAttachmentView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailAttachmentView(filename: "Some pdf name.pdf")
    }
}
