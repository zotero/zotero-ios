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
    func text(for pageIndex: Index) -> String?
    func moved(to pageIndex: Index)
}

final class SpeechManager<Delegate: SpeechmanagerDelegate>: NSObject, AVSpeechSynthesizerDelegate {
    enum State {
        case speaking, paused, stopped
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
            threshold = Int(Double(text.count) * 0.85)
        }
    }

    private let synthetizer: AVSpeechSynthesizer
    let state: BehaviorRelay<State>

    private var speech: SpeechData?
    private var page: PageData?
    private var enqueuedNextPage: PageData?
    private var enqueuedPreviousPage: PageData?
    private var ignoreFinishCallCount = 0
    private weak var delegate: Delegate?
    var isSpeaking: Bool {
        return synthetizer.isSpeaking
    }

    init(delegate: Delegate) {
        synthetizer = AVSpeechSynthesizer()
        state = BehaviorRelay(value: .stopped)
        self.delegate = delegate
        super.init()
        synthetizer.delegate = self
    }

    // MARK: - Actions

    func start() {
        guard let page = delegate?.getCurrentPageIndex(), let (text, voice) = getData(for: page) else { return }
        go(to: PageData(index: page, text: text, voice: voice), reportPageChange: false)

        func getData(for page: Delegate.Index) -> (String, AVSpeechSynthesisVoice)? {
            guard let text = delegate?.text(for: page) else { return nil }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            let language = recognizer.dominantLanguage?.rawValue
            let voice = language.flatMap({ findVoice(for: $0) }) ?? AVSpeechSynthesisVoice(identifier: "en-US")!
            return (text, voice)

            func findVoice(for language: String) -> AVSpeechSynthesisVoice? {
                return AVSpeechSynthesisVoice.speechVoices().first { $0.language.starts(with: language) }
            }
        }
    }

    private func go(to page: PageData, reportPageChange: Bool = true) {
        self.page = page
        speech = SpeechData(startIndex: 0, speakingRange: NSRange(location: 0, length: 0))
        speak(text: page.text, voice: page.voice)
        guard reportPageChange else { return }
        delegate?.moved(to: page.index)
    }

    private func skip(to index: Int, on page: PageData) {
        DDLogInfo("SpeechManager: SKIP TO \(index) ON \(page.index)")
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
        synthetizer.speak(utterance)
    }

    func pause() {
        guard synthetizer.isSpeaking else { return }
        synthetizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthetizer.isPaused else { return }
        synthetizer.continueSpeaking()
    }

    func stop() {
        synthetizer.stopSpeaking(at: .immediate)
    }

    func forward() {
        guard let page, let speech else { return }

        let globalRange = speech.globalRange
        let start = globalRange.location + globalRange.length + 50

        if start < page.text.count {
            DDLogInfo("SpeechManager: FORWARD TO \(start); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: start, on: page)
        } else if let enqueuedNextPage {
            go(to: enqueuedNextPage)
            self.enqueuedNextPage = nil
        } else {
            stop()
        }
    }

    func back() {
        guard let page, let speech else { return }

        let globalRange = speech.globalRange
        if globalRange.location >= 50 {
            let start = globalRange.location - 50
            DDLogInfo("SpeechManager: BACKWARD TO \(start); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: start, on: page)
        } else if let previousIndex = delegate?.getPreviousPageIndex(from: page.index), let text = delegate?.text(for: previousIndex) {
            go(to: .init(index: previousIndex, text: text, voice: page.voice))
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
            go(to: enqueuedNextPage)
            self.enqueuedNextPage = nil
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
        guard enqueuedNextPage == nil && (page.text.count <= 300 || characterRange.location >= page.threshold),
              let nextPageIndex = delegate?.getNextPageIndex(from: page.index),
              let text = delegate?.text(for: nextPageIndex)
        else { return }
        enqueuedNextPage = PageData(index: nextPageIndex, text: text, voice: page.voice)
    }
}
