//
//  DiffableDataSource.swift
//  Zotero
//
//  Created by Michal Rentka on 12.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import Differ

enum DiffableDataSourceAnimation {
    case none
    case animate(reload: UITableView.RowAnimation, insert: UITableView.RowAnimation, delete: UITableView.RowAnimation)
}

struct DiffableDataSourceSnapshot<Section: Hashable, Object: Hashable> {
    fileprivate var sections: [Section]
    fileprivate var objects: [Section: [Object]]

    init() {
        self.sections = []
        self.objects = [:]
    }

    func count(for section: Section) -> Int {
        return self.objects[section]?.count ?? 0
    }

    func object(at indexPath: IndexPath) -> Object? {
        guard indexPath.section < self.sections.count, let objects = self.objects[self.sections[indexPath.section]], indexPath.row < objects.count else { return nil }
        return objects[indexPath.row]
    }

    func indexPath(where: (Object) -> Bool) -> IndexPath? {
        for (section, objects) in self.objects {
            if let index = objects.firstIndex(where: `where`), let sectionIndex = self.sections.firstIndex(of: section) {
                return IndexPath(row: index, section: sectionIndex)
            }
        }
        return nil
    }

    mutating func create(section: Section) {
        assert(!self.sections.contains(section), "Section already exists")
        self.sections.append(section)
    }

    mutating func append(objects: [Object], for section: Section) {
        assert(self.sections.contains(section), "Assigned section does not exist")
        self.objects[section] = objects
    }
}

class DiffableDataSource<Section: Hashable, Object: Hashable>: NSObject, UITableViewDataSource {
    typealias DequeueAction = (UITableView, IndexPath, Object) -> UITableViewCell
    typealias SetupAction = (UITableViewCell, Object) -> Void

    private let dequeueAction: DequeueAction
    private let setupAction: SetupAction

    private(set) var snapshot: DiffableDataSourceSnapshot<Section, Object>
    private weak var tableView: UITableView?

    init(tableView: UITableView, dequeueAction: @escaping DequeueAction, setupAction: @escaping SetupAction) {
        self.tableView = tableView
        self.dequeueAction = dequeueAction
        self.setupAction = setupAction
        self.snapshot = DiffableDataSourceSnapshot()

        super.init()

        tableView.dataSource = self
    }

    // MARK: - Snapshot

    func apply(snapshot: DiffableDataSourceSnapshot<Section, Object>, animation: DiffableDataSourceAnimation = .none, completion: ((Bool) -> Void)?) {
        guard let tableView = self.tableView else { return }

        switch animation {
        case .none:
            self.snapshot = snapshot
            tableView.reloadData()

        case .animate(let reload, let insert, let delete):
            self.animateChanges(for: snapshot, reloadAnimation: reload, insertAnimation: insert, deleteAnimation: delete, in: tableView, completion: completion)
        }
    }

    func update(object: Object, at indexPath: IndexPath) {
        guard indexPath.section < self.snapshot.sections.count, var objects = self.snapshot.objects[self.snapshot.sections[indexPath.section]], indexPath.row < objects.count else { return }

        objects[indexPath.row] = object
        self.snapshot.objects[self.snapshot.sections[indexPath.section]] = objects

        guard let cell = self.tableView?.cellForRow(at: indexPath) else { return }
        self.setupAction(cell, object)
    }

    // MARK: - Tableview Changes

    private func animateChanges(for snapshot: DiffableDataSourceSnapshot<Section, Object>, reloadAnimation: UITableView.RowAnimation, insertAnimation: UITableView.RowAnimation,
                                deleteAnimation: UITableView.RowAnimation, in tableView: UITableView, completion: ((Bool) -> Void)?) {
        let (sectionInsert, sectionDelete, rowReload, rowInsert, rowDelete, rowMove) = self.diff(from: self.snapshot, to: snapshot)

        if sectionInsert.isEmpty && sectionDelete.isEmpty && rowInsert.isEmpty && rowDelete.isEmpty && rowMove.isEmpty {
            self.snapshot = snapshot
            if !rowReload.isEmpty {
                // Reload only visible cells, others will load as they come up on the screen.
                self.updateVisibleCells(for: rowReload, in: tableView)
            }
            completion?(true)
            return
        }

        // Perform batch updates
        tableView.performBatchUpdates({
            self.snapshot = snapshot
            tableView.insertSections(sectionInsert, with: .automatic)
            tableView.deleteSections(sectionDelete, with: .automatic)
            tableView.reloadRows(at: rowReload, with: reloadAnimation)
            tableView.insertRows(at: rowInsert, with: insertAnimation)
            tableView.deleteRows(at: rowDelete, with: deleteAnimation)
        }, completion: completion)
    }

