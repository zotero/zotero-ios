//
//  TagFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

protocol TagFilterDelegate: AnyObject {
    func tagSelectionDidChange(selected: Set<String>)
}

class TagFilterViewController: UIViewController {
    private struct FilterTag: Hashable, Equatable {
        let tag: Tag
        let isActive: Bool
    }

    private var collectionView: UICollectionView!
    private weak var searchBarTopConstraint: NSLayoutConstraint!
    private var dataSource: UICollectionViewDiffableDataSource<Int, FilterTag>!
    weak var delegate: TagFilterDelegate?
    private var searchBarScrollEnabled: Bool
    private var didAppear: Bool

    private static let cellId = "TagFilterCell"
    private static let searchBarHeight: CGFloat = 56
    private static let searchBarOffset: CGFloat = -10
    private let viewModel: ViewModel<TagFilterActionHandler>
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<TagFilterActionHandler>) {
        self.viewModel = viewModel
        self.searchBarScrollEnabled = true
        self.disposeBag = DisposeBag()
        self.didAppear = false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemBackground
        self.setupViews()
        self.setupDataSource()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !self.didAppear else { return }

        let height = TagFilterViewController.searchBarHeight + TagFilterViewController.searchBarOffset
        self.collectionView.setContentOffset(CGPoint(x: 0, y: height), animated: false)
    }

    private func update(to state: TagFilterState) {
        if state.changes.contains(.selection) {
            self.delegate?.tagSelectionDidChange(selected: state.selectedTags)
        }

        if state.changes.contains(.tags), let colored = state.coloredResults, let other = state.otherResults, let filtered = state.filteredResults {
            self.dataSource.apply(self.createSnapshot(fromColoredResults: colored, otherResults: other, filteredResults: filtered))
        }

        if state.coloredChange != nil || state.otherChange != nil, let coloredResults = state.coloredResults, let filteredResults = state.filteredResults {
            self.dataSource.apply(self.updatedSnapshot(withColoredChange: state.coloredChange, coloredResults: coloredResults, otherChange: state.otherChange, filteredResults: filteredResults))
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func snapSearchBarToAppropriatePosition(scrollView: UIScrollView) {
        let height = TagFilterViewController.searchBarHeight + TagFilterViewController.searchBarOffset
        guard scrollView.contentOffset.y > 0 && scrollView.contentOffset.y < height else { return }
        let offset = scrollView.contentOffset.y > (height / 2) ? CGPoint(x: 0, y: height) : CGPoint()
        self.collectionView.setContentOffset(offset, animated: true)
    }

    private func createSnapshot(fromColoredResults coloredResults: Results<RTag>, otherResults: Results<RTag>, filteredResults: Results<RTag>) -> NSDiffableDataSourceSnapshot<Int, FilterTag> {
        var tags: [FilterTag] = []
        // Load colored and other results, see whether tags are included in the filter or not.
        for rTag in coloredResults {
            let isActive = filteredResults.filter(.name(rTag.name)).first != nil
            tags.append(FilterTag(tag: Tag(tag: rTag), isActive: isActive))
        }
//        for rTag in otherResults {
//            let isActive = filteredResults.filter(.name(rTag.name)).first != nil
//            tags.append(FilterTag(tag: Tag(tag: rTag), isActive: isActive))
//        }
        tags.append(contentsOf: otherResults.map({ FilterTag(tag: Tag(tag: $0), isActive: true) }))
        
        var snapshot = NSDiffableDataSourceSnapshot<Int, FilterTag>()
        snapshot.appendSections([0])
        snapshot.appendItems(tags)
        return snapshot
    }

    private func updatedSnapshot(withColoredChange coloredChange: TagFilterState.ObservedChange?, coloredResults: Results<RTag>, otherChange: TagFilterState.ObservedChange?, filteredResults: Results<RTag>) -> NSDiffableDataSourceSnapshot<Int, FilterTag> {
        var tags = self.dataSource.snapshot().itemIdentifiers

        if let change = coloredChange {
            self.update(tags: &tags, change: change, filteredResults: filteredResults)
        }

        if let change = otherChange {
            let coloredCount = (coloredChange?.results ?? coloredResults).count
            self.update(tags: &tags, change: change, filteredResults: filteredResults, baseIndex: coloredCount, defaultIsActive: true)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, FilterTag>()
        snapshot.appendSections([0])
        snapshot.appendItems(tags)
        return snapshot
    }

    private func update(tags: inout [FilterTag], change: TagFilterState.ObservedChange, filteredResults: Results<RTag>, baseIndex: Int = 0, defaultIsActive: Bool? = nil) {
        // Get modification indices in new results
        let correctedModifications = Database.correctedModifications(from: change.modifications, insertions: change.insertions, deletions: change.deletions)
        // Update modified tags
        for idx in 0..<change.modifications.count {
            let newTag = change.results[correctedModifications[idx]]
            let index = baseIndex + change.modifications[idx]
            let isActive = defaultIsActive ?? (filteredResults.filter(.name(newTag.name)).first != nil)
            tags[index] = FilterTag(tag: Tag(tag: newTag), isActive: isActive)
        }
        // Remove deleted tags
        for index in change.deletions.reversed() {
            tags.remove(at: (baseIndex + index))
        }
        // Insert new tags
        for index in change.insertions {
            let newTag = change.results[index]
            let isActive = defaultIsActive ?? (filteredResults.filter(.name(newTag.name)).first != nil)
            tags.insert(FilterTag(tag: Tag(tag: newTag), isActive: isActive), at: (baseIndex + index))
        }
    }

    private func setupViews() {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search Tags"
        searchBar.backgroundColor = .systemBackground
        searchBar.backgroundImage = UIImage()
        searchBar.delegate = self
        searchBar.rx.text.observe(on: MainScheduler.instance)
                 .skip(1)
                 .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                 .subscribe(onNext: { [weak self] text in
                     self?.viewModel.process(action: .search(text ?? ""))
                 })
                 .disposed(by: self.disposeBag)
        self.view.addSubview(searchBar)

        let layout = TagsFlowLayout(maxWidth: self.view.frame.width, minimumInteritemSpacing: 8, minimumLineSpacing: 8,
                                    sectionInset: UIEdgeInsets(top: (TagFilterViewController.searchBarHeight + TagFilterViewController.searchBarOffset), left: 10, bottom: 8, right: 10))
        let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColor = .systemBackground
        collectionView.layer.masksToBounds = true
        collectionView.register(UINib(nibName: "TagFilterCell", bundle: nil), forCellWithReuseIdentifier: TagFilterViewController.cellId)
        self.collectionView = collectionView
        self.view.insertSubview(collectionView, belowSubview: searchBar)

        let searchBarTop = searchBar.topAnchor.constraint(equalTo: self.view.topAnchor, constant: TagFilterViewController.searchBarOffset)

        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            searchBarTop,
            self.collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.collectionView.trailingAnchor)
        ])

        self.searchBarTopConstraint = searchBarTop
    }

    private func setupDataSource() {
        self.dataSource = UICollectionViewDiffableDataSource(collectionView: self.collectionView, cellProvider: { collectionView, indexPath, filterTag in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TagFilterViewController.cellId, for: indexPath)
            if let cell = cell as? TagFilterCell, let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
                cell.maxWidth = collectionView.frame.width - flowLayout.sectionInset.left - flowLayout.sectionInset.right -
                                collectionView.contentInset.left - collectionView.contentInset.right - 20
                let color: UIColor = filterTag.tag.color.isEmpty ? .label : UIColor(hex: filterTag.tag.color)
                cell.setup(with: filterTag.tag.name, color: color, isActive: filterTag.isActive)
            }
            return cell
        })
    }
}

