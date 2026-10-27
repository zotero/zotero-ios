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
import RxCocoa
import RxSwift

/// Stores the position where read aloud of a document is, debounced the same way as in the readers.
final class CarPlayReadAloudPositionStore {
    private let debounce: RxTimeInterval = .seconds(3)
    private let key: String
    private let libraryId: LibraryIdentifier
    private unowned let dbStorage: DbStorage
    /// Position waiting out the debounce before it's written to the database.
    private var pending: (position: ReadAloudResumePosition, disposeBag: DisposeBag)?

    init(key: String, libraryId: LibraryIdentifier, dbStorage: DbStorage) {
        self.key = key
        self.libraryId = libraryId
        self.dbStorage = dbStorage
    }

    deinit {
        flush()
    }

    func schedule(position: ReadAloudResumePosition) {
        let disposeBag = DisposeBag()
        pending = (position, disposeBag)

        Single<Int>.timer(debounce, scheduler: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.flush()
            })
            .disposed(by: disposeBag)
    }

    /// Writes the pending position right away.
    func flush() {
        guard let (position, _) = pending else { return }
        pending = nil
        do {
            try dbStorage.perform(request: StoreLastReadAloudPositionDbRequest(key: key, libraryId: libraryId, position: position), on: .main)
        } catch let error {
            DDLogError("CarPlayReadAloudPositionStore: can't store read aloud position - \(error)")
        }
    }
}

/// Read aloud of a PDF without a reader. Playback is controlled through the Now Playing controls.
final class CarPlayReadAloudSession {
    let key: String
    let libraryId: LibraryIdentifier
    let documentTitle: String?
    let documentAuthors: String?
    let documentFile: FileData?
    private let pageCount: UInt
    private let dbStorage: DbStorage
    let remoteVoicesController: RemoteVoicesController
    private let positionStore: CarPlayReadAloudPositionStore
    private let disposeBag: DisposeBag
    /// Page being read. Starts at the page the reader was last left on, like the reader does.
    private var currentPage: UInt
    private var speechManager: SpeechManager<CarPlayReadAloudSession>!

    var state: BehaviorRelay<SpeechState> {
        return speechManager.state
    }

    /// Progress of structured document text extraction, see `SpeechManager.extractionProgress`.
    var extractionProgress: BehaviorRelay<Double?> {
        return speechManager.extractionProgress
    }

    /// Called when reading is stopped because another session started (e.g. in the reader on the phone).
    var onPlaybackTakenOver: (() -> Void)? {
        get { speechManager.onPlaybackTakenOver }
        set { speechManager.onPlaybackTakenOver = newValue }
    }

    var voice: SpeechVoice? {
        return speechManager.voice
    }

    var language: String? {
        return speechManager.language
    }

    var detectedLanguage: String {
        return speechManager.detectedLanguage
    }

    init(
        key: String,
        libraryId: LibraryIdentifier,
        file: FileData,
        title: String?,
        authors: String?,
        dbStorage: DbStorage,
        lastReadWatcher: LastReadWatcher,
        speechPlaybackOwnership: SpeechPlaybackOwnership,
        documentWorkerController: DocumentWorkerController,
        documentPreviewController: DocumentPreviewController,
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
        positionStore = CarPlayReadAloudPositionStore(key: key, libraryId: libraryId, dbStorage: dbStorage)
        disposeBag = DisposeBag()

        // Set up the same way as in the readers: the document's stored language and the selected voice tier.
        let language = try? dbStorage.perform(request: ReadSpeechLanguageDbRequest(key: key, libraryId: libraryId), on: .main)
        speechManager = SpeechManager(
            delegate: self,
            key: key,
            libraryId: libraryId,
            voiceLanguage: language,
            remoteVoiceTier: Defaults.shared.remoteVoiceTier,
            speechPlaybackOwnership: speechPlaybackOwnership,
            remoteVoicesController: remoteVoicesController,
            documentWorkerController: documentWorkerController,
            documentPreviewController: documentPreviewController
        )
        observeReading(lastReadWatcher: lastReadWatcher)
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

    /// Starts reading from the beginning of the document, whether it's currently reading, paused or stopped.
    func startFromBeginning() {
        speechManager.start(.documentStart)
    }

    func stop() {
        speechManager.stop()
        positionStore.flush()
    }

    func pause() {
        speechManager.pause()
    }

    func resume() {
        speechManager.resume()
    }

    /// Stores the document's language and switches the voice, like `ReadAloudViewHandler` does when the voice picker closes.
    func apply(voiceChange change: ReadAloudVoiceChange) {
        do {
            try dbStorage.perform(request: SetSpeechLanguageDbRequest(key: key, libraryId: libraryId, language: change.preferredLanguage), on: .main)
        } catch let error {
            DDLogError("CarPlayReadAloudSession: can't store speech language - \(error)")
        }
        speechManager.set(voice: change.voice, preferredLanguage: change.preferredLanguage)
    }

    /// Stores the reported reading position, right away once reading ends. Records reading of the document as its last
    /// read date (which puts it in Recently Read) the same way the readers do: when reading starts, at most every few
    /// minutes while reading, and when reading ends.
    private func observeReading(lastReadWatcher: LastReadWatcher) {
        speechManager.onSpeakingPositionChanged = { [weak positionStore] position in
            positionStore?.schedule(position: position)
        }
        let key = key
        let libraryId = libraryId
        // Only reading which actually started counts, not a document which couldn't be processed or had no credits.
        var didSpeak = false
        speechManager.state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak positionStore, weak lastReadWatcher] state in
                switch state {
                case .speaking:
                    didSpeak = true
                    // Stored right away for a different document than last time, coalesced while reading the same one.
                    lastReadWatcher?.submitAfterDelay(key: key, libraryId: libraryId, date: Date())

                case .stopped, .outOfCredits:
                    positionStore?.flush()
                    guard didSpeak else { return }
                    didSpeak = false
                    lastReadWatcher?.submit(key: key, libraryId: libraryId, date: Date())

                case .paused, .initializing, .loading:
                    break
                }
            })
            .disposed(by: disposeBag)
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
