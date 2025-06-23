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

class TagFilterViewController: UIViewController {
    private(set) weak var searchBar: UISearchBar!
    private weak var collectionView: UICollectionView!
    private weak var searchBarTopConstraint: NSLayoutConstraint!
    private weak var optionsButton: UIButton!
    weak var delegate: FiltersDelegate?
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
        searchBarScrollEnabled = true
        disposeBag = DisposeBag()
        didAppear = false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupViews()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)

        func setupViews() {
            let searchBar = UISearchBar()
            searchBar.placeholder = L10n.TagPicker.searchPlaceholder
            searchBar.backgroundColor = .systemBackground
            searchBar.backgroundImage = UIImage()
            searchBar.delegate = self
            self.searchBar = searchBar

            searchBar.rx.text.observe(on: MainScheduler.instance)
                .skip(1)
                .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak viewModel] text in
                    viewModel?.process(action: .search(text ?? ""))
                })
                .disposed(by: disposeBag)

            var optionsConfiguration = UIButton.Configuration.plain()
            optionsConfiguration.image = UIImage(systemName: "ellipsis")
            optionsConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            optionsConfiguration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
            let optionsButton = UIButton()
            optionsButton.configuration = optionsConfiguration
            optionsButton.showsMenuAsPrimaryAction = true
            optionsButton.menu = createOptionsMenu(with: viewModel.state)
            self.optionsButton = optionsButton

            let searchContainer = UIStackView(arrangedSubviews: [searchBar, optionsButton])
            searchContainer.translatesAutoresizingMaskIntoConstraints = false
            searchContainer.axis = .horizontal
            view.addSubview(searchContainer)

            let layout = TagsFlowLayout(
                maxWidth: view.frame.width,
                minimumInteritemSpacing: 8,
                minimumLineSpacing: 8,
                sectionInset: UIEdgeInsets(top: (Self.searchBarHeight + Self.searchBarTopOffset + Self.searchBarBottomOffset), left: 10, bottom: 8, right: 10)
            )
            let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: layout)
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            collectionView.delegate = self
            collectionView.dataSource = self
            collectionView.allowsMultipleSelection = true
            collectionView.backgroundColor = .systemBackground
            collectionView.layer.masksToBounds = true
            collectionView.register(UINib(nibName: Self.cellId, bundle: nil), forCellWithReuseIdentifier: Self.cellId)
            self.collectionView = collectionView
            view.insertSubview(collectionView, belowSubview: searchContainer)

            if traitCollection.horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
                collectionView.dropDelegate = self
            } else {
                collectionView.keyboardDismissMode = .onDrag
            }

            let searchBarTop = searchContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.searchBarTopOffset)

            NSLayoutConstraint.activate([
                searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
                view.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: 10),
                searchBarTop,
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor)
            ])

            searchBarTopConstraint = searchBarTop
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if traitCollection.horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone {
            // Trigger initial load on iPhone and compact iPad.
            delegate?.tagOptionsDidChange()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard traitCollection.horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad && !didAppear else { return }

        let height = Self.searchBarHeight + Self.searchBarTopOffset
        collectionView.setContentOffset(CGPoint(x: 0, y: height), animated: false)
    }

    private func update(to state: TagFilterState) {
        if state.changes.contains(.selection) {
            optionsButton.menu = createOptionsMenu(with: state)
            delegate?.tagSelectionDidChange(selected: state.selectedTags)
        }

        if state.changes.contains(.tags) {
            collectionView.reloadData()
            fixSelectionIfNeeded(selected: state.selectedTags)
        }

        if state.changes.contains(.options) {
            optionsButton.menu = createOptionsMenu(with: state)
            delegate?.tagOptionsDidChange()
        }

        if let count = state.automaticCount {
            confirmDeletion(count: count)
        }

        if let error = state.error {
            // TODO: - show error
        }

        func fixSelectionIfNeeded(selected: Set<String>) {
            guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems else { return }

            var currentlySelected: Set<String> = []
            for indexPath in selectedIndexPaths {
                guard let name = tag(for: indexPath)?.tag.name else { continue }
                currentlySelected.insert(name)
            }

            guard selected != currentlySelected else { return }

            for indexPath in selectedIndexPaths {
                collectionView.deselectItem(at: indexPath, animated: false)
                (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
            }

            for (idx, tag) in viewModel.state.tags.enumerated() {
                guard selected.contains(tag.tag.name) else { continue }

                let indexPath = IndexPath(row: idx, section: 0)
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: true)
            }
        }

        func confirmDeletion(count: Int) {
            let controller = UIAlertController(title: L10n.TagPicker.confirmDeletionQuestion, message: L10n.TagPicker.confirmDeletion(count), preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.ok, style: .destructive, handler: { [weak self] _ in
                guard let self, let libraryId = delegate?.currentLibrary.identifier else { return }
                viewModel.process(action: .deleteAutomatic(libraryId))
            }))
            controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
            present(controller, animated: true)
        }
    }

    private func snapSearchBarToAppropriatePosition(scrollView: UIScrollView) {
        let height = Self.searchBarHeight + Self.searchBarTopOffset
        guard scrollView.contentOffset.y > 0 && scrollView.contentOffset.y < height else { return }
        let offset = scrollView.contentOffset.y > (height / 2) ? CGPoint(x: 0, y: height) : CGPoint()
        collectionView.setContentOffset(offset, animated: true)
    }

    private func createOptionsMenu(with state: TagFilterState) -> UIMenu {
        let deselectAction = UIAction(title: L10n.TagPicker.deselectAll, attributes: (state.selectedTags.isEmpty ? .disabled : []), handler: { [weak viewModel] _ in
            viewModel?.process(action: .deselectAll)
        })
        let selectionTitle = L10n.TagPicker.tagsSelected(state.selectedTags.count)
        let selectionCount = UIAction(title: selectionTitle, attributes: .disabled, handler: { _ in })
        let deselectMenu = UIMenu(options: .displayInline, children: [selectionCount, deselectAction].orderedMenuChildrenBasedOnDevice())

        let showAutomatic = UIAction(title: L10n.TagPicker.showAuto, state: (state.showAutomatic ? .on : .off)) { [weak viewModel] _ in
            guard let viewModel else { return }
            viewModel.process(action: .setShowAutomatic(!viewModel.state.showAutomatic))
        }
        var options: [UIAction] = [showAutomatic]
        if traitCollection.horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
            let displayAll = UIAction(title: L10n.TagPicker.showAll, state: (state.displayAll ? .on : .off)) { [weak viewModel] _ in
                guard let viewModel else { return }
                viewModel.process(action: .setDisplayAll(!viewModel.state.displayAll))
            }
            options.append(displayAll)
        }
        let optionsMenu = UIMenu(options: .displayInline, children: options.orderedMenuChildrenBasedOnDevice())

        let deleteAutomatic = UIAction(title: L10n.TagPicker.deleteAutomatic, attributes: .destructive) { [weak self] _ in
            guard let self, let libraryId = delegate?.currentLibrary.identifier else { return }
            viewModel.process(action: .loadAutomaticCount(libraryId))
        }
        let deleteMenu = UIMenu(options: .displayInline, children: [deleteAutomatic])

        return UIMenu(children: [deselectMenu, optionsMenu, deleteMenu].orderedMenuChildrenBasedOnDevice())
    }
}

