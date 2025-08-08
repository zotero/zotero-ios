//
//  DragDropController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

@preconcurrency
import RxSwift

final class DragDropController: @unchecked Sendable {
    class LocalContext: @unchecked Sendable {
        let uuid = UUID()
        let libraryIdentifier: LibraryIdentifier
        private(set) var keys: Set<String>
        fileprivate let itemProvider: NSItemProvider
        private var providerKey: String?

        fileprivate init(libraryIdentifier: LibraryIdentifier) {
            self.libraryIdentifier = libraryIdentifier
            self.keys = Set([])
            self.itemProvider = NSItemProvider()
        }

        func addToContext(item: RItem) -> Bool {
            guard libraryIdentifier == item.libraryIdentifier, !keys.contains(item.key) else { return false }
            if providerKey == nil {
                providerKey = item.key
            }
            keys.insert(item.key)
            return true
        }

        fileprivate func itemProvider(for key: String) -> NSItemProvider? {
            return (key == providerKey) ? itemProvider : nil
        }
    }

    private unowned var citationController: CitationController
    private let disposeBag: DisposeBag

    init(citationController: CitationController) {
        self.citationController = citationController
        disposeBag = DisposeBag()
    }

    func startContext(libraryIdentifier: LibraryIdentifier) -> LocalContext {
        let localContext = LocalContext(libraryIdentifier: libraryIdentifier)
        // Register data representation for html.
        localContext.itemProvider.registerDataRepresentation(for: .html, visibility: .all) { [weak self, weak localContext] completion in
            let keys = localContext?.keys ?? []
            guard !keys.isEmpty else {
                completion(nil, nil)
                return nil
            }
            let progress = Progress(totalUnitCount: 2)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(nil, nil)
                    return
                }
                var session: CitationController.Session?
                citationController.startSession(
                    for: keys,
                    libraryId: libraryIdentifier,
                    styleId: Defaults.shared.quickCopyStyleId,
                    localeId: Defaults.shared.quickCopyLocaleId
                )
                .flatMap { [weak self] startedSession -> Single<String> in
                    guard let self else { return .just("") }
                    session = startedSession
                    progress.completedUnitCount = 1
                    return citationController.bibliography(for: startedSession, format: .html(wrapped: true))
                }
                .subscribe { [weak self] wrappedHTML in
                    progress.completedUnitCount = 2
                    completion(wrappedHTML.data(using: .utf8), nil)
                    if let session {
                        self?.citationController.endSession(session)
                    }
                } onFailure: { [weak self] error in
                    progress.completedUnitCount = 2
                    completion(nil, error)
                    if let session {
                        self?.citationController.endSession(session)
                    }
                }
                .disposed(by: disposeBag)
            }
            return progress
        }
        // Register data representation for plain text. Use html without wrapping according to user option.
        localContext.itemProvider.registerDataRepresentation(for: .plainText, visibility: .all) { [weak self, weak localContext] completion in
            let keys = localContext?.keys ?? []
            guard !keys.isEmpty else {
                completion(nil, nil)
                return nil
            }
            let progress = Progress(totalUnitCount: 2)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(nil, nil)
                    return
                }
                var session: CitationController.Session?
                citationController.startSession(
                    for: keys,
                    libraryId: libraryIdentifier,
                    styleId: Defaults.shared.quickCopyStyleId,
                    localeId: Defaults.shared.quickCopyLocaleId
                )
                .flatMap { [weak self] startedSession -> Single<String> in
                    guard let self else { return .just("") }
                    session = startedSession
                    progress.completedUnitCount = 1
                    return citationController.bibliography(for: startedSession, format: Defaults.shared.quickCopyAsHtml ? .html(wrapped: false) : .text)
                }
                .subscribe { [weak self] plainText in
                    progress.completedUnitCount = 2
                    completion(plainText.data(using: .utf8), nil)
                    if let session {
                        self?.citationController.endSession(session)
                    }
                } onFailure: { [weak self] error in
                    progress.completedUnitCount = 2
                    completion(nil, error)
                    if let session {
                        self?.citationController.endSession(session)
                    }
                }
                .disposed(by: disposeBag)
            }
            return progress
        }
        // Register data representation for rtf. Create html and transform it to rtf
        localContext.itemProvider.registerDataRepresentation(for: .rtf, visibility: .all) { [weak self, weak localContext] completion in
            let keys = localContext?.keys ?? []
            guard !keys.isEmpty else {
                completion(nil, nil)
                return nil
            }
            let progress = Progress(totalUnitCount: 2)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(nil, nil)
                    return
                }
                var session: CitationController.Session?
                citationController.startSession(
                    for: keys,
                    libraryId: libraryIdentifier,
                    styleId: Defaults.shared.quickCopyStyleId,
                    localeId: Defaults.shared.quickCopyLocaleId
                )
                .flatMap { [weak self] startedSession -> Single<String> in
                    guard let self else { return .just("") }
                    session = startedSession
                    progress.completedUnitCount = 1
                    return citationController.bibliography(for: startedSession, format: .html(wrapped: true))
                }
                .subscribe { [weak self] wrappedHTML in
                    progress.completedUnitCount = 2
                    if let htmlData = wrappedHTML.data(using: .utf8) {
                        do {
                            completion(try Data.convertHTMLToRTF(htmlData: htmlData), nil)
                        } catch let error {
                            completion(nil, error)
                        }
                    } else {
                        completion(nil, nil)
                    }
                    if let session {
                        self?.citationController.endSession(session)
                    }
                } onFailure: { [weak self] error in
                    progress.completedUnitCount = 2
                    completion(nil, error)
                    if let session {
                        self?.citationController.endSession(session)
                    }
                }
                .disposed(by: disposeBag)
            }
            return progress
        }
        return localContext
    }

    func dragItem(from item: RItem, localContext: LocalContext) -> UIDragItem {
        // Use an actual item provider only for the first key, so that it will only provide a bibliography for all the items of the local context.
        // All other items use an empty item provider.
        let dragItem = UIDragItem(itemProvider: localContext.itemProvider(for: item.key) ?? NSItemProvider())
        dragItem.localObject = item
        return dragItem
    }
}
