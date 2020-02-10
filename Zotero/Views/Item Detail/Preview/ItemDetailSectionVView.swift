//
//  ItemDetailSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailSectionVView: View {
    let title: String

    var body: some View {
        Text(self.title)
            .fontWeight(.light)
            .font(.title)
            .padding(.top)
            .listRowBackground(Color.gray.opacity(0.15))
    }
}

struct ItemDetailSectionVView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailSectionVView(title: "Section")
    }
}
