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
    associatedtype Index: Hashable

    func getCurrentPageIndex() -> Index
    func getNextPageIndex(from currentPageIndex: Index) -> Index?
    func getPreviousPageIndex(from currentPageIndex: Index) -> Index?
    func text(for indices: [Index], completion: @escaping ([Index: String]?) -> Void)
    func moved(to pageIndex: Index)
}

final class SpeechManager<Delegate: SpeechmanagerDelegate>: NSObject, AVSpeechSynthesizerDelegate {
    enum State {
        case speaking, paused, stopped, loading

        var isStopped: Bool {
            switch self {
            case .speaking, .loading, .paused:
                return false

            case .stopped:
                return true
            }
        }
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
        // Text to read
        let text: String
        // Voice used for this page
        let voice: AVSpeechSynthesisVoice
    }

    private let synthesizer: AVSpeechSynthesizer
    let state: BehaviorRelay<State>
    private let disposeBag: DisposeBag

    private var speech: SpeechData?
    private var cachedPages: [Delegate.Index: PageData]
    private var currentIndex: Delegate.Index?
    private var speechRateModifier: Float
    private var ignoreFinishCallCount = 0
    private var shouldReloadUtteranceOnResume = false
    private weak var delegate: Delegate?
    private lazy var paragraphRegex: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: "[\r\n]{1,}")
    }()
    var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }
    var isPaused: Bool {
        return synthesizer.isPaused
    }
    var currentVoice: AVSpeechSynthesisVoice? {
        return currentIndex.flatMap({ cachedPages[$0] })?.voice
    }
    private var overrideLanguage: String?

    init(delegate: Delegate, speechRateModifier: Float, voiceLanguage: String? = nil) {
        cachedPages = [:]
        self.speechRateModifier = speechRateModifier
        overrideLanguage = voiceLanguage
        synthesizer = AVSpeechSynthesizer()
        state = BehaviorRelay(value: .stopped)
        disposeBag = DisposeBag()
        self.delegate = delegate
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Actions

    func start() {
        guard let delegate else {
            DDLogError("SpeechManager: can't get delegate")
            return
        }

        let index = delegate.getCurrentPageIndex()
        if let page = cachedPages[index] {
            go(to: page, pageIndex: index, reportPageChange: false)
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
            go(to: page, pageIndex: index, reportPageChange: false)
        }
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
        guard synthesizer.isSpeaking || synthesizer.isPaused || state.value == .loading else { return }
        if state.value == .loading {
            state.accept(.stopped)
        } else {
            // Ignore finish delegate, which would move us to another page
            ignoreFinishCallCount = 1
            synthesizer.stopSpeaking(at: .immediate)
            state.accept(.stopped)
        }
    }

    func set(voice: AVSpeechSynthesisVoice) {
        Defaults.shared.defaultVoiceForLanguage[voice.baseLanguage] = voice.identifier

        guard let currentVoice else { return }

        let newBaseLanguage = voice.baseLanguage
        if currentVoice.baseLanguage != newBaseLanguage {
            set(overrideLanguage: newBaseLanguage, voice: voice)
        } else {
            for (key, value) in cachedPages {
                guard value.voice.baseLanguage == newBaseLanguage else { continue }
                cachedPages[key] = PageData(text: value.text, voice: voice)
            }
        }
        utteranceChanged()

        func set(overrideLanguage: String, voice: AVSpeechSynthesisVoice) {
            self.overrideLanguage = overrideLanguage
            for (key, value) in cachedPages {
                cachedPages[key] = PageData(text: value.text, voice: voice)
            }
        }
    }

    func set(rateModifier: Float) {
        speechRateModifier = rateModifier
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
        guard let currentIndex, let page = cachedPages[currentIndex], let speech else { return }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
        let text = String(page.text[page.text.index(page.text.startIndex, offsetBy: speech.globalRange.location)..<page.text.endIndex])
        speak(text: text, voice: page.voice)
    }

    private func getData(for indices: [Delegate.Index], from delegate: Delegate, completion: @escaping (([Delegate.Index: PageData])?) -> Void) {
        delegate.text(for: indices) { texts in
            guard let texts, texts.count == indices.count else {
                completion(nil)
                return
            }
            
            var pages: [Delegate.Index: PageData] = [:]
            for index in indices {
                guard let text = texts[index] else {
                    completion(nil)
                    return
                }
                pages[index] = PageData(text: text, voice: voice(for: text))
            }
            completion(pages)
        }

        func voice(for text: String) -> AVSpeechSynthesisVoice {
            if let overrideLanguage {
                return findVoice(for: overrideLanguage)
            }

            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            let language = recognizer.dominantLanguage?.rawValue ?? "en"
            return findVoice(for: language)
        }
    }

    private func findVoice(for language: String) -> AVSpeechSynthesisVoice {
        let voiceId = Defaults.shared.defaultVoiceForLanguage[language]
        return AVSpeechSynthesisVoice.speechVoices().first(where: isProperVoice) ?? AVSpeechSynthesisVoice(identifier: "en-US")!

        func isProperVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
            if let voiceId {
                return voice.identifier == voiceId
            }
            return voice.language.starts(with: language)
        }
    }

    private func go(to page: PageData, pageIndex: Delegate.Index, speechStartIndex: Int? = nil, reportPageChange: Bool = true) {
        let text: String
        if let index = speechStartIndex {
            text = String(page.text[page.text.index(page.text.startIndex, offsetBy: index)..<page.text.endIndex])
        } else {
            text = page.text
        }
        currentIndex = pageIndex
        speech = SpeechData(startIndex: speechStartIndex ?? 0, speakingRange: NSRange(location: 0, length: 0))
        speak(text: text, voice: page.voice)
        
        guard let delegate else { return }
        
        if reportPageChange {
            delegate.moved(to: pageIndex)
        }
        
        // Cache next/previous page after page change if needed
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

    private func skip(to index: Int, on page: PageData) {
        speech = SpeechData(startIndex: index, speakingRange: NSRange(location: 0, length: 0))
        let text = page.text[page.text.index(page.text.startIndex, offsetBy: index)..<page.text.endIndex]
        speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 0), utterance: AVSpeechUtterance())
        speak(text: String(text), voice: page.voice)
    }

    private func speak(text: String, voice: AVSpeechSynthesisVoice) {
        if synthesizer.isSpeaking {
            ignoreFinishCallCount += 1
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.5 * speechRateModifier
        synthesizer.speak(utterance)
    }

    func forward() {
        guard let currentIndex, let currentPage = cachedPages[currentIndex], let speech else { return }

        if let index = findNextIndex(on: currentPage, speechRange: speech.globalRange) {
            DDLogInfo("SpeechManager: forward to \(index); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: index, on: currentPage)
        } else if let nextIndex = delegate?.getNextPageIndex(from: currentIndex), let page = cachedPages[nextIndex] {
            go(to: page, pageIndex: nextIndex)
        } else {
            stop()
        }

        func findNextIndex(on page: PageData, speechRange: NSRange) -> Int? {
            guard let paragraphRegex else { return nil }
            let matches = paragraphRegex.matches(in: page.text, range: NSRange(page.text.index(page.text.startIndex, offsetBy: speechRange.location + speechRange.length)..., in: page.text))
            guard let range = matches.first?.range else { return nil }
            return range.location + range.length
        }
    }

    func backward() {
        guard let currentIndex, let currentPage = cachedPages[currentIndex], let speech else { return }
  
        if let index = findPreviousIndex(in: currentPage.text, endIndex: currentPage.text.index(currentPage.text.startIndex, offsetBy: speech.globalRange.location)) {
            DDLogInfo("SpeechManager: backward to \(index); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: index, on: currentPage)
        } else if speech.startIndex != 0 {
            skip(to: 0, on: currentPage)
        } else if let previousIndex = delegate?.getPreviousPageIndex(from: currentIndex),
                  let previousPage = cachedPages[previousIndex],
                  let speechIndex = findPreviousIndex(in: previousPage.text, endIndex: previousPage.text.endIndex) {
            go(to: previousPage, pageIndex: previousIndex, speechStartIndex: speechIndex)
        } else {
            stop()
        }

        func findPreviousIndex(in text: String, endIndex: String.Index) -> Int? {
            guard let paragraphRegex else { return nil }
            let range = NSRange(text.startIndex..<endIndex, in: text)
            let matches = paragraphRegex.matches(in: text, range: range)
            if matches.count > 1 {
                let matchRange = matches[matches.count - 2].range
                return matchRange.location + matchRange.length
            }
            return nil
        }
    }

    private func cleanup() {
        speech = nil
        currentIndex = nil
        cachedPages = [:]
    }

    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        cleanup()
        state.accept(.stopped)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        state.accept(.paused)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        state.accept(.speaking)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        state.accept(.speaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard ignoreFinishCallCount <= 0 else {
            ignoreFinishCallCount -= 1
            return
        }

        if let currentIndex, let nextIndex = delegate?.getNextPageIndex(from: currentIndex), let page = cachedPages[nextIndex] {
            go(to: page, pageIndex: nextIndex)
        } else {
            cleanup()
            state.accept(.stopped)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard currentIndex != nil && characterRange.length > 0 else { return }
        speech = speech?.copy(with: characterRange)
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
