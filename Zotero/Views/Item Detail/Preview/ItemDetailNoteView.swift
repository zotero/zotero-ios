//
//  ItemDetailNoteView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailNoteView: View {
    let text: String

    var body: some View {
        HStack {
            Image("note")
                .renderingMode(.original)
                .resizable()
                .frame(width: 18, height: 18)
            Text(self.text)
        }
    }
}

#if DEBUG

struct ItemDetailNoteView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailNoteView(text: "Some note")
    }
}

#endif
