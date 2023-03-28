//
//  TagFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift
import RxSwift

protocol TagFilterDelegate: AnyObject {
    func tagSelectionDidChange(selected: Set<String>)
}

class TagFilterViewController: UIViewController, ItemsTagFilterDelegate {
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Tag>!
    weak var delegate: TagFilterDelegate?

    var selectedTags: Set<String> {
        return self.viewModel.state.selectedTags
    }

    private static let cellId = "TagFilterCell"
    private let viewModel: ViewModel<TagFilterActionHandler>
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<TagFilterActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupViews()
        self.setupDataSource()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .load(libraryId: self.viewModel.state.libraryId, collectionId: self.viewModel.state.collectionId, clearSelection: false))
    }

    func change(to libraryId: LibraryIdentifier, collectionId: CollectionIdentifier) {
        self.viewModel.process(action: .load(libraryId: libraryId, collectionId: collectionId, clearSelection: true))
    }

    private func update(to state: TagFilterState) {
        if state.changes.contains(.selection) {
            self.delegate?.tagSelectionDidChange(selected: state.selectedTags)
        }

        if state.changes.contains(.tags), let colored = state.coloredResults, let other = state.otherResults {
            self.dataSource.apply(self.createSnapshot(fromColoredResults: colored, otherResults: other))
        }

        if state.coloredChange != nil || state.otherChange != nil, let coloredResults = state.coloredResults {
            self.dataSource.apply(self.updatedSnapshot(withColoredChange: state.coloredChange, coloredResults: coloredResults, otherChange: state.otherChange))
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func createSnapshot(fromColoredResults coloredResults: Results<RTag>, otherResults: Results<RTag>) -> NSDiffableDataSourceSnapshot<Int, Tag> {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Tag>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(coloredResults.map(Tag.init)) + Array(otherResults.map(Tag.init)))
        return snapshot
    }

    private func updatedSnapshot(withColoredChange coloredChange: TagFilterState.ObservedChange?, coloredResults: Results<RTag>, otherChange: TagFilterState.ObservedChange?) -> NSDiffableDataSourceSnapshot<Int, Tag> {
        var tags = self.dataSource.snapshot().itemIdentifiers

        if let change = coloredChange {
            self.update(tags: &tags, change: change)
        }

        if let change = otherChange {
            let coloredCount = (coloredChange?.results ?? coloredResults).count
            self.update(tags: &tags, change: change, baseIndex: coloredCount)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, Tag>()
        snapshot.appendSections([0])
        snapshot.appendItems(tags)
        return snapshot
    }

    private func update(tags: inout [Tag], change: TagFilterState.ObservedChange, baseIndex: Int = 0) {
        // Get modification indices in new results
        let correctedModifications = Database.correctedModifications(from: change.modifications, insertions: change.insertions, deletions: change.deletions)
        // Update modified tags
        for idx in 0..<change.modifications.count {
            let index = baseIndex + change.modifications[idx]
            tags[index] = Tag(tag: change.results[correctedModifications[idx]])
        }
        // Remove deleted tags
        for index in change.deletions.reversed() {
            tags.remove(at: (baseIndex + index))
        }
        // Insert new tags
        for index in change.insertions {
            tags.insert(Tag(tag: change.results[index]), at: (baseIndex + index))
        }
    }

    private func setupViews() {
        let layout = TagsFlowLayout(maxWidth: self.view.frame.width, minimumInteritemSpacing: 8, minimumLineSpacing: 8,
                                    sectionInset: UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
        let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        collectionView.register(UINib(nibName: "TagFilterCell", bundle: nil), forCellWithReuseIdentifier: TagFilterViewController.cellId)
        self.collectionView = collectionView

        self.view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            self.collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])
    }

    private func setupDataSource() {
        self.dataSource = UICollectionViewDiffableDataSource(collectionView: self.collectionView, cellProvider: { collectionView, indexPath, tag in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TagFilterViewController.cellId, for: indexPath)
            if let cell = cell as? TagFilterCell {
                cell.maxWidth = collectionView.bounds.width - 20
                let color: UIColor = tag.color.isEmpty ? .label : UIColor(hex: tag.color)
                cell.setup(with: tag.name, color: color)
            }
            return cell
        })
    }
}

extension TagFilterViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let tag = self.dataSource.itemIdentifier(for: indexPath) else { return }

        self.viewModel.process(action: .select(tag.name))

        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let tag = self.dataSource.itemIdentifier(for: indexPath) else { return }

        self.viewModel.process(action: .deselect(tag.name))

        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
    }
}
