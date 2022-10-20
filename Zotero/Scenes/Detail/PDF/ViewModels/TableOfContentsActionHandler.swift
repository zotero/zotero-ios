//
//  TableOfContentsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 20.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit

struct TableOfContentsActionHandler: ViewModelActionHandler {
    typealias Action = TableOfContentsAction
    typealias State = TableOfContentsState

    func process(action: TableOfContentsAction, in viewModel: ViewModel<TableOfContentsActionHandler>) {
        switch action {
        case .search(let search):
            guard search != viewModel.state.search else { return }
            self.update(viewModel: viewModel) { state in
                state.search = search
                state.outlineSnapshot = self.createSnapshot(from: state.document, search: search)
                state.changes = .snapshot
            }

        case .load:
            self.update(viewModel: viewModel) { state in
                state.outlineSnapshot = self.createSnapshot(from: state.document, search: state.search)
                state.changes = .snapshot
            }
        }
    }

    private func createSnapshot(from document: Document, search: String) -> NSDiffableDataSourceSectionSnapshot<TableOfContentsViewController.Row>? {
        guard let outlines = document.outline?.children else { return nil }

        var snapshot = NSDiffableDataSourceSectionSnapshot<TableOfContentsViewController.Row>()
        self.append(outlines: outlines, parent: nil, to: &snapshot, search: search)
        snapshot.expand(snapshot.items)
        return snapshot
    }

    private func append(outlines: [OutlineElement], parent: TableOfContentsViewController.Row?, to snapshot: inout NSDiffableDataSourceSectionSnapshot<TableOfContentsViewController.Row>, search: String) {
        var rows: [TableOfContentsViewController.Row] = []
        for element in outlines {
            if search.isEmpty {
                let outline = TableOfContentsState.Outline(element: element, isActive: true)
                rows.append(.outline(outline))
                continue
            }

            let elementContainsSearch = self.outline(element, contains: search)
            let childContainsSearch = self.child(in: (element.children ?? []), contains: search)

            guard elementContainsSearch || childContainsSearch else { continue }

            let outline = TableOfContentsState.Outline(element: element, isActive: elementContainsSearch)
            rows.append(.outline(outline))
        }
        snapshot.append(rows, to: parent)

        for (idx, element) in outlines.enumerated() {
            guard let children = element.children else { continue }

            if search.isEmpty {
                self.append(outlines: children, parent: rows[idx], to: &snapshot, search: search)
                continue
            }

            let index = rows.firstIndex(where: { row in
                switch row {
                case .outline(let outline):
                    return outline.title == element.title && outline.page == element.pageIndex
                case .searchBar:
                    return false
                }
            })

            guard let index = index else { continue }
            self.append(outlines: children, parent: rows[index], to: &snapshot, search: search)
        }
    }

    private func child(in children: [OutlineElement], contains string: String) -> Bool {
        guard !children.isEmpty else { return false }

        for child in children {
            if self.outline(child, contains: string) {
                return true
            }

            if let children = child.children, self.child(in: children, contains: string) {
                return true
            }
        }

        return false
    }

    private func outline(_ outline: OutlineElement, contains string: String) -> Bool {
        return (outline.title ?? "").localizedCaseInsensitiveContains(string) || UInt(string) == outline.pageIndex
    }
}

#endif
