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

    fileprivate static let baseCellOffset: CGFloat = 36

    var picked: (Collection, Library) -> Void

    var body: some View {
        ScrollableView(id: self.store.state.selectedCollectionId) {
            List {
                ForEach(self.store.state.libraries) { library in
                    CollapsibleLibraryRow(library: library, collapsed: (self.store.state.librariesCollapsed[library.identifier] ?? true)) {
                        self.store.toggleLibraryCollapsed(id: library.identifier)
                    }

                    if self.store.state.librariesCollapsed[library.identifier] == false {
                        CollapsibleCollectionRow(collection: Collection(custom: .all),
                                                 pickAction: {
                                                    self.picked(Collection(custom: .all), library)
                                                 },
                                                 collapseAction: {})
                            .id(CollectionIdentifier.custom(.all))

                        self.store.state.collections[library.identifier].flatMap {
                            ForEach($0.filter({ $0.visible })) { collection in
                                CollapsibleCollectionRow(collection: collection,
                                                         pickAction: {
                                                            self.picked(collection, library)
                                                         },
                                                         collapseAction: {
                                                            self.store.toggleCollectionCollapsed(collection: collection, libraryId: library.identifier)
                                                         })
                                    .id(collection.identifier)
                            }
                        }
                    }
                }
            }
        }
    }
}

fileprivate struct ScrollableView<Content>: View where Content: View {
    private let content: Content

    let id: CollectionIdentifier

    init(id: CollectionIdentifier, @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }

    var body: some View {
        if #available(iOSApplicationExtension 14.0, *) {
            ScrollViewReader { proxy in
                self.content.onAppear {
                    proxy.scrollTo(self.id)
                }
            }
        } else {
            // TODO: - implement scrolling for iOS 13 if needed
            self.content
        }
    }
}

fileprivate struct CollapsibleLibraryRow: View {
    let library: Library
    let collapsed: Bool
    let action: () -> Void

    var body: some View {
        GeometryReader(content: { geometry in
            ZStack(alignment: .leading) {
                LibraryRow(title: self.library.name, isReadOnly: !self.library.metadataEditable)
                    .frame(height: geometry.size.height)

                CollapseButton(collapsed: self.collapsed, size: geometry.size.height, action: self.action)
                    .offset(x: -(geometry.size.height * 0.92))
            }
        })
        .listRowInsets(EdgeInsets(top: 0, leading: ListView.baseCellOffset, bottom: 0, trailing: 0))
    }
}

fileprivate struct CollapsibleCollectionRow: View {

    let collection: Collection
    let pickAction: () -> Void
    let collapseAction: () -> Void

    var body: some View {
        GeometryReader(content: { geometry in
            ZStack(alignment: .leading) {
                Button(action: {
                    self.pickAction()
                }) {
                    CollectionRow(data: self.collection)
                    Spacer()
                }
                .buttonStyle(BorderlessButtonStyle())
                .frame(height: geometry.size.height)

                if self.collection.hasChildren {
                    CollapseButton(collapsed: self.collection.collapsed, size: geometry.size.height, action: self.collapseAction)
                        .offset(x: -(geometry.size.height * 0.92))
                }
            }
        })
        .listRowInsets(EdgeInsets(top: 0, leading: CollectionRow.inset(for: self.collection.level, baseOffset: ListView.baseCellOffset), bottom: 0, trailing: 0))
    }
}

fileprivate struct CollapseButton: View {

    let collapsed: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: {
            self.action()
        }) {
            Image(systemName: self.collapsed ? "chevron.right" : "chevron.down")
                .imageScale(.small)
                .frame(width: self.size, height: self.size)
                .background(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.3))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
    }
}

struct AllCollectionPickerView_Previews: PreviewProvider {
    static var previews: some View {
        AllCollectionPickerView(picked: { _, _ in })
    }
}
