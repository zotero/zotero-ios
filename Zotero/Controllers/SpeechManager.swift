//
//  SpeechManager.swift
//  Zotero
//
//  Created by Michal Rentka on 11.03.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation
import NaturalLanguage
import UIKit

import Alamofire
import CocoaLumberjackSwift
import RxCocoa
import RxSwift

protocol SpeechManagerDelegate: AnyObject {
    associatedtype Index: Hashable

    var documentTitle: String? { get }
    /// File of the document being read. Used by `SpeechManager` to extract structured document text for the whole document.
    var documentFile: FileData? { get }
    /// Password for the document, if it is locked/encrypted.
    var documentPassword: String? { get }
    func getCurrentPageIndex() -> Index
    func getNextPageIndex(from currentPageIndex: Index) -> Index?
    func getPreviousPageIndex(from currentPageIndex: Index) -> Index?
    /// Maps a 0-based structured-document-text page index to the delegate's page index type. Returns nil if the page
    /// is out of bounds.
    func pageIndex(forStructuredDocumentTextPage page: Int) -> Index?
    func moved(to pageIndex: Index, from previousPageIndex: Index)
    func focusPage(_ pageIndex: Index)
    /// Called when the highlighted text changes during text-to-speech playback.
    /// The highlight covers the current text unit (sentence or paragraph) being spoken, matching the voice's
    /// segmentation granularity. Local voices and remote voices with sentence granularity highlight sentences;
    /// remote voices with paragraph granularity highlight paragraphs.
    /// - Parameters:
    ///   - text: The text to highlight
    ///   - pageIndex: The page index where the text is located
    ///   - sourceLocation: UTF-16 offset of `text` in the source page text. Disambiguates when `text` appears
    ///     multiple times on `pageIndex` (e.g. duplicated math formulas).
    ///   - sourceTextLength: UTF-16 length of the source page text, used together with `sourceLocation` as a
    ///     proportional hint.
    func readAloudHighlightChanged(text: String, pageIndex: Index, sourceLocation: Int, sourceTextLength: Int)
    /// Called when the annotation preview highlight changes during a highlight session. `sourceLocation` and
    /// `sourceTextLength` carry the same disambiguation hint as `readAloudHighlightChanged`.
    func annotationPreviewChanged(text: String, pageIndex: Index, tool: AnnotationTool, color: String, sourceLocation: Int, sourceTextLength: Int)
    /// Called when the user confirms an annotation from the highlighter overlay. `sourceLocation` and
    /// `sourceTextLength` carry the same disambiguation hint as `readAloudHighlightChanged`.
    func createAnnotation(ofType tool: AnnotationTool, color: String, forText text: String, onPage pageIndex: Index, sourceLocation: Int, sourceTextLength: Int)
    /// Called when the highlight session ends, to remove the annotation preview highlight.
    func clearAnnotationPreview()
}

enum SpeechState: Equatable {
    enum OutOfCreditsReason {
        case dailyLimitExceeded
        case quotaExceeded
    }

    /// First-time initialization (fetching text, detecting voice). All controls disabled.
    case initializing
    /// Loading a new segment after navigation (forward/backward). Navigation controls remain enabled.
    case loading
    case speaking, paused, stopped
    case outOfCredits(OutOfCreditsReason)

    var isStopped: Bool {
        switch self {
        case .speaking, .initializing, .loading, .paused, .outOfCredits:
            return false

        case .stopped:
            return true
        }
    }

    var isPaused: Bool {
        switch self {
        case .speaking, .initializing, .loading, .stopped, .outOfCredits:
            return false

        case .paused:
            return true
        }
    }

    var isSpeaking: Bool {
        switch self {
        case .stopped, .initializing, .loading, .paused, .outOfCredits:
            return false

        case .speaking:
            return true
        }
    }

    var isSpeakingOrLoading: Bool {
        switch self {
        case .stopped, .paused, .outOfCredits:
            return false

        case .speaking, .initializing, .loading:
            return true
        }
    }

    var isOutOfCredits: Bool {
        switch self {
        case .speaking, .initializing, .loading, .paused, .stopped:
            return false

        case .outOfCredits:
            return true
        }
    }
}

enum SpeechVoice: Equatable {
    case local(AVSpeechSynthesisVoice)
    case remote(RemoteVoice)
}

final class SpeechManager<Delegate: SpeechManagerDelegate>: NSObject, VoiceProcessorDelegate {
    private enum Error: Swift.Error {
        case cantGetText
    }

    /// A readable paragraph, resolved to the delegate's page index type.
    struct SpeechParagraph {
        let text: String
        let page: Delegate.Index
        /// Character offset of the paragraph within its page's readable text.
        let pageOffset: Int
        /// Bounding rects (PDF space) on its page..
        let rects: [CGRect]
    }

    /// Current speech position, anchored to a paragraph.
    private struct Position {
        var paragraphIndex: Int
        /// Range of the currently spoken segment within the paragraph (word-level for local, sentence/paragraph for remote).
        var range: NSRange
        /// Range of the highlighted unit (sentence or paragraph) within the paragraph.
        var highlightRange: NSRange
        var highlightGranularity: NLTokenUnit
    }

    /// A resumable playback position, anchored to a paragraph. Reported as playback progresses and passed back to
    /// `start(resuming:)` to resume where reading left off.
    struct ResumePosition {
        let page: Delegate.Index
        let paragraphIndex: Int
        /// Character offset within the paragraph's text.
        let offset: Int
    }

    private enum NavigationDirection {
        case forward
        case backward
    }

    /// Where playback should begin.
    enum StartTarget {
        /// The first readable paragraph at or after the delegate's current page.
        case currentPage
        /// Start at a page-text offset resolved by the closure (used for a PSPDFKit text selection), then map to a paragraph.
        case pageTextOffset((String) -> Int)
        /// Resume at a previously reported paragraph anchor.
        case resume(ResumePosition)
    }

    /// Time window within which a second forward/backward call upgrades the pending sentence skip to a paragraph skip.
    private let navigationMultiTapInterval: TimeInterval = 0.3
    private let parsingQueue: DispatchQueue
    let state: BehaviorRelay<SpeechState>
    let remainingTime: BehaviorRelay<TimeInterval?>
    /// Progress (0...1) of structured document text extraction while the document is being loaded, or `nil` when the
    /// progress is not yet known (indeterminate). Reset to `nil` once extraction finishes.
    let extractionProgress: BehaviorRelay<Double?>
    private let disposeBag: DisposeBag
    private unowned let remoteVoicesController: RemoteVoicesController
    private unowned let documentWorkerController: DocumentWorkerController
    private let nowPlayingManager: NowPlayingManager

