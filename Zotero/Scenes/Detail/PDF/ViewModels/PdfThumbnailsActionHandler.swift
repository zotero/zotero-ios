//
//  PdfThumbnailsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import RxSwift

struct PdfThumbnailsActionHandler: ViewModelActionHandler {
    typealias Action = PdfThumbnailsAction
    typealias State = PdfThumbnailsState

    private unowned let thumbnailController: PdfThumbnailController
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    init(thumbnailController: PdfThumbnailController) {
        self.thumbnailController = thumbnailController
        self.queue = DispatchQueue(label: "org.zotero.PdfThumbnailsActionHandler.background", qos: .userInitiated, attributes: .concurrent)
        self.disposeBag = DisposeBag()
    }

    func process(action: PdfThumbnailsAction, in viewModel: ViewModel<PdfThumbnailsActionHandler>) {
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
        }
    }

    private func set(selectedPage: Int, type: PdfThumbnailsState.SelectionType, viewModel: ViewModel<PdfThumbnailsActionHandler>) {
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

    private func loadPages(viewModel: ViewModel<PdfThumbnailsActionHandler>) {
        let labels = (0..<viewModel.state.document.pageCount).map({ viewModel.state.document.pageLabelForPage(at: $0, substituteWithPlainLabel: true) ?? "" })
        update(viewModel: viewModel) { state in
            state.pages = labels
            state.changes = .pages
        }
    }

    private func prefetch(pageIndices: [UInt], in viewModel: ViewModel<PdfThumbnailsActionHandler>) {
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

    private func load(pageIndex: UInt, in viewModel: ViewModel<PdfThumbnailsActionHandler>) {
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

        func cache(image: UIImage, viewModel: ViewModel<PdfThumbnailsActionHandler>) {
            viewModel.state.cache.setObject(image, forKey: NSNumber(value: pageIndex))
            update(viewModel: viewModel) { state in
                state.loadedThumbnail = Int(pageIndex)
            }
        }
    }

    private func setUserInteraface(isDark: Bool, in viewModel: ViewModel<PdfThumbnailsActionHandler>) {
        viewModel.state.cache.removeAllObjects()
        update(viewModel: viewModel) { state in
            state.isDark = isDark
            state.changes = .userInterface
        }
    }
}
