//
//  ItemDetailEditNoteSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditNoteSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailSectionVView(title: "Notes")
            ForEach(self.store.state.data.notes) { note in
                ItemDetailNoteView(text: note.title)
            }
            .onDelete(perform: self.store.deleteNotes)
            ItemDetailAddView(title: "Add note", action: {
                self.store.addNote()
                NotificationCenter.default.post(name: .presentNote, object: (self.$store.state.presentedNote, self.store.saveNote))
            })
        }
    }
}

struct ItemDetailEditNoteSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditNoteSectionView()
    }
}