    private var processor: VoiceProcessor!
    private var position: Position? {
        didSet {
            guard let position, position.paragraphIndex < paragraphs.count else { return }
            let paragraph = paragraphs[position.paragraphIndex]
            onSpeakingPositionChanged?(ResumePosition(page: paragraph.page, paragraphIndex: position.paragraphIndex, offset: position.range.location))
        }
    }
    /// The page currently handed to the voice processor. Used to map processor-reported page-text offsets back to a paragraph.
    private var currentSpeakingPage: Delegate.Index?
    /// Readable paragraphs for the whole document, in reading order.
    private var paragraphs: [SpeechParagraph]
    /// Indices into `paragraphs`, grouped by page in reading order.
    private var paragraphIndicesByPage: [Delegate.Index: [Int]]
    /// Total readable-text length per page (character count), used as the highlight hint denominator.
    private var pageTextLength: [Delegate.Index: Int]
    /// Whether the whole document has already been extracted and cached.
    private var documentLoaded: Bool
    /// Document language (BCP-47 tag) read from the structured document text metadata, if any.
    private var documentLanguage: String?
    /// Worker used to extract structured document text for the whole document.
    private var speechWorker: DocumentWorkerController.Worker?
    /// Navigation tap waiting for the multi-tap window to elapse. Executed as a sentence skip if no second tap
    /// arrives within `navigationMultiTapInterval`; replaced by a paragraph skip if one does.
    private var pendingNavigation: (direction: NavigationDirection, workItem: DispatchWorkItem)?
    let highlightSessionManager: SpeechHighlightSessionManager<SpeechManager<Delegate>>
    var onHighlightSessionTimedOut: (() -> Void)?
    var onSpeakingPositionChanged: ((ResumePosition) -> Void)?
    private weak var delegate: Delegate?
    var voice: SpeechVoice? { processor.speechVoice }
    var language: String? { processor.preferredLanguage }
    var speechRateModifier: Float { processor.speechRateModifier }
    var detectedLanguage: String {
        return processor.detectedLanguage ?? "en"
    }
    /// Current position expressed as a page-text offset range, for the voice processors (which work in page-text offsets).
    fileprivate var speechRange: NSRange? {
        guard let position, position.paragraphIndex < paragraphs.count else { return nil }
        let paragraph = paragraphs[position.paragraphIndex]
        return NSRange(location: paragraph.pageOffset + position.range.location, length: position.range.length)
    }
    var currentPageIndex: Delegate.Index? { delegate?.getCurrentPageIndex() }
    /// Granularity at which the read-aloud highlight is rendered. Mirrors the voice's segmentation granularity:
    /// remote voices use their declared granularity, local voices always highlight sentences (since they emit
    /// word-level progress events).
    private var highlightGranularity: NLTokenUnit {
        switch processor.speechVoice {
        case .remote(let voice):
            return voice.granularity == .paragraph ? .paragraph : .sentence

        case .local, .none:
            return .sentence
        }
    }

    private func findHighlightUnit(at index: Int, in text: String, granularity: NLTokenUnit) -> (text: String, range: NSRange)? {
        switch granularity {
        case .paragraph:
            return TextTokenizer.findParagraphContaining(index: index, in: text)

        case .sentence:
            return TextTokenizer.findSentenceContaining(index: index, in: text)

        case .word, .document:
            return nil

        @unknown default:
            return nil
        }
    }

    /// Returns the current read-aloud highlight text, page index, and source-text position info
    /// (used to disambiguate duplicate occurrences when highlighting), if speech is active.
    /// The highlight covers a sentence or paragraph depending on the voice's segmentation granularity.
    var currentReadAloudHighlight: (text: String, pageIndex: Delegate.Index, sourceLocation: Int, sourceTextLength: Int)? {
        guard let position, position.paragraphIndex < paragraphs.count else { return nil }
        let paragraph = paragraphs[position.paragraphIndex]
        let range = position.highlightRange
        guard range.length > 0, let textRange = Range(range, in: paragraph.text) else { return nil }
        let text = String(paragraph.text[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (text, paragraph.page, paragraph.pageOffset + range.location, pageTextLength[paragraph.page] ?? (paragraph.text as NSString).length)
    }

    // MARK: - Paragraph model helpers

    /// Page-local segments (text + page offset) for the given page, in reading order. Handed to voice processors.
    private func segments(forPage page: Delegate.Index) -> [SpeechDocumentParser.Segment] {
        return (paragraphIndicesByPage[page] ?? []).map { SpeechDocumentParser.Segment(text: paragraphs[$0].text, pageOffset: paragraphs[$0].pageOffset) }
    }

    /// The page's readable text (paragraphs joined by a blank line). Derived on demand; used by the local voice utterance
    /// and the (page-text based) highlight session manager.
    private func pageText(forPage page: Delegate.Index) -> String {
        return (paragraphIndicesByPage[page] ?? []).map { paragraphs[$0].text }.joined(separator: SpeechDocumentParser.segmentSeparator)
    }

    /// Maps a page-text offset on `page` to a paragraph index and the offset within that paragraph.
    private func resolveParagraph(atPageTextOffset offset: Int, page: Delegate.Index) -> (index: Int, offset: Int)? {
        let indices = paragraphIndicesByPage[page] ?? []
        guard let first = indices.first else { return nil }
        var chosen = first
        for index in indices {
            if paragraphs[index].pageOffset <= offset {
                chosen = index
            } else {
                break
            }
        }
        let paragraph = paragraphs[chosen]
        return (chosen, max(0, min(offset - paragraph.pageOffset, paragraph.text.count)))
    }

    init(delegate: Delegate, voiceLanguage: String?, remoteVoiceTier: RemoteVoice.Tier?, remoteVoicesController: RemoteVoicesController, documentWorkerController: DocumentWorkerController) {
        self.delegate = delegate
        self.remoteVoicesController = remoteVoicesController
        self.documentWorkerController = documentWorkerController
        paragraphs = []
        paragraphIndicesByPage = [:]
        pageTextLength = [:]
        documentLoaded = false
        highlightSessionManager = SpeechHighlightSessionManager<SpeechManager<Delegate>>()
        state = BehaviorRelay(value: .stopped)
        remainingTime = BehaviorRelay(value: nil)
        extractionProgress = BehaviorRelay(value: nil)
        disposeBag = DisposeBag()
        nowPlayingManager = NowPlayingManager()
        parsingQueue = DispatchQueue(label: "SpeechManager.ParsingQueue", qos: .userInteractive, attributes: .concurrent)
        super.init()
        highlightSessionManager.delegate = self
        highlightSessionManager.onSessionTimedOut = { [weak self] in
            self?.onHighlightSessionTimedOut?()
        }
        if let remoteVoiceTier {
            processor = RemoteVoiceProcessor(
                language: voiceLanguage,
                detectedLanguage: nil,
                tier: remoteVoiceTier,
                speechRateModifier: 1,
                delegate: self,
                remoteVoicesController: remoteVoicesController
            )
        } else {
            processor = LocalVoiceProcessor(language: voiceLanguage, detectedLanguage: nil, speechRateModifier: 1, delegate: self)
        }
        processor.speechRateModifier = speechRateModifier

        setupNowPlayingManager()

        state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                switch state {
                case .speaking:
                    nowPlayingManager.updatePlaybackState(isPlaying: true)

                case .paused, .initializing, .loading:
                    nowPlayingManager.updatePlaybackState(isPlaying: false)

                case .outOfCredits:
                    nowPlayingManager.updatePlaybackState(isPlaying: false)

                case .stopped:
                    // The extracted paragraphs are kept across stops so playback can restart without re-loading them.
                    position = nil
                    currentSpeakingPage = nil
                    processor.detectedLanguage = nil
                    pendingNavigation?.workItem.cancel()
                    pendingNavigation = nil
                    highlightSessionManager.cancelSession()
                    nowPlayingManager.deactivate()
                }
            })
            .disposed(by: disposeBag)
    }

    deinit {
        if let speechWorker {
            documentWorkerController.cleanupWorker(speechWorker)
        }
    }

    private func setupNowPlayingManager() {
        nowPlayingManager.playPauseHandler = { [weak self] in
            guard let self else { return }
            switch state.value {
            case .paused, .outOfCredits:
                resume()

            case .speaking:
                pause()

            case .initializing, .loading, .stopped:
                break
            }
        }
        nowPlayingManager.forwardHandler = { [weak self] in
            self?.navigateForward()
        }
        nowPlayingManager.backwardHandler = { [weak self] in
            self?.navigateBackward()
        }
    }

    // MARK: - Actions

    func start(_ target: StartTarget) {
        guard let delegate else {
            DDLogError("SpeechManager: can't get delegate")
            return
        }

        nowPlayingManager.activate(title: delegate.documentTitle)

        state.accept(.initializing)
        // Load (extract and cache) the whole document once, then detect the session language and start playback.
        // No further document data is requested afterwards.
        loadDocumentIfNeeded { [weak self] success in
            guard let self, state.value == .initializing else { return }
            guard success else {
                state.accept(.stopped)
                return
            }
            // Set the session language from the document metadata before playback starts, so that the voice stays
            // constant for the whole session. No-op when the user has already picked a language or it was already set.
            applySessionLanguageIfNeeded()
            startPlayback(target: target)
        }
    }

