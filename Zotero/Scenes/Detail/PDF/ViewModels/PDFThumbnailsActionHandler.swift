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

final class PDFThumbnailsActionHandler: ViewModelActionHandler {
    typealias Action = PDFThumbnailsAction
    typealias State = PDFThumbnailsState

    private unowned let thumbnailController: PDFThumbnailController
    private let disposeBag: DisposeBag
    private var prefetchDisposables: [UInt: Disposable]

    init(thumbnailController: PDFThumbnailController) {
        self.thumbnailController = thumbnailController
        self.disposeBag = DisposeBag()
        self.prefetchDisposables = [:]
    }

    func process(action: PDFThumbnailsAction, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        switch action {
        case .load(let pageIndex):
            load(pageIndex: pageIndex, in: viewModel)

        case .prefetch(let pageIndices):
            prefetch(pageIndices: pageIndices, in: viewModel)

        case .cancelPrefetch(let pageIndices):
            cancelPrefetch(pageIndices: pageIndices)

        case .setAppearance(let appearance):
            setAppearance(appearance: appearance, in: viewModel)

        case .loadPages:
            loadPages(viewModel: viewModel)

        case .setSelectedPage(let pageIndex, let type):
            set(selectedPage: pageIndex, type: type, viewModel: viewModel)

        case .reloadThumbnails(let pageIndices):
            reloadThumbnails(pageIndices: pageIndices, viewModel: viewModel)
        }
    }

    private func reloadThumbnails(pageIndices: Set<Int>, viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        guard !viewModel.state.pages.isEmpty, !pageIndices.isEmpty else { return }
        cancelPrefetch(pageIndices: pageIndices.compactMap({ UInt(exactly: $0) }))
        pageIndices.forEach({ viewModel.state.cache.removeObject(forKey: NSNumber(value: $0)) })
        update(viewModel: viewModel) { state in
            state.reloadedPageIndices = pageIndices
            state.changes = .reload
        }
    }

    private func set(selectedPage: Int, type: PDFThumbnailsState.SelectionType, viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        guard selectedPage != viewModel.state.selectedPageIndex && selectedPage < viewModel.state.pages.count else { return }
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
            if state.selectedPageIndex >= state.pages.count {
                state.selectedPageIndex = state.pages.count - 1
            }
            state.changes = .pages
        }
    }

    private func cache(image: UIImage, pageIndex: UInt, viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        let cost = image.cgImage.map({ $0.bytesPerRow * $0.height }) ?? 0
        viewModel.state.cache.setObject(image, forKey: NSNumber(value: pageIndex), cost: cost)
    }

    private func prefetch(pageIndices: [UInt], in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        for pageIndex in Set(pageIndices) {
            guard prefetchDisposables[pageIndex] == nil else { continue }

            let disposable = thumbnailController.thumbnail(
                page: pageIndex,
                key: viewModel.state.key,
                libraryId: viewModel.state.libraryId,
                document: viewModel.state.document,
                imageSize: viewModel.state.thumbnailSize,
                appearance: viewModel.state.appearance,
                priority: .prefetch
            )
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self, weak viewModel] image in
                guard let self, let viewModel else { return }
                cache(image: image, pageIndex: pageIndex, viewModel: viewModel)
            }, onDisposed: { [weak self] in
                self?.prefetchDisposables[pageIndex] = nil
            })
            prefetchDisposables[pageIndex] = disposable
            disposable.disposed(by: disposeBag)
        }
    }

    private func cancelPrefetch(pageIndices: [UInt]) {
        for pageIndex in Set(pageIndices) {
            prefetchDisposables.removeValue(forKey: pageIndex)?.dispose()
        }
    }

    private func cancelAllPrefetches() {
        let disposables = Array(prefetchDisposables.values)
        prefetchDisposables.removeAll()
        disposables.forEach({ $0.dispose() })
    }

    private func load(pageIndex: UInt, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        thumbnailController.thumbnail(
            page: pageIndex,
            key: viewModel.state.key,
            libraryId: viewModel.state.libraryId,
            document: viewModel.state.document,
            imageSize: viewModel.state.thumbnailSize,
            appearance: viewModel.state.appearance,
            priority: .visible
        )
        .observe(on: MainScheduler.instance)
        .subscribe(onSuccess: { [weak self, weak viewModel] image in
            guard let self, let viewModel else { return }
            cache(image: image, pageIndex: pageIndex, viewModel: viewModel)
            update(viewModel: viewModel) { state in
                state.loadedThumbnail = Int(pageIndex)
            }
        })
        .disposed(by: disposeBag)
    }

    private func setAppearance(appearance: Appearance, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        cancelAllPrefetches()
        viewModel.state.cache.removeAllObjects()
        update(viewModel: viewModel) { state in
            state.appearance = appearance
            state.changes = .appearance
        }
    }
}
