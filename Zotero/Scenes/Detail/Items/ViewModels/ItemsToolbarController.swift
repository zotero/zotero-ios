//
//  ItemsToolbarController.swift
//  Zotero
//
//  Created by Michal Rentka on 19.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift
import RxSwift

protocol ItemsToolbarControllerDelegate: UITraitEnvironment {
    func process(action: ItemAction.Kind, button: UIBarButtonItem)
    func showLookup()
    func sortTypeChanged(_ sortType: ItemsSortType)
}

final class ItemsToolbarController {
    struct Data {
        let isEditing: Bool
        let selectedItems: Set<AnyHashable>
        let filters: [ItemsFilter]
        let sortType: ItemsSortType
        let allowsManualSort: Bool
        let downloadBatchData: ItemsState.DownloadBatchData?
        let remoteDownloadBatchData: ItemsState.DownloadBatchData?
        let identifierLookupBatchData: ItemsState.IdentifierLookupBatchData
        let itemCount: Int
    }

    enum ToolbarItem: Int {
        case empty = 1
        case single
        case filter
        case title
        case sort

        var tag: Int {
            rawValue
        }
    }

    private unowned let viewController: UIViewController
    private let editingActions: [ItemAction]
    private let disposeBag: DisposeBag

    private weak var delegate: ItemsToolbarControllerDelegate?

    init(viewController: UIViewController, data: Data, collection: Collection, library: Library, delegate: ItemsToolbarControllerDelegate) {
        self.viewController = viewController
        self.delegate = delegate
        editingActions = createEditingActions(collection: collection, library: library)
        disposeBag = DisposeBag()

        createToolbarItems(data: data)

        func createEditingActions(collection: Collection, library: Library) -> [ItemAction] {
            var types: [ItemAction.Kind] = []
            if collection.identifier.isTrash && library.metadataEditable {
                types.append(contentsOf: [.restore, .delete, .download, .removeDownload])
            } else {
                if library.metadataEditable {
                    types.append(contentsOf: [.addToCollection, .trash])
                }
                switch collection.identifier {
                case .collection:
                    if library.metadataEditable {
                        types.insert(.removeFromCollection, at: 1)
                    }

                case .custom, .search:
                    break
                }
                types.append(contentsOf: [.download, .removeDownload, .share])
            }
            return types.map { .init(type: $0) }
        }
    }

    func willAppear() {
        viewController.navigationController?.setToolbarHidden(false, animated: false)
    }

    // MARK: - Actions

    func createToolbarItems(data: Data) {
        if data.isEditing {
            viewController.toolbarItems = createEditingToolbarItems(from: editingActions)
            updateEditingToolbarItems(for: data.selectedItems)
        } else {
            let filters = sizeClassSpecificFilters(from: data.filters)
            viewController.toolbarItems = createNormalToolbarItems(for: filters)
            updateNormalToolbarItems(
                for: filters,
                sortType: data.sortType,
                downloadBatchData: data.downloadBatchData,
                remoteDownloadBatchData: data.remoteDownloadBatchData,
                identifierLookupBatchData: data.identifierLookupBatchData,
                itemCount: data.itemCount
            )
        }

        func createEditingToolbarItems(from actions: [ItemAction]) -> [UIBarButtonItem] {
            let items = actions.map({ action -> UIBarButtonItem in
                let item = UIBarButtonItem(image: action.image, style: .plain, target: nil, action: nil)
                switch action.type {
                case .addToCollection, .trash, .delete, .removeFromCollection, .restore, .share, .download, .removeDownload, .removeFromRecentlyRead:
                    item.tag = ToolbarItem.empty.tag

                case .sort, .filter, .createParent, .retrieveMetadata, .copyCitation, .copyBibliography, .duplicate, .debugReader:
                    break
                }
                switch action.type {
                case .addToCollection:
                    item.accessibilityLabel = L10n.Accessibility.Items.addToCollection

                case .trash:
                    item.accessibilityLabel = L10n.Accessibility.Items.trash

                case .delete:
                    item.accessibilityLabel = L10n.Accessibility.Items.delete

                case .removeFromCollection:
                    item.accessibilityLabel = L10n.Accessibility.Items.removeFromCollection

                case .restore:
                    item.accessibilityLabel = L10n.Accessibility.Items.restore

                case .share:
                    item.accessibilityLabel = L10n.Accessibility.Items.share

                case .download:
                    item.accessibilityLabel = L10n.Accessibility.Items.downloadAttachments

                case .removeDownload:
                    item.accessibilityLabel = L10n.Accessibility.Items.removeDownloads

                case .removeFromRecentlyRead:
                    item.accessibilityLabel = L10n.Accessibility.Items.removeFromRecentlyRead

                case .sort, .filter, .createParent, .retrieveMetadata, .copyCitation, .copyBibliography, .duplicate, .debugReader:
                    break
                }
                item.rx.tap.subscribe(onNext: { [weak self] _ in
                    self?.delegate?.process(action: action.type, button: item)
                })
                .disposed(by: disposeBag)
                return item
            })
            let innerFlexibleSpace = UIBarButtonItem.flexibleSpace()
            if #available(iOS 26.0, *) {
                innerFlexibleSpace.hidesSharedBackground = false
            }
            return [.flexibleSpace()] + items.enumerated().flatMap({ index, item in
                [item, index < items.count - 1 ? innerFlexibleSpace : .flexibleSpace()]
            })
        }

