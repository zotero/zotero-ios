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
    typealias Action = TableOfContentsAction<O>
    typealias State = TableOfContentsState<O>

    func process(action: TableOfContentsAction<O>, in viewModel: ViewModel<TableOfContentsActionHandler>) {
        switch action {
        case .search(let search):
            guard search != viewModel.state.search else { return }
            self.update(viewModel: viewModel) { state in
                state.search = search
                state.outlineSnapshot = createSnapshot(from: state.outlines, search: search, currentId: state.currentOutlineId)
                state.changes = .snapshot
            }

        case .load:
            self.update(viewModel: viewModel) { state in
                state.outlineSnapshot = createSnapshot(from: state.outlines, search: state.search, currentId: state.currentOutlineId)
                var changes: TableOfContentsChanges = .snapshot
                if state.currentOutlineId != nil {
                    changes.insert(.currentOutline)
                }
                state.changes = changes
            }

        case .setCurrentOutline(let id):
            guard id != viewModel.state.currentOutlineId else { return }
            self.update(viewModel: viewModel) { state in
                state.currentOutlineId = id
                state.outlineSnapshot = createSnapshot(from: state.outlines, search: state.search, currentId: id)
                state.changes = [.snapshot, .currentOutline]
            }

        case .setOutlines(let outlines):
            self.update(viewModel: viewModel) { state in
                state.outlines = outlines
                state.outlineSnapshot = createSnapshot(from: outlines, search: state.search, currentId: state.currentOutlineId)
                state.changes = .snapshot
            }
        }
    }

    private func createSnapshot(from outlines: [O], search: String, currentId: UUID?) -> NSDiffableDataSourceSectionSnapshot<TableOfContentsState<O>.Row>? {
        var snapshot = NSDiffableDataSourceSectionSnapshot<TableOfContentsState<O>.Row>()
        append(outlines: outlines, parent: nil, to: &snapshot, search: search, currentId: currentId)
        snapshot.collapse(snapshot.items)
        if snapshot.rootItems.count == 1 {
            snapshot.expand(snapshot.rootItems)
        }

        if let currentId {
            var ancestors: Set<UUID> = []
            _ = collectAncestors(of: currentId, in: outlines, ancestors: [], into: &ancestors)
            if !ancestors.isEmpty {
                let rowsToExpand = snapshot.items.compactMap({ row -> TableOfContentsState<O>.Row? in
                    guard case .outline(let outline, _, _) = row, ancestors.contains(outline.id) else { return nil }
                    return row
                })
                snapshot.expand(rowsToExpand)
            }
        }

        return snapshot
    }

    private func collectAncestors(of targetId: UUID, in outlines: [O], ancestors: [UUID], into result: inout Set<UUID>) -> Bool {
        for outline in outlines {
            if outline.id == targetId {
                result.formUnion(ancestors)
                return true
            }
            if collectAncestors(of: targetId, in: outline.children, ancestors: ancestors + [outline.id], into: &result) {
                return true
            }
        }
        return false
    }

    private func append(
        outlines: [O],
        parent: TableOfContentsState<O>.Row?,
        to snapshot: inout NSDiffableDataSourceSectionSnapshot<TableOfContentsState<O>.Row>,
        search: String,
        currentId: UUID?
    ) {
        var rows: [TableOfContentsState<O>.Row] = []
        for outline in outlines {
            let isCurrent = outline.id == currentId
            if search.isEmpty {
                rows.append(.outline(outline: outline, isActive: true, isCurrent: isCurrent))
                continue
            }

            let containsSearch = outline.contains(string: search)
            let childrenContainSearch = outline.childrenContain(string: search)

            guard containsSearch || childrenContainSearch else { continue }
            rows.append(.outline(outline: outline, isActive: containsSearch, isCurrent: isCurrent))
        }
        snapshot.append(rows, to: parent)

        for (idx, element) in outlines.enumerated() {
            guard !element.children.isEmpty else { continue }

            if search.isEmpty {
                append(outlines: element.children, parent: rows[idx], to: &snapshot, search: search, currentId: currentId)
                continue
            }

            let index = rows.firstIndex(where: { row in
                switch row {
                case .outline(let outline, _, _):
                    return outline == element

                case .searchBar:
                    return false
                }
            })

            guard let index else { continue }
            append(outlines: element.children, parent: rows[index], to: &snapshot, search: search, currentId: currentId)
        }
    }
}
