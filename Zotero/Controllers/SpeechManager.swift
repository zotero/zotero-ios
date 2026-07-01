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

final class SpeechManager<Delegate: SpeechManagerDelegate>: NSObject, VoiceProcessorDelegate, @unchecked Sendable {
    private enum Error: Swift.Error {
        case cantGetText
    }

    struct SpeechData {
        let index: Delegate.Index
        /// The range of the currently spoken text segment as reported by the voice processor.
        /// Word-level for local voice; sentence- or paragraph-level for remote voice depending on granularity.
        let range: NSRange
        /// The range of the text unit currently highlighted (sentence or paragraph depending on `highlightGranularity`).
        let highlightRange: NSRange
        /// The granularity at which the highlight was computed. Recorded so that a voice/granularity change
        /// can be detected and the highlight recomputed even if the speech position is still within the old range.
        let highlightGranularity: NLTokenUnit

        func copy(range: NSRange, highlightRange: NSRange, highlightGranularity: NLTokenUnit) -> SpeechData {
            return SpeechData(index: index, range: range, highlightRange: highlightRange, highlightGranularity: highlightGranularity)
        }
    }

    private enum NavigationDirection {
        case forward
        case backward
    }

    /// Time window within which a second forward/backward call upgrades the pending sentence skip to a paragraph skip.
    private let navigationMultiTapInterval: TimeInterval = 0.3
    let state: BehaviorRelay<SpeechState>
    let remainingTime: BehaviorRelay<TimeInterval?>
    private let disposeBag: DisposeBag
    private unowned let remoteVoicesController: RemoteVoicesController
    private unowned let documentWorkerController: DocumentWorkerController
    private let nowPlayingManager: NowPlayingManager

