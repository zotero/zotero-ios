//
//  ItemDetailAttachmentSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailAttachmentSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailSectionVView(title: "Attachments")
            ForEach(self.store.state.data.attachments) { attachment in
                Button(action: {
                    self.store.openAttachment(attachment)
                }) {
                    ItemDetailAttachmentView(iconName: attachment.iconName,
                                             title: attachment.title,
                                             rightAccessory: self.accessory(for: attachment,
                                                                            progress: self.store.state.downloadProgress[attachment.key],
                                                                            error: self.store.state.downloadError[attachment.key]),
                                             progress: self.store.state.downloadProgress[attachment.key])
                }
            }
        }
    }

        private func accessory(for attachment: Attachment, progress: Double?, error: Error?) -> AccessoryView.Accessory {
            if error != nil {
                return .error
            }

            if progress != nil {
                return .progress
            }

            switch attachment.type {
            case .file(_, _, let isLocal):
                return isLocal ? .disclosureIndicator : .downloadIcon
            case .url:
                return .disclosureIndicator
            }
        }
}

struct ItemDetailAttachmentSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailAttachmentSectionView()
    }
}
