//
//  ItemDetailEditAttachmentSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditAttachmentSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailSectionVView(title: "Attachments")
            ForEach(self.store.state.data.attachments) { attachment in
                ItemDetailAttachmentView(iconName: attachment.iconName,
                                         title: attachment.title,
                                         rightAccessory: .disclosureIndicator,
                                         progress: nil)
            }
            .onDelete(perform: self.store.deleteAttachments)
            ItemDetailAddView(title: "Add attachment", action: {
                NotificationCenter.default.post(name: .presentFilePicker, object: self.store.addAttachments)
            })
        }
    }
}

struct ItemDetailEditAttachmentSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditAttachmentSectionView()
    }
}
