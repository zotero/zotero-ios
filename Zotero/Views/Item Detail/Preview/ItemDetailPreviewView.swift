//
//  ItemDetailPreviewView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailPreviewView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        List {
            ItemDetailTitleView(title: self.store.state.data.title)

            ItemDetailMetadataSectionView()

            if !self.store.state.data.notes.isEmpty {
                ItemDetailNoteSectionView()
            }

            if !self.store.state.data.tags.isEmpty {
                ItemDetailTagSectionView()
            }

            if !self.store.state.data.attachments.isEmpty {
                ItemDetailAttachmentSectionView()
            }
        }
    }
}

struct ItemDetailPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailPreviewView()
    }
}
