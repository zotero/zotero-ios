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
        ScrollableView(scrollToHash: self.hash(forCollection: self.store.state.selectedCollectionId, andLibrary: self.store.state.selectedLibraryId)) {
            List {
                if !self.store.state.recentCollections.isEmpty {
                    Section(header: Text(L10n.recent.uppercased())) {
                        ForEach(self.store.state.recentCollections) { collectionWithLibrary in
                            CollapsibleRow(content: CollectionRow(data: collectionWithLibrary.collection),
                                           showCollapseButton: true,
                                           collapsed: true,
                                           pickAction: {
                                               self.picked(collectionWithLibrary.collection, collectionWithLibrary.library)
                                           },
                                           collapseAction: {})
                                .listRowInsets(EdgeInsets(top: 0, leading: ListView.baseCellOffset, bottom: 0, trailing: 0))
                                .id(collectionWithLibrary.id)
                        }
                    }
                }

                Section {
                    ForEach(self.store.state.libraries) { library in
                        CollapsibleRow(content: LibraryRow(title: library.name, isReadOnly: !library.metadataEditable),
                                       showCollapseButton: true,
                                       collapsed: self.libraryCollapsed(library),
                                       pickAction: {
                                           self.picked(Collection(custom: .all), library)
                                       },
                                       collapseAction: {
                                           self.store.toggleLibraryCollapsed(id: library.identifier)
                                       })
                            .listRowInsets(EdgeInsets(top: 0, leading: ListView.baseCellOffset, bottom: 0, trailing: 0))

                        if self.store.state.librariesCollapsed[library.identifier] == false {
                            self.store.state.collections[library.identifier].flatMap {
                                ForEach($0.filter({ $0.visible })) { collection in
                                    CollapsibleRow(content: CollectionRow(data: collection),
                                                   showCollapseButton: collection.hasChildren,
                                                   collapsed: collection.collapsed,
                                                   pickAction: {
                                                       self.picked(collection, library)
                                                   },
                                                   collapseAction: {
                                                       self.store.toggleCollectionCollapsed(collection: collection, libraryId: library.identifier)
                                                   })
                                        .listRowInsets(EdgeInsets(top: 0, leading: CollectionRow.inset(for: collection.level, baseOffset: ListView.baseCellOffset), bottom: 0, trailing: 0))
                                        .id(self.hash(forCollection: collection.identifier, andLibrary: library.identifier))
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
        }
    }

    private func libraryCollapsed(_ library: Library) -> Bool {
        return self.store.state.librariesCollapsed[library.identifier] ?? true
    }

    private func hash(forCollection collectionId: CollectionIdentifier, andLibrary libraryId: LibraryIdentifier) -> Int {
        var hasher = Hasher()
        hasher.combine(collectionId)
        hasher.combine(libraryId)
        return hasher.finalize()
    }
}

fileprivate struct ScrollableView<Content>: View where Content: View {
    private let content: Content

    let scrollToHash: Int

    init(scrollToHash: Int, @ViewBuilder content: () -> Content) {
        self.scrollToHash = scrollToHash
        self.content = content()
    }

    var body: some View {
        if #available(iOSApplicationExtension 14.0, *) {
            ScrollViewReader { proxy in
                self.content.onAppear {
                    proxy.scrollTo(self.scrollToHash)
                }
            }
        } else {
            // TODO: - implement scrolling for iOS 13 if needed
            self.content
        }
    }
}

fileprivate struct CollapsibleRow<Content>: View where Content: View {

    let content: Content
    let showCollapseButton: Bool
    let collapsed: Bool
    let pickAction: () -> Void
    let collapseAction: () -> Void

    var body: some View {
        GeometryReader(content: { geometry in
            ZStack(alignment: .leading) {
                Button(action: {
                    self.pickAction()
                }) {
                    self.content
                    Spacer()
                }
                .buttonStyle(BorderlessButtonStyle())
                .frame(height: geometry.size.height)

                if self.showCollapseButton {
                    CollapseButton(collapsed: self.collapsed, size: geometry.size.height, action: self.collapseAction)
                        .offset(x: -(geometry.size.height * 0.92))
                }
            }
        })
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