    /// Extracts and caches structured document text for the whole document, keeping only readable (paragraph/list)
    /// content. Calls `completion(true)` once the cache is ready (or already present), `completion(false)` on failure.
    private func loadDocumentIfNeeded(completion: @escaping (Bool) -> Void) {
        if documentLoaded {
            completion(true)
            return
        }
        guard let delegate, let file = delegate.documentFile else {
            DDLogError("SpeechManager: can't get document file")
            completion(false)
            return
        }
        let worker = speechWorker ?? DocumentWorkerController.Worker(file: file, kind: .oneOff, priority: .high, password: delegate.documentPassword)
        speechWorker = worker
        let start = CFAbsoluteTimeGetCurrent()
        documentWorkerController.queue(work: .structuredDocumentText, in: worker)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] update in
                guard let self else { return }
                switch update.kind {
                case .failed, .cancelled:
                    DDLogError("SpeechManager: structured document text extraction failed")
                    extractionProgress.accept(nil)
                    // Drop the finished one-off worker so a retry creates a fresh one.
                    speechWorker = nil
                    completion(false)

                case .queued:
                    // Extraction is queued but not started yet; progress is unknown (indeterminate).
                    extractionProgress.accept(nil)

                case .inProgress(let progress):
                    extractionProgress.accept(progress.map { $0 / 100 })

                case .extractedData(let result, _):
                    extractionProgress.accept(nil)
                    switch result {
                    case .structuredDocumentText(let result):
                        // Parsing the whole document can be heavy, so do it off the main thread.
                        parsingQueue.async { [weak self] in
                            let parsed: SpeechDocumentParser.ParsedDocument
                            do {
                                parsed = SpeechDocumentParser.parse(materialized: try result.pack().materialize())
                            } catch {
                                DDLogError("SpeechManager: could not parse structured document text - \(error)")
                                parsed = SpeechDocumentParser.ParsedDocument(paragraphs: [], language: nil)
                            }
                            DispatchQueue.main.async { [weak self] in
                                guard let self else { return }
                                store(parsed)
                                documentLoaded = true
                                DDLogInfo("SpeechManager: extracted \(paragraphs.count) paragraph(s) in \(CFAbsoluteTimeGetCurrent() - start)")
                                completion(true)
                            }
                        }

                    case .fullText, .recognizerData:
                        DDLogError("SpeechManager: SDT extraction result invalid")
                        speechWorker = nil
                        completion(false)
                    }
                }
            })
            .disposed(by: disposeBag)
    }

    /// Stores parsed paragraphs, mapping structured-document-text page indices to the delegate's page index type and
    /// building the per-page index and length lookups. Paragraphs whose page is out of bounds are dropped.
    private func store(_ parsed: SpeechDocumentParser.ParsedDocument) {
        guard let delegate else { return }
        var paragraphs: [SpeechParagraph] = []
        var indicesByPage: [Delegate.Index: [Int]] = [:]
        var lengths: [Delegate.Index: Int] = [:]
        for paragraph in parsed.paragraphs {
            guard let page = delegate.pageIndex(forStructuredDocumentTextPage: paragraph.page) else { continue }
            let index = paragraphs.count
            paragraphs.append(SpeechParagraph(text: paragraph.text, page: page, pageOffset: paragraph.pageOffset, rects: paragraph.rects))
            indicesByPage[page, default: []].append(index)
            lengths[page] = max(lengths[page] ?? 0, paragraph.pageOffset + paragraph.text.count)
        }
        self.paragraphs = paragraphs
        paragraphIndicesByPage = indicesByPage
        pageTextLength = lengths
        documentLanguage = parsed.language
    }

    private func startPlayback(target: StartTarget) {
        guard let delegate else {
            state.accept(.stopped)
            return
        }

        // Resume targets a stored paragraph anchor directly, with no page-text round-trip.
        if case .resume(let resumePosition) = target, resumePosition.paragraphIndex < paragraphs.count {
            let paragraph = paragraphs[resumePosition.paragraphIndex]
            let offset = min(max(0, resumePosition.offset), paragraph.text.count)
            startSpeaking(paragraphIndex: resumePosition.paragraphIndex, offset: offset, reportPageChange: false)
            return
        }

        let currentIndex = delegate.getCurrentPageIndex()
        guard let page = firstReadablePage(atOrAfter: currentIndex) else {
            DDLogWarn("SpeechManager: no readable content to play")
            state.accept(.stopped)
            return
        }
        // A PSPDFKit text selection maps to a page-text offset, which we then resolve to a paragraph. Only honored when
        // the readable page is the page the user is on.
        let startOffset: Int
        if case .pageTextOffset(let map) = target, page == currentIndex {
            startOffset = map(pageText(forPage: page))
        } else {
            startOffset = 0
        }
        guard let (paragraphIndex, offset) = resolveParagraph(atPageTextOffset: startOffset, page: page) else {
            state.accept(.stopped)
            return
        }
        startSpeaking(paragraphIndex: paragraphIndex, offset: offset, reportPageChange: false)
    }

    /// Sets the session language from the document metadata (defaulting to English when absent), so that the voice stays
    /// constant for the whole session. No-op when the user has chosen a language explicitly or it was already set.
    private func applySessionLanguageIfNeeded() {
        guard processor.preferredLanguage == nil, processor.detectedLanguage == nil else { return }
        let language = documentLanguage ?? "en"
        processor.detectedLanguage = language
        DDLogInfo("SpeechManager: using session language \(language) (from document metadata: \(documentLanguage != nil))")
    }

    func pause() {
        processor.pause()
    }

    func resume() {
        if processor.canResume {
            processor.resume()
        } else {
            start(.currentPage)
        }
    }

    func stop() {
        processor.stop()
    }

    func set(voice: SpeechVoice, preferredLanguage: String?) {
        switch voice {
        case .local(let voice):
            if let processor = processor as? LocalVoiceProcessor {
                processor.set(voice: voice, preferredLanguage: preferredLanguage)
            } else {
                let _processor = LocalVoiceProcessor(
                    language: preferredLanguage,
                    detectedLanguage: processor.detectedLanguage,
                    speechRateModifier: processor.speechRateModifier,
                    delegate: self
                )
                _processor.set(voice: voice, preferredLanguage: preferredLanguage)
                processor = _processor
                remainingTime.accept(nil)
                nowPlayingManager.reconfigureAudioSession()
            }

        case .remote(let voice):
            if let processor = processor as? RemoteVoiceProcessor {
                processor.set(voice: voice, preferredLanguage: preferredLanguage)
            } else {
                let _processor = RemoteVoiceProcessor(
                    language: preferredLanguage,
                    detectedLanguage: processor.detectedLanguage,
                    tier: voice.tier,
                    speechRateModifier: processor.speechRateModifier,
                    delegate: self,
                    remoteVoicesController: remoteVoicesController
                )
                _processor.set(voice: voice, preferredLanguage: preferredLanguage)
                processor = _processor
                nowPlayingManager.reconfigureAudioSession()
            }
        }
    }

    func set(rateModifier: Float) {
        processor.speechRateModifier = rateModifier
    }

    // MARK: - Highlight Session

    /// Starts a highlight session. Returns the initial text and page index, and shows a temporary highlight in the document.
    func startHighlightSession() -> (text: String, pageIndex: Delegate.Index)? {
        guard state.value.isSpeaking || state.value.isPaused, let position, position.paragraphIndex < paragraphs.count else { return nil }
        let paragraph = paragraphs[position.paragraphIndex]
        let voiceInfo: HighlightVoiceInfo
        switch processor.speechVoice {
        case .remote(let remoteVoice):
            let granularity: NLTokenUnit = remoteVoice.granularity == .paragraph ? .paragraph : .sentence
            voiceInfo = .remote(granularity: granularity, audioProgress: processor.segmentAudioProgress, elapsedTime: processor.segmentAudioElapsedTime)

        case .local:
            voiceInfo = .local

        case .none:
            return nil
        }

        guard let result = highlightSessionManager.startSession(
            voiceInfo: voiceInfo,
            position: paragraph.pageOffset + position.range.location,
            segments: segments(forPage: paragraph.page),
            pageIndex: paragraph.page
        ) else { return nil }

        notifyAnnotationPreviewChanged(result)
        return result
    }

    func moveHighlightForward() -> (text: String, pageIndex: Delegate.Index)? {
        guard let result = highlightSessionManager.moveForward() else { return nil }
        notifyAnnotationPreviewChanged(result)
        return result
    }

    func moveHighlightBackward() -> (text: String, pageIndex: Delegate.Index)? {
        guard let result = highlightSessionManager.moveBackward() else { return nil }
        notifyAnnotationPreviewChanged(result)
        return result
    }

    func extendHighlightForward() -> (text: String, pageIndex: Delegate.Index)? {
        guard let result = highlightSessionManager.extendForward() else { return nil }
        notifyAnnotationPreviewChanged(result)
        return result
    }

    func extendHighlightBackward() -> (text: String, pageIndex: Delegate.Index)? {
        guard let result = highlightSessionManager.extendBackward() else { return nil }
        notifyAnnotationPreviewChanged(result)
        return result
    }

    private func notifyAnnotationPreviewChanged(_ result: (text: String, pageIndex: Delegate.Index)) {
        let sourceLocation = highlightSessionManager.session?.range.location ?? 0
        let sourceTextLength = highlightSessionManager.session.map { ($0.pageText as NSString).length } ?? 0
        delegate?.annotationPreviewChanged(
            text: result.text,
            pageIndex: result.pageIndex,
            tool: highlightSessionManager.annotationTool,
            color: highlightSessionManager.annotationColor,
            sourceLocation: sourceLocation,
            sourceTextLength: sourceTextLength
        )
    }

    func setHighlightAnnotationTool(_ tool: AnnotationTool) {
        highlightSessionManager.annotationTool = tool
        highlightSessionManager.startInactivityTimer()
    }

    func setHighlightAnnotationColor(_ color: String) {
        highlightSessionManager.annotationColor = color
        highlightSessionManager.startInactivityTimer()
    }

    func stopHighlightInactivityTimer() {
        highlightSessionManager.stopInactivityTimer()
    }

    func startHighlightInactivityTimer() {
        highlightSessionManager.startInactivityTimer()
    }

    var highlightAnnotationTool: AnnotationTool {
        highlightSessionManager.annotationTool
    }

    var highlightAnnotationColor: String {
        highlightSessionManager.annotationColor
    }

    func endHighlightSession() {
        // Capture range info before `endSession()` clears the session.
        let sourceLocation = highlightSessionManager.session?.range.location ?? 0
        let sourceTextLength = highlightSessionManager.session.map { ($0.pageText as NSString).length } ?? 0
        if let result = highlightSessionManager.endSession() {
            delegate?.createAnnotation(
                ofType: highlightSessionManager.annotationTool,
                color: highlightSessionManager.annotationColor,
                forText: result.text,
                onPage: result.pageIndex,
                sourceLocation: sourceLocation,
                sourceTextLength: sourceTextLength
            )
        }
        delegate?.clearAnnotationPreview()
    }

    func cancelHighlightSession() {
        highlightSessionManager.cancelSession()
        delegate?.clearAnnotationPreview()
    }

    /// Downgrades the voice to a lower tier and continues playback.
    /// - If currently using premium remote voice, switches to standard remote voice
    /// - If currently using standard remote voice, switches to local voice
    /// - If already using local voice, does nothing
    func downgradeVoiceTierAndContinue() {
        guard let voice else { return }

        switch voice {
        case .remote(let remoteVoice):
            switch remoteVoice.tier {
            case .premium:
                // Downgrade from premium to standard
                guard let remoteProcessor = processor as? RemoteVoiceProcessor,
                      let language = processor.preferredLanguage ?? processor.detectedLanguage,
                      let standardVoice = remoteProcessor.standardVoice(for: language) else {
                    // No standard voice available, fall through to local
                    downgradeToLocalVoice()
                    return
                }
                Defaults.shared.remoteVoiceTier = .standard
                remoteProcessor.set(voice: standardVoice, preferredLanguage: remoteProcessor.preferredLanguage)
                resume()

            case .standard:
                // Downgrade from standard to local voice
                downgradeToLocalVoice()
            }

        case .local:
            // Already at lowest tier, nothing to downgrade to
            break
        }

        func downgradeToLocalVoice() {
            Defaults.shared.remoteVoiceTier = nil
            let newProcessor = LocalVoiceProcessor(
                language: processor.preferredLanguage,
                detectedLanguage: processor.detectedLanguage,
                speechRateModifier: processor.speechRateModifier,
                delegate: self
            )
            let voice = VoiceUtility.findLocalVoice(for: processor.language) ?? AVSpeechSynthesisVoice(language: "en-US")!
            newProcessor.set(voice: voice, preferredLanguage: processor.preferredLanguage)
            processor = newProcessor
            remainingTime.accept(nil)
            nowPlayingManager.reconfigureAudioSession()
            resume()
        }
    }

    /// Returns the first readable page (one that has paragraphs) at or after `index`, or nil if there is none.
    private func firstReadablePage(atOrAfter index: Delegate.Index) -> Delegate.Index? {
        if paragraphIndicesByPage[index]?.isEmpty == false {
            return index
        }
        return nextReadablePage(after: index)
    }

    /// Returns the next readable page after `index`, skipping pages without readable content, or nil.
    private func nextReadablePage(after index: Delegate.Index) -> Delegate.Index? {
        guard let delegate else { return nil }
        var current = index
        while let next = delegate.getNextPageIndex(from: current) {
            if paragraphIndicesByPage[next]?.isEmpty == false {
                return next
            }
            current = next
        }
        return nil
    }

    /// Returns the previous readable page before `index`, skipping pages without readable content, or nil.
    private func previousReadablePage(before index: Delegate.Index) -> Delegate.Index? {
        guard let delegate else { return nil }
        var current = index
        while let previous = delegate.getPreviousPageIndex(from: current) {
            if paragraphIndicesByPage[previous]?.isEmpty == false {
                return previous
            }
            current = previous
        }
        return nil
    }

    /// Navigates forward with tap coalescing: a single call skips by sentence, two calls in quick succession skip by paragraph.
    func navigateForward() {
        coalesceNavigation(.forward)
    }

    /// Navigates backward with tap coalescing: a single call skips by sentence, two calls in quick succession skip by paragraph.
    func navigateBackward() {
        coalesceNavigation(.backward)
    }

    /// Coalesces rapid navigation taps so that a single tap skips by sentence and a double tap skips by paragraph.
    /// The first tap schedules a sentence skip after `navigationMultiTapInterval`; a second tap in the same direction
    /// within that window cancels it and performs a single paragraph skip instead, so a double tap moves by exactly
    /// one paragraph. A tap in the opposite direction flushes the pending sentence skip immediately and starts a new window.
    private func coalesceNavigation(_ direction: NavigationDirection) {
        if let pending = pendingNavigation {
            pending.workItem.cancel()
            pendingNavigation = nil
            if pending.direction == direction {
                navigate(direction, by: .paragraph)
                return
            }
            navigate(pending.direction, by: .sentence)
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingNavigation = nil
            navigate(direction, by: .sentence)
        }
        pendingNavigation = (direction, workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + navigationMultiTapInterval, execute: workItem)
    }

    private func navigate(_ direction: NavigationDirection, by unit: NLTokenUnit) {
        switch direction {
        case .forward:
            forward(by: unit)

        case .backward:
            backward(by: unit)
        }
    }

    func forward(by unit: NLTokenUnit) {
        guard let position, position.paragraphIndex < paragraphs.count else { return }
        if unit == .paragraph {
            move(toParagraph: position.paragraphIndex + 1, offset: 0)
            return
        }
        // Sentences are detected within the current paragraph's text, so they never span a paragraph boundary.
        let paragraph = paragraphs[position.paragraphIndex]
        let currentEnd = position.range.location + position.range.length
        if let next = TextTokenizer.nextSentenceStart(after: currentEnd, in: paragraph.text), next < paragraph.text.count {
            move(toParagraph: position.paragraphIndex, offset: next)
        } else {
            move(toParagraph: position.paragraphIndex + 1, offset: 0)
        }
    }

    func backward(by unit: NLTokenUnit) {
        guard let position, position.paragraphIndex < paragraphs.count else { return }
        let paragraph = paragraphs[position.paragraphIndex]
        if unit == .paragraph {
            // A back press within a paragraph returns to its start; at the start it moves to the previous paragraph.
            move(toParagraph: position.range.location > 0 ? position.paragraphIndex : position.paragraphIndex - 1, offset: 0)
            return
        }
        if let previous = TextTokenizer.previousSentenceStart(before: position.range.location, in: paragraph.text) {
            move(toParagraph: position.paragraphIndex, offset: previous)
        } else if position.paragraphIndex > 0 {
            // At the first sentence of the paragraph: go to the previous paragraph's last sentence.
            let previousParagraph = paragraphs[position.paragraphIndex - 1]
            let lastSentence = TextTokenizer.previousSentenceStart(before: previousParagraph.text.count, in: previousParagraph.text) ?? 0
            move(toParagraph: position.paragraphIndex - 1, offset: lastSentence)
        } else if position.range.location != 0 {
            move(toParagraph: position.paragraphIndex, offset: 0)
        } else {
            stop()
        }
    }

    /// Moves to a paragraph position: updates the highlight, restarts playback (unless paused), and focuses the page.
    /// Stops when the target index is out of bounds (start/end of document).
    private func move(toParagraph index: Int, offset: Int) {
        guard index >= 0, index < paragraphs.count else {
            stop()
            return
        }
        DDLogInfo("SpeechManager: move to paragraph \(index), offset \(offset)")
        moveTo(paragraphIndex: index, offset: offset)
        if !state.value.isPaused {
            startSpeaking(paragraphIndex: index, offset: offset, reportPageChange: false)
        }
        delegate?.focusPage(paragraphs[index].page)
    }

    private func startSpeaking(paragraphIndex index: Int, offset: Int = 0, reportPageChange: Bool) {
        guard index < paragraphs.count else {
            stop()
            return
        }
        let paragraph = paragraphs[index]
        let previousPage = currentPage(ofParagraph: position?.paragraphIndex)
        if position?.paragraphIndex != index {
            position = Position(paragraphIndex: index, range: NSRange(location: offset, length: 0), highlightRange: NSRange(), highlightGranularity: highlightGranularity)
        }
        if reportPageChange, let previousPage, previousPage != paragraph.page {
            delegate?.moved(to: paragraph.page, from: previousPage)
        }
        currentSpeakingPage = paragraph.page
        processor.speak(segments: segments(forPage: paragraph.page), startPageTextOffset: paragraph.pageOffset + offset)
    }

    /// Updates the current position and highlight for a paragraph offset, without starting playback.
    /// Used when navigating while paused, and to seed the highlight before playback resumes.
    private func moveTo(paragraphIndex index: Int, offset: Int) {
        guard index < paragraphs.count else { return }
        let paragraph = paragraphs[index]
        guard let sentence = TextTokenizer.findSentence(startingAt: offset, in: paragraph.text) else { return }

        let previousPage = currentPage(ofParagraph: position?.paragraphIndex)
        let pageDidChange = previousPage != paragraph.page
        let granularity = highlightGranularity

        // Keep the existing highlight range if we're still inside it (same paragraph and granularity).
        let isInCurrentHighlight: Bool
        if let position, position.paragraphIndex == index, position.highlightRange.length > 0, position.highlightGranularity == granularity {
            isInCurrentHighlight = NSLocationInRange(offset, position.highlightRange)
        } else {
            isInCurrentHighlight = false
        }

        let newHighlightRange: NSRange
        let highlightText: String?
        if isInCurrentHighlight, let position {
            newHighlightRange = position.highlightRange
            highlightText = nil
        } else {
            let unit = findHighlightUnit(at: offset, in: paragraph.text, granularity: granularity)
            newHighlightRange = unit?.range ?? sentence.range
            highlightText = unit?.text ?? sentence.text
        }

        position = Position(paragraphIndex: index, range: sentence.range, highlightRange: newHighlightRange, highlightGranularity: granularity)
        processor.invalidateCurrentPlayback()

        if let highlightText {
            delegate?.readAloudHighlightChanged(
                text: highlightText,
                pageIndex: paragraph.page,
                sourceLocation: paragraph.pageOffset + newHighlightRange.location,
                sourceTextLength: pageTextLength[paragraph.page] ?? (paragraph.text as NSString).length
            )
        }

        if pageDidChange, let previousPage {
            delegate?.moved(to: paragraph.page, from: previousPage)
        }
    }

    private func currentPage(ofParagraph index: Int?) -> Delegate.Index? {
        guard let index, index < paragraphs.count else { return nil }
        return paragraphs[index].page
    }

    // MARK: - VoiceProcessorDelegate

    func goToNextPageIfAvailable() -> Bool {
        guard let position else { return false }
        let nextIndex = position.paragraphIndex + 1
        guard nextIndex < paragraphs.count else { return false }
        startSpeaking(paragraphIndex: nextIndex, offset: 0, reportPageChange: true)
        return true
    }

    func speechRangeWillChange(to range: NSRange) {
        guard let page = currentSpeakingPage, let (index, _) = resolveParagraph(atPageTextOffset: range.location, page: page) else { return }
        let paragraph = paragraphs[index]
        let intraLocation = max(0, range.location - paragraph.pageOffset)
        let intraLength = min(range.length, max(0, paragraph.text.count - intraLocation))
        let intraRange = NSRange(location: intraLocation, length: intraLength)
        let granularity = highlightGranularity

        // Still within the current highlighted unit (same paragraph and granularity): just update the speech range.
        if let position, position.paragraphIndex == index, position.highlightGranularity == granularity, NSLocationInRange(intraLocation, position.highlightRange) {
            self.position = Position(paragraphIndex: index, range: intraRange, highlightRange: position.highlightRange, highlightGranularity: granularity)
            return
        }

        let unit = findHighlightUnit(at: intraLocation, in: paragraph.text, granularity: granularity)
        let newHighlightRange = unit?.range ?? intraRange
        position = Position(paragraphIndex: index, range: intraRange, highlightRange: newHighlightRange, highlightGranularity: granularity)

        if let highlightText = unit?.text {
            delegate?.readAloudHighlightChanged(
                text: highlightText,
                pageIndex: paragraph.page,
                sourceLocation: paragraph.pageOffset + newHighlightRange.location,
                sourceTextLength: pageTextLength[paragraph.page] ?? (paragraph.text as NSString).length
            )
        }
    }
}

