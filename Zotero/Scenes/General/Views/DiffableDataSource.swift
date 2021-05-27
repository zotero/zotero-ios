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

@objc protocol AdditionalDiffableDataSource : NSObjectProtocol {
    @objc optional func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
    @objc optional func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    @objc optional func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    @objc optional func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool
    @objc optional func sectionIndexTitles(for tableView: UITableView) -> [String]?
    @objc optional func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int
    @objc optional func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    @objc optional func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
}

enum DiffableDataSourceAnimation {
    case none
    case sections
    case rows(reload: UITableView.RowAnimation, insert: UITableView.RowAnimation, delete: UITableView.RowAnimation)
}

struct DiffableDataSourceSnapshot<Section: Hashable, Object: Hashable> {
    fileprivate(set) var isEditing: Bool
    fileprivate var sections: [Section]
    fileprivate var objects: [Section: [Object]]

    init(isEditing: Bool) {
        self.isEditing = isEditing
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

    func objects(for section: Section) -> [Object]? {
        return self.objects[section]
    }

    func sectionIndex(for section: Section) -> Int? {
        return self.sections.firstIndex(of: section)
    }

    func section(for index: Int) -> Section? {
        guard index < self.sections.count else { return nil }
        return self.sections[index]
    }

    func indexPath(where: (Object) -> Bool) -> IndexPath? {
        for (section, objects) in self.objects {
            if let index = objects.firstIndex(where: `where`), let sectionIndex = self.sections.firstIndex(of: section) {
                return IndexPath(row: index, section: sectionIndex)
            }
        }
        return nil
    }

    mutating func append(section: Section) {
        assert(!self.sections.contains(section), "Section already exists")
        self.sections.append(section)
    }

    mutating func append(objects: [Object], for section: Section) {
        assert(self.sections.contains(section), "Assigned section does not exist")
        self.objects[section] = objects
    }
}

class DiffableDataSource<Section: Hashable, Object: Hashable>: NSObject, UITableViewDataSource {
    typealias DequeueAction = (UITableView, IndexPath, Section, Object) -> UITableViewCell
    typealias SetupAction = (UITableViewCell, IndexPath, Section, Object) -> Void

    private let dequeueAction: DequeueAction
    private let setupAction: SetupAction

    private(set) var snapshot: DiffableDataSourceSnapshot<Section, Object>
    private weak var tableView: UITableView?

    weak var dataSource: AdditionalDiffableDataSource?

    init(tableView: UITableView, dequeueAction: @escaping DequeueAction, setupAction: @escaping SetupAction) {
        self.tableView = tableView
        self.dequeueAction = dequeueAction
        self.setupAction = setupAction
        self.snapshot = DiffableDataSourceSnapshot(isEditing: false)

        super.init()

        tableView.dataSource = self
    }

    // MARK: - Snapshot

    func apply(snapshot: DiffableDataSourceSnapshot<Section, Object>, animation: DiffableDataSourceAnimation = .none, completion: ((Bool) -> Void)?) {
        guard let tableView = self.tableView else { return }

        switch animation {
        case .none:
            self.snapshot = snapshot
            tableView.setEditing(snapshot.isEditing, animated: false)
            tableView.reloadData()

        case .sections:
            self.animateSectionChanges(for: snapshot, in: tableView, completion: completion)

        case .rows(let reload, let insert, let delete):
            self.animateSectionAndRowChanges(for: snapshot, reloadAnimation: reload, insertAnimation: insert, deleteAnimation: delete, in: tableView, completion: completion)
        }
    }

    func set(editing: Bool, animated: Bool) {
        self.snapshot.isEditing = editing
        self.tableView?.setEditing(editing, animated: animated)
    }

    func update(section: Section, with objects: [Object], animation: DiffableDataSourceAnimation = .none) {
        guard self.snapshot.objects[section] != nil else {
            DDLogWarn("DiffableDataSource: tried reloading section which is not in snapshot")
            return
        }
        var newSnapshot = self.snapshot
        newSnapshot.objects[section] = objects
        self.apply(snapshot: newSnapshot, animation: animation, completion: nil)
    }

    func updateWithoutReload(section: Section, with objects: [Object]) {
        guard self.snapshot.objects[section] != nil else {
            DDLogWarn("DiffableDataSource: tried reloading section which is not in snapshot")
            return
        }
        self.snapshot.objects[section] = objects
    }

    func update(object: Object, at indexPath: IndexPath) {
        guard indexPath.section < self.snapshot.sections.count else { return }
        let section = self.snapshot.sections[indexPath.section]
        guard var objects = self.snapshot.objects[section], indexPath.row < objects.count else { return }

        objects[indexPath.row] = object
        self.snapshot.objects[section] = objects

        guard let cell = self.tableView?.cellForRow(at: indexPath) else { return }
        self.setupAction(cell, indexPath, section, object)
    }

    // MARK: - Tableview Changes

