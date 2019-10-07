//
//  NoteEditorView.swift
//  Zotero
//
//  Created by Michal Rentka on 07/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct NoteEditorView: UIViewControllerRepresentable {
    @Binding private(set) var note: ItemDetailStore.State.Note
    let saveAction: () -> Void

    func makeUIViewController(context: Self.Context) -> UINavigationController {
        let controller = NoteEditorViewController(text: self.note.text) { text in
            self.note.text = text
            self.note.title = text.strippedHtml ?? ""
            self.saveAction()
        }
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController,
                                context: UIViewControllerRepresentableContext<NoteEditorView>) {
    }
}

struct NoteEditorView_Previews: PreviewProvider {
    static var previews: some View {
        NoteEditorView(note: .constant(.init(key: "AAAAAA", text: "Test")),
                       saveAction: {})
    }
}