    private var processor: VoiceProcessor!
    private var speechData: SpeechData? {
        didSet {
            if let speechData {
                onSpeakingPositionChanged?(speechData.index, speechData.range.location)
            }
        }
    }
    /// Per-page read-aloud text, extracted once for the whole document from structured document text when playback starts.
    private var cachedPages: [Delegate.Index: String]
    /// Per-page paragraph segment ranges (character offsets within the page text), derived from the structured document
    /// text. Used for paragraph-granularity navigation instead of heuristic paragraph detection.
    private var paragraphRanges: [Delegate.Index: [NSRange]]
    /// Whether the whole document has already been extracted and cached. Set once per session; no further data is requested afterwards.
    private var documentLoaded: Bool
    /// Document language (BCP-47 tag) read from the structured document text metadata, if any. Used as the session language.
    private var documentLanguage: String?
    /// Worker used to extract structured document text for the whole document.
    private var speechWorker: DocumentWorkerController.Worker?
    /// Navigation tap waiting for the multi-tap window to elapse. Executed as a sentence skip if no second tap
    /// arrives within `navigationMultiTapInterval`; replaced by a paragraph skip if one does.
    private var pendingNavigation: (direction: NavigationDirection, workItem: DispatchWorkItem)?
    let highlightSessionManager: SpeechHighlightSessionManager<SpeechManager<Delegate>>
    var onHighlightSessionTimedOut: (() -> Void)?
    var onSpeakingPositionChanged: ((Delegate.Index, Int) -> Void)?
    private weak var delegate: Delegate?
    var voice: SpeechVoice? { processor.speechVoice }
    var language: String? { processor.preferredLanguage }
    var speechRateModifier: Float { processor.speechRateModifier }
    var detectedLanguage: String {
        return processor.detectedLanguage ?? "en"
    }
    fileprivate var speechRange: NSRange? {
        return speechData?.range
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
        guard let speechData, let pageText = cachedPages[speechData.index] else { return nil }
        let range = speechData.highlightRange
        guard range.length > 0, let textRange = Range(range, in: pageText) else { return nil }
        let text = String(pageText[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (text, speechData.index, range.location, (pageText as NSString).length)
    }

    init(delegate: Delegate, voiceLanguage: String?, remoteVoiceTier: RemoteVoice.Tier?, remoteVoicesController: RemoteVoicesController, documentWorkerController: DocumentWorkerController) {
        self.delegate = delegate
        self.remoteVoicesController = remoteVoicesController
        self.documentWorkerController = documentWorkerController
        cachedPages = [:]
        paragraphRanges = [:]
        documentLoaded = false
        highlightSessionManager = SpeechHighlightSessionManager<SpeechManager<Delegate>>()
        state = BehaviorRelay(value: .stopped)
        remainingTime = BehaviorRelay(value: nil)
        disposeBag = DisposeBag()
        nowPlayingManager = NowPlayingManager()
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
                    // The extracted document text is kept across stops so playback can restart without re-loading it.
                    speechData = nil
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

    // Start speech
    // - parameter mapStartIndexToPage: Used to map startIndex from PSPDFKit document to the structured-document-text page.
    func start(mapStartIndexToPage: ((String) -> Int)? = nil) {
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
            startPlayback(mapStartIndexToPage: mapStartIndexToPage)
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
                    // Drop the finished one-off worker so a retry creates a fresh one.
                    speechWorker = nil
                    completion(false)

                case .queued, .inProgress:
                    break

                case .extractedData(let data, _):
                    guard let buffer = data["buf"] as? Data else {
                        DDLogError("SpeechManager: structured document text result has unexpected shape - \(data)")
                        speechWorker = nil
                        completion(false)
                        return
                    }
                    // Parsing the whole document can be heavy, so do it off the main thread.
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        let parsed: [Int: SpeechDocumentParser.ParsedPage]
                        let language: String?
                        do {
                            let pack = try SDTPack(data: buffer)
                            let materialized = try pack.materialize()
                            parsed = SpeechDocumentParser.parse(materialized: materialized)
                            language = SpeechDocumentParser.language(from: materialized)
                        } catch {
                            DDLogError("SpeechManager: could not parse structured document text - \(error)")
                            parsed = [:]
                            language = nil
                        }
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            store(parsed: parsed)
                            documentLanguage = language
                            documentLoaded = true
                            DDLogInfo("SpeechManager: extracted structured document text in \(CFAbsoluteTimeGetCurrent() - start)")
                            completion(true)
                        }
                    }
                }
            })
            .disposed(by: disposeBag)
    }

    /// Stores parsed structured document text into the page caches, mapping structured-document-text page indices to
    /// the delegate's page index type.
    private func store(parsed: [Int: SpeechDocumentParser.ParsedPage]) {
        guard let delegate else { return }
        for (sdtPage, page) in parsed {
            guard let index = delegate.pageIndex(forStructuredDocumentTextPage: sdtPage) else { continue }
            cachedPages[index] = page.text
            paragraphRanges[index] = page.paragraphRanges
        }
    }

    private func startPlayback(mapStartIndexToPage: ((String) -> Int)?) {
        guard let delegate else {
            state.accept(.stopped)
            return
        }
        let currentIndex = delegate.getCurrentPageIndex()
        guard let pageIndex = firstReadablePageIndex(atOrAfter: currentIndex), let page = cachedPages[pageIndex] else {
            DDLogWarn("SpeechManager: no readable content to play")
            state.accept(.stopped)
            return
        }
        // Only honor the requested start offset when the readable page is the page the user is on.
        let startIndex = (pageIndex == currentIndex) ? (mapStartIndexToPage?(page) ?? 0) : 0
        startSpeaking(at: startIndex, page: page, pageIndex: pageIndex, reportPageChange: false)
    }

    /// Sets the session language from the document metadata (defaulting to English when absent), so that the voice stays
    /// constant for the whole session. No-op when the user has chosen a language explicitly or it was already set.
    private func applySessionLanguageIfNeeded() {
        guard processor.preferredLanguage == nil, processor.detectedLanguage == nil else { return }
        let language = documentLanguage ?? "en"
        processor.detectedLanguage = language
        DDLogInfo("SpeechManager: using session language \(language) (from document metadata: \(documentLanguage != nil))")
    }

    // Start speech
    // - parameter startIndex: Start speaking at given index.
    func start(startIndex: Int) {
        start(mapStartIndexToPage: { _ in startIndex })
    }

    func pause() {
        processor.pause()
    }

    func resume() {
        if processor.canResume {
            processor.resume()
        } else {
            start()
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
        guard state.value.isSpeaking || state.value.isPaused,
              let speechData,
              let pageText = cachedPages[speechData.index] else { return nil }

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
            position: speechData.range.location,
            pageText: pageText,
            pageIndex: speechData.index
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

    /// Returns the first readable (cached) page index at or after `index`, or nil if there is none.
    private func firstReadablePageIndex(atOrAfter index: Delegate.Index) -> Delegate.Index? {
        if cachedPages[index] != nil {
            return index
        }
        return nextReadablePageIndex(from: index)
    }

    /// Returns the next readable (cached) page index after `index`, skipping pages without readable content, or nil.
    private func nextReadablePageIndex(from index: Delegate.Index) -> Delegate.Index? {
        guard let delegate else { return nil }
        var current = index
        while let next = delegate.getNextPageIndex(from: current) {
            if cachedPages[next] != nil {
                return next
            }
            current = next
        }
        return nil
    }

    /// Returns the previous readable (cached) page index before `index`, skipping pages without readable content, or nil.
    private func previousReadablePageIndex(from index: Delegate.Index) -> Delegate.Index? {
        guard let delegate else { return nil }
        var current = index
        while let previous = delegate.getPreviousPageIndex(from: current) {
            if cachedPages[previous] != nil {
                return previous
            }
            current = previous
        }
        return nil
    }

    /// Returns the paragraph range (from the structured document text) that contains, or most closely precedes, `index`.
    private func paragraphRange(containing index: Int, pageIndex: Delegate.Index) -> NSRange? {
        let ranges = paragraphRanges[pageIndex] ?? []
        var best: NSRange?
        for range in ranges {
            if index >= range.location, index < range.location + range.length {
                return range
            }
            if range.location <= index {
                best = range
            }
        }
        return best ?? ranges.first
    }

    /// Returns the start index of the next paragraph after the one containing `position`, or nil if there is none on this page.
    private func nextParagraphStartIndex(after position: Int, pageIndex: Delegate.Index) -> Int? {
        let ranges = paragraphRanges[pageIndex] ?? []
        guard let current = paragraphRange(containing: position, pageIndex: pageIndex) else {
            return ranges.first?.location
        }
        return ranges.first(where: { $0.location > current.location })?.location
    }

    /// Returns the start index for a backward paragraph skip from `position`: the start of the current paragraph when
    /// `position` is past it, otherwise the start of the previous paragraph. Returns nil at the first paragraph's start.
    private func previousParagraphStartIndex(before position: Int, pageIndex: Delegate.Index) -> Int? {
        let ranges = paragraphRanges[pageIndex] ?? []
        guard let current = paragraphRange(containing: position, pageIndex: pageIndex) else {
            return ranges.last(where: { $0.location < position })?.location
        }
        if position > current.location {
            return current.location
        }
        return ranges.last(where: { $0.location < current.location })?.location
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
        guard let speechData, let currentPage = cachedPages[speechData.index] else { return }

        // Both units come from the structured document text: paragraph boundaries directly, sentences detected within
        // the paragraph that contains them (so a sentence never spans a paragraph boundary).
        let nextIndex: Int?
        if unit == .paragraph {
            nextIndex = nextParagraphStartIndex(after: speechData.range.location, pageIndex: speechData.index)
        } else {
            let currentEndIndex = speechData.range.location + speechData.range.length
            nextIndex = SpeechDocumentParser.nextSentenceStart(after: currentEndIndex, in: currentPage, paragraphRanges: paragraphRanges[speechData.index] ?? [])
        }

        if let index = nextIndex {
            DDLogInfo("SpeechManager: forward to \(index); \(speechData.range.location); \(speechData.range.length)")
            moveTo(index: index, on: currentPage, pageIndex: speechData.index)
            if !state.value.isPaused {
                startSpeaking(at: index, page: currentPage, pageIndex: speechData.index, reportPageChange: false)
            }
            delegate?.focusPage(speechData.index)
        } else if let nextPageIndex = nextReadablePageIndex(from: speechData.index), let page = cachedPages[nextPageIndex] {
            moveTo(index: 0, on: page, pageIndex: nextPageIndex)
            if !state.value.isPaused {
                startSpeaking(page: page, pageIndex: nextPageIndex, reportPageChange: false)
            }
            delegate?.focusPage(nextPageIndex)
        } else {
            stop()
        }
    }

    func backward(by unit: NLTokenUnit) {
        guard let speechData, let currentPage = cachedPages[speechData.index] else { return }

        // Both units come from the structured document text: paragraph boundaries directly, sentences detected within
        // the paragraph that contains them (so a sentence never spans a paragraph boundary).
        let previousIndex: Int?
        if unit == .paragraph {
            previousIndex = previousParagraphStartIndex(before: speechData.range.location, pageIndex: speechData.index)
        } else {
            previousIndex = SpeechDocumentParser.previousSentenceStart(before: speechData.range.location, in: currentPage, paragraphRanges: paragraphRanges[speechData.index] ?? [])
        }

        if let index = previousIndex {
            DDLogInfo("SpeechManager: backward to \(index); \(speechData.range.location); \(speechData.range.length)")
            moveTo(index: index, on: currentPage, pageIndex: speechData.index)
            if !state.value.isPaused {
                startSpeaking(at: index, page: currentPage, pageIndex: speechData.index, reportPageChange: false)
            }
            delegate?.focusPage(speechData.index)
        } else if unit != .paragraph, speechData.range.location != 0 {
            moveTo(index: 0, on: currentPage, pageIndex: speechData.index)
            if !state.value.isPaused {
                startSpeaking(page: currentPage, pageIndex: speechData.index, reportPageChange: false)
            }
            delegate?.focusPage(speechData.index)
        } else if let previousPageIndex = previousReadablePageIndex(from: speechData.index), let previousPage = cachedPages[previousPageIndex] {
            let speechIndex: Int?
            if unit == .paragraph {
                speechIndex = paragraphRanges[previousPageIndex]?.last?.location ?? 0
            } else {
                // Resume at the last sentence of the previous page's last paragraph.
                speechIndex = SpeechDocumentParser.lastSentenceStart(in: previousPage, paragraphRanges: paragraphRanges[previousPageIndex] ?? [])
            }
            if let speechIndex {
                moveTo(index: speechIndex, on: previousPage, pageIndex: previousPageIndex)
                if !state.value.isPaused {
                    startSpeaking(at: speechIndex, page: previousPage, pageIndex: previousPageIndex, reportPageChange: false)
                }
                delegate?.focusPage(previousPageIndex)
            } else {
                stop()
            }
        } else {
            stop()
        }
    }

    private func startSpeaking(at index: Int = 0, page: String, pageIndex: Delegate.Index, reportPageChange: Bool) {
        let previousPageIndex = speechData?.index
        if previousPageIndex != pageIndex {
            speechData = SpeechData(index: pageIndex, range: NSRange(), highlightRange: NSRange(), highlightGranularity: highlightGranularity)
        }
        if reportPageChange, let previousPageIndex {
            delegate?.moved(to: pageIndex, from: previousPageIndex)
        }
        processor.speak(text: page, startIndex: index, paragraphRanges: paragraphRanges[pageIndex] ?? [])
    }

    /// Moves the current speech position without starting playback.
    /// Used when navigating while paused to update the highlight position.
    private func moveTo(index: Int, on page: String, pageIndex: Delegate.Index) {
        guard let sentenceData = TextTokenizer.findSentence(startingAt: index, in: page) else { return }

        let previousPageIndex = speechData?.index
        let pageDidChange = previousPageIndex != pageIndex
        let previousHighlight = speechData.map({ (range: $0.highlightRange, granularity: $0.highlightGranularity) })
        let granularity = highlightGranularity

        // Check if the new position is still within the current highlighted unit (same granularity)
        let isInCurrentHighlight: Bool
        if let previousHighlight, previousHighlight.range.length > 0, previousHighlight.granularity == granularity {
            isInCurrentHighlight = !pageDidChange && NSLocationInRange(index, previousHighlight.range)
        } else {
            isInCurrentHighlight = false
        }

        let newHighlightRange: NSRange
        let highlightText: String?
        if isInCurrentHighlight, let previousHighlight {
            // Still in the same unit, keep the existing range
            newHighlightRange = previousHighlight.range
            highlightText = nil
        } else {
            // Find the full unit (sentence/paragraph) containing this position
            let containingUnit = findHighlightUnit(at: index, in: page, granularity: granularity)
            newHighlightRange = containingUnit?.range ?? sentenceData.range
            highlightText = containingUnit?.text ?? sentenceData.text
        }

        speechData = SpeechData(index: pageIndex, range: sentenceData.range, highlightRange: newHighlightRange, highlightGranularity: granularity)
        processor.invalidateCurrentPlayback()

        // Only notify delegate if the highlight changed
        if let highlightText {
            delegate?.readAloudHighlightChanged(
                text: highlightText,
                pageIndex: pageIndex,
                sourceLocation: newHighlightRange.location,
                sourceTextLength: (page as NSString).length
            )
        }

        if pageDidChange, let previousPageIndex {
            delegate?.moved(to: pageIndex, from: previousPageIndex)
        }
    }

    // MARK: - VoiceProcessorDelegate

    func goToNextPageIfAvailable() -> Bool {
        guard let speechData, let nextIndex = nextReadablePageIndex(from: speechData.index), let page = cachedPages[nextIndex] else {
            return false
        }
        startSpeaking(page: page, pageIndex: nextIndex, reportPageChange: true)
        return true
    }

    func speechRangeWillChange(to range: NSRange) {
        guard let speechData else { return }
        guard let pageText = cachedPages[speechData.index] else { return }

        let granularity = highlightGranularity

        // Check if the new range is still within the current highlighted unit and granularity hasn't changed
        if speechData.highlightGranularity == granularity, NSLocationInRange(range.location, speechData.highlightRange) {
            // Still in the same unit, just update the speech range
            self.speechData = speechData.copy(range: range, highlightRange: speechData.highlightRange, highlightGranularity: granularity)
            return
        }

        // New range is outside the current unit (or granularity changed), find the new unit
        let unitResult = findHighlightUnit(at: range.location, in: pageText, granularity: granularity)
        let newHighlightRange = unitResult?.range ?? range

        // Update speech data with the new range and highlight range
        self.speechData = speechData.copy(range: range, highlightRange: newHighlightRange, highlightGranularity: granularity)

        // Notify delegate of the highlight change
        if let highlightText = unitResult?.text {
            delegate?.readAloudHighlightChanged(
                text: highlightText,
                pageIndex: speechData.index,
                sourceLocation: newHighlightRange.location,
                sourceTextLength: (pageText as NSString).length
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

    /// Starts speaking `text` from `startIndex`. `paragraphRanges` are the structured-document-text paragraph segment
    /// ranges (character offsets) within `text`; processors that segment by paragraph use them instead of re-detecting
    /// boundaries. Processors that speak the whole text at once may ignore them.
    func speak(text: String, startIndex: Int, paragraphRanges: [NSRange])
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

    func speak(text: String, startIndex: Int, paragraphRanges: [NSRange]) {
        // Local voice speaks the whole page as a single utterance, so paragraph ranges are not used here.
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
        speak(text: text, startIndex: speechRange.location, paragraphRanges: [])
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

    private var text: String?
    /// Structured-document-text paragraph segment ranges (character offsets) for the page currently being read.
    /// Used to segment playback by paragraph (and to bound sentences to their paragraph) instead of re-detecting boundaries.
    private var paragraphRanges: [NSRange] = []
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

    func speak(text: String, startIndex: Int, paragraphRanges: [NSRange]) {
        // Immediate: stop current playback and update state
        if self.text != text || startIndex != 0 {
            stopPreloadingAndClearCache()
        }
        self.text = text
        self.paragraphRanges = paragraphRanges
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
            loadVoiceAndStartSpeaking(text: text, startIndex: startIndex)
            return
        }

        // Debounce segment download so rapid forward/backward taps don't trigger multiple network requests
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.loadVoiceAndStartSpeaking(text: text, startIndex: startIndex)
        }
        debouncedSpeakWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func loadVoiceAndStartSpeaking(text: String, startIndex: Int) {
        // Language is detected once at session start, so the voice is resolved only the first time and then reused.
        let getVoice: Single<RemoteVoice>
        if let voice {
            getVoice = Single.just(voice)
        } else {
            getVoice = loadVoice(forText: text)
        }

        getVoice
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] voice in
                    self?.startSpeaking(text: text, startIndex: startIndex, voice: voice)
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
            guard let text, let voice, let speechRange = delegate.speechRange else { return }
            // Clear cache since voice changed
            segmentCache.removeAll()
            loadingSegments.removeAll()
            player.stop()
            self.player = nil
            startSpeaking(text: text, startIndex: speechRange.location, voice: voice)
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

    private func loadVoice(forText text: String) -> Single<RemoteVoice> {
        if let allAvailableVoices {
            return loadVoice(forText: text, language: language, tier: tier, allVoices: allAvailableVoices)
        }
        return remoteVoicesController.loadVoices()
            .do(onSuccess: { [weak self] result in
                self?.allAvailableVoices = result.response
            })
            .flatMap({ [weak self] result in
                guard let self else {
                    return Single.error(Error.cancelled)
                }
                return loadVoice(forText: text, language: language, tier: tier, allVoices: result.response)
            })
            .do(onSuccess: { [weak self] voice in
                self?.voice = voice
            })

        func loadVoice(forText text: String, language: String, tier: RemoteVoice.Tier, allVoices: VoicesResponse) -> Single<RemoteVoice> {
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

    private func startSpeaking(text: String, startIndex: Int, voice: RemoteVoice) {
        // Find the range for the segment at startIndex
        guard let range = findNextRange(startingAt: startIndex, voice: voice, in: text) else {
            handleSpeechFailure(error: Error.endOfPage)
            return
        }

        // Report the range immediately so the highlight updates without waiting for audio to load
        delegate.speechRangeWillChange(to: range)

        // Check if we already have the segment cached
        if let cachedData = segmentCache[range] {
            handleSpeechSuccess(data: cachedData, range: range)
            ensureSegmentsPreloaded(after: range, text: text, voice: voice)
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
        loadAndPlaySegment(range: range, text: text, voice: voice)

        func loadAndPlaySegment(range: NSRange, text: String, voice: RemoteVoice) {
            // Mark as loading
            loadingSegments.insert(range)

            // Start loading the segment we need to play
            loadSegment(for: range, in: text, voice: voice)
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onSuccess: { [weak self] data in
                        guard let self else { return }
                        loadingSegments.remove(range)
                        // Play immediately
                        handleSpeechSuccess(data: data, range: range)
                        ensureSegmentsPreloaded(after: range, text: text, voice: voice)
                    },
                    onFailure: { [weak self] error in
                        self?.loadingSegments.remove(range)
                        self?.handleSpeechFailure(error: error)
                    }
                )
                .disposed(by: disposeBag)

            // Start preloading next segments concurrently
            ensureSegmentsPreloaded(after: range, text: text, voice: voice)
        }
    }

    private func loadSegment(for range: NSRange, in text: String, voice: RemoteVoice) -> Single<Data> {
        guard let textRange = Range(range, in: text) else {
            return .error(Error.endOfPage)
        }
        let segmentText = String(text[textRange])
        return remoteVoicesController.downloadSound(forText: segmentText, voiceId: voice.id)
    }

    private func ensureSegmentsPreloaded(after currentRange: NSRange, text: String, voice: RemoteVoice) {
        // Calculate how many more segments we need to preload
        let currentlyBuffered = segmentCache.count + loadingSegments.count
        let segmentsToLoad = Self.preloadAheadCount - currentlyBuffered
        guard segmentsToLoad > 0 else { return }

        var nextIndex = currentRange.location + currentRange.length
        var loaded = 0

        while loaded < segmentsToLoad {
            guard let range = findNextRange(startingAt: nextIndex, voice: voice, in: text) else { break }

            // Skip if already cached or being loaded
            if segmentCache[range] != nil || loadingSegments.contains(range) {
                nextIndex = range.location + range.length
                continue
            }

            // Mark as loading and start download
            loadingSegments.insert(range)

            loadSegment(for: range, in: text, voice: voice)
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
                        ensureSegmentsPreloaded(after: range, text: text, voice: voice)
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

    private func findNextRange(startingAt index: Int, voice: RemoteVoice, in text: String) -> NSRange? {
        // Paragraph boundaries come from the structured document text; sentences are detected within a paragraph.
        if voice.granularity == .sentence {
            return SpeechDocumentParser.sentenceSegment(startingAt: index, in: text, paragraphRanges: paragraphRanges)
        }
        return SpeechDocumentParser.paragraphSegment(startingAt: index, in: paragraphRanges)
    }

    private func finishSpeaking() {
        debouncedSpeakWorkItem?.cancel()
        debouncedSpeakWorkItem = nil
        text = nil
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
        guard flag, let text, let voice, let speechRange = delegate.speechRange else {
            finishSpeaking()
            return
        }

        // Keep the app alive while transitioning to the next segment in background
        beginBackgroundTask()
        let nextStartIndex = speechRange.location + speechRange.length

        let delay = voice.sentenceDelay > 0 ? TimeInterval(voice.sentenceDelay) / (1000.0 * TimeInterval(speechRateModifier)) : 0
        if delay == 0 {
            startSpeaking(text: text, startIndex: nextStartIndex, voice: voice)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.delegate.state.value.isSpeaking || self.delegate.state.value == .loading else { return }
                self.startSpeaking(text: text, startIndex: nextStartIndex, voice: voice)
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
    func highlightSessionNextPageData(from pageIndex: Delegate.Index) -> (pageText: String, pageIndex: Delegate.Index)? {
        guard let nextIndex = nextReadablePageIndex(from: pageIndex),
              let text = cachedPages[nextIndex] else { return nil }
        return (text, nextIndex)
    }

    func highlightSessionPreviousPageData(from pageIndex: Delegate.Index) -> (pageText: String, pageIndex: Delegate.Index)? {
        guard let prevIndex = previousReadablePageIndex(from: pageIndex),
              let text = cachedPages[prevIndex] else { return nil }
        return (text, prevIndex)
    }
}
