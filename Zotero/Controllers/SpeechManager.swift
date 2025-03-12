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
    associatedtype Page

    func getCurrentPage() -> Page
    func getNextPage(from currentPage: Page) -> Page?
    func getPreviousPage(from currentPage: Page) -> Page?
    func text(for page: Page) -> String?
    func moved(to page: Page)
}

final class SpeechManager<Delegate: SpeechmanagerDelegate>: NSObject, AVSpeechSynthesizerDelegate {
    enum State {
        case speaking, paused, stopped
    }

    private struct PageData {
        // Index in given document
        let index: Delegate.Page
        // Threshold which marks ending of this page, when new page should be loaded
        let threshold: Int
        // Voice used for this page
        let voice: AVSpeechSynthesisVoice

        init(index: Delegate.Page, length: Int, voice: AVSpeechSynthesisVoice) {
            self.index = index
            self.voice = voice
            threshold = Int(Double(length) * 0.85)
        }
    }

    private struct EnqueuedPageData {
        let page: PageData
        let text: String
    }

    private let synthetizer: AVSpeechSynthesizer
    let state: BehaviorRelay<State>

    private var currentPage: PageData?
    private var enqueuedPage: EnqueuedPageData?
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
        guard let page = delegate?.getCurrentPage(), let (text, voice) = getData(for: page) else { return }
        currentPage = PageData(index: page, length: text.count, voice: voice)
        speak(text: text, voice: voice)

        func getData(for page: Delegate.Page) -> (String, AVSpeechSynthesisVoice)? {
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

    private func speak(text: String, voice: AVSpeechSynthesisVoice) {
        if synthetizer.isSpeaking {
            synthetizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 4
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

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        enqueuedPage = nil
        currentPage = nil
        state.accept(.stopped)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let enqueuedPage {
            currentPage = enqueuedPage.page
            speak(text: enqueuedPage.text, voice: enqueuedPage.page.voice)
            delegate?.moved(to: enqueuedPage.page.index)
            self.enqueuedPage = nil
        } else {
            currentPage = nil
            state.accept(.stopped)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard let currentPage,
              characterRange.location >= currentPage.threshold,
              let nextPageIndex = delegate?.getNextPage(from: currentPage.index),
              let text = delegate?.text(for: nextPageIndex)
        else { return }
        let nextPage = PageData(index: nextPageIndex, length: text.count, voice: currentPage.voice)
        enqueuedPage = EnqueuedPageData(page: nextPage, text: text)
    }
}
