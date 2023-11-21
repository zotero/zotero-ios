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
}

final class ItemsToolbarController {
    enum ToolbarItem: Int {
        case empty = 1
        case single
        case filter
        case title
        
        var tag: Int {
            rawValue
        }
    }

    private unowned let viewController: UIViewController
    private let editingActions: [ItemAction]
    private let disposeBag: DisposeBag

    private weak var delegate: ItemsToolbarControllerDelegate?

    init(viewController: UIViewController, initialState: ItemsState, delegate: ItemsToolbarControllerDelegate) {
        self.viewController = viewController
        self.delegate = delegate
        self.editingActions = Self.editingActions(for: initialState)
        self.disposeBag = DisposeBag()

        self.createToolbarItems(for: initialState)
    }

    func willAppear() {
        self.viewController.navigationController?.setToolbarHidden(false, animated: false)
    }

    private static func editingActions(for state: ItemsState) -> [ItemAction] {
        if state.collection.identifier.isTrash {
            return [ItemAction(type: .restore), ItemAction(type: .delete)]
        }

        var actions = [ItemAction(type: .addToCollection), ItemAction(type: .trash)]
        switch state.collection.identifier {
        case .collection:
            actions.insert(ItemAction(type: .removeFromCollection), at: 1)
        case .custom, .search: break
        }
        actions.append(ItemAction(type: .share))
        return actions
    }

    // MARK: - Actions

    func createToolbarItems(for state: ItemsState) {
        if state.isEditing {
            self.viewController.toolbarItems = self.createEditingToolbarItems(from: self.editingActions)
            self.updateEditingToolbarItems(for: state.selectedItems, results: state.results)
        } else {
            let filters = self.sizeClassSpecificFilters(from: state.filters)
            self.viewController.toolbarItems = self.createNormalToolbarItems(for: filters)
            self.updateNormalToolbarItems(
                for: filters,
                downloadBatchData: state.downloadBatchData,
                remoteDownloadBatchData: state.remoteDownloadBatchData,
                identifierLookupBatchData: state.identifierLookupBatchData,
                results: state.results
            )
        }
    }

    func reloadToolbarItems(for state: ItemsState) {
        if state.isEditing {
            self.updateEditingToolbarItems(for: state.selectedItems, results: state.results)
        } else {
            self.updateNormalToolbarItems(
                for: self.sizeClassSpecificFilters(from: state.filters),
                downloadBatchData: state.downloadBatchData,
                remoteDownloadBatchData: state.remoteDownloadBatchData,
                identifierLookupBatchData: state.identifierLookupBatchData,
                results: state.results
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

    // MARK: - Helpers

    private func updateEditingToolbarItems(for selectedItems: Set<String>, results: Results<RItem>?) {
        self.viewController.toolbarItems?.forEach({ item in
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
        downloadBatchData: ItemsState.DownloadBatchData?,
        remoteDownloadBatchData: ItemsState.DownloadBatchData?,
        identifierLookupBatchData: ItemsState.IdentifierLookupBatchData,
        results: Results<RItem>?
    ) {
        if let item = self.viewController.toolbarItems?.first(where: { $0.tag == ToolbarItem.filter.tag }) {
            let filterImageName = filters.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill"
            item.image = UIImage(systemName: filterImageName)
        }

        if let item = self.viewController.toolbarItems?.first(where: { $0.tag == ToolbarItem.title.tag }),
           let stackView = item.customView as? UIStackView {
            if let filterLabel = stackView.subviews.first as? UILabel {
                let itemCount = results?.count ?? 0
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

    private func createNormalToolbarItems(for filters: [ItemsFilter]) -> [UIBarButtonItem] {
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
        .disposed(by: self.disposeBag)

        let action = ItemAction(type: .sort)
        let sortButton = UIBarButtonItem(image: action.image, style: .plain, target: nil, action: nil)
        sortButton.accessibilityLabel = L10n.Accessibility.Items.sortItems
        sortButton.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.delegate?.process(action: action.type, button: sortButton)
        })
        .disposed(by: self.disposeBag)

        let titleButton = UIBarButtonItem(customView: self.createTitleView())
        titleButton.tag = ToolbarItem.title.tag

        return [fixedSpacer, filterButton, flexibleSpacer, titleButton, flexibleSpacer, sortButton, fixedSpacer]
    }

    private func createEditingToolbarItems(from actions: [ItemAction]) -> [UIBarButtonItem] {
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let items = actions.map({ action -> UIBarButtonItem in
            let item = UIBarButtonItem(image: action.image, style: .plain, target: nil, action: nil)
            switch action.type {
            case .addToCollection, .trash, .delete, .removeFromCollection, .restore:
                item.tag = ToolbarItem.empty.tag
            case .sort, .filter, .createParent, .copyCitation, .copyBibliography, .share, .removeDownload, .download, .duplicate: break
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
            case .sort, .filter, .createParent, .copyCitation, .copyBibliography, .removeDownload, .download, .duplicate: break
            }
            item.rx.tap.subscribe(onNext: { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.process(action: action.type, button: item)
            })
            .disposed(by: self.disposeBag)
            return item
        })
        return [spacer] + (0..<(2 * items.count)).map({ idx -> UIBarButtonItem in idx % 2 == 0 ? items[idx / 2] : spacer })
    }

    private func createTitleView() -> UIStackView {
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
