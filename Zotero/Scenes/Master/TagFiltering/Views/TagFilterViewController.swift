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
    func tagOptionsDidChange()
}

class TagFilterViewController: UIViewController {
    private struct FilterTag: Hashable, Equatable {
        let tag: Tag
        let isActive: Bool
    }

    private weak var collectionView: UICollectionView!
    private weak var searchBarTopConstraint: NSLayoutConstraint!
    private weak var optionsButton: UIButton!
    private var dataSource: UICollectionViewDiffableDataSource<Int, FilterTag>!
    weak var delegate: TagFilterDelegate?
    private var searchBarScrollEnabled: Bool
    private var didAppear: Bool

    private static let cellId = "TagFilterCell"
    private static let searchBarHeight: CGFloat = 56
    private static let searchBarTopOffset: CGFloat = -10
    private static let searchBarBottomOffset: CGFloat = -8
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

        let height = TagFilterViewController.searchBarHeight + TagFilterViewController.searchBarTopOffset
        self.collectionView.setContentOffset(CGPoint(x: 0, y: height), animated: false)
    }

    private func update(to state: TagFilterState) {
        if state.changes.contains(.selection) {
            self.delegate?.tagSelectionDidChange(selected: state.selectedTags)
        }

        if state.changes.contains(.tags), let colored = state.coloredResults, let other = state.otherResults, let filtered = state.filteredResults {
            self.dataSource.apply(self.createSnapshot(fromColoredResults: colored, otherResults: other, filteredResults: filtered, displayAll: state.displayAll))
            self.fixSelectionIfNeeded(selected: state.selectedTags)
        }

        if state.coloredChange != nil || state.otherChange != nil, let coloredResults = state.coloredResults, let filteredResults = state.filteredResults {
            self.dataSource.apply(self.updatedSnapshot(withColoredChange: state.coloredChange, coloredResults: coloredResults, otherChange: state.otherChange, filteredResults: filteredResults))
            self.fixSelectionIfNeeded(selected: state.selectedTags)
        }

        if state.changes.contains(.options) {
            self.optionsButton.menu = self.createOptionsMenu(with: state)
            self.delegate?.tagOptionsDidChange()
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func fixSelectionIfNeeded(selected: Set<String>) {
        guard let selectedIndexPaths = self.collectionView.indexPathsForSelectedItems else { return }

        var currentlySelected: Set<String> = []
        for indexPath in selectedIndexPaths {
            guard let name = self.dataSource.itemIdentifier(for: indexPath)?.tag.name else { continue }
            currentlySelected.insert(name)
        }

        guard selected != currentlySelected else { return }

        for indexPath in selectedIndexPaths {
            self.collectionView.deselectItem(at: indexPath, animated: false)
            (self.collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
        }

        let itemIdentifiers = self.dataSource.snapshot().itemIdentifiers
        var indexPathsToSelect: [IndexPath] = []
        for name in selected {
            guard let index = itemIdentifiers.firstIndex(where: { $0.tag.name == name }) else { continue }
            indexPathsToSelect.append(IndexPath(row: index, section: 0))
        }

        for indexPath in indexPathsToSelect {
            self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            (self.collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: true)
        }
    }

    private func snapSearchBarToAppropriatePosition(scrollView: UIScrollView) {
        let height = TagFilterViewController.searchBarHeight + TagFilterViewController.searchBarTopOffset
        guard scrollView.contentOffset.y > 0 && scrollView.contentOffset.y < height else { return }
        let offset = scrollView.contentOffset.y > (height / 2) ? CGPoint(x: 0, y: height) : CGPoint()
        self.collectionView.setContentOffset(offset, animated: true)
    }

    private func createSnapshot(fromColoredResults coloredResults: Results<RTag>, otherResults: Results<RTag>, filteredResults: Results<RTag>, displayAll: Bool) -> NSDiffableDataSourceSnapshot<Int, FilterTag> {
        var tags: [FilterTag] = []
        // Load colored and other results, see whether tags are included in the filter or not.
        for rTag in coloredResults {
            let isActive = filteredResults.filter(.name(rTag.name)).first != nil
            tags.append(FilterTag(tag: Tag(tag: rTag), isActive: isActive))
        }

        if !displayAll {
            tags.append(contentsOf: otherResults.map({ FilterTag(tag: Tag(tag: $0), isActive: true) }))
        } else {
            for rTag in otherResults {
                let isActive = filteredResults.filter(.name(rTag.name)).first != nil
                tags.append(FilterTag(tag: Tag(tag: rTag), isActive: isActive))
            }
        }
        
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

    private func createOptionsMenu(with state: TagFilterState) -> UIMenu {
        let deselectAction = UIAction(title: "Deselect All", handler: { [weak self] _ in
            self?.viewModel.process(action: .deselectAll)
        })
        let deselectMenu = UIMenu(options: .displayInline, children: [deselectAction])

        let showAutomatic = UIAction(title: "Show Automatic", state: (state.showAutomatic ? .on : .off), handler: { [weak self] _ in
            guard let `self` = self else { return }
            self.viewModel.process(action: .setShowAutomatic(!self.viewModel.state.showAutomatic))
        })
        let displayAll = UIAction(title: "Display All Tags in This Library", state: (state.displayAll ? .on : .off), handler: { [weak self] _ in
            guard let `self` = self else { return }
            self.viewModel.process(action: .setDisplayAll(!self.viewModel.state.displayAll))
        })
        let optionsMenu = UIMenu(options: .displayInline, children: [showAutomatic, displayAll])

        let deleteAutomatic = UIAction(title: "Delete Automatic Tags in This Library", attributes: .destructive, handler: { _ in })
        let deleteMenu = UIMenu(options: .displayInline, children: [deleteAutomatic])

        return UIMenu(children: [deleteMenu, optionsMenu, deselectMenu])
    }

    private func setupViews() {
        let searchBar = UISearchBar()
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

        let optionsButton = UIButton()
        optionsButton.setTitle("Options", for: .normal)
        optionsButton.setTitleColor(Asset.Colors.zoteroBlueWithDarkMode.color, for: .normal)
        optionsButton.showsMenuAsPrimaryAction = true
        optionsButton.menu = self.createOptionsMenu(with: self.viewModel.state)
        self.optionsButton = optionsButton

        let searchContainer = UIStackView(arrangedSubviews: [searchBar, optionsButton])
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.axis = .horizontal
        self.view.addSubview(searchContainer)

        let layout = TagsFlowLayout(maxWidth: self.view.frame.width, minimumInteritemSpacing: 8, minimumLineSpacing: 8,
                                    sectionInset: UIEdgeInsets(top: (TagFilterViewController.searchBarHeight + TagFilterViewController.searchBarTopOffset + TagFilterViewController.searchBarBottomOffset), left: 10, bottom: 8, right: 10))
        let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColor = .systemBackground
        collectionView.layer.masksToBounds = true
        collectionView.register(UINib(nibName: "TagFilterCell", bundle: nil), forCellWithReuseIdentifier: TagFilterViewController.cellId)
        self.collectionView = collectionView
        self.view.insertSubview(collectionView, belowSubview: searchContainer)

        let searchBarTop = searchContainer.topAnchor.constraint(equalTo: self.view.topAnchor, constant: TagFilterViewController.searchBarTopOffset)

        NSLayoutConstraint.activate([
            searchContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 10),
            self.view.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: 10),
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
                cell.setup(with: filterTag.tag.name, color: color, bolded: !filterTag.tag.color.isEmpty, isActive: filterTag.isActive)
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
        self.searchBarTopConstraint.constant = -scrollView.contentOffset.y + TagFilterViewController.searchBarTopOffset
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
        self.searchBarTopConstraint.constant = TagFilterViewController.searchBarTopOffset

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
        self.viewModel.process(action: .loadWithCollection(collectionId: collectionId, libraryId: libraryId, clearSelection: isInitial))
    }

    func itemsDidChange(results: Results<RItem>, libraryId: LibraryIdentifier, isInitial: Bool) {
        var keys: Set<String> = []
        for item in results {
            keys.insert(item.key)
            self.keys(fromChildren: item.children, keys: &keys)
        }
        self.viewModel.process(action: .loadWithKeys(itemKeys: keys, libraryId: libraryId, clearSelection: isInitial))
    }

    private func keys(fromChildren results: LinkingObjects<RItem>, keys: inout Set<String>) {
        guard !results.isEmpty else { return }
        for item in results {
            keys.insert(item.key)
            self.keys(fromChildren: item.children, keys: &keys)
        }
    }
}
