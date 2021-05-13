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

struct DiffableDataSourceSnapshot<Object: Identifiable & Hashable & Equatable> {
    fileprivate let sections: Int
    fileprivate var objects: [Int: [Object]]

    init(numberOfSections: Int) {
        self.sections = numberOfSections
        self.objects = [:]
    }

    func count(for section: Int) -> Int {
        return self.objects[section]?.count ?? 0
    }

    func object(at indexPath: IndexPath) -> Object? {
        guard let objects = self.objects[indexPath.section], indexPath.row < objects.count else { return nil }
        return objects[indexPath.row]
    }

    func indexPath(for identifier: Object.ID) -> IndexPath? {
        for (section, objects) in self.objects {
            if let index = objects.firstIndex(where: { $0.id == identifier }) {
                return IndexPath(row: index, section: section)
            }
        }
        return nil
    }

    mutating func append(objects: [Object], for section: Int) {
        assert(section < self.sections, "Assigned section is more than number of sections")
        self.objects[section] = objects
    }
}

class DiffableDataSource<Object: Identifiable & Hashable & Equatable>: NSObject, UITableViewDataSource {
    typealias DequeueAction = (UITableView, IndexPath) -> UITableViewCell
    typealias SetupAction = (UITableViewCell, Object) -> Void

    private let dequeueAction: DequeueAction
    private let setupAction: SetupAction

    private(set) var snapshot: DiffableDataSourceSnapshot<Object>
    private weak var tableView: UITableView?

    init(tableView: UITableView, dequeueAction: @escaping DequeueAction, setupAction: @escaping SetupAction) {
        self.tableView = tableView
        self.dequeueAction = dequeueAction
        self.setupAction = setupAction
        self.snapshot = DiffableDataSourceSnapshot(numberOfSections: 0)

        super.init()

        tableView.dataSource = self
    }

    // MARK: - Snapshot

    func apply(snapshot: DiffableDataSourceSnapshot<Object>, animation: DiffableDataSourceAnimation = .none, completion: ((Bool) -> Void)?) {
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
        guard indexPath.section < self.snapshot.sections, var objects = self.snapshot.objects[indexPath.section], indexPath.row < objects.count else { return }

        objects[indexPath.row] = object
        self.snapshot.objects[indexPath.section] = objects

        guard let cell = self.tableView?.cellForRow(at: indexPath) else { return }
        self.setupAction(cell, object)
    }

    // MARK: - Tableview Changes

    private func animateChanges(for snapshot: DiffableDataSourceSnapshot<Object>, reloadAnimation: UITableView.RowAnimation, insertAnimation: UITableView.RowAnimation,
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

    private func diff(from oldSnapshot: DiffableDataSourceSnapshot<Object>, to newSnapshot: DiffableDataSourceSnapshot<Object>)
                                            -> (sectionInsert: IndexSet, sectionDelete: IndexSet, rowReload: [IndexPath], rowInsert: [IndexPath], rowDelete: [IndexPath], rowMove: [(IndexPath, IndexPath)]) {
        let (sectionReload, sectionInsert, sectionDelete) = self.diff(from: oldSnapshot.sections, to: newSnapshot.sections)

        var rowReload: [IndexPath] = []
        var rowInsert: [IndexPath] = []
        var rowDelete: [IndexPath] = []
        var rowMove: [(IndexPath, IndexPath)] = []

        for section in sectionReload {
            let (reload, insert, delete, move) = self.diff(from: (oldSnapshot.objects[section] ?? []), to: (newSnapshot.objects[section] ?? []), in: section)

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
        return self.snapshot.sections
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.snapshot.objects[section]?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = self.dequeueAction(tableView, indexPath)
        if let object = self.snapshot.object(at: indexPath) {
            self.setupAction(cell, object)
        }
        return cell
    }
}
