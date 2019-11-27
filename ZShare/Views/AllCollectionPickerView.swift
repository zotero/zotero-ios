//
//  AllCollectionPicker.swift
//  ZShare
//
//  Created by Michal Rentka on 27/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct AllCollectionPickerView: View {
    @EnvironmentObject private var store: AllCollectionPickerStore

    var picked: (Collection, Library) -> Void

    var body: some View {
        Group {
            if self.store.state.libraries.count == 0 {
                ActivityIndicatorView(style: .large, isAnimating: .constant(true))
            } else {
                ListView(picked: self.picked)
            }
        }
        .onAppear(perform: self.store.load)
    }
}

fileprivate struct ListView: View {
    @EnvironmentObject private var store: AllCollectionPickerStore

    var picked: (Collection, Library) -> Void

    var body: some View {
        List {
            ForEach(self.store.state.libraries) { library in
                LibraryRow(title: library.name)

                CollectionRow(data: Collection(custom: .all))
                    .onTapGesture {
                        self.picked(Collection(custom: .all), library)
                    }
                self.store.state.collections[library.identifier].flatMap {
                    ForEach($0) { collection in
                        CollectionRow(data: collection)
                            .onTapGesture {
                                self.picked(collection, library)
                            }
                    }
                }
            }
        }
    }
}

struct AllCollectionPickerView_Previews: PreviewProvider {
    static var previews: some View {
        AllCollectionPickerView(picked: { _, _ in })
    }
}

extension Library: Identifiable {
    var id: LibraryIdentifier {
        return self.identifier
    }
}
