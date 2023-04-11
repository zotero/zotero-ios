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
    var currentLibraryId: LibraryIdentifier { get }

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
    weak var delegate: TagFilterDelegate?
    private var searchBarScrollEnabled: Bool
    private var didAppear: Bool

    private static let cellId = "TagFilterCell"
    private static let searchBarHeight: CGFloat = 56
    private static let searchBarTopOffset: CGFloat = -10
    private static let searchBarBottomOffset: CGFloat = -8
    private let viewModel: ViewModel<TagFilterActionHandler>
    private unowned let dragDropController: DragDropController
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<TagFilterActionHandler>, dragDropController: DragDropController) {
        self.viewModel = viewModel
        self.dragDropController = dragDropController
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

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
        // Trigger initial load on phone.
        self.delegate?.tagOptionsDidChange()
        default: break
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard UIDevice.current.userInterfaceIdiom == .pad && !self.didAppear else { return }

        let height = TagFilterViewController.searchBarHeight + TagFilterViewController.searchBarTopOffset
        self.collectionView.setContentOffset(CGPoint(x: 0, y: height), animated: false)
    }

    private func update(to state: TagFilterState) {
        if state.changes.contains(.selection) {
            self.optionsButton.menu = self.createOptionsMenu(with: state)
            self.delegate?.tagSelectionDidChange(selected: state.selectedTags)
        }

        if state.changes.contains(.tags) {
            self.collectionView.reloadData()
            self.fixSelectionIfNeeded(selected: state.selectedTags)
        }

        if state.changes.contains(.options) {
            self.optionsButton.menu = self.createOptionsMenu(with: state)
            self.delegate?.tagOptionsDidChange()
        }

        if let count = state.automaticCount {
            self.confirmDeletion(count: count)
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func fixSelectionIfNeeded(selected: Set<String>) {
        guard let selectedIndexPaths = self.collectionView.indexPathsForSelectedItems else { return }

        var currentlySelected: Set<String> = []
        for indexPath in selectedIndexPaths {
            guard let name = self.tag(for: indexPath)?.name else { continue }
            currentlySelected.insert(name)
        }

        guard selected != currentlySelected else { return }

        for indexPath in selectedIndexPaths {
            self.collectionView.deselectItem(at: indexPath, animated: false)
            (self.collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
        }

        var indexPathsToSelect: [IndexPath] = []
        if let tags = self.viewModel.state.coloredResults {
            for (idx, tag) in tags.enumerated() {
                if selected.contains(tag.name) {
                    indexPathsToSelect.append(IndexPath(row: idx, section: 0))
                }
            }
        }
        let coloredCount = self.viewModel.state.coloredResults?.count ?? 0
        if let tags = self.viewModel.state.otherResults {
            for (idx, tag) in tags.enumerated() {
                if selected.contains(tag.name) {
                    indexPathsToSelect.append(IndexPath(row: (coloredCount + idx), section: 0))
                }
            }
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

    private func confirmDeletion(count: Int) {
        let controller = UIAlertController(title: L10n.TagPicker.confirmDeletionQuestion, message: L10n.TagPicker.confirmDeletion(count), preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .destructive, handler: { [weak self] _ in
            guard let libraryId = self?.delegate?.currentLibraryId else { return }
            self?.viewModel.process(action: .deleteAutomatic(libraryId))
        }))
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        self.present(controller, animated: true)
    }

    private func createOptionsMenu(with state: TagFilterState) -> UIMenu {
        let deselectAction = UIAction(title: L10n.TagPicker.deselectAll, attributes: (state.selectedTags.isEmpty ? .disabled : []), handler: { [weak self] _ in
            self?.viewModel.process(action: .deselectAll)
        })
        let selectionTitle = state.selectedTags.count == 1 ? L10n.TagPicker.oneTagSelected : L10n.TagPicker.xTagsSelected(state.selectedTags.count)
        let selectionCount = UIAction(title: selectionTitle, attributes: .disabled, handler: { _ in })
        let deselectMenu = UIMenu(options: .displayInline, children: [selectionCount, deselectAction].orderedMenuChildrenBasedOnDevice())

        let showAutomatic = UIAction(title: L10n.TagPicker.showAuto, state: (state.showAutomatic ? .on : .off), handler: { [weak self] _ in
            guard let `self` = self else { return }
            self.viewModel.process(action: .setShowAutomatic(!self.viewModel.state.showAutomatic))
        })
        let displayAll = UIAction(title: L10n.TagPicker.showAll, attributes: .hidden, state: (state.displayAll ? .on : .off), handler: { [weak self] _ in
            guard let `self` = self else { return }
            self.viewModel.process(action: .setDisplayAll(!self.viewModel.state.displayAll))
        })
        let optionsMenu = UIMenu(options: .displayInline, children: [showAutomatic, displayAll].orderedMenuChildrenBasedOnDevice())

        let deleteAutomatic = UIAction(title: L10n.TagPicker.deleteAutomatic, attributes: .destructive, handler: { [weak self] _ in
            guard let `self` = self, let libraryId = self.delegate?.currentLibraryId else { return }
            self.viewModel.process(action: .loadAutomaticCount(libraryId))
        })
        let deleteMenu = UIMenu(options: .displayInline, children: [deleteAutomatic])

        return UIMenu(children: [deselectMenu, optionsMenu, deleteMenu].orderedMenuChildrenBasedOnDevice())
    }

    private func setupViews() {
        let searchBar = UISearchBar()
        searchBar.placeholder = L10n.TagPicker.searchPlaceholder
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
        optionsButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        optionsButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
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
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColor = .systemBackground
        collectionView.layer.masksToBounds = true
        collectionView.register(UINib(nibName: TagFilterViewController.cellId, bundle: nil), forCellWithReuseIdentifier: TagFilterViewController.cellId)
        self.collectionView = collectionView
        self.view.insertSubview(collectionView, belowSubview: searchContainer)

        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            collectionView.keyboardDismissMode = .onDrag
        case .pad:
            collectionView.dragDelegate = self
        default: break
        }

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
}

extension TagFilterViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return (self.viewModel.state.coloredResults?.count ?? 0) + (self.viewModel.state.otherResults?.count ?? 0)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TagFilterViewController.cellId, for: indexPath)
        if let cell = cell as? TagFilterCell, let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout, let tag = self.tag(for: indexPath) {
            cell.maxWidth = collectionView.frame.width - flowLayout.sectionInset.left - flowLayout.sectionInset.right -
                            collectionView.contentInset.left - collectionView.contentInset.right - 20
            let color: UIColor = tag.color.isEmpty ? .label : UIColor(hex: tag.color)
            cell.setup(with: tag.name, color: color, bolded: !tag.color.isEmpty, isActive: self.isActive(tag: tag))
        }
        return cell
    }

    private func tag(for indexPath: IndexPath) -> RTag? {
        if let colored = self.viewModel.state.coloredResults, indexPath.row < colored.count {
            return colored[indexPath.row]
        }

        if let other = self.viewModel.state.otherResults {
            let index = indexPath.row - (self.viewModel.state.coloredResults?.count ?? 0)
            if index < other.count {
                return other[index]
            }
        }

        return nil
    }

    private func isActive(tag: RTag) -> Bool {
        return self.viewModel.state.filteredResults?.filter(.name(tag.name)).first != nil
    }
}

