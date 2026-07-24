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
    private let disposeBag: DisposeBag

    init(thumbnailController: PDFThumbnailController) {
        self.thumbnailController = thumbnailController
        self.disposeBag = DisposeBag()
    }

    func process(action: PDFThumbnailsAction, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        switch action {
        case .load(let pageIndex):
            load(pageIndex: pageIndex, in: viewModel)

        case .prefetch(let pageIndices):
            prefetch(pageIndices: pageIndices, in: viewModel)

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

    private func prefetch(pageIndices: [UInt], in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        thumbnailController.cache(
            pages: pageIndices,
            key: viewModel.state.key,
            libraryId: viewModel.state.libraryId,
            document: viewModel.state.document,
            imageSize: viewModel.state.thumbnailSize,
            appearance: viewModel.state.appearance
        )
        .subscribe()
        .disposed(by: disposeBag)
    }

    private func load(pageIndex: UInt, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        thumbnailController.thumbnail(
            page: pageIndex,
            key: viewModel.state.key,
            libraryId: viewModel.state.libraryId,
            document: viewModel.state.document,
            imageSize: viewModel.state.thumbnailSize,
            appearance: viewModel.state.appearance
        )
        .observe(on: MainScheduler.instance)
        .subscribe(with: viewModel) { viewModel, image in
            cache(image: image, viewModel: viewModel)
        }
        .disposed(by: disposeBag)

        func cache(image: UIImage, viewModel: ViewModel<PDFThumbnailsActionHandler>) {
            viewModel.state.cache.setObject(image, forKey: NSNumber(value: pageIndex))
            update(viewModel: viewModel) { state in
                state.loadedThumbnail = Int(pageIndex)
            }
        }
    }

    private func setAppearance(appearance: Appearance, in viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        viewModel.state.cache.removeAllObjects()
        update(viewModel: viewModel) { state in
            state.appearance = appearance
            state.changes = .appearance
        }
    }
}
