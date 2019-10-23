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

            ForEach(self.store.state.data.creators) { creator in
                ItemDetailEditCreatorView(creator: self.binding(from: creator))
            }
            .onDelete(perform: self.store.deleteCreators)
            .onMove(perform: self.store.moveCreators)
            ItemDetailAddView(title: "Add creator", action: self.store.addCreator)

            ForEach(self.store.state.data.fields) { field in
                ItemDetailEditMetadataView(title: field.name,
                                           value: self.binding(from: field))
            }

            Binding(self.$store.state.data.abstract).flatMap {
                ItemDetailEditAbstractView(abstract: $0)
            }
        }
    }

    private func binding(from creator: ItemDetailStore.State.Creator) -> Binding<ItemDetailStore.State.Creator> {
        return Binding(get: {
            return self.store.state.data.creators.first(where: { $0.id == creator.id }) ?? ItemDetailStore.State.Creator(type: "", localizedType: "")
        }, set: { newValue in
            if let index = self.store.state.data.creators.firstIndex(where: { $0.id == creator.id }) {
                self.store.state.data.creators[index] = newValue
            }
        })
    }

    private func binding(from field: ItemDetailStore.State.Field) -> Binding<String> {
        return Binding(get: {
            return self.store.state.data.fields.first(where: { $0.id == field.id })?.value ?? ""
        }, set: { newValue in
            if let index = self.store.state.data.fields.firstIndex(where: { $0.id == field.id }) {
                self.store.state.data.fields[index].value = newValue
            }
        })
    }
}

struct ItemDetailEditMetadataSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailEditMetadataSectionView()
    }
}