extension TagFilterViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.state.tags.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.cellId, for: indexPath)
        if let cell = cell as? TagFilterCell, let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout, let tag = tag(for: indexPath) {
            cell.maxWidth = collectionView.frame.width - flowLayout.sectionInset.left - flowLayout.sectionInset.right - collectionView.contentInset.left - collectionView.contentInset.right - 20
            let color: UIColor = tag.tag.color.isEmpty ? .label : UIColor(hex: tag.tag.color)
            cell.setup(with: tag.tag.name, color: color, bolded: !tag.tag.color.isEmpty, isActive: tag.isActive)
        }
        return cell
    }

    private func tag(for indexPath: IndexPath) -> TagFilterState.FilterTag? {
        guard indexPath.row < viewModel.state.tags.count else { return nil }
        return viewModel.state.tags[indexPath.row]
    }
}

extension TagFilterViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard delegate?.currentLibrary.metadataEditable == true,    // allow only when library is editable
              session.localDragSession != nil,                  // allow only local drag session
              let destinationIndexPath = destinationIndexPath,
              destinationIndexPath.row < self.collectionView(collectionView, numberOfItemsInSection: destinationIndexPath.section) else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }

        let dragItemsLibraryId = session.items.compactMap({ $0.localObject as? RItem }).compactMap({ $0.libraryId }).first
        if dragItemsLibraryId == delegate?.currentLibrary.identifier {
            return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
        }

        return UICollectionViewDropProposal(operation: .forbidden)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let tag = coordinator.destinationIndexPath.flatMap({ tag(for: $0) }), let libraryId = (coordinator.items.first?.dragItem.localObject as? RItem)?.libraryId else { return }
        switch coordinator.proposal.operation {
        case .copy:
            dragDropController.keys(from: coordinator.items.map({ $0.dragItem })) { [weak viewModel] keys in
                viewModel?.process(action: .assignTag(name: tag.tag.name, toItemKeys: keys, libraryId: libraryId))
            }

        default:
            break
        }
    }
}

extension TagFilterViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let tag = tag(for: indexPath), tag.isActive else { return }
        viewModel.process(action: .select(tag.tag.name))
        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let tag = tag(for: indexPath), tag.isActive else { return }
        viewModel.process(action: .deselect(tag.tag.name))
        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard searchBarScrollEnabled else { return }
        searchBarTopConstraint.constant = Self.searchBarTopOffset - scrollView.contentOffset.y
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        snapSearchBarToAppropriatePosition(scrollView: scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        snapSearchBarToAppropriatePosition(scrollView: scrollView)
    }
}

extension TagFilterViewController: DraggableViewController {
    func enablePanning() {
        collectionView.isScrollEnabled = true
    }

    func disablePanning() {
        collectionView.isScrollEnabled = false
    }
}

extension TagFilterViewController: UISearchBarDelegate {
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        searchBarScrollEnabled = false
        searchBarTopConstraint.constant = Self.searchBarTopOffset

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: { [weak self] in
            guard let self else { return }
            collectionView.setContentOffset(CGPoint(), animated: false)
            view.layoutIfNeeded()
        })

        return true
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        searchBarScrollEnabled = true
        return true
    }
}

extension TagFilterViewController: ItemsTagFilterDelegate {
    func clearSelection() {
        viewModel.process(action: .deselectAllWithoutNotifying)
    }

    func itemsDidChange(filters: [ItemsFilter], collectionId: CollectionIdentifier, libraryId: LibraryIdentifier) {
        viewModel.process(action: .load(itemFilters: filters, collectionId: collectionId, libraryId: libraryId))
    }
}
