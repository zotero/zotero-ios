//
//  SpeechManager.swift
//  Zotero
//
//  Created by Michal Rentka on 11.03.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation
import NaturalLanguage

import CocoaLumberjackSwift
import RxCocoa
import RxSwift

protocol SpeechmanagerDelegate: AnyObject {
    associatedtype Index

    func getCurrentPageIndex() -> Index
    func getNextPageIndex(from currentPageIndex: Index) -> Index?
    func getPreviousPageIndex(from currentPageIndex: Index) -> Index?
    func text(for pageIndex: Index, completion: @escaping (String?) -> Void)
    func moved(to pageIndex: Index)
}

final class SpeechManager<Delegate: SpeechmanagerDelegate>: NSObject, AVSpeechSynthesizerDelegate {
    enum State {
        case speaking, paused, stopped, loading
    }
    
    private enum Error: Swift.Error {
        case cantGetText
    }

    private struct SpeechData {
        let startIndex: Int
        let speakingRange: NSRange

        func copy(with localRange: NSRange) -> SpeechData {
            return SpeechData(startIndex: startIndex, speakingRange: localRange)
        }

        var globalRange: NSRange {
            return NSRange(location: startIndex + speakingRange.location, length: speakingRange.length)
        }
    }

    private struct PageData {
        // Index in given document
        let index: Delegate.Index
        // Threshold which marks ending of this page, when new page should be loaded
        let threshold: Int
        // Voice used for this page
        let voice: AVSpeechSynthesisVoice
        // Text to read
        let text: String

        init(index: Delegate.Index, text: String, voice: AVSpeechSynthesisVoice) {
            self.index = index
            self.voice = voice
            self.text = text
            threshold = Int(Double(text.count) * 0.75)
        }
    }

    private let synthetizer: AVSpeechSynthesizer
    let state: BehaviorRelay<State>
    private let disposeBag: DisposeBag