extension AVSpeechSynthesisVoice {
    var baseLanguage: String {
        if let index = language.firstIndex(of: "-") {
            return String(language[language.startIndex..<index])
        }
        return language
    }
}

private protocol VoiceProcessor {
    var speechVoice: SpeechVoice? { get }
    var preferredLanguage: String? { get }
    var detectedLanguage: String? { get set }
    var speechRateModifier: Float { get set }
    var canResume: Bool { get }
    /// Progress of current audio segment (0.0 to 1.0).
    var segmentAudioProgress: Float { get }
    /// Time elapsed since current audio segment started playing.
    var segmentAudioElapsedTime: TimeInterval { get }

    /// Starts speaking the page's `segments` (paragraphs, each with its page-text offset) from `startPageTextOffset`
    /// (a character offset within the page's readable text). The local voice joins the segments into one utterance;
    /// the remote voice reads them segment by segment.
    func speak(segments: [SpeechDocumentParser.Segment], startPageTextOffset: Int)
    func pause()
    func resume()
    func stop()
    /// Called when the speech position changes while paused (e.g., via forward/backward navigation).
    /// The processor should invalidate current playback state so that resume() starts from the new position.
    func invalidateCurrentPlayback()
}

extension VoiceProcessor {
    var language: String {
        return preferredLanguage ?? detectedLanguage ?? "en"
    }
}

