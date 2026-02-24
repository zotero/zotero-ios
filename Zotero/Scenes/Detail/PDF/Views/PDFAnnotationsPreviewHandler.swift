//
//  PDFAnnotationsPreviewHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 24/02/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import RxSwift

final class PDFAnnotationsPreviewHandler {
    private let annotationPreviewController: AnnotationPreviewController
    private let attachmentKey: String
    private let libraryId: LibraryIdentifier
    private let previewCache: NSCache<NSString, UIImage>
    private let disposeBag: DisposeBag

    private weak var annotationProvider: PDFReaderAnnotationProvider?
    private var appearance: Appearance
    private var isObserving = false

    var previewsDidLoad: ((Set<String>) -> Void)?

    init(
        annotationPreviewController: AnnotationPreviewController,
        annotationProvider: PDFReaderAnnotationProvider?,
        attachmentKey: String,
        libraryId: LibraryIdentifier,
        appearance: Appearance
    ) {
        self.annotationPreviewController = annotationPreviewController
        self.annotationProvider = annotationProvider
        self.attachmentKey = attachmentKey
        self.libraryId = libraryId
        self.appearance = appearance
        previewCache = NSCache()
        previewCache.totalCostLimit = 1024 * 1024 * 10
        disposeBag = DisposeBag()
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        annotationPreviewController
            .observable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] annotationKey, attachmentKey, image in
                guard let self, self.attachmentKey == attachmentKey else { return }
                previewCache.setObject(image, forKey: annotationKey as NSString)
                previewsDidLoad?([annotationKey])
            })
            .disposed(by: disposeBag)
    }

    func image(for key: String) -> UIImage? {
        return previewCache.object(forKey: key as NSString)
    }

    func setAppearance(_ appearance: Appearance) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        previewCache.removeAllObjects()
    }

    func requestPreviews(keys: [String], notify: Bool) {
        guard !keys.isEmpty else { return }
        
        let group = DispatchGroup()
        var loadedKeys: Set<String> = []
        
        for key in keys {
            let nsKey = key as NSString
            guard previewCache.object(forKey: nsKey) == nil else { continue }
            
            group.enter()
            annotationPreviewController.preview(for: key, parentKey: attachmentKey, libraryId: libraryId, appearance: appearance) { [weak self] image in
                if let self {
                    if let image {
                        previewCache.setObject(image, forKey: nsKey)
                        loadedKeys.insert(key)
                    } else {
                        generatePreviewIfPossible(for: key, notify: notify)
                    }
                }
                group.leave()
            }
        }
        
        guard notify else { return }
        group.notify(queue: .main) { [weak self] in
            guard !loadedKeys.isEmpty else { return }
            self?.previewsDidLoad?(loadedKeys)
        }
        
        func generatePreviewIfPossible(for key: String, notify: Bool) {
            guard let annotation = annotationProvider?.loadedAnnotation(with: key), annotation.shouldRenderPreview else { return }
            if notify {
                annotationPreviewController.store(for: annotation, parentKey: attachmentKey, libraryId: libraryId, appearance: appearance)
            } else {
                annotationPreviewController.store(annotations: [annotation], parentKey: attachmentKey, libraryId: libraryId, appearance: appearance)
            }
        }
    }
}