    private func diff(from oldSnapshot: DiffableDataSourceSnapshot<Section, Object>, to newSnapshot: DiffableDataSourceSnapshot<Section, Object>)
                                            -> (sectionInsert: IndexSet, sectionDelete: IndexSet, rowReload: [IndexPath], rowInsert: [IndexPath], rowDelete: [IndexPath], rowMove: [(IndexPath, IndexPath)]) {
        let (sectionReload, sectionInsert, sectionDelete) = self.diff(from: oldSnapshot.sections.count, to: newSnapshot.sections.count)

        var rowReload: [IndexPath] = []
        var rowInsert: [IndexPath] = []
        var rowDelete: [IndexPath] = []
        var rowMove: [(IndexPath, IndexPath)] = []

        for section in sectionReload {
            let (reload, insert, delete, move) = self.diff(from: (oldSnapshot.objects[oldSnapshot.sections[section]] ?? []), to: (newSnapshot.objects[newSnapshot.sections[section]] ?? []), in: section)

            rowReload.append(contentsOf: reload)
            rowInsert.append(contentsOf: insert)
            rowDelete.append(contentsOf: delete)
            rowMove.append(contentsOf: move)
        }

        return (IndexSet(sectionInsert), IndexSet(sectionDelete), rowReload, rowInsert, rowDelete, rowMove)
    }

    private func diff(from oldSections: Int, to newSections: Int) -> (reload: [Int], insert: [Int], delete: [Int]) {
        if oldSections == newSections {
            return (Array(0..<newSections), [], [])
        }

        if oldSections > newSections {
            return (Array(0..<newSections), [], Array((oldSections - newSections)..<oldSections))
        }

        return (Array(0..<oldSections), Array((newSections - oldSections)..<newSections), [])
    }

    private func diff(from oldObjects: [Object], to newObjects: [Object], in section: Int) -> (reload: [IndexPath], insert: [IndexPath], delete: [IndexPath], move: [(IndexPath, IndexPath)]) {
        let diff = oldObjects.extendedDiff(newObjects)

        var insertions: Set<Int> = []
        var deletions: Set<Int> = []
        var moves: [(Int, Int)] = []

        diff.elements.forEach { element in
            switch element {
            case .delete(let index):
                deletions.insert(index)
            case .insert(let index):
                insertions.insert(index)
            case .move(let from, let to):
                moves.append((from, to))
            }
        }

        let reloads = insertions.intersection(deletions)
        insertions.subtract(reloads)
        deletions.subtract(reloads)

        return (reloads.map({ IndexPath(row: $0, section: section) }),
                insertions.map({ IndexPath(row: $0, section: section) }),
                deletions.map({ IndexPath(row: $0, section: section) }),
                moves.map({ (IndexPath(row: $0.0, section: section), IndexPath(row: $0.1, section: section)) }))
    }

    private func updateVisibleCells(for indexPaths: [IndexPath], in tableView: UITableView) {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else { return }
        for indexPath in visibleIndexPaths.filter({ indexPaths.contains($0) }) {
            guard let cell = tableView.cellForRow(at: indexPath), let object = self.snapshot.object(at: indexPath) else { continue }
            self.setupAction(cell, object)
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.snapshot.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < self.snapshot.sections.count else { return 0 }
        return self.snapshot.objects[self.snapshot.sections[section]]?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let object = self.snapshot.object(at: indexPath) else { return UITableViewCell() }

        let cell = self.dequeueAction(tableView, indexPath, object)
        self.setupAction(cell, object)
        return cell
    }
}