private protocol VoiceProcessorDelegate: AnyObject {
    var state: BehaviorRelay<SpeechState> { get }
    var remainingTime: BehaviorRelay<TimeInterval?> { get }
    var speechRange: NSRange? { get }

    func goToNextPageIfAvailable() -> Bool
    func speechRangeWillChange(to range: NSRange)
}

private final class LocalVoiceProcessor: NSObject, VoiceProcessor {
    private struct PageData {
        // Text to read
        let text: String
        // Voice used for this page
        let voice: AVSpeechSynthesisVoice
    }

    private let synthesizer: AVSpeechSynthesizer
    private unowned let delegate: VoiceProcessorDelegate

    private var text: String?
    /// The start index offset in the original text where the current utterance begins.
    /// AVSpeechSynthesizer reports ranges relative to the utterance text, so we need this
    /// to convert back to ranges in the original full text.
    private var utteranceStartIndex: Int = 0
    private(set) var preferredLanguage: String?
    var detectedLanguage: String?
    private var voice: AVSpeechSynthesisVoice?
    private var shouldReloadUtteranceOnResume = false
    private var ignoreFinishCallCount = 0
    /// Background task identifier to keep the app alive during page transitions
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    var speechRateModifier: Float {
        didSet {
            utteranceChanged()
        }
    }
    var speechVoice: SpeechVoice? {
        return voice.flatMap({ .local($0) })
    }
    var canResume: Bool {
        return synthesizer.isPaused
    }
    var segmentAudioProgress: Float {
        // Local voice doesn't have audio-level segment tracking.
        // SpeechManager computes sentence progress from character position instead.
        return 0
    }
    var segmentAudioElapsedTime: TimeInterval {
        // Local voice plays the whole page as one utterance, so elapsed time is not meaningful per-segment.
        return 0
    }

