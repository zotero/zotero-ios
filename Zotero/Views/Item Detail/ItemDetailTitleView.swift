//
//  ItemDetailTitleView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailTitleView: View {
    @Binding var title: String
    let editingEnabled: Bool

    var body: some View {
        Group {
            if self.editingEnabled {
                TextField("Title", text: self.$title)
                    .font(.title)
            } else {
                Text(self.title)
                    .fontWeight(.light)
                    .font(.title)
            }
        }
        .padding(.top)
    }
}

#if DEBUG

struct ItemDetailTitleView_Previews: PreviewProvider {
    
    static var previews: some View {
        List {
            ItemDetailTitleView(title: .constant("Some title"), editingEnabled: true)
        }
    }
}

#endif
