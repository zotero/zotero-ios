//
//  PDFThumbnailsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import RxSwift

struct PDFThumbnailsActionHandler: ViewModelActionHandler {
    typealias Action = PDFThumbnailsAction
    typealias State = PDFThumbnailsState

    private unowned let thumbnailController: PDFThumbnailController
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    init(thumbnailController: PDFThumbnailController) {
        self.thumbnailController = thumbnailController
        self.queue = DispatchQueue(label: "org.zotero.PDFThumbnailsActionHandler.background", qos: .userInitiated, attributes: .concurrent)
        self.disposeBag = DisposeBag()
    }

    func process(action: PDFThumbnailsAction, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        switch action {
        case .load(let pageIndex):
            load(pageIndex: pageIndex, in: viewModel)

        case .prefetch(let pageIndices):
            prefetch(pageIndices: pageIndices, in: viewModel)

        case .setUserInterface(let isDark):
            setUserInteraface(isDark: isDark, in: viewModel)

        case .loadPages:
            loadPages(viewModel: viewModel)

        case .setSelectedPage(let pageIndex, let type):
            set(selectedPage: pageIndex, type: type, viewModel: viewModel)

        case .reloadThumbnails:
            reloadThumbnails(viewModel: viewModel)
        }
    }

    private func reloadThumbnails(viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        viewModel.state.cache.removeAllObjects()
        thumbnailController.deleteAll(forKey: viewModel.state.key, libraryId: viewModel.state.libraryId)
        update(viewModel: viewModel) { state in
            state.changes = .reload
        }
    }

    private func set(selectedPage: Int, type: PDFThumbnailsState.SelectionType, viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        guard selectedPage != viewModel.state.selectedPageIndex else { return }
        update(viewModel: viewModel) { state in
            state.selectedPageIndex = selectedPage
            switch type {
            case .fromDocument:
                state.changes = .scrollToSelection

            case .fromSidebar:
                state.changes = .selection
            }
        }
    }

    private func loadPages(viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        guard viewModel.state.document.pageCount > 0 else { return }
        let labels = (0..<viewModel.state.document.pageCount).map({ PDFThumbnailsState.Page(title: viewModel.state.document.pageLabelForPage(at: $0, substituteWithPlainLabel: true) ?? "") })
        update(viewModel: viewModel) { state in
            state.pages = labels
            state.changes = .pages
        }
    }

    private func prefetch(pageIndices: [UInt], in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        let toFetch = pageIndices.compactMap { pageIndex in
            let hasImage = thumbnailController.hasThumbnail(page: pageIndex, key: viewModel.state.key, libraryId: viewModel.state.libraryId, isDark: viewModel.state.isDark)
            return hasImage ? nil : pageIndex
        }
        thumbnailController.cache(
            pages: toFetch,
            key: viewModel.state.key,
            libraryId: viewModel.state.libraryId,
            document: viewModel.state.document,
            imageSize: viewModel.state.thumbnailSize,
            isDark: viewModel.state.isDark
        )
        .subscribe()
        .disposed(by: disposeBag)
    }

    private func load(pageIndex: UInt, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        if thumbnailController.hasThumbnail(page: pageIndex, key: viewModel.state.key, libraryId: viewModel.state.libraryId, isDark: viewModel.state.isDark) {
            loadCachedThumbnailAsync()
        } else {
            loadAndCacheThumbnailAsync()
        }

        func loadCachedThumbnailAsync() {
            queue.async { [weak thumbnailController, weak viewModel] in
                guard let thumbnailController,
                      let viewModel,
                      let image = thumbnailController.thumbnail(page: pageIndex, key: viewModel.state.key, libraryId: viewModel.state.libraryId, isDark: viewModel.state.isDark)
                else { return }
                DispatchQueue.main.async { [weak viewModel] in
                    guard let viewModel else { return }
                    cache(image: image, viewModel: viewModel)
                }
            }
        }

        func loadAndCacheThumbnailAsync() {
            thumbnailController.cache(
                page: pageIndex,
                key: viewModel.state.key,
                libraryId: viewModel.state.libraryId,
                document: viewModel.state.document,
                imageSize: viewModel.state.thumbnailSize,
                isDark: viewModel.state.isDark
            )
            .observe(on: MainScheduler.instance)
            .subscribe(with: viewModel) { viewModel, image in
                cache(image: image, viewModel: viewModel)
            }
            .disposed(by: disposeBag)
        }

        func cache(image: UIImage, viewModel: ViewModel<PDFThumbnailsActionHandler>) {
            viewModel.state.cache.setObject(image, forKey: NSNumber(value: pageIndex))
            update(viewModel: viewModel) { state in
                state.loadedThumbnail = Int(pageIndex)
            }
        }
    }

    private func setUserInteraface(isDark: Bool, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        viewModel.state.cache.removeAllObjects()
        update(viewModel: viewModel) { state in
            state.isDark = isDark
            state.changes = .userInterface
        }
    }
}