    init(language: String?, detectedLanguage: String?, speechRateModifier: Float, delegate: VoiceProcessorDelegate) {
        preferredLanguage = language
        self.detectedLanguage = detectedLanguage
        self.speechRateModifier = speechRateModifier
        self.delegate = delegate
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(segments: [SpeechDocumentParser.Segment], startPageTextOffset: Int) {
        // Local voice reads the whole page as one utterance, so it joins the paragraphs into the page's readable text.
        speak(pageText: segments.map(\.text).joined(separator: SpeechDocumentParser.segmentSeparator), startIndex: startPageTextOffset)
    }

    private func speak(pageText text: String, startIndex: Int) {
        if synthesizer.isSpeaking {
            ignoreFinishCallCount += 1
            synthesizer.stopSpeaking(at: .immediate)
        }

        self.text = text
        self.utteranceStartIndex = startIndex
        let remainingText = String(text[text.index(text.startIndex, offsetBy: startIndex)..<text.endIndex])

        // Language is detected once at session start, so the voice is resolved only the first time and then reused.
        if voice == nil {
            voice = voice(for: remainingText)
        }

        let utterance = AVSpeechUtterance(string: remainingText)
        utterance.voice = voice
        utterance.rate = 0.5 * speechRateModifier
        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthesizer.isPaused else { return }

        if !shouldReloadUtteranceOnResume {
            synthesizer.continueSpeaking()
        } else {
            reloadUtterance()
        }
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused || delegate.state.value == .initializing else { return }
        if delegate.state.value == .initializing {
            finishSpeaking()
        } else {
            // Ignore finish delegate, which would move us to another page
            ignoreFinishCallCount = 1
            synthesizer.stopSpeaking(at: .immediate)
            finishSpeaking()
        }
    }

    func invalidateCurrentPlayback() {
        shouldReloadUtteranceOnResume = true
    }

    func set(voice: AVSpeechSynthesisVoice, preferredLanguage: String?) {
        guard self.voice?.identifier != voice.identifier else { return }
        self.preferredLanguage = preferredLanguage
        self.voice = voice
        utteranceChanged()
    }

    private func utteranceChanged() {
        if synthesizer.isPaused {
            shouldReloadUtteranceOnResume = true
        } else if synthesizer.isSpeaking {
            reloadUtterance()
        }
    }

    private func reloadUtterance() {
        guard let text, let speechRange = delegate.speechRange else { return }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
        speak(pageText: text, startIndex: speechRange.location)
    }

    private func voice(for text: String) -> AVSpeechSynthesisVoice {
        return VoiceUtility.findLocalVoice(for: language) ?? AVSpeechSynthesisVoice(language: "en-US")!
    }

    private func finishSpeaking() {
        text = nil
        utteranceStartIndex = 0
        voice = nil
        shouldReloadUtteranceOnResume = false
        ignoreFinishCallCount = 0
        endBackgroundTask()
        delegate.state.accept(.stopped)
    }

    // MARK: - Background Task

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.zotero.speech.pageTransition") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}

extension LocalVoiceProcessor: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        delegate.state.accept(.paused)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        endBackgroundTask()
        delegate.state.accept(.speaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        endBackgroundTask()
        delegate.state.accept(.speaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard ignoreFinishCallCount <= 0 else {
            ignoreFinishCallCount -= 1
            return
        }

        // Keep the app alive while transitioning to the next page in background
        beginBackgroundTask()
        if !delegate.goToNextPageIfAvailable() {
            finishSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard characterRange.length > 0 else { return }
        // AVSpeechSynthesizer reports ranges relative to the utterance text, which may be a substring
        // of the original text starting at utteranceStartIndex. Adjust the range to be relative to
        // the original full text.
        let adjustedRange = NSRange(location: characterRange.location + utteranceStartIndex, length: characterRange.length)
        delegate.speechRangeWillChange(to: adjustedRange)
    }
}

private final class RemoteVoiceProcessor: NSObject, VoiceProcessor {
    enum Error: Swift.Error {
        case cancelled
        case missingVoices
        case endOfPage
    }

    /// Number of segments to keep preloaded ahead of current playback
    private static let preloadAheadCount = 2
    /// Interval for polling remaining credits from the server
    private static let creditPollInterval: TimeInterval = 60

    private unowned let delegate: VoiceProcessorDelegate
    private unowned let remoteVoicesController: RemoteVoicesController
    private var tier: RemoteVoice.Tier

    /// The current page's paragraph segments (text + page-text offset). The remote voice reads these segment by segment,
    /// splitting a segment into sentences with `TextTokenizer` when the voice's granularity is `.sentence`.
    private var segments: [SpeechDocumentParser.Segment] = []
    private(set) var preferredLanguage: String?
    var detectedLanguage: String?
    private var voice: RemoteVoice?
    private var player: AVAudioPlayer?
    private var allAvailableVoices: VoicesResponse?
    private var disposeBag = DisposeBag()
    /// Cache of downloaded audio data keyed by their text range
    private var segmentCache: [NSRange: Data] = [:]
    /// Set of ranges currently being loaded
    private var loadingSegments: Set<NSRange> = []
    /// Range that should start playing as soon as it's loaded (when waiting for an in-progress preload)
    private var pendingPlaybackRange: NSRange?
    private var shouldReloadOnResume = false
    private var debouncedSpeakWorkItem: DispatchWorkItem?
    private var creditPollTimer: Timer?
    /// Background task identifier to keep the app alive during segment transitions
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    var speechRateModifier: Float {
        didSet {
            player?.rate = speechRateModifier
        }
    }
    var speechVoice: SpeechVoice? {
        return voice.flatMap({ .remote($0) })
    }
    var canResume: Bool {
        return player != nil
    }
    var segmentAudioProgress: Float {
        guard let player, player.duration > 0 else { return 0 }
        return Float(player.currentTime / player.duration)
    }
    var segmentAudioElapsedTime: TimeInterval {
        return player?.currentTime ?? 0
    }

    init(language: String?, detectedLanguage: String?, tier: RemoteVoice.Tier, speechRateModifier: Float, delegate: VoiceProcessorDelegate, remoteVoicesController: RemoteVoicesController) {
        preferredLanguage = language
        self.detectedLanguage = detectedLanguage
        self.tier = tier
        self.speechRateModifier = speechRateModifier
        self.delegate = delegate
        self.remoteVoicesController = remoteVoicesController
        super.init()
    }

    // MARK: - Actions

    func set(voice: RemoteVoice, preferredLanguage: String?) {
        let voiceChanged = self.voice?.id != voice.id
        self.preferredLanguage = preferredLanguage
        self.voice = voice

        if voiceChanged {
            stopPreloadingAndClearCache()
            delegate.remainingTime.accept(nil)
            loadCredits()
            if let player {
                if player.isPlaying {
                    player.pause()
                }
                shouldReloadOnResume = true
            }
        }
    }

    /// Attempts to downgrade to standard tier using cached voices.
    /// Returns the voice and language if successful, nil if no standard voice is available.
    func standardVoice(for language: String) -> RemoteVoice? {
        guard let allAvailableVoices else { return nil }
        return VoiceUtility.findRemoteVoice(for: language, tier: .standard, response: allAvailableVoices)
    }

    func speak(segments: [SpeechDocumentParser.Segment], startPageTextOffset: Int) {
        // Immediate: stop current playback and update state
        if self.segments.map(\.text) != segments.map(\.text) || startPageTextOffset != 0 {
            stopPreloadingAndClearCache()
        }
        self.segments = segments
        if player?.isPlaying == true {
            player?.stop()
        }
        player = nil
        disposeBag = DisposeBag()
        debouncedSpeakWorkItem?.cancel()
        debouncedSpeakWorkItem = nil

        // Start .loading state unless we're already .initializing
        if delegate.state.value != .initializing {
            delegate.state.accept(.loading)
        }

        // If the voice is not known yet, start loading immediately so that there is no unnecessary delay
        if voice == nil {
            loadVoiceAndStartSpeaking(startIndex: startPageTextOffset)
            return
        }

        // Debounce segment download so rapid forward/backward taps don't trigger multiple network requests
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.loadVoiceAndStartSpeaking(startIndex: startPageTextOffset)
        }
        debouncedSpeakWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func loadVoiceAndStartSpeaking(startIndex: Int) {
        // Language is detected once at session start, so the voice is resolved only the first time and then reused.
        let getVoice: Single<RemoteVoice>
        if let voice {
            getVoice = Single.just(voice)
        } else {
            getVoice = loadVoice()
        }

        getVoice
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] voice in
                    self?.startSpeaking(startIndex: startIndex, voice: voice)
                },
                onFailure: { [weak self] error in
                    self?.handleSpeechFailure(error: error)
                }
            )
            .disposed(by: disposeBag)
    }

