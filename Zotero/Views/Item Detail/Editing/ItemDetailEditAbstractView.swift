//
//  ItemDetailEditAbstractView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditAbstractView: View {
    @Binding var abstract: String

    var body: some View {
        VStack(alignment: .leading) {
            ItemDetailMetadataTitleView(title: "Abstract")
            TextView(text: self.$abstract).frame(height: 160)
        }
    }
}

struct ItemDetailEditAbstractView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditAbstractView(abstract: .constant("Abstract"))
    }
}
