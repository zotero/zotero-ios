//
//  TrashViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class TrashViewController: BaseItemsViewController {
    private let viewModel: ViewModel<TrashActionHandler>

    private var dataSource: TrashTableViewDataSource!
    override var toolbarData: ItemsToolbarController.Data {
        return toolbarData(from: viewModel.state)
    }

    init(viewModel: ViewModel<TrashActionHandler>, controllers: Controllers, coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)) {
        self.viewModel = viewModel
        super.init(controllers: controllers, coordinatorDelegate: coordinatorDelegate)
        viewModel.process(action: .loadData)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dataSource = TrashTableViewDataSource(viewModel: viewModel)
        handler = ItemsTableViewHandler(tableView: tableView, delegate: self, dataSource: dataSource, dragDropController: controllers.dragDropController)
        toolbarController = ItemsToolbarController(viewController: self, data: toolbarData, collection: collection, library: library, delegate: self)
        setupRightBarButtonItems(expectedItems: rightBarButtonItemTypes(for: viewModel.state))
        dataSource.apply(snapshot: viewModel.state.objects)

        viewModel
            .stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: self.disposeBag)
    }

    // MARK: - Actions

    private func update(state: TrashState) {
    }

    override func search(for term: String) {
//        self.viewModel.process(action: .search(term))
    }

    override func process(action: ItemAction.Kind, for selectedKeys: Set<String>, button: UIBarButtonItem?, completionAction: ((Bool) -> Void)?) {
        switch action {
        case .createParent, .duplicate, .trash, .copyBibliography, .copyCitation, .share:
            // These actions are not available in trash collection
            break

        case .addToCollection:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showCollectionsPicker(in: library, completed: { [weak self] collections in
                self?.viewModel.process(action: .assignItemsToCollections(items: selectedKeys, collections: collections))
                completionAction?(true)
            })

        case .delete:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showDeletionQuestion(
                count: selectedKeys.count,
                confirmAction: { [weak self] in
                    self?.viewModel.process(action: .deleteItems(selectedKeys))
                },
                cancelAction: {
                    completionAction?(false)
                }
            )

        case .removeFromCollection:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showRemoveFromCollectionQuestion(
                count: viewModel.state.objects.count
            ) { [weak self] in
                self?.viewModel.process(action: .deleteItemsFromCollection(selectedKeys))
                completionAction?(true)
            }

        case .restore:
            guard !selectedKeys.isEmpty else { return }
            viewModel.process(action: .restoreItems(selectedKeys))
            completionAction?(true)

        case .filter:
            guard let button else { return }
            coordinatorDelegate?.showFilters(filters: viewModel.state.filters, filtersDelegate: self, button: button)

        case .sort:
            guard let button else { return }
//            coordinatorDelegate?.showSortActions(viewModel: viewModel, button: button)

        case .download:
//            viewModel.process(action: .download(selectedKeys))
            break

        case .removeDownload:
//            viewModel.process(action: .removeDownloads(selectedKeys))
            break
        }
    }

    override func process(barButtonItemAction: BaseItemsViewController.RightBarButtonItem, sender: UIBarButtonItem) {
        switch barButtonItemAction {
        case .add:
            break

        case .deselectAll, .selectAll:
            viewModel.process(action: .toggleSelectionState)

        case .done:
            viewModel.process(action: .stopEditing)

        case .emptyTrash:
            viewModel.process(action: .emptyTrash)

        case .select:
            viewModel.process(action: .startEditing)
        }
    }

    // MARK: - Helpers

    private func toolbarData(from state: TrashState) -> ItemsToolbarController.Data {
        return .init(
            isEditing: false,
            selectedItems: [],
            filters: [],
            downloadBatchData: nil,
            remoteDownloadBatchData: nil,
            identifierLookupBatchData: .init(saved: 0, total: 0),
            itemCount: state.objects.count
        )
    }

    private func rightBarButtonItemTypes(for state: TrashState) -> [RightBarButtonItem] {
        let selectItems = rightBarButtonSelectItemTypes(for: state)
        return selectItems + [.emptyTrash]

        func rightBarButtonSelectItemTypes(for state: TrashState) -> [RightBarButtonItem] {
            if !state.isEditing {
                return [.select]
            }
            if state.selectedItems.count == state.objects.count {
                return [.deselectAll, .done]
            }
            return [.selectAll, .done]
        }
    }

    // MARK: - Tag filter delegate

    override func tagSelectionDidChange(selected: Set<String>) {
        if selected.isEmpty {
            if let tags = viewModel.state.filters.compactMap({ $0.tags }).first {
                viewModel.process(action: .disableFilter(.tags(tags)))
            }
        } else {
            viewModel.process(action: .enableFilter(.tags(selected)))
        }
    }
}

extension TrashViewController: ItemsTableViewHandlerDelegate {
    var isInViewHierarchy: Bool {
        return view.window != nil
    }
    
    var collectionKey: String? {
        return nil
    }
    
    func process(action: ItemAction.Kind, at index: Int, completionAction: ((Bool) -> Void)?) {
        guard let object = dataSource.object(at: index) else { return }
        process(action: action, for: [object.key], button: nil, completionAction: completionAction)
    }
    
    func process(tapAction action: ItemsTableViewHandler.TapAction) {
        resetActiveSearch()

        switch action {
        case .metadata(let object):
            coordinatorDelegate?.showItemDetail(for: .preview(key: object.key), libraryId: viewModel.state.library.identifier, scrolledToKey: nil, animated: true)

        case .attachment(let attachment, let parentKey):
//            viewModel.process(action: .openAttachment(attachment: attachment, parentKey: parentKey))
            break

        case .doi(let doi):
            coordinatorDelegate?.show(doi: doi)

        case .url(let url):
            coordinatorDelegate?.show(url: url)

        case .selectItem(let object):
            guard let trashObject = object as? TrashObject else { return }
            viewModel.process(action: .selectItem(trashObject.trashKey))

        case .deselectItem(let object):
            guard let trashObject = object as? TrashObject else { return }
            viewModel.process(action: .deselectItem(trashObject.trashKey))

        case .note(let object):
            guard let item = object as? RItem, let note = Note(item: item) else { return }
            let tags = Array(item.tags.map({ Tag(tag: $0) }))
            coordinatorDelegate?.showNote(library: viewModel.state.library, kind: .edit(key: note.key), text: note.text, tags: tags, parentTitleData: nil, title: note.title, saveCallback: nil)
        }

        func resetActiveSearch() {
            guard let searchBar = navigationItem.searchController?.searchBar else { return }
            searchBar.resignFirstResponder()
        }
    }
    
    func process(dragAndDropAction action: ItemsTableViewHandler.DragAndDropAction) {
        switch action {
        case .moveItems(let keys, let toKey):
            viewModel.process(action: .moveItems(keys: keys, toItemKey: toKey))

        case .tagItem(let key, let libraryId, let tags):
            viewModel.process(action: .tagItem(itemKey: key, libraryId: libraryId, tagNames: tags))
        }
    }
}
