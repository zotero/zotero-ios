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
        case .addToCollection:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showCollectionsPicker(in: library, completed: { [weak self] collections in
//                self?.viewModel.process(action: .assignItemsToCollections(items: selectedKeys, collections: collections))
                completionAction?(true)
            })

        case .createParent:
//            guard let key = selectedKeys.first, case .attachment(let attachment, _) = viewModel.state.itemAccessories[key] else { return }
//            let collectionKey = collection.identifier.key
//            coordinatorDelegate?.showItemDetail(
//                for: .creation(type: ItemTypes.document, child: attachment, collectionKey: collectionKey),
//                libraryId: library.identifier,
//                scrolledToKey: nil,
//                animated: true
//            )
            break

        case .delete:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showDeletionQuestion(
                count: 0,//viewModel.state.selectedItems.count,
                confirmAction: { [weak self] in
//                    self?.viewModel.process(action: .deleteItems(selectedKeys))
                },
                cancelAction: {
                    completionAction?(false)
                }
            )

        case .duplicate:
//            guard let key = selectedKeys.first else { return }
//            viewModel.process(action: .loadItemToDuplicate(key))
            break

        case .removeFromCollection:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showRemoveFromCollectionQuestion(
                count: viewModel.state.objects.count
            ) { [weak self] in
//                self?.viewModel.process(action: .deleteItemsFromCollection(selectedKeys))
                completionAction?(true)
            }

        case .restore:
            guard !selectedKeys.isEmpty else { return }
//            viewModel.process(action: .restoreItems(selectedKeys))
            completionAction?(true)

        case .trash:
            guard !selectedKeys.isEmpty else { return }
//            viewModel.process(action: .trashItems(selectedKeys))
            break

        case .filter:
            guard let button else { return }
//            coordinatorDelegate?.showFilters(viewModel: viewModel, itemsController: self, button: button)
            break

        case .sort:
            guard let button else { return }
//            coordinatorDelegate?.showSortActions(viewModel: viewModel, button: button)
            break

        case .share:
            guard !selectedKeys.isEmpty else { return }
            coordinatorDelegate?.showCiteExport(for: selectedKeys, libraryId: library.identifier)

        case .copyBibliography:
            var presenter: UIViewController = self
            if let searchController = navigationItem.searchController, searchController.isActive {
                presenter = searchController
            }
            coordinatorDelegate?.copyBibliography(using: presenter, for: selectedKeys, libraryId: library.identifier, delegate: nil)

        case .copyCitation:
            coordinatorDelegate?.showCitation(using: nil, for: selectedKeys, libraryId: library.identifier, delegate: nil)

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
//            coordinatorDelegate?.showAddActions(viewModel: viewModel, button: sender)
            break

        case .deselectAll, .selectAll:
//            viewModel.process(action: .toggleSelectionState)
            break

        case .done:
//            viewModel.process(action: .stopEditing)
            break

        case .emptyTrash:
            break

        case .select:
//            viewModel.process(action: .startEditing)
            break
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
            return [.select]
//            if !state.isEditing {
//                return [.select]
//            }
//            if state.selectedItems.count == (state.results?.count ?? 0) {
//                return [.deselectAll, .done]
//            }
//            return [.selectAll, .done]
        }
    }

    // MARK: - Tag filter delegate

    override func tagSelectionDidChange(selected: Set<String>) {
//        if selected.isEmpty {
//            if let tags = viewModel.state.tagsFilter {
//                viewModel.process(action: .disableFilter(.tags(tags)))
//            }
//        } else {
//            viewModel.process(action: .enableFilter(.tags(selected)))
//        }
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
    }
    
    func process(tapAction action: ItemsTableViewHandler.TapAction) {
    }
    
    func process(dragAndDropAction action: ItemsTableViewHandler.DragAndDropAction) {
    }
}
