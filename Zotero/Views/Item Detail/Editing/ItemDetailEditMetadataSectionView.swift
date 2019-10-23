//
//  ItemDetailEditMetadataSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

extension Notification.Name {
    static let presentTypePicker = Notification.Name(rawValue: "org.zotero.PresentItemTypePicker")
}

struct ItemDetailEditMetadataSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailMetadataView(title: "Item Type",
                                   value: self.store.state.data.localizedType)
            .onTapGesture {
                NotificationCenter.default.post(name: .presentTypePicker, object: (self.store.state.data.type, self.store.changeType))
            }

            ForEach(self.store.state.data.creators.indices, id:\.self) { index in
                ItemDetailEditCreatorView(creator: self.$store.state.data.creators[index])
            }
            .onMove(perform: self.store.moveCreators)

            ForEach(self.store.state.data.fields.indices, id: \.self) { index in
                ItemDetailEditMetadataView(title: self.store.state.data.fields[index].name,
                                           value: self.$store.state.data.fields[index].value)
            }

            Binding(self.$store.state.data.abstract).flatMap {
                ItemDetailEditAbstractView(abstract: $0)
            }
        }
    }
}

struct ItemDetailEditMetadataSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditMetadataSectionView()
    }
}
