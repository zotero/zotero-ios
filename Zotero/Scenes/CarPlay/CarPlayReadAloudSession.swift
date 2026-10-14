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

/// Read aloud of a document without a reader. Playback is controlled through the Now Playing controls.
protocol CarPlayReadAloudSession: AnyObject {
    var documentTitle: String? { get }
    var state: BehaviorRelay<SpeechState> { get }
    /// Progress of structured document text extraction, see `SpeechManager.extractionProgress`.
    var extractionProgress: BehaviorRelay<Double?> { get }
    var voice: SpeechVoice? { get }
    var language: String? { get }
    var detectedLanguage: String { get }
    var remoteVoicesController: RemoteVoicesController { get }

    func start()
    func stop()
    func pause()
    func resume()
    /// Applies the voice and language selected in voice settings, the same way the readers do.
    func apply(voiceChange: ReadAloudVoiceChange)
}

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

final class CarPlayPdfReadAloudSession {
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
    private var speechManager: SpeechManager<CarPlayPdfReadAloudSession>!

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
        positionStore = CarPlayReadAloudPositionStore(key: key, libraryId: libraryId, dbStorage: dbStorage)
        disposeBag = DisposeBag()

        speechManager = SpeechManager<CarPlayPdfReadAloudSession>.carPlay(delegate: self, key: key, libraryId: libraryId, dbStorage: dbStorage, remoteVoicesController: remoteVoicesController, documentWorkerController: documentWorkerController)
        speechManager.observePosition(storingIn: positionStore, disposeBag: disposeBag)
    }
}

extension CarPlayPdfReadAloudSession: CarPlayReadAloudSession {
    var state: BehaviorRelay<SpeechState> {
        return speechManager.state
    }

    var extractionProgress: BehaviorRelay<Double?> {
        return speechManager.extractionProgress
    }

    /// Starts reading where reading aloud of this document last left off, otherwise at the page the reader was last left on.
    func start() {
        let documentData = CarPlayReadAloudSessionHelper.documentData(key: key, libraryId: libraryId, defaultPageValue: "0", dbStorage: dbStorage)
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
        positionStore.flush()
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

    func pause() {
        speechManager.pause()
    }

    func resume() {
        speechManager.resume()
    }

    func apply(voiceChange: ReadAloudVoiceChange) {
        speechManager.apply(voiceChange: voiceChange, key: key, libraryId: libraryId, dbStorage: dbStorage)
    }
}

extension CarPlayPdfReadAloudSession: SpeechManagerDelegate {
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

enum CarPlayReadAloudSessionHelper {
    static func documentData(key: String, libraryId: LibraryIdentifier, defaultPageValue: String, dbStorage: DbStorage) -> ReadDocumentDataDbRequest.Response? {
        do {
            return try dbStorage.perform(request: ReadDocumentDataDbRequest(attachmentKey: key, libraryId: libraryId, defaultPageValue: defaultPageValue), on: .main)
        } catch let error {
            DDLogError("CarPlayReadAloudSession: can't read document data - \(error)")
            return nil
        }
    }
}

extension SpeechManager {
    /// Speech manager set up the same way as in the readers: the document's stored language and the selected voice tier.
    static func carPlay(
        delegate: Delegate,
        key: String,
        libraryId: LibraryIdentifier,
        dbStorage: DbStorage,
        remoteVoicesController: RemoteVoicesController,
        documentWorkerController: DocumentWorkerController
    ) -> SpeechManager<Delegate> {
        let language = try? dbStorage.perform(request: ReadSpeechLanguageDbRequest(key: key, libraryId: libraryId), on: .main)
        return SpeechManager(
            delegate: delegate,
            voiceLanguage: language,
            remoteVoiceTier: Defaults.shared.remoteVoiceTier,
            remoteVoicesController: remoteVoicesController,
            documentWorkerController: documentWorkerController
        )
    }

    /// Stores the document's language and switches the voice, like `ReadAloudViewHandler` does when the voice picker closes.
    func apply(voiceChange change: ReadAloudVoiceChange, key: String, libraryId: LibraryIdentifier, dbStorage: DbStorage) {
        do {
            try dbStorage.perform(request: SetSpeechLanguageDbRequest(key: key, libraryId: libraryId, language: change.preferredLanguage), on: .main)
        } catch let error {
            DDLogError("SpeechManager: can't store speech language - \(error)")
        }
        set(voice: change.voice, preferredLanguage: change.preferredLanguage)
    }

    /// Stores the reported reading position, right away once reading ends.
    func observePosition(storingIn positionStore: CarPlayReadAloudPositionStore, disposeBag: DisposeBag) {
        onSpeakingPositionChanged = { [weak positionStore] position in
            positionStore?.schedule(position: position)
        }
        state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak positionStore] state in
                guard state.isStoppedOrOutOfCredits else { return }
                positionStore?.flush()
            })
            .disposed(by: disposeBag)
    }
}