extension TagFilterViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let filterTag = self.dataSource.itemIdentifier(for: indexPath), filterTag.isActive else { return }

        self.viewModel.process(action: .select(filterTag.tag.name))

        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let filterTag = self.dataSource.itemIdentifier(for: indexPath), filterTag.isActive else { return }

        self.viewModel.process(action: .deselect(filterTag.tag.name))

        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard self.searchBarScrollEnabled else { return }
        self.searchBarTopConstraint.constant = -scrollView.contentOffset.y + TagFilterViewController.searchBarOffset
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        self.snapSearchBarToAppropriatePosition(scrollView: scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.snapSearchBarToAppropriatePosition(scrollView: scrollView)
    }
}

extension TagFilterViewController: DraggableViewController {
    func enablePanning() {
        self.collectionView.isScrollEnabled = true
    }

    func disablePanning() {
        self.collectionView.isScrollEnabled = false
    }
}

extension TagFilterViewController: UISearchBarDelegate {
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        self.searchBarScrollEnabled = false
        self.searchBarTopConstraint.constant = TagFilterViewController.searchBarOffset

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
            self.collectionView.setContentOffset(CGPoint(), animated: false)
            self.view.layoutIfNeeded()
        })

        return true
    }

    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        self.searchBarScrollEnabled = true
        return true
    }
}

extension TagFilterViewController: ItemsTagFilterDelegate {
    var selectedTags: Set<String> {
        return self.viewModel.state.selectedTags
    }

    func itemsDidChange(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, isInitial: Bool) {
        let start = CFAbsoluteTimeGetCurrent()
        self.viewModel.process(action: .loadWithCollection(collectionId: collectionId, libraryId: libraryId, clearSelection: isInitial))
        let res = CFAbsoluteTimeGetCurrent() - start
        DDLogInfo("TAGS TIME 1: \(res)")
    }

    func itemsDidChange(results: Results<RItem>, libraryId: LibraryIdentifier, isInitial: Bool) {
        let start = CFAbsoluteTimeGetCurrent()
        var keys: Set<String> = []
        for item in results {
            keys.insert(item.key)
            self.keys(fromChildren: item.children, keys: &keys)
        }
        self.viewModel.process(action: .loadWithKeys(itemKeys: keys, libraryId: libraryId, clearSelection: isInitial))
        let res = CFAbsoluteTimeGetCurrent() - start
        DDLogInfo("TAGS TIME 2: \(res)")
    }

    private func keys(fromChildren results: LinkingObjects<RItem>, keys: inout Set<String>) {
        guard !results.isEmpty else { return }
        for item in results {
            keys.insert(item.key)
            self.keys(fromChildren: item.children, keys: &keys)
        }
    }
}
