//
//  SpeechManager.swift
//  Zotero
//
//  Created by Michal Rentka on 11.03.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation
import NaturalLanguage

import Alamofire
import CocoaLumberjackSwift
import RxCocoa
import RxSwift

protocol SpeechManagerDelegate: AnyObject {
    associatedtype Index: Hashable

    func getCurrentPageIndex() -> Index
    func getNextPageIndex(from currentPageIndex: Index) -> Index?
    func getPreviousPageIndex(from currentPageIndex: Index) -> Index?
    func text(for indices: [Index], completion: @escaping ([Index: String]?) -> Void)
    func moved(to pageIndex: Index)
    /// Called when the speech range changes during text-to-speech playback
    /// - Parameters:
    ///   - text: The text currently being spoken
    ///   - pageIndex: The page index where the text is located
    func speechTextChanged(text: String, pageIndex: Index)
}

enum SpeechState {
    case speaking, paused, stopped, loading, outOfCredits

    var isStopped: Bool {
        switch self {
        case .speaking, .loading, .paused, .outOfCredits:
            return false

        case .stopped:
            return true
        }
    }
    
    var isPaused: Bool {
        switch self {
        case .speaking, .loading, .stopped, .outOfCredits:
            return false

        case .paused:
            return true
        }
    }
    
    var isSpeaking: Bool {
        switch self {
        case .stopped, .loading, .paused, .outOfCredits:
            return false

        case .speaking:
            return true
        }
    }
}

enum SpeechVoice {
    case local(AVSpeechSynthesisVoice)
    case remote(RemoteVoice)
}

final class SpeechManager<Delegate: SpeechManagerDelegate>: NSObject, VoiceProcessorDelegate {
    private enum Error: Swift.Error {
        case cantGetText
    }

    struct SpeechData {
        let index: Delegate.Index
        let range: NSRange

        func copy(range: NSRange) -> SpeechData {
            return SpeechData(index: index, range: range)
        }
    }

    let state: BehaviorRelay<SpeechState>
    let remainingTime: BehaviorRelay<TimeInterval?>
    private let disposeBag: DisposeBag
    private unowned let remoteVoicesController: RemoteVoicesController
    
