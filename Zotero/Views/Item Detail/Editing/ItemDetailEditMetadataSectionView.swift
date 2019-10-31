//
//  ItemDetailEditMetadataSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailEditMetadataSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    var body: some View {
        Section {
            ItemDetailMetadataView(title: "Item Type",
                                   value: self.store.state.data.localizedType)
            .onTapGesture {
                if self.store.state.data.type != ItemTypes.attachment {
                    NotificationCenter.default.post(name: .presentTypePicker, object: (self.store.state.data.type, self.store.changeType))
                }
            }

            if self.store.state.data.type != ItemTypes.attachment {
                ForEach(self.store.state.data.creatorIds, id: \.self) { creatorId in
                    ItemDetailEditCreatorView(creator: self.binding(from: creatorId))
                }
                .onDelete(perform: self.store.deleteCreators)
                .onMove(perform: self.store.moveCreators)
                ItemDetailAddView(title: "Add creator", action: self.store.addCreator)

                ForEach(self.store.state.data.fieldIds, id: \.self) { fieldId in
                    ItemDetailEditMetadataView(title: self.store.state.data.fields[fieldId]?.name ?? "",
                                               value: self.binding(from: fieldId))
                }

                Binding(self.$store.state.data.abstract).flatMap {
                    ItemDetailEditAbstractView(abstract: $0)
                }
            }
        }
    }

    private func binding(from creatorId: UUID) -> Binding<ItemDetailStore.State.Creator> {
        return Binding(get: {
            return self.store.state.data.creators[creatorId] ?? ItemDetailStore.State.Creator(type: "", primary: false, localizedType: "")
        }, set: { newValue in
            self.store.state.data.creators[newValue.id] = newValue
        })
    }

    private func binding(from fieldId: String) -> Binding<String> {
        return Binding(get: {
            return self.store.state.data.fields[fieldId]?.value ?? ""
        }, set: { newValue in
            self.store.state.data.fields[fieldId]?.value = newValue
        })
    }
}

struct ItemDetailEditMetadataSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditMetadataSectionView()
    }
}
