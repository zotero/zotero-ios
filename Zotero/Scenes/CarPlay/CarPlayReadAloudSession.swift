//
//  CarPlayReadAloudSession.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import PSPDFKit
import RxSwift

/// Read aloud of a PDF without a reader. Playback is controlled through the Now Playing controls.
final class CarPlayReadAloudSession {
    private let positionStoreDebounce: RxTimeInterval = .seconds(3)

    let key: String
    let libraryId: LibraryIdentifier
    let documentTitle: String?
    let documentAuthors: String?
    let documentFile: FileData?
    private let pageCount: UInt
    private let dbStorage: DbStorage
    private let remoteVoicesController: RemoteVoicesController
    private let disposeBag: DisposeBag
    /// Page being read. Starts at the page the reader was last left on, like the reader does.
    private var currentPage: UInt
    /// Position waiting out the debounce before it's written to the database.
    private var pendingPositionStore: (position: ReadAloudResumePosition, disposeBag: DisposeBag)?
    private(set) var speechManager: SpeechManager<CarPlayReadAloudSession>!

    init(
        key: String,
        libraryId: LibraryIdentifier,
        file: FileData,
        title: String?,
        authors: String?,
        dbStorage: DbStorage,
        documentWorkerController: DocumentWorkerController,
        apiClient: ApiClient
    ) {
        self.key = key
        self.libraryId = libraryId
        self.dbStorage = dbStorage
        documentFile = file
        documentTitle = title
        documentAuthors = authors
        pageCount = Document(url: file.createUrl()).pageCount
        currentPage = 0
        remoteVoicesController = RemoteVoicesController(apiClient: apiClient)
        disposeBag = DisposeBag()

        let language = try? dbStorage.perform(request: ReadSpeechLanguageDbRequest(key: key, libraryId: libraryId), on: .main)
        speechManager = SpeechManager(
            delegate: self,
            voiceLanguage: language,
            remoteVoiceTier: Defaults.shared.remoteVoiceTier,
            remoteVoicesController: remoteVoicesController,
            documentWorkerController: documentWorkerController
        )
        speechManager.onSpeakingPositionChanged = { [weak self] position in
            self?.scheduleStore(position: position)
        }
        speechManager.state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard state.isStoppedOrOutOfCredits else { return }
                // Reading ended, so the position it stopped at is written right away.
                self?.storePendingPosition()
            })
            .disposed(by: disposeBag)
    }

    deinit {
        storePendingPosition()
    }

    /// Starts reading where reading aloud of this document last left off, otherwise at the page the reader was last left on.
    func start() {
        let documentData: ReadDocumentDataDbRequest.Response?
        do {
            documentData = try dbStorage.perform(request: ReadDocumentDataDbRequest(attachmentKey: key, libraryId: libraryId, defaultPageValue: "0"), on: .main)
        } catch let error {
            DDLogError("CarPlayReadAloudSession: can't read document data - \(error)")
            documentData = nil
        }

        if let page = documentData.flatMap({ UInt($0.page) }), page < pageCount {
            currentPage = page
        }

        if let position = documentData?.lastReadAloudPosition {
            speechManager.start(.resume(position))
        } else {
            speechManager.start(.currentPage)
        }
    }

    func stop() {
        speechManager.stop()
        storePendingPosition()
    }

    // MARK: - Position storing

    private func scheduleStore(position: ReadAloudResumePosition) {
        let disposeBag = DisposeBag()
        pendingPositionStore = (position, disposeBag)

        Single<Int>.timer(positionStoreDebounce, scheduler: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.storePendingPosition()
            })
            .disposed(by: disposeBag)
    }

    private func storePendingPosition() {
        guard let (position, _) = pendingPositionStore else { return }
        pendingPositionStore = nil
        do {
            try dbStorage.perform(request: StoreLastReadAloudPositionDbRequest(key: key, libraryId: libraryId, position: position), on: .main)
        } catch let error {
            DDLogError("CarPlayReadAloudSession: can't store read aloud position - \(error)")
        }
    }
}

extension CarPlayReadAloudSession: SpeechManagerDelegate {
    var documentPassword: String? {
        return nil
    }

    func getCurrentPageIndex() -> UInt {
        return currentPage
    }

    func getNextPageIndex(from currentPageIndex: UInt) -> UInt? {
        guard currentPageIndex + 1 < pageCount else { return nil }
        return currentPageIndex + 1
    }

    func getPreviousPageIndex(from currentPageIndex: UInt) -> UInt? {
        guard currentPageIndex > 0 else { return nil }
        return currentPageIndex - 1
    }

    func pageIndex(forStructuredDocumentTextPage page: Int) -> UInt? {
        guard page >= 0, page < Int(pageCount) else { return nil }
        return UInt(page)
    }

    func structuredDocumentTextPage(forPageIndex pageIndex: UInt) -> Int? {
        guard pageIndex < pageCount else { return nil }
        return Int(pageIndex)
    }

    func moved(to pageIndex: UInt, from previousPageIndex: UInt) {
        currentPage = pageIndex
    }

    func focusPage(_ pageIndex: UInt) {
        currentPage = pageIndex
    }

    // There is no document to highlight in and highlight sessions can't be started without a reader.

    func readAloudHighlightChanged(position: ReadAloudPosition, pageIndex: UInt) {}

    func annotationPreviewChanged(position: ReadAloudPosition, pageIndex: UInt, tool: AnnotationTool, color: String) {}

    func createAnnotation(ofType tool: AnnotationTool, color: String, position: ReadAloudPosition, onPage pageIndex: UInt) {}

    func clearAnnotationPreview() {}
}