    func pause() {
        debouncedSpeakWorkItem?.cancel()
        debouncedSpeakWorkItem = nil
        guard player?.isPlaying == true else { return }
        player?.pause()
        stopCreditPollTimer()
        delegate.state.accept(.paused)
    }

    func resume() {
        guard let player, delegate.state.value == .paused || delegate.state.value.isOutOfCredits else { return }

        if shouldReloadOnResume {
            shouldReloadOnResume = false
            reloadCurrentSegment()
        } else {
            player.play()
            delegate.state.accept(.speaking)
            startCreditPollTimer()
        }

        func reloadCurrentSegment() {
            guard !segments.isEmpty, let voice, let speechRange = delegate.speechRange else { return }
            // Clear cache since voice changed
            segmentCache.removeAll()
            loadingSegments.removeAll()
            player.stop()
            self.player = nil
            startSpeaking(startIndex: speechRange.location, voice: voice)
        }
    }

    func stop() {
        finishSpeaking()
        disposeBag = DisposeBag()
    }

    func invalidateCurrentPlayback() {
        shouldReloadOnResume = true
    }

    private func stopPreloadingAndClearCache() {
        disposeBag = DisposeBag()
        segmentCache.removeAll()
        loadingSegments.removeAll()
        pendingPlaybackRange = nil
    }

    // MARK: - Background Task

    /// Begins a background task to keep the app alive during segment transitions.
    /// When audio finishes and the app is in the background, iOS may suspend it before the next segment
    /// can be downloaded and played. This gives us ~30 seconds to complete the transition.
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.zotero.speech.segmentTransition") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Voices

    private func loadVoice() -> Single<RemoteVoice> {
        if let allAvailableVoices {
            return resolveVoice(language: language, tier: tier, allVoices: allAvailableVoices)
        }
        return remoteVoicesController.loadVoices()
            .do(onSuccess: { [weak self] result in
                self?.allAvailableVoices = result.response
            })
            .flatMap({ [weak self] result in
                guard let self else {
                    return Single.error(Error.cancelled)
                }
                return resolveVoice(language: language, tier: tier, allVoices: result.response)
            })
            .do(onSuccess: { [weak self] voice in
                self?.voice = voice
            })

        func resolveVoice(language: String, tier: RemoteVoice.Tier, allVoices: VoicesResponse) -> Single<RemoteVoice> {
            return Single.create { subscriber in
                if let voice = VoiceUtility.findRemoteVoice(for: language, tier: tier, response: allVoices) ?? allVoices.firstVoice(for: tier) {
                    subscriber(.success(voice))
                } else {
                    subscriber(.failure(Error.missingVoices))
                }
                return Disposables.create()
            }
        }
    }

    // MARK: - Speech

