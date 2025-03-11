//
//  DocumentSpeechManager.swift
//  Zotero
//
//  Created by Michal Rentka on 11.03.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

protocol DocumentSpeechmanagerDelegate: AnyObject {
    associatedtype Page

    func getCurrentPage() -> Page
    func getNextPage(from currentPage: Page) -> Page?
    func getPreviousPage(from currentPage: Page) -> Page?
    func text(for page: Page) -> String?
}

final class DocumentSpeechManager<Delegate: DocumentSpeechmanagerDelegate> {
    private let speechManager: SpeechManager

    private var currentPage: Delegate.Page?
    private weak var delegate: Delegate?

    init(delegate: Delegate) {
        speechManager = SpeechManager()
        self.delegate = delegate
    }

    func startOnCurrentPage() {
        guard let page = delegate?.getCurrentPage() else { return }
        start(on: page)
    }

    func start(on page: Delegate.Page) {
        guard !speechManager.isSpeaking, let text = delegate?.text(for: page) else { return }
        currentPage = page
        speechManager.speak(text: text)
    }

    func resume() {
        speechManager.resume()
    }

    func pause() {
        speechManager.pause()
    }

    func stop() {
        speechManager.stop()
    }
}