        func createNormalToolbarItems(for filters: [ItemsFilter]) -> [UIBarButtonItem] {
            let fixedSpacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
            fixedSpacer.width = 16
            let flexibleSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

            let filterImageName = filters.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill"
            let filterButton = UIBarButtonItem(image: UIImage(systemName: filterImageName), style: .plain, target: nil, action: nil)
            filterButton.tag = ToolbarItem.filter.tag
            filterButton.accessibilityLabel = L10n.Accessibility.Items.filterItems
            filterButton.rx.tap.subscribe(onNext: { [weak self] _ in
                self?.delegate?.process(action: .filter, button: filterButton)
            })
            .disposed(by: disposeBag)

            let titleButton = UIBarButtonItem(customView: createTitleView())
            titleButton.tag = ToolbarItem.title.tag

            var items: [UIBarButtonItem] = [fixedSpacer, filterButton, flexibleSpacer, titleButton]

            if data.allowsManualSort {
                let action = ItemAction(type: .sort)
                let sortButton = UIBarButtonItem(image: action.image, menu: createSortMenu(for: data.sortType))
                sortButton.tag = ToolbarItem.sort.tag
                sortButton.accessibilityLabel = L10n.Accessibility.Items.sortItems
                items.append(contentsOf: [flexibleSpacer, sortButton, fixedSpacer])
            } else {
                items.append(contentsOf: [flexibleSpacer, fixedSpacer])
            }

            return items

            func createTitleView() -> UIStackView {
                // Filter title label
                let filterLabel = UILabel()
                filterLabel.adjustsFontForContentSizeCategory = true
                filterLabel.textColor = .label
                filterLabel.font = .preferredFont(forTextStyle: .footnote)
                filterLabel.textAlignment = .center
                filterLabel.isHidden = true

                // Batch download view
                let progressView = ItemsToolbarDownloadProgressView()
                let tap = UITapGestureRecognizer()
                tap.rx
                   .event
                   .observe(on: MainScheduler.instance)
                   .subscribe(onNext: { [weak self] _ in
                       self?.delegate?.showLookup()
                   })
                   .disposed(by: self.disposeBag)
                progressView.addGestureRecognizer(tap)
                progressView.isHidden = true

                let stackView = UIStackView(arrangedSubviews: [filterLabel, progressView])
                stackView.axis = .horizontal
                return stackView
            }
        }
    }

    func reloadToolbarItems(for data: Data) {
        if data.isEditing {
            updateEditingToolbarItems(for: data.selectedItems)
        } else {
            updateNormalToolbarItems(
                for: sizeClassSpecificFilters(from: data.filters),
                sortType: data.sortType,
                downloadBatchData: data.downloadBatchData,
                remoteDownloadBatchData: data.remoteDownloadBatchData,
                identifierLookupBatchData: data.identifierLookupBatchData,
                itemCount: data.itemCount
            )
        }
    }

    private func sizeClassSpecificFilters(from filters: [ItemsFilter]) -> [ItemsFilter] {
        // There is different functionality based on horizontal size class. iPhone and compact iPad show tag filters in filter popup in items screen while iPad shows tag filters in master controller.
        // So filter icon and description should always show up on iPhone and compact iPad, while it should not show up on regular iPad for tag filters.
        // Therefore we ignore `.tag` filter on iPhone and compact iPad, and keep it on regular iPad.
        if delegate?.traitCollection.horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone {
            return filters
        }
        return filters.filter({
            switch $0 {
            case .tags:
                return false
                
            case .downloadedFiles:
                return true
            }
        })
    }

    private func createSortMenu(for sortType: ItemsSortType) -> UIMenu {
        let ascendingAction = UIAction(title: L10n.Items.ascending, state: sortType.ascending ? .on : .off) { [weak self] _ in
            var newSortType = sortType
            newSortType.ascending = true
            self?.delegate?.sortTypeChanged(newSortType)
        }
        let descendingAction = UIAction(title: L10n.Items.descending, state: sortType.ascending ? .off : .on) { [weak self] _ in
            var newSortType = sortType
            newSortType.ascending = false
            self?.delegate?.sortTypeChanged(newSortType)
        }
        let orderMenu = UIMenu(title: L10n.Items.sortOrder, options: .displayInline, children: [ascendingAction, descendingAction])

        let fieldActions = ItemsSortType.Field.allCases.map { field in
            UIAction(title: field.title, state: sortType.field == field ? .on : .off) { [weak self] _ in
                let newSortType = ItemsSortType(field: field, ascending: field.defaultOrderAscending)
                self?.delegate?.sortTypeChanged(newSortType)
            }
        }
        let fieldsMenu = UIMenu(title: L10n.Items.sortBy, options: .displayInline, children: fieldActions)

        return UIMenu(children: [orderMenu, fieldsMenu])
    }

    // MARK: - Helpers

    private func updateEditingToolbarItems(for selectedItems: Set<AnyHashable>) {
        viewController.toolbarItems?.forEach({ item in
            switch ToolbarItem(rawValue: item.tag) {
            case .empty:
                item.isEnabled = !selectedItems.isEmpty

            case .single:
                item.isEnabled = selectedItems.count == 1
                
            default:
                break
            }
        })
    }

    private func updateNormalToolbarItems(
        for filters: [ItemsFilter],
        sortType: ItemsSortType,
        downloadBatchData: ItemsState.DownloadBatchData?,
        remoteDownloadBatchData: ItemsState.DownloadBatchData?,
        identifierLookupBatchData: ItemsState.IdentifierLookupBatchData,
        itemCount: Int
    ) {
        if let item = viewController.toolbarItems?.first(where: { $0.tag == ToolbarItem.sort.tag }) {
            item.menu = createSortMenu(for: sortType)
        }

        if let item = viewController.toolbarItems?.first(where: { $0.tag == ToolbarItem.filter.tag }) {
            let filterImageName = filters.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill"
            item.image = UIImage(systemName: filterImageName)
        }

        if let item = viewController.toolbarItems?.first(where: { $0.tag == ToolbarItem.title.tag }),
           let stackView = item.customView as? UIStackView {
            if let filterLabel = stackView.subviews.first as? UILabel {
                filterLabel.isHidden = filters.isEmpty

                if !filterLabel.isHidden {
                    filterLabel.text = L10n.Items.toolbarFilter(itemCount)
                    filterLabel.sizeToFit()
                }
            }

            if let progressView = stackView.subviews.last as? ItemsToolbarDownloadProgressView {
                var isUserInteractionEnabled = false
                let attributedText = NSMutableAttributedString()
                var progress: Float?
                let remoteDownloading = remoteDownloadBatchData != nil
                let defaultAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.label, .font: UIFont.preferredFont(forTextStyle: .footnote)]
                if identifierLookupBatchData != .zero, !identifierLookupBatchData.isFinished || remoteDownloading {
                    // Show "Saved x / y" only if lookup hasn't finished, or there are also ongoing remote downloads
                    isUserInteractionEnabled = true
                    let identifierLookupText = L10n.Items.toolbarSaved(identifierLookupBatchData.saved, identifierLookupBatchData.total)
                    let identifierLookupAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: Asset.Colors.zoteroBlueWithDarkMode.color, .font: UIFont.preferredFont(forTextStyle: .footnote)]
                    attributedText.append(.init(string: identifierLookupText, attributes: identifierLookupAttributes))
                }
                if let combinedDownloadBatchData = ItemsState.DownloadBatchData.combineDownloadBatchData([downloadBatchData, remoteDownloadBatchData]) {
                    if attributedText.length > 0 {
                        attributedText.append(.init(string: " / ", attributes: defaultAttributes))
                    }
                    let downloadText = L10n.Items.toolbarDownloaded(combinedDownloadBatchData.downloaded, combinedDownloadBatchData.total)
                    attributedText.append(.init(string: downloadText, attributes: defaultAttributes))
                    progress = Float(combinedDownloadBatchData.fraction)
                }
                progressView.isUserInteractionEnabled = isUserInteractionEnabled

                if !filters.isEmpty || (attributedText.length == 0) {
                    progressView.isHidden = true
                } else {
                    progressView.set(attributedText: attributedText, progress: progress)
                    progressView.isHidden = false
                    progressView.sizeToFit()
                }
            }

            stackView.sizeToFit()
        }
    }
}
