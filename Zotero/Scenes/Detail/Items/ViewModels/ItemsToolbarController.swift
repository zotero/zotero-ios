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

protocol ItemsToolbarControllerDelegate: AnyObject {
    func process(action: ItemAction.Kind, button: UIBarButtonItem)
}

final class ItemsToolbarController {
    private static let barButtonItemEmptyTag = 1
    private static let barButtonItemSingleTag = 2
    private static let barButtonItemFilterTag = 3
    private static let barButtonItemTitleTag = 4
    private static let finishVisibilityTime: RxTimeInterval = .seconds(2)

    private unowned let viewController: UIViewController
    private let editingActions: [ItemAction]
    private let disposeBag: DisposeBag

    private weak var delegate: ItemsToolbarControllerDelegate?

    init(viewController: UIViewController, initialState: ItemsState, delegate: ItemsToolbarControllerDelegate) {
        self.viewController = viewController
        self.delegate = delegate
        self.editingActions = ItemsToolbarController.editingActions(for: initialState)
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
            self.viewController.toolbarItems = self.createNormalToolbarItems(for: state.filters)
            self.updateNormalToolbarItems(for: state.filters, downloadBatchData: state.downloadBatchData, results: state.results)
        }
    }

    func reloadToolbarItems(for state: ItemsState) {
        if state.isEditing {
            self.updateEditingToolbarItems(for: state.selectedItems, results: state.results)
        } else {
            self.updateNormalToolbarItems(for: state.filters, downloadBatchData: state.downloadBatchData, results: state.results)
        }
    }

    // MARK: - Helpers

    private func updateEditingToolbarItems(for selectedItems: Set<String>, results: Results<RItem>?) {
        self.viewController.toolbarItems?.forEach({ item in
            switch item.tag {
            case ItemsToolbarController.barButtonItemEmptyTag:
                item.isEnabled = !selectedItems.isEmpty
            case ItemsToolbarController.barButtonItemSingleTag:
                item.isEnabled = selectedItems.count == 1
            default: break
            }
        })
    }

    private func updateNormalToolbarItems(for filters: [ItemsState.Filter], downloadBatchData: ItemsState.DownloadBatchData?, results: Results<RItem>?) {
        if let item = self.viewController.toolbarItems?.first(where: { $0.tag == ItemsToolbarController.barButtonItemFilterTag }) {
            let filterImageName = filters.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill"
            item.image = UIImage(systemName: filterImageName)
        }

        if let item = self.viewController.toolbarItems?.first(where: { $0.tag == ItemsToolbarController.barButtonItemTitleTag }),
           let stackView = item.customView as? UIStackView {

            if let filterLabel = stackView.subviews.first as? UILabel {
                let itemCount = results?.count ?? 0
                filterLabel.isHidden = filters.isEmpty

                if !filterLabel.isHidden {
                    filterLabel.text = itemCount == 1 ? L10n.Items.toolbarFilterSingle : L10n.Items.toolbarFilterMultiple(itemCount)
                    filterLabel.sizeToFit()
                }
            }

            if let progressView = stackView.subviews.last as? ItemsToolbarDownloadProgressView {
                progressView.isHidden = !filters.isEmpty || downloadBatchData == nil

                if let data = downloadBatchData {
                    progressView.set(downloaded: data.downloaded, total: data.total, progress: Float(data.fraction))
                    progressView.sizeToFit()
                }
            }

            stackView.sizeToFit()
        }
    }

    private func createNormalToolbarItems(for filters: [ItemsState.Filter]) -> [UIBarButtonItem] {
        let fixedSpacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpacer.width = 16
        let flexibleSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let filterImageName = filters.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill"
        let filterButton = UIBarButtonItem(image: UIImage(systemName: filterImageName), style: .plain, target: nil, action: nil)
        filterButton.tag = ItemsToolbarController.barButtonItemFilterTag
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
        titleButton.tag = ItemsToolbarController.barButtonItemTitleTag

        return [fixedSpacer, filterButton, flexibleSpacer, titleButton, flexibleSpacer, sortButton, fixedSpacer]
    }

    private func createEditingToolbarItems(from actions: [ItemAction]) -> [UIBarButtonItem] {
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let items = actions.map({ action -> UIBarButtonItem in
            let item = UIBarButtonItem(image: action.image, style: .plain, target: nil, action: nil)
            switch action.type {
            case .addToCollection, .trash, .delete, .removeFromCollection, .restore:
                item.tag = ItemsToolbarController.barButtonItemEmptyTag
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
                guard let `self` = self else { return }
                self.delegate?.process(action: action.type, button: item)
            })
            .disposed(by: self.disposeBag)
            return item
        })
        return [spacer] + (0..<(2 * items.count)).map({ idx -> UIBarButtonItem in idx % 2 == 0 ? items[idx/2] : spacer })
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
        progressView.isHidden = true

        let stackView = UIStackView(arrangedSubviews: [filterLabel, progressView])
        stackView.axis = .horizontal
        return stackView
    }
}