    private func animateSectionChanges(for snapshot: DiffableDataSourceSnapshot<Section, Object>, in tableView: UITableView, completion: ((Bool) -> Void)?) {
        let editingChanged = self.snapshot.isEditing != snapshot.isEditing
        let (sectionReload, sectionInsert, sectionDelete) = self.diff(from: self.snapshot.sections.count, to: snapshot.sections.count)

        tableView.performBatchUpdates({
            self.snapshot = snapshot
            if !sectionReload.isEmpty {
                tableView.reloadSections(sectionReload, with: .automatic)
            }
            if !sectionInsert.isEmpty {
                tableView.insertSections(sectionInsert, with: .automatic)
            }
            if !sectionDelete.isEmpty {
                tableView.deleteSections(sectionDelete, with: .automatic)
            }
            if editingChanged {
                tableView.setEditing(snapshot.isEditing, animated: true)
            }
        }, completion: completion)
    }

    private func animateSectionAndRowChanges(for snapshot: DiffableDataSourceSnapshot<Section, Object>, reloadAnimation: UITableView.RowAnimation, insertAnimation: UITableView.RowAnimation,
                                deleteAnimation: UITableView.RowAnimation, in tableView: UITableView, completion: ((Bool) -> Void)?) {
        let (sectionInsert, sectionDelete, rowReload, rowInsert, rowDelete, rowMove, editingChanged) = self.diff(from: self.snapshot, to: snapshot)

//        if sectionInsert.isEmpty && sectionDelete.isEmpty && rowInsert.isEmpty && rowDelete.isEmpty && rowMove.isEmpty {
//            self.snapshot = snapshot
//            if !rowReload.isEmpty {
//                // Reload only visible cells, others will load as they come up on the screen.
//                self.updateVisibleCells(for: rowReload, in: tableView)
//            }
//            if editingChanged {
//                tableView.setEditing(snapshot.isEditing, animated: true)
//            }
//            completion?(true)
//            return
//        }

        // Perform batch updates
        tableView.performBatchUpdates({
            self.snapshot = snapshot
            if !sectionInsert.isEmpty {
                tableView.insertSections(sectionInsert, with: .automatic)
            }
            if !sectionDelete.isEmpty {
                tableView.deleteSections(sectionDelete, with: .automatic)
            }
            if !rowReload.isEmpty {
                tableView.reloadRows(at: rowReload, with: reloadAnimation)
            }
            if !rowInsert.isEmpty {
                tableView.insertRows(at: rowInsert, with: insertAnimation)
            }
            if !rowDelete.isEmpty {
                tableView.deleteRows(at: rowDelete, with: deleteAnimation)
            }
            if editingChanged {
                tableView.setEditing(snapshot.isEditing, animated: true)
            }
            if !rowMove.isEmpty {
                rowMove.forEach({ tableView.moveRow(at: $0.0, to: $0.1) })
            }
        }, completion: completion)
    }

    private func diff(from oldSnapshot: DiffableDataSourceSnapshot<Section, Object>, to newSnapshot: DiffableDataSourceSnapshot<Section, Object>)
                -> (sectionInsert: IndexSet, sectionDelete: IndexSet, rowReload: [IndexPath], rowInsert: [IndexPath], rowDelete: [IndexPath], rowMove: [(IndexPath, IndexPath)], editingChanged: Bool) {
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

        return (sectionInsert, sectionDelete, rowReload, rowInsert, rowDelete, rowMove, (oldSnapshot.isEditing != newSnapshot.isEditing))
    }

    private func diff(from oldSections: Int, to newSections: Int) -> (reload: IndexSet, insert: IndexSet, delete: IndexSet) {
        if oldSections == newSections {
            return (IndexSet(0..<newSections), [], [])
        }

        if oldSections > newSections {
            return (IndexSet(0..<newSections), [], IndexSet((oldSections - newSections)..<oldSections))
        }

        return (IndexSet(0..<oldSections), IndexSet((newSections - oldSections)..<newSections), [])
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
            self.setupAction(cell, indexPath, self.snapshot.sections[indexPath.section], object)
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
        let section = self.snapshot.sections[indexPath.section]

        let cell = self.dequeueAction(tableView, indexPath, section, object)
        self.setupAction(cell, indexPath, section, object)
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.dataSource?.tableView?(tableView, titleForHeaderInSection: section)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return self.dataSource?.tableView?(tableView, titleForFooterInSection: section)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return self.dataSource?.tableView?(tableView, canEditRowAt: indexPath) ?? false
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return self.dataSource?.tableView?(tableView, canMoveRowAt: indexPath) ?? false
    }

    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return self.dataSource?.sectionIndexTitles?(for: tableView)
    }

    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return self.dataSource?.tableView?(tableView, sectionForSectionIndexTitle: title, at: index) ?? 0
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        self.dataSource?.tableView?(tableView, commit: editingStyle, forRowAt: indexPath)
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        self.dataSource?.tableView?(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
    }
}
