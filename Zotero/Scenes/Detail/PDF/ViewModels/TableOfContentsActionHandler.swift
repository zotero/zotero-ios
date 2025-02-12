//
//  TableOfContentsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 20.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

struct TableOfContentsActionHandler<O: Outline>: ViewModelActionHandler {
    typealias Action = TableOfContentsAction
    typealias State = TableOfContentsState<O>

    func process(action: TableOfContentsAction, in viewModel: ViewModel<TableOfContentsActionHandler>) {
        switch action {
        case .search(let search):
            guard search != viewModel.state.search else { return }
            self.update(viewModel: viewModel) { state in
                state.search = search
                state.outlineSnapshot = createSnapshot(from: state.outlines, search: search)
                state.changes = .snapshot
            }

        case .load:
            self.update(viewModel: viewModel) { state in
                state.outlineSnapshot = createSnapshot(from: state.outlines, search: state.search)
                state.changes = .snapshot
            }
        }
    }

    private func createSnapshot(from outlines: [O], search: String) -> NSDiffableDataSourceSectionSnapshot<TableOfContentsState<O>.Row>? {
        var snapshot = NSDiffableDataSourceSectionSnapshot<TableOfContentsState<O>.Row>()
        append(outlines: outlines, parent: nil, to: &snapshot, search: search)
        snapshot.collapse(snapshot.items)
        if snapshot.rootItems.count == 1 {
            snapshot.expand(snapshot.rootItems)
        }
        return snapshot
    }

    private func append(outlines: [O], parent: TableOfContentsState<O>.Row?, to snapshot: inout NSDiffableDataSourceSectionSnapshot<TableOfContentsState<O>.Row>, search: String) {
        var rows: [TableOfContentsState<O>.Row] = []
        for outline in outlines {
            if search.isEmpty {
                rows.append(.outline(outline: outline, isActive: true))
                continue
            }

            let containsSearch = outline.contains(string: search)
            let childrenContainSearch = outline.childrenContain(string: search)

            guard containsSearch || childrenContainSearch else { continue }
            rows.append(.outline(outline: outline, isActive: containsSearch))
        }
        snapshot.append(rows, to: parent)

        for (idx, element) in outlines.enumerated() {
            guard !element.children.isEmpty else { continue }

            if search.isEmpty {
                append(outlines: element.children, parent: rows[idx], to: &snapshot, search: search)
                continue
            }

            let index = rows.firstIndex(where: { row in
                switch row {
                case .outline(let outline, _):
                    return outline == element

                case .searchBar:
                    return false
                }
            })

            guard let index else { continue }
            append(outlines: element.children, parent: rows[index], to: &snapshot, search: search)
        }
    }
}
