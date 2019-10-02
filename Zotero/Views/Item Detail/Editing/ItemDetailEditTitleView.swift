//
//  ItemDetailEditTitleView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditTitleView: View {
    @Binding var title: String

    var body: some View {
        TextField("Title", text: self.$title)
            .font(.title)
            .padding(.top)
    }
}

struct ItemDetailEditTitleView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditTitleView(title: .constant("Some title"))
    }
}
