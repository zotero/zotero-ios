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
    enum Context {
        case masterBottomSheet
        case filterScreen
    }

    lazy private(set) var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        if #unavailable(iOS 26.0) {
            searchBar.backgroundColor = .systemBackground
        }
        searchBar.backgroundImage = UIImage()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.heightAnchor.constraint(equalToConstant: searchBarHeight).isActive = true
        searchBar.placeholder = L10n.TagPicker.searchPlaceholder
        searchBar.delegate = self
        searchBar.rx.text.observe(on: MainScheduler.instance)
            .skip(1)
            .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak viewModel] text in
                viewModel?.process(action: .search(text ?? ""))
            })
            .disposed(by: disposeBag)
        return searchBar
    }()
    private weak var collectionView: UICollectionView!
    private weak var optionsButton: UIButton?
    private weak var moreButton: UIBarButtonItem?
    weak var delegate: FiltersDelegate?

    private static let cellId = "TagFilterCell"
    private let searchBarHeight: CGFloat
    private static let searchBarTopOffset: CGFloat = -10
    private static let searchBarBottomOffset: CGFloat = -8
    private let viewModel: ViewModel<TagFilterActionHandler>
    private let context: Context
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<TagFilterActionHandler>, context: Context) {
        self.viewModel = viewModel
        self.context = context
        disposeBag = DisposeBag()
        if #available(iOS 26.0, *) {
            searchBarHeight = 48
        } else {
            searchBarHeight = 56
        }
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
            var searchContainer: UIStackView?
            var bottomToolbar: UIToolbar?
            if #unavailable(iOS 26.0) {
                var optionsConfiguration = UIButton.Configuration.plain()
                optionsConfiguration.image = UIImage(systemName: "ellipsis")
                optionsConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
                optionsConfiguration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
                let optionsButton = UIButton()
                optionsButton.configuration = optionsConfiguration
                optionsButton.showsMenuAsPrimaryAction = true
                optionsButton.menu = createOptionsMenu(with: viewModel.state)
                self.optionsButton = optionsButton

                let container = UIStackView(arrangedSubviews: [searchBar, optionsButton])
                container.translatesAutoresizingMaskIntoConstraints = false
                container.axis = .horizontal
                view.addSubview(container)
                searchContainer = container
            } else if context == .masterBottomSheet {
                let toolbar = UIToolbar()
                toolbar.translatesAutoresizingMaskIntoConstraints = false
                toolbar.items = createBottomToolbarItems()
                view.addSubview(toolbar)
                bottomToolbar = toolbar
            }

            let layout = TagsFlowLayout(
                maxWidth: view.frame.width,
                minimumInteritemSpacing: 8,
                minimumLineSpacing: 8,
                sectionInset: UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
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
            if let searchContainer {
                view.insertSubview(collectionView, belowSubview: searchContainer)
            } else {
                view.addSubview(collectionView)
            }

            collectionView.dropDelegate = self
            if context == .filterScreen {
                collectionView.keyboardDismissMode = .onDrag
            }

            var constraints = [
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor)
            ]
            if let searchContainer {
                constraints.append(contentsOf: [
                    searchContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.searchBarTopOffset),
                    searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
                    view.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: 10),
                    collectionView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: Self.searchBarBottomOffset)
                ])
            } else {
                constraints.append(collectionView.topAnchor.constraint(equalTo: view.topAnchor))
            }
            if let bottomToolbar {
                constraints.append(contentsOf: [
                    collectionView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
                    bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor),
                    bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
                ])
            } else {
                constraints.append(collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor))
            }
            NSLayoutConstraint.activate(constraints)
        }
    }

    @available(iOS 26.0, *)
    func setupBottomToolbar(in viewController: UIViewController) {
        guard context == .filterScreen, moreButton == nil else { return }
        viewController.toolbarItems = createBottomToolbarItems()
    }

    @available(iOS 26.0, *)
    private func createBottomToolbarItems() -> [UIBarButtonItem] {
        let moreButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis"))
        moreButton.menu = createOptionsMenu(with: viewModel.state)
        self.moreButton = moreButton
        return [
            UIBarButtonItem(customView: searchBar),
            .flexibleSpace(),
            moreButton
        ]
    }

    private func update(to state: TagFilterState) {
        if state.changes.contains(.selection) {
            updateOptionsMenu(with: state)
            delegate?.tagSelectionDidChange(selected: state.selectedTags)
        }

        if state.changes.contains(.tags) {
            updateOptionsMenu(with: state)
            collectionView.reloadData()
            fixSelectionIfNeeded(selected: state.selectedTags)
        }

        if state.changes.contains(.options) {
            updateOptionsMenu(with: state)
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

    private func updateOptionsMenu(with state: TagFilterState) {
        let menu = createOptionsMenu(with: state)
        optionsButton?.menu = menu
        moreButton?.menu = menu
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
        let displayAll = UIAction(title: L10n.TagPicker.showAll, state: (state.displayAll ? .on : .off)) { [weak viewModel] _ in
            guard let viewModel else { return }
            viewModel.process(action: .setDisplayAll(!viewModel.state.displayAll))
        }
        var options: [UIAction] = [showAutomatic, displayAll]
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
        guard let library = delegate?.currentLibrary,
              library.metadataEditable,
              let localContext = session.localDragSession?.localContext as? DragDropController.LocalContext,
              localContext.libraryIdentifier == library.identifier,
              !localContext.keys.isEmpty,
              let destinationIndexPath,
              destinationIndexPath.row < viewModel.state.tags.count
        else { return UICollectionViewDropProposal(operation: .forbidden) }
        return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath, let tag = tag(for: indexPath) else { return }
        switch coordinator.proposal.operation {
        case .copy:
            guard let localContext = coordinator.session.localDragSession?.localContext as? DragDropController.LocalContext, !localContext.keys.isEmpty else { break }
            viewModel.process(action: .assignTag(name: tag.tag.name, toItemKeys: localContext.keys, libraryId: localContext.libraryIdentifier))

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
        guard let tag = tag(for: indexPath) else { return }
        viewModel.process(action: .deselect(tag.tag.name))
        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
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
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
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