extension TagFilterViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let tag = self.tag(for: indexPath) else { return [] }
        return [self.dragDropController.dragItem(from: tag)]
    }
}

extension TagFilterViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let tag = self.tag(for: indexPath), self.isActive(tag: tag) else { return }

        self.viewModel.process(action: .select(tag.name))

        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let tag = self.tag(for: indexPath), self.isActive(tag: tag) else { return }

        self.viewModel.process(action: .deselect(tag.name))

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

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        self.searchBarScrollEnabled = true
        return true
    }
}

extension TagFilterViewController: ItemsTagFilterDelegate {
    func clearSelection() {
        self.viewModel.process(action: .deselectAllWithoutNotifying)
    }

    func itemsDidChange(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier) {
        self.viewModel.process(action: .loadWithCollection(collectionId: collectionId, libraryId: libraryId))
    }

    func itemsDidChange(results: Results<RItem>, libraryId: LibraryIdentifier) {
        var keys: Set<String> = []
        for item in results {
            keys.insert(item.key)
            self.keys(fromChildren: item.children, keys: &keys)
        }
        self.viewModel.process(action: .loadWithKeys(itemKeys: keys, libraryId: libraryId))
    }

    private func keys(fromChildren results: LinkingObjects<RItem>, keys: inout Set<String>) {
        guard !results.isEmpty else { return }
        for item in results {
            keys.insert(item.key)
            self.keys(fromChildren: item.children, keys: &keys)
        }
    }
}