    private func startSpeaking(startIndex: Int, voice: RemoteVoice) {
        // Find the range for the segment at startIndex
        guard let range = findNextRange(startingAt: startIndex, voice: voice) else {
            handleSpeechFailure(error: Error.endOfPage)
            return
        }

        // Report the range immediately so the highlight updates without waiting for audio to load
        delegate.speechRangeWillChange(to: range)

        // Check if we already have the segment cached
        if let cachedData = segmentCache[range] {
            handleSpeechSuccess(data: cachedData, range: range)
            ensureSegmentsPreloaded(after: range, voice: voice)
            return
        }

        // Check if this segment is already being loaded (preload in progress)
        if loadingSegments.contains(range) {
            // Mark this range as pending playback - it will start playing when the preload completes
            pendingPlaybackRange = range
            delegate.state.accept(.loading)
            return
        }

        // Load segment and start playing as soon as it's ready, while preloading others
        delegate.state.accept(.loading)
        startCreditPollTimer()
        loadAndPlaySegment(range: range, voice: voice)

        func loadAndPlaySegment(range: NSRange, voice: RemoteVoice) {
            // Mark as loading
            loadingSegments.insert(range)

            // Start loading the segment we need to play
            loadSegment(for: range, voice: voice)
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onSuccess: { [weak self] data in
                        guard let self else { return }
                        loadingSegments.remove(range)
                        // Play immediately
                        handleSpeechSuccess(data: data, range: range)
                        ensureSegmentsPreloaded(after: range, voice: voice)
                    },
                    onFailure: { [weak self] error in
                        self?.loadingSegments.remove(range)
                        self?.handleSpeechFailure(error: error)
                    }
                )
                .disposed(by: disposeBag)

            // Start preloading next segments concurrently
            ensureSegmentsPreloaded(after: range, voice: voice)
        }
    }

    /// Returns the text to synthesize for a page-text range, extracted from the segment that contains it (ranges from
    /// `findNextRange` always lie within a single segment).
    private func loadSegment(for range: NSRange, voice: RemoteVoice) -> Single<Data> {
        guard let segmentText = text(forPageTextRange: range) else {
            return .error(Error.endOfPage)
        }
        return remoteVoicesController.downloadSound(forText: segmentText, voiceId: voice.id)
    }

    private func text(forPageTextRange range: NSRange) -> String? {
        for segment in segments where range.location >= segment.pageOffset && range.location < segment.pageOffset + segment.text.count {
            let intra = NSRange(location: range.location - segment.pageOffset, length: range.length)
            guard let textRange = Range(intra, in: segment.text) else { return nil }
            return String(segment.text[textRange])
        }
        return nil
    }

    private func ensureSegmentsPreloaded(after currentRange: NSRange, voice: RemoteVoice) {
        // Calculate how many more segments we need to preload
        let currentlyBuffered = segmentCache.count + loadingSegments.count
        let segmentsToLoad = Self.preloadAheadCount - currentlyBuffered
        guard segmentsToLoad > 0 else { return }

        var nextIndex = currentRange.location + currentRange.length
        var loaded = 0

        while loaded < segmentsToLoad {
            guard let range = findNextRange(startingAt: nextIndex, voice: voice) else { break }

            // Skip if already cached or being loaded
            if segmentCache[range] != nil || loadingSegments.contains(range) {
                nextIndex = range.location + range.length
                continue
            }

            // Mark as loading and start download
            loadingSegments.insert(range)

            loadSegment(for: range, voice: voice)
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onSuccess: { [weak self] data in
                        guard let self else { return }
                        loadingSegments.remove(range)
                        // Check if this segment was requested for playback while loading
                        if pendingPlaybackRange == range {
                            pendingPlaybackRange = nil
                            handleSpeechSuccess(data: data, range: range)
                        } else {
                            segmentCache[range] = data
                        }
                        ensureSegmentsPreloaded(after: range, voice: voice)
                    },
                    onFailure: { [weak self] error in
                        guard let self else { return }
                        loadingSegments.remove(range)
                        // If this was pending for playback, report the failure
                        if pendingPlaybackRange == range {
                            pendingPlaybackRange = nil
                            handleSpeechFailure(error: error)
                        }
                    }
                )
                .disposed(by: disposeBag)

            nextIndex = range.location + range.length
            loaded += 1
        }
    }

    private func handleSpeechSuccess(data: Data, range: NSRange) {
        // Remove this segment from cache since we're now playing it
        segmentCache.removeValue(forKey: range)
        play(data: data)
    }

    private func handleSpeechFailure(error: Swift.Error) {
        if case Error.endOfPage = error {
            // Reached end of current page, try to go to next page
            // Background task is still active from audioPlayerDidFinishPlaying, keeping us alive for this transition
            if !delegate.goToNextPageIfAvailable() {
                finishSpeaking()
            }
        } else if let responseError = error as? AFResponseError,
                  case .responseValidationFailed(let reason) = responseError.error,
                  case .unacceptableStatusCode(let code) = reason,
                  code == 402 {
            // Out of credits - determine reason from response
            let outOfCreditsReason: SpeechState.OutOfCreditsReason
            if responseError.response.contains("daily_limit_exceeded") {
                outOfCreditsReason = .dailyLimitExceeded
            } else {
                outOfCreditsReason = .quotaExceeded
            }
            updateRemainingTimeDisplay(credits: (standard: 0, premium: 0))
            endBackgroundTask()
            delegate.state.accept(.outOfCredits(outOfCreditsReason))
        } else {
            DDLogError("RemoteVoiceProcessor: can't download sound - \(error)")
            endBackgroundTask()
            delegate.state.accept(.stopped)
        }
    }

    private func play(data: Data) {
        do {
            let audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer.delegate = self
            audioPlayer.enableRate = true
            audioPlayer.rate = speechRateModifier
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            player = audioPlayer
            delegate.state.accept(.speaking)
            // Audio is now playing, safe to end the background task
            endBackgroundTask()
        } catch {
            DDLogError("RemoteVoiceProcessor: can't play audio - \(error)")
            endBackgroundTask()
            delegate.state.accept(.stopped)
        }
    }

    // MARK: - Credits

    private func startCreditPollTimer() {
        guard creditPollTimer == nil else { return }
        // Load credits immediately
        loadCredits()
        // Then poll every 60 seconds
        creditPollTimer = Timer.scheduledTimer(withTimeInterval: Self.creditPollInterval, repeats: true) { [weak self] _ in
            self?.loadCredits()
        }
    }

    private func stopCreditPollTimer() {
        creditPollTimer?.invalidate()
        creditPollTimer = nil
    }

    private func loadCredits() {
        remoteVoicesController.loadCredits()
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] credits in
                    self?.updateRemainingTimeDisplay(credits: credits)
                },
                onFailure: { error in
                    DDLogError("RemoteVoiceProcessor: could not load credits - \(error)")
                }
            )
            .disposed(by: disposeBag)
    }

    private func updateRemainingTimeDisplay(credits: (standard: Int, premium: Int)) {
        guard let voice, voice.tier != .standard else {
            // Standard tier voice - report nil remaining time (unlimited)
            delegate.remainingTime.accept(nil)
            return
        }
        // Select credits based on voice tier
        let tierCredits: Int
        switch voice.tier {
        case .standard:
            tierCredits = credits.standard

        case .premium:
            tierCredits = credits.premium
        }
        // Calculate remaining time from credits (creditsPerMinute means credits per minute of audio)
        let remainingTime = (TimeInterval(tierCredits) / TimeInterval(voice.creditsPerMinute)) * 60
        delegate.remainingTime.accept(remainingTime)
    }

    // MARK: - Helpers

    private func findNextRange(startingAt index: Int, voice: RemoteVoice) -> NSRange? {
        // Segments are the structured-document-text paragraphs; sentences are detected within a single segment.
        if voice.granularity == .sentence {
            return SpeechDocumentParser.sentenceRange(startingAt: index, in: segments)
        }
        return SpeechDocumentParser.paragraphRange(startingAt: index, in: segments)
    }

    private func finishSpeaking() {
        debouncedSpeakWorkItem?.cancel()
        debouncedSpeakWorkItem = nil
        segments = []
        player?.stop()
        player = nil
        segmentCache.removeAll()
        loadingSegments.removeAll()
        pendingPlaybackRange = nil
        shouldReloadOnResume = false
        stopCreditPollTimer()
        endBackgroundTask()
        delegate.state.accept(.stopped)
    }
}

extension RemoteVoiceProcessor: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag, !segments.isEmpty, let voice, let speechRange = delegate.speechRange else {
            finishSpeaking()
            return
        }

        // Keep the app alive while transitioning to the next segment in background
        beginBackgroundTask()
        let nextStartIndex = speechRange.location + speechRange.length

        let delay = voice.sentenceDelay > 0 ? TimeInterval(voice.sentenceDelay) / (1000.0 * TimeInterval(speechRateModifier)) : 0
        if delay == 0 {
            startSpeaking(startIndex: nextStartIndex, voice: voice)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.delegate.state.value.isSpeaking || self.delegate.state.value == .loading else { return }
                self.startSpeaking(startIndex: nextStartIndex, voice: voice)
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Swift.Error)?) {
        DDLogError("RemoteVoiceProcessor: decode error - \(String(describing: error))")
        finishSpeaking()
    }
}

// MARK: - SpeechHighlightSessionManagerDelegate

extension SpeechManager: SpeechHighlightSessionManagerDelegate {
    func highlightSessionSegments(forPage pageIndex: Delegate.Index) -> [SpeechDocumentParser.Segment] {
        return segments(forPage: pageIndex)
    }

    func highlightSessionNextReadablePage(after pageIndex: Delegate.Index) -> Delegate.Index? {
        return nextReadablePage(after: pageIndex)
    }

    func highlightSessionPreviousReadablePage(before pageIndex: Delegate.Index) -> Delegate.Index? {
        return previousReadablePage(before: pageIndex)
    }
}
