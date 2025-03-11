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

final class SpeechManager {
    private let synthetizer = AVSpeechSynthesizer()

    var isSpeaking: Bool {
        return synthetizer.isSpeaking
    }

    func speak(text: String) {
        // Detect language
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage?.rawValue
        // Create speech utterance with proper voice
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = language.flatMap({ findVoice(for: $0) }) ?? AVSpeechSynthesisVoice(identifier: "en-US")
        // Start speaking
        synthetizer.speak(utterance)

        func findVoice(for language: String) -> AVSpeechSynthesisVoice? {
            return AVSpeechSynthesisVoice.speechVoices().first { $0.language.starts(with: language) }
        }
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
}