    private var processor: VoiceProcessor!
    private var speechData: SpeechData?
    private var cachedPages: [Delegate.Index: String]
    private weak var delegate: Delegate?
    var voice: SpeechVoice? { processor.speechVoice }
    var language: String? { processor.preferredLanguage }
    var speechRateModifier: Float { processor.speechRateModifier }
    var detectedLanguage: String {
        guard let text = speechData.flatMap({ cachedPages[$0.index] }) else { return "en" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }
    fileprivate var speechRange: NSRange? {
        return speechData?.range
    }

    init(delegate: Delegate, voiceLanguage: String?, useRemoteVoices: Bool, remoteVoicesController: RemoteVoicesController) {
        self.delegate = delegate
        self.remoteVoicesController = remoteVoicesController
        cachedPages = [:]
        state = BehaviorRelay(value: .loading)
        remainingTime = BehaviorRelay(value: nil)
        disposeBag = DisposeBag()
        super.init()
        if useRemoteVoices {
            processor = RemoteVoiceProcessor(language: voiceLanguage, speechRateModifier: 1, delegate: self, remoteVoicesController: remoteVoicesController)
        } else {
            processor = LocalVoiceProcessor(language: voiceLanguage, speechRateModifier: 1, delegate: self)
        }
        processor.speechRateModifier = speechRateModifier
        
        state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                if let self, state.isStopped {
                    speechData = nil
                    cachedPages = [:]
                }
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Actions

    func start() {
        guard let delegate else {
            DDLogError("SpeechManager: can't get delegate")
            return
        }

        let index = delegate.getCurrentPageIndex()
        if let page = cachedPages[index] {
            startSpeaking(page: page, pageIndex: index, reportPageChange: false)
            return
        }

        state.accept(.loading)
        getData(for: [index], from: delegate) { [weak self] pages in
            guard let self, let pages, let page = pages[index] else {
                self?.state.accept(.stopped)
                return
            }
            cachedPages = pages
            guard state.value == .loading else { return }
            startSpeaking(page: page, pageIndex: index, reportPageChange: false)
        }
    }
    
    func pause() {
        processor.pause()
    }

    func resume() {
        processor.resume()
    }

    func stop() {
        processor.stop()
    }

    func set(voice: SpeechVoice, voiceLanguage: String, preferredLanguage: String?) {
        switch voice {
        case .local(let voice):
            if let processor = processor as? LocalVoiceProcessor {
                processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
            } else {
                let _processor = LocalVoiceProcessor(
                    language: preferredLanguage,
                    speechRateModifier: processor.speechRateModifier,
                    delegate: self
                )
                _processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
                // TODO: - start speaking?
                processor = _processor
                remainingTime.accept(nil)
            }
            
        case .remote(let voice):
            if let processor = processor as? RemoteVoiceProcessor {
                processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
            } else {
                let _processor = RemoteVoiceProcessor(
                    language: preferredLanguage,
                    speechRateModifier: processor.speechRateModifier,
                    delegate: self,
                    remoteVoicesController: remoteVoicesController
                )
                _processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
                // TODO: - start speaking?
                processor = _processor
            }
        }
    }

    func set(rateModifier: Float) {
        processor.speechRateModifier = rateModifier
    }

    private func getData(for indices: [Delegate.Index], from delegate: Delegate, completion: @escaping (([Delegate.Index: String])?) -> Void) {
        delegate.text(for: indices) { texts in
            guard let texts, texts.count == indices.count else {
                completion(nil)
                return
            }
            completion(texts)
        }
    }

    func forward(by unit: NLTokenUnit) {
        guard let speechData, let currentPage = cachedPages[speechData.index] else { return }

        let currentEndIndex = speechData.range.location + speechData.range.length
        if let index = TextTokenizer.findIndex(ofNext: unit, startingAt: currentEndIndex, in: currentPage) {
            DDLogInfo("SpeechManager: forward to \(index); \(speechData.range.location); \(speechData.range.length)")
            if state.value.isPaused {
                moveTo(index: index, on: currentPage, pageIndex: speechData.index)
            } else {
                startSpeaking(at: index, on: currentPage)
            }
        } else if let nextIndex = delegate?.getNextPageIndex(from: speechData.index), let page = cachedPages[nextIndex] {
            if state.value.isPaused {
                moveTo(index: 0, on: page, pageIndex: nextIndex)
            } else {
                startSpeaking(page: page, pageIndex: nextIndex)
            }
        } else {
            stop()
        }
    }

    func backward(by unit: NLTokenUnit) {
        guard let speechData, let currentPage = cachedPages[speechData.index] else { return }
  
        if let index = TextTokenizer.findIndex(ofPreviousWhole: unit, beforeIndex: speechData.range.location, in: currentPage) {
            DDLogInfo("SpeechManager: backward to \(index); \(speechData.range.location); \(speechData.range.length)")
            if state.value.isPaused {
                moveTo(index: index, on: currentPage, pageIndex: speechData.index)
            } else {
                startSpeaking(at: index, on: currentPage)
            }
        } else if speechData.range.location != 0 {
            if state.value.isPaused {
                moveTo(index: 0, on: currentPage, pageIndex: speechData.index)
            } else {
                startSpeaking(at: 0, on: currentPage)
            }
        } else if let previousIndex = delegate?.getPreviousPageIndex(from: speechData.index),
                  let previousPage = cachedPages[previousIndex],
                  let speechIndex = TextTokenizer.findIndex(ofPreviousWhole: unit, beforeIndex: previousPage.count, in: previousPage) {
            if state.value.isPaused {
                moveTo(index: speechIndex, on: previousPage, pageIndex: previousIndex)
            } else {
                startSpeaking(page: previousPage, pageIndex: previousIndex, speechStartIndex: speechIndex)
            }
        } else {
            stop()
        }
    }
    
    private func startSpeaking(at index: Int, on page: String) {
        processor.speak(text: page, startIndex: index, shouldDetectVoice: false)
    }

    private func startSpeaking(page: String, pageIndex: Delegate.Index, speechStartIndex: Int? = nil, reportPageChange: Bool = true) {
        speechData = SpeechData(index: pageIndex, range: NSRange())
        processor.speak(text: page, startIndex: speechStartIndex ?? 0, shouldDetectVoice: true)
        if reportPageChange {
            delegate?.moved(to: pageIndex)
        }
        cacheAdjacentPages(for: pageIndex)
    }
    
    /// Moves the current speech position without starting playback.
    /// Used when navigating while paused to update the highlight position.
    private func moveTo(index: Int, on page: String, pageIndex: Delegate.Index) {
        guard let data = TextTokenizer.findSentence(startingAt: index, in: page) else { return }
        let pageDidChange = speechData?.index != pageIndex
        speechData = SpeechData(index: pageIndex, range: data.range)
        processor.invalidateCurrentPlayback()
        delegate?.speechTextChanged(text: data.text, pageIndex: pageIndex)
        if pageDidChange {
            delegate?.moved(to: pageIndex)
            cacheAdjacentPages(for: pageIndex)
        }
    }

    private func cacheAdjacentPages(for pageIndex: Delegate.Index) {
        guard let delegate else { return }
        var indices: [Delegate.Index] = []
        if let index = delegate.getPreviousPageIndex(from: pageIndex), cachedPages[index] == nil {
            indices.append(index)
        }
        if let index = delegate.getNextPageIndex(from: pageIndex), cachedPages[index] == nil {
            indices.append(index)
        }
        if !indices.isEmpty {
            getData(for: indices, from: delegate) { [weak self] pages in
                guard let self else { return }
                for (index, page) in pages ?? [:] {
                    cachedPages[index] = page
                }
            }
        }
    }
    
    // MARK: - VoiceProcessorDelegate

    func goToNextPageIfAvailable() -> Bool {
        guard let speechData, let nextIndex = delegate?.getNextPageIndex(from: speechData.index), let page = cachedPages[nextIndex] else {
            return false
        }
        startSpeaking(page: page, pageIndex: nextIndex)
        return true
    }
    
    func speechRangeWillChange(to range: NSRange) {
        guard let speechData else { return }
        self.speechData = speechData.copy(range: range)
        
        // Extract the actual text being spoken and pass it to the delegate
        if let pageText = cachedPages[speechData.index],
           let textRange = Range(range, in: pageText) {
            let spokenText = String(pageText[textRange])
            delegate?.speechTextChanged(text: spokenText, pageIndex: speechData.index)
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
    var speechRateModifier: Float { get set }
    
    func speak(text: String, startIndex: Int, shouldDetectVoice: Bool)
    func pause()
    func resume()
    func stop()
    /// Called when the speech position changes while paused (e.g., via forward/backward navigation).
    /// The processor should invalidate current playback state so that resume() starts from the new position.
    func invalidateCurrentPlayback()
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
    private var voice: AVSpeechSynthesisVoice?
    private var shouldReloadUtteranceOnResume = false
    private var ignoreFinishCallCount = 0
    var speechRateModifier: Float {
        didSet {
            utteranceChanged()
        }
    }
    var speechVoice: SpeechVoice? {
        return voice.flatMap({ .local($0) })
    }

    init(language: String?, speechRateModifier: Float, delegate: VoiceProcessorDelegate) {
        preferredLanguage = language
        self.speechRateModifier = speechRateModifier
        self.delegate = delegate
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, startIndex: Int, shouldDetectVoice: Bool) {
        if synthesizer.isSpeaking {
            ignoreFinishCallCount += 1
            synthesizer.stopSpeaking(at: .immediate)
        }

        self.text = text
        self.utteranceStartIndex = startIndex
        let remainingText = String(text[text.index(text.startIndex, offsetBy: startIndex)..<text.endIndex])

        if voice == nil || shouldDetectVoice {
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
        guard synthesizer.isSpeaking || synthesizer.isPaused || delegate.state.value == .loading else { return }
        if delegate.state.value == .loading {
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

    func set(voice: AVSpeechSynthesisVoice, voiceLanguage: String, preferredLanguage: String?) {
        guard self.voice?.identifier != voice.identifier else { return }
        Defaults.shared.defaultLocalVoiceForLanguage[voiceLanguage] = voice.identifier
        Defaults.shared.isUsingRemoteVoice = false
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
        speak(text: text, startIndex: speechRange.location, shouldDetectVoice: false)
    }

    private func voice(for text: String) -> AVSpeechSynthesisVoice {
        if let preferredLanguage {
            return findVoice(for: preferredLanguage)
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage?.rawValue ?? "en"
        return findVoice(for: language)
    }

    private func findVoice(for language: String) -> AVSpeechSynthesisVoice {
        let voiceId = Defaults.shared.defaultLocalVoiceForLanguage[language]
        return AVSpeechSynthesisVoice.speechVoices().first(where: isProperVoice) ?? AVSpeechSynthesisVoice(identifier: "en-US")!

        func isProperVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
            if let voiceId {
                return voice.identifier == voiceId
            }
            return voice.language.starts(with: language)
        }
    }
    
    private func finishSpeaking() {
        text = nil
        utteranceStartIndex = 0
        voice = nil
        shouldReloadUtteranceOnResume = false
        ignoreFinishCallCount = 0
        delegate.state.accept(.stopped)
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
        delegate.state.accept(.speaking)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        delegate.state.accept(.speaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard ignoreFinishCallCount <= 0 else {
            ignoreFinishCallCount -= 1
            return
        }

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

    struct VoiceData {
        let voice: RemoteVoice
        let language: String
    }

    /// Number of segments to keep preloaded ahead of current playback
    private static let preloadAheadCount = 2
    /// Interval for polling remaining credits from the server
    private static let creditPollInterval: TimeInterval = 60
    
    private unowned let delegate: VoiceProcessorDelegate
    private unowned let remoteVoicesController: RemoteVoicesController

    private var text: String?
    private(set) var preferredLanguage: String?
    private var voiceData: VoiceData?
    private var player: AVAudioPlayer?
    private var availableVoices: [RemoteVoice]?
    private var disposeBag = DisposeBag()
    /// Cache of downloaded audio data keyed by their text range
    private var segmentCache: [NSRange: Data] = [:]
    /// Set of ranges currently being loaded
    private var loadingSegments: Set<NSRange> = []
    /// Range that should start playing as soon as it's loaded (when waiting for an in-progress preload)
    private var pendingPlaybackRange: NSRange?
    private var shouldReloadOnResume = false
    private var creditPollTimer: Timer?
    var speechRateModifier: Float
    var speechVoice: SpeechVoice? {
        return voiceData.flatMap({ .remote($0.voice) })
    }

    init(language: String?, speechRateModifier: Float, delegate: VoiceProcessorDelegate, remoteVoicesController: RemoteVoicesController) {
        preferredLanguage = language
        self.speechRateModifier = speechRateModifier
        self.delegate = delegate
        self.remoteVoicesController = remoteVoicesController
        super.init()
    }
    
    // MARK: - Actions

    func set(voice: RemoteVoice, voiceLanguage: String, preferredLanguage: String?) {
        let voiceChanged = self.voiceData?.voice.id != voice.id
        self.preferredLanguage = preferredLanguage
        self.voiceData = VoiceData(voice: voice, language: voiceLanguage)
        Defaults.shared.defaultRemoteVoiceForLanguage[voiceLanguage] = voice
        Defaults.shared.isUsingRemoteVoice = true
        
        if voiceChanged {
            stopPreloadingAndClearCache()
            delegate.remainingTime.accept(nil)
            if voice.creditsPerSecond > 0 {
                loadCredits()
            }
            if let player {
                if player.isPlaying {
                    player.pause()
                }
                shouldReloadOnResume = true
            }
        }
    }

    func speak(text: String, startIndex: Int, shouldDetectVoice: Bool) {
        // Clear preload cache if text changed (new page) or skipping within same text (forward/backward)
        if self.text != text || startIndex != 0 {
            stopPreloadingAndClearCache()
        }
        self.text = text
        if player?.isPlaying == true {
            player?.stop()
        }
        player = nil
        disposeBag = DisposeBag()

        let getVoice: Single<VoiceData>
        if let voiceData, !shouldDetectVoice {
            getVoice = Single.just(voiceData)
        } else {
            getVoice = loadVoice(forText: text)
        }

        getVoice
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] voiceData in
                    self?.startSpeaking(text: text, startIndex: startIndex, voiceData: voiceData)
                },
                onFailure: { [weak self] error in
                    self?.handleSpeechFailure(error: error)
                }
            )
            .disposed(by: disposeBag)
    }

    func pause() {
        guard player?.isPlaying == true else { return }
        player?.pause()
        stopCreditPollTimer()
        delegate.state.accept(.paused)
    }

    func resume() {
        guard let player, delegate.state.value == .paused || delegate.state.value == .outOfCredits else { return }
        
        if shouldReloadOnResume {
            shouldReloadOnResume = false
            reloadCurrentSegment()
        } else {
            player.play()
            delegate.state.accept(.speaking)
            startCreditPollTimer()
        }
        
        func reloadCurrentSegment() {
            guard let text, let voiceData, let speechRange = delegate.speechRange else { return }
            // Clear cache since voice changed
            segmentCache.removeAll()
            loadingSegments.removeAll()
            player.stop()
            self.player = nil
            startSpeaking(text: text, startIndex: speechRange.location, voiceData: voiceData)
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
    
    // MARK: - Voices
    
    private func loadVoice(forText text: String) -> Single<VoiceData> {
        if let availableVoices, !availableVoices.isEmpty {
            return loadVoice(forText: text, voices: availableVoices, preferredLanguage: preferredLanguage)
        }
        return remoteVoicesController.loadVoices()
            .do(onSuccess: { [weak self] voices in
                self?.availableVoices = voices
            })
            .flatMap({ [weak self] voices in
                guard let self else {
                    return Single.error(Error.cancelled)
                }
                return loadVoice(forText: text, voices: voices, preferredLanguage: preferredLanguage)
            })
            .do(onSuccess: { [weak self] voiceData in
                self?.voiceData = voiceData
            })
        
        func loadVoice(forText text: String, voices: [RemoteVoice], preferredLanguage: String?) -> Single<VoiceData> {
            return Single.create { subscriber in
                guard !voices.isEmpty else {
                    subscriber(.failure(Error.missingVoices))
                    return Disposables.create()
                }
                
                if let preferredLanguage {
                    subscriber(.success(VoiceData(voice: findVoice(for: preferredLanguage), language: preferredLanguage)))
                } else {
                    let recognizer = NLLanguageRecognizer()
                    recognizer.processString(text)
                    let language = recognizer.dominantLanguage?.rawValue ?? "en"
                    subscriber(.success(VoiceData(voice: findVoice(for: language), language: language)))
                }
                
                return Disposables.create()
            }
            
            func findVoice(for language: String) -> RemoteVoice {
                if let voice = Defaults.shared.defaultRemoteVoiceForLanguage[language] {
                    return voice
                }
                return voices.first(where: { voice in voice.locales.contains(where: { $0.contains(language) }) }) ?? voices[0]
            }
        }
    }
    
    // MARK: - Speech
    
    private func startSpeaking(text: String, startIndex: Int, voiceData: VoiceData) {
        // Find the range for the segment at startIndex
        guard let range = findNextRange(startingAt: startIndex, voiceData: voiceData, in: text) else {
            handleSpeechFailure(error: Error.endOfPage)
            return
        }

        // Check if we already have the segment cached
        if let cachedData = segmentCache[range] {
            handleSpeechSuccess(data: cachedData, range: range)
            ensureSegmentsPreloaded(after: range, text: text, voiceData: voiceData)
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
        loadAndPlaySegment(range: range, text: text, voiceData: voiceData)
        
        func loadAndPlaySegment(range: NSRange, text: String, voiceData: VoiceData) {
            // Mark as loading
            loadingSegments.insert(range)
            
            // Start loading the segment we need to play
            loadSegment(for: range, in: text, voiceData: voiceData)
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onSuccess: { [weak self] data in
                        guard let self else { return }
                        loadingSegments.remove(range)
                        // Play immediately
                        handleSpeechSuccess(data: data, range: range)
                        ensureSegmentsPreloaded(after: range, text: text, voiceData: voiceData)
                    },
                    onFailure: { [weak self] error in
                        self?.loadingSegments.remove(range)
                        self?.handleSpeechFailure(error: error)
                    }
                )
                .disposed(by: disposeBag)
            
            // Start preloading next segments concurrently
            ensureSegmentsPreloaded(after: range, text: text, voiceData: voiceData)
        }
    }

    private func loadSegment(for range: NSRange, in text: String, voiceData: VoiceData) -> Single<Data> {
        guard let textRange = Range(range, in: text) else {
            return .error(Error.endOfPage)
        }
        let segmentText = String(text[textRange])
        
        return remoteVoicesController.downloadSound(forText: segmentText, voiceId: voiceData.voice.id, language: voiceData.language)
    }
    
    private func ensureSegmentsPreloaded(after currentRange: NSRange, text: String, voiceData: VoiceData) {
        // Calculate how many more segments we need to preload
        let currentlyBuffered = segmentCache.count + loadingSegments.count
        let segmentsToLoad = Self.preloadAheadCount - currentlyBuffered
        guard segmentsToLoad > 0 else { return }
        
        var nextIndex = currentRange.location + currentRange.length
        var loaded = 0
        
        while loaded < segmentsToLoad {
            guard let range = findNextRange(startingAt: nextIndex, voiceData: voiceData, in: text) else { break }
            
            // Skip if already cached or being loaded
            if segmentCache[range] != nil || loadingSegments.contains(range) {
                nextIndex = range.location + range.length
                continue
            }
            
            // Mark as loading and start download
            loadingSegments.insert(range)
            
            loadSegment(for: range, in: text, voiceData: voiceData)
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
                        ensureSegmentsPreloaded(after: range, text: text, voiceData: voiceData)
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
        delegate.speechRangeWillChange(to: range)
        play(data: data)
    }
    
    private func handleSpeechFailure(error: Swift.Error) {
        if case Error.endOfPage = error {
            // Reached end of current page, try to go to next page
            if !delegate.goToNextPageIfAvailable() {
                finishSpeaking()
            }
        } else if let responseError = error as? AFResponseError,
                  case .responseValidationFailed(let reason) = responseError.error,
                  case .unacceptableStatusCode(let code) = reason,
                  code == 402 {
            // Out of credits - update state
            updateRemainingTimeDisplay(credits: 0)
            delegate.state.accept(.outOfCredits)
        } else {
            DDLogError("RemoteVoiceProcessor: can't download sound - \(error)")
            delegate.state.accept(.stopped)
        }
    }
    
    private func play(data: Data) {
        do {
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            delegate.state.accept(.speaking)
        } catch {
            DDLogError("RemoteVoiceProcessor: can't play audio - \(error)")
            delegate.state.accept(.stopped)
        }
    }
    
    // MARK: - Credits
    
    private func startCreditPollTimer() {
        guard voiceData?.voice.creditsPerSecond ?? 0 > 0, creditPollTimer == nil else { return }
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
    
    private func updateRemainingTimeDisplay(credits: Int) {
        guard let creditsPerSecond = voiceData?.voice.creditsPerSecond, creditsPerSecond > 0 else {
            // Unlimited voice - report nil remaining time
            delegate.remainingTime.accept(nil)
            return
        }
        // Calculate remaining time from credits
        let remainingTime = TimeInterval(credits) / TimeInterval(creditsPerSecond)
        delegate.remainingTime.accept(remainingTime)
    }
    
    // MARK: - Helpers
    
    private func findNextRange(startingAt index: Int, voiceData: VoiceData, in text: String) -> NSRange? {
        let result: (text: String, range: NSRange)?
        if voiceData.voice.granularity == .sentence {
            result = TextTokenizer.findSentence(startingAt: index, in: text)
        } else {
            result = TextTokenizer.findParagraph(startingAt: index, in: text)
        }
        return result?.range
    }
    
    private func finishSpeaking() {
        text = nil
        player?.stop()
        player = nil
        segmentCache.removeAll()
        loadingSegments.removeAll()
        pendingPlaybackRange = nil
        shouldReloadOnResume = false
        stopCreditPollTimer()
        delegate.state.accept(.stopped)
    }
}

extension RemoteVoiceProcessor: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag, let text, let voiceData, let speechRange = delegate.speechRange else {
            finishSpeaking()
            return
        }

        let nextStartIndex = speechRange.location + speechRange.length
        startSpeaking(text: text, startIndex: nextStartIndex, voiceData: voiceData)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Swift.Error)?) {
        DDLogError("RemoteVoiceProcessor: decode error - \(String(describing: error))")
        finishSpeaking()
    }
}
