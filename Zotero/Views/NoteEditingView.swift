//
//  NoteEditingView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct NoteEditingView: View {
    var note: ItemDetailStore.StoreState.Note
    let saveAction: () -> Void

    var body: some View {
        NavigationView {
            Text(self.note.text)
        }.navigationBarItems(trailing: Button(action: self.saveAction, label: { Text("Save") }))
    }
}

struct NoteEditingView_Previews: PreviewProvider {
    static var previews: some View {
        NoteEditingView(note: .init(key: "", text: "Test"), saveAction: {})
    }
}