    private var speech: SpeechData?
    private var page: PageData?
    private var enqueuedNextPage: BehaviorSubject<PageData?>?
    private var ignoreFinishCallCount = 0
    private weak var delegate: Delegate?
    private lazy var paragraphRegex: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: "(?:[^\r\n]+(?:\r?\n(?!\r?\n))*)")
    }()
    var isSpeaking: Bool {
        return synthetizer.isSpeaking
    }

    init(delegate: Delegate) {
        synthetizer = AVSpeechSynthesizer()
        state = BehaviorRelay(value: .stopped)
        disposeBag = DisposeBag()
        self.delegate = delegate
        super.init()
        synthetizer.delegate = self
    }

    // MARK: - Actions

    func start() {
        guard let delegate else {
            DDLogError("SpeechManager: can't get delegate")
            return
        }
        
        state.accept(.loading)
        
        let page = delegate.getCurrentPageIndex()
        getData(for: page, from: delegate) { [weak self] data in
            guard let self, let data else {
                self?.state.accept(.stopped)
                return
            }
            go(to: PageData(index: page, text: data.0, voice: data.1), reportPageChange: false)
        }

        func getData(for page: Delegate.Index, from delegate: Delegate, completion: @escaping ((String, AVSpeechSynthesisVoice)?) -> Void) {
            delegate.text(for: page) { text in
                guard let text else {
                    completion(nil)
                    return
                }
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)
                let language = recognizer.dominantLanguage?.rawValue
                let voice = language.flatMap({ findVoice(for: $0) }) ?? AVSpeechSynthesisVoice(identifier: "en-US")!
                completion((text, voice))
            }

            func findVoice(for language: String) -> AVSpeechSynthesisVoice? {
                return AVSpeechSynthesisVoice.speechVoices().first { $0.language.starts(with: language) }
            }
        }
    }
    
    func pause() {
        guard synthetizer.isSpeaking else { return }
        state.accept(.paused)
        synthetizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthetizer.isPaused else { return }
        synthetizer.continueSpeaking()
    }

    func stop() {
        synthetizer.stopSpeaking(at: .immediate)
    }

    private func go(to page: PageData, index: Int? = nil, reportPageChange: Bool = true) {
        self.page = page
        speech = SpeechData(startIndex: index ?? 0, speakingRange: NSRange(location: 0, length: 0))
        let text: String
        if let index {
            text = String(page.text[page.text.index(page.text.startIndex, offsetBy: index)..<page.text.endIndex])
        } else {
            text = page.text
        }
        speak(text: text, voice: page.voice)
        guard reportPageChange else { return }
        delegate?.moved(to: page.index)
    }

    private func skip(to index: Int, on page: PageData) {
        speech = SpeechData(startIndex: index, speakingRange: NSRange(location: 0, length: 0))
        let text = page.text[page.text.index(page.text.startIndex, offsetBy: index)..<page.text.endIndex]
        speechSynthesizer(synthetizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 0), utterance: AVSpeechUtterance())
        speak(text: String(text), voice: page.voice)
    }

    private func speak(text: String, voice: AVSpeechSynthesisVoice) {
        if synthetizer.isSpeaking {
            ignoreFinishCallCount += 1
            synthetizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        state.accept(.speaking)
        synthetizer.speak(utterance)
    }
    
    private func preloadText(for page: Delegate.Index, voice: AVSpeechSynthesisVoice, delegate: Delegate) -> BehaviorSubject<PageData?> {
        let subject = BehaviorSubject<PageData?>(value: nil)
        delegate.text(for: page) { [weak subject] text in
            if let text {
                subject?.on(.next(PageData(index: page, text: text, voice: voice)))
            } else {
                subject?.on(.error(Error.cantGetText))
            }
        }
        return subject
    }
    
    private func loadEnqueuedPage(_ page: BehaviorSubject<PageData?>, cleanPage: @escaping () -> Void) {
        page.subscribe(
            onNext: { [weak self] page in
                guard let self else { return }
                if let page {
                    cleanPage()
                    go(to: page)
                } else {
                    state.accept(.loading)
                }
            },
            onError: { [weak self] _ in
                guard let self else { return }
                cleanup()
                state.accept(.stopped)
            }
        )
        .disposed(by: disposeBag)
    }

    func forward() {
        guard let page, let speech else { return }
        
        pause()

        let globalRange = speech.globalRange
        let start = globalRange.location + globalRange.length + 50

        if let index = findNextIndex() {
            DDLogInfo("SpeechManager: forward to \(start); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: index, on: page)
        } else if let enqueuedNextPage {
            loadEnqueuedPage(enqueuedNextPage, cleanPage: { [weak self] in self?.enqueuedNextPage = nil })
        } else {
            stop()
        }

        func findNextIndex() -> Int? {
            guard let paragraphRegex else { return nil }
            let matches = paragraphRegex.matches(in: page.text, range: NSRange(page.text.index(page.text.startIndex, offsetBy: globalRange.location)..., in: page.text))
            guard let range = matches.first?.range else { return nil }
            return range.location + range.length
        }
    }

    func back() {
        guard let page, let speech else { return }
        
        pause()

        if let index = findPreviousIndex(in: page.text, endIndex: page.text.index(page.text.startIndex, offsetBy: speech.globalRange.location)) {
            DDLogInfo("SpeechManager: backward to \(index); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: index, on: page)
        } else if speech.startIndex != 0 {
            skip(to: 0, on: page)
        } else if let previousIndex = delegate?.getPreviousPageIndex(from: page.index) {
            state.accept(.loading)
            delegate?.text(for: previousIndex) { [weak self] text in
                guard let self else { return }
                if let text, let index = findPreviousIndex(in: text, endIndex: text.endIndex) {
                    go(to: PageData(index: previousIndex, text: text, voice: page.voice), index: index, reportPageChange: true)
                } else {
                    state.accept(.stopped)
                }
            }
        }

        func findPreviousIndex(in text: String, endIndex: String.Index) -> Int? {
            guard let paragraphRegex else { return nil }
            let matches = paragraphRegex.matches(in: text, range: NSRange(text.startIndex..<endIndex, in: page.text))
            guard let range = matches.first?.range else { return nil }
            return range.location + range.length
        }
    }

    private func cleanup() {
        speech = nil
        page = nil
        enqueuedNextPage = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        cleanup()
        state.accept(.stopped)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard ignoreFinishCallCount <= 0 else {
            ignoreFinishCallCount -= 1
            return
        }

        if let enqueuedNextPage {
            loadEnqueuedPage(enqueuedNextPage, cleanPage: { [weak self] in self?.enqueuedNextPage = nil })
        } else {
            cleanup()
            state.accept(.stopped)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard let page else { return }
        if characterRange.length > 0 {
            speech = speech?.copy(with: characterRange)
        }
        guard enqueuedNextPage == nil && (page.text.count <= 300 || characterRange.location >= page.threshold), let delegate, let nextPageIndex = delegate.getNextPageIndex(from: page.index)
        else { return }
        enqueuedNextPage = preloadText(for: nextPageIndex, voice: page.voice, delegate: delegate)
    }
}
