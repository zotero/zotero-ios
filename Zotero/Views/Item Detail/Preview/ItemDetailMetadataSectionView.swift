//
//  ItemDetailMetadataSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 01/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailMetadataSectionView: View {
    @EnvironmentObject private(set) var store: ItemDetailStore

    private static let dateFormatter: DateFormatter = createDateFormatter()

    private static func createDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        return formatter
    }

    var body: some View {
        Section {
            ItemDetailMetadataView(title: "Item Type",
                                   value: self.store.state.data.localizedType)

            ForEach(self.store.state.data.creatorIds, id: \.self) { creatorId in
                self.store.state.data.creators[creatorId].flatMap { ItemDetailCreatorView(creator: $0) }
            }

            ForEach(self.store.state.data.fieldIds, id: \.self) { fieldId in
                self.store.state.data.fields[fieldId].flatMap { field -> ItemDetailMetadataView? in
                    if !field.value.isEmpty {
                        return ItemDetailMetadataView(title: field.name,
                                                      value: field.value)
                    }
                    return nil
                }
            }

            ItemDetailMetadataView(title: "Date Added",
                                   value: ItemDetailMetadataSectionView.dateFormatter.string(from: self.store.state.data.dateAdded))
            ItemDetailMetadataView(title: "Date Modified",
                                   value: ItemDetailMetadataSectionView.dateFormatter.string(from: self.store.state.data.dateModified))

            self.store.state.data.abstract.flatMap {
                $0.isEmpty ? nil : ItemDetailAbstractView(abstract: $0)
            }
        }
    }
}

struct ItemDetailMetadataSectionView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ItemDetailMetadataSectionView()
        }
    }
}
