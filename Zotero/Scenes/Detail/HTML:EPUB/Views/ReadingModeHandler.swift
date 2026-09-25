//
//  ReadingModeHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 25.09.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

/// Drives reading mode in the HTML/EPUB reader, which renders the document's structured text as reflowable HTML over
/// the (hidden) base view inside the same web view.
///
/// Owns the navigation bar toggle button and the structured-document-text extraction which enabling requires. The
/// button reflects the state the reader reports back, not the state which was requested, because the reader can refuse
/// to enable reading mode when the structured text is unavailable.
final class ReadingModeHandler {
    enum State {
        /// Base document is shown.
        case disabled
        /// Structured text is being extracted, or the reader is switching views.
        case loading
        /// Reading mode is shown.
        case enabled
    }

    /// Size of the reading mode checkbox capsule itself.
    private let navbarButtonSize: CGFloat = 38
    /// Transparent horizontal padding added around the capsule so the bar button matches the standard bar button
    /// footprint and lines up evenly with the system bar buttons next to it.
    private var navbarHorizontalPadding: CGFloat {
        return max(0, (CheckboxButton.standardNavigationBarButtonSize - navbarButtonSize) / 2)
    }

    private let file: FileData
    private unowned let documentWorkerController: DocumentWorkerController
    private weak var documentController: HtmlEpubDocumentViewController?
    private let disposeBag: DisposeBag

    private weak var buttonRef: CheckboxButton?
    private weak var progressViewRef: CircularProgressView?
    /// Latest extraction progress reported by the document worker, `nil` while it is unknown.
    private var currentProgress: Double?
    /// Worker extracting the structured text of this document, kept so that it can be cleaned up when the reader closes
    /// while the extraction is still running. A one-off worker is finished as soon as its work drains and rejects any
    /// further work, so each extraction gets a fresh one.
    private var worker: DocumentWorkerController.Worker?
    /// Dispose bag of the current extraction, so that starting another one drops the previous subscription.
    private var extractionDisposeBag: DisposeBag?

    private(set) var state: State = .disabled {
        didSet {
            updateButton()
        }
    }
    /// Called when enabling reading mode failed, so that the reader can report it to the user.
    var onEnableFailed: (() -> Void)?

    init(file: FileData, documentController: HtmlEpubDocumentViewController, documentWorkerController: DocumentWorkerController) {
        self.file = file
        self.documentController = documentController
        self.documentWorkerController = documentWorkerController
        disposeBag = DisposeBag()
    }

    deinit {
        if let worker {
            documentWorkerController.cleanupWorker(worker)
        }
        DDLogInfo("ReadingModeHandler: deinitialized")
    }

    // MARK: - Actions

    func toggle() {
        switch state {
        case .loading:
            // Ignore taps while the previous change is still in flight, the button is disabled anyway.
            break

        case .enabled:
            disable()

        case .disabled:
            enable()
        }
    }

    private func enable() {
        guard let documentController else { return }
        state = .loading
        // Read aloud may have handed the pack over already, in which case the reader can switch right away.
        guard !documentController.hasSDTPack else {
            setReadingModeEnabled(true)
            return
        }
        loadSDTPack { [weak self] didLoad in
            guard let self else { return }
            guard didLoad else {
                DDLogError("ReadingModeHandler: could not load structured document text")
                state = .disabled
                onEnableFailed?()
                return
            }
            setReadingModeEnabled(true)
        }
    }

    private func disable() {
        state = .loading
        setReadingModeEnabled(false)
    }

    private func setReadingModeEnabled(_ enabled: Bool) {
        guard let documentController else {
            state = .disabled
            return
        }
        documentController.setReadingModeEnabled(enabled) { [weak self] isEnabled in
            guard let self else { return }
            state = isEnabled ? .enabled : .disabled
            if enabled && !isEnabled {
                DDLogError("ReadingModeHandler: reader did not enable reading mode")
                onEnableFailed?()
            }
        }
    }

    // MARK: - Structured document text

    /// Extracts the structured text of the document and hands it to the reader. Reports whether the reader has the pack
    /// afterwards. Progress of the extraction is shown in the toggle button.
    private func loadSDTPack(completion: @escaping (Bool) -> Void) {
        // A one-off worker is finished as soon as its work drains, and rejects anything queued afterwards, so every
        // extraction starts from a fresh worker.
        if let worker {
            documentWorkerController.cleanupWorker(worker)
        }
        let worker = DocumentWorkerController.Worker(file: file, kind: .oneOff, priority: .high)
        self.worker = worker
        let extractionDisposeBag = DisposeBag()
        self.extractionDisposeBag = extractionDisposeBag

        documentWorkerController.queue(work: .structuredDocumentText, in: worker)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] update in
                guard let self else { return }

                switch update.kind {
                case .queued:
                    // Extraction is queued but not started yet, progress is unknown.
                    updateProgress(nil)

                case .inProgress(let progress):
                    updateProgress(progress.map({ $0 / 100 }))

                case .failed, .cancelled:
                    DDLogError("ReadingModeHandler: structured document text extraction failed")
                    updateProgress(nil)
                    completion(false)

                case .extractedData(let result, _):
                    // Extraction is done, but handing the pack over and switching the reader to the structured text
                    // still takes a moment, so go back to the indeterminate spinner for the rest of the wait.
                    updateProgress(nil)
                    guard case .structuredDocumentText(let sdtResult) = result else {
                        DDLogError("ReadingModeHandler: unexpected result for structured document text work")
                        completion(false)
                        return
                    }
                    guard let documentController else {
                        completion(false)
                        return
                    }
                    do {
                        let pack = try sdtResult.pack()
                        documentController.setSDTPack(
                            bytes: pack.data,
                            packVersion: pack.header.packVersion,
                            schemaMajorVersion: pack.header.schemaMajorVersion,
                            completion: completion
                        )
                    } catch let error {
                        DDLogError("ReadingModeHandler: could not open structured document text pack - \(error)")
                        completion(false)
                    }
                }
            })
            .disposed(by: extractionDisposeBag)
    }

    // MARK: - Button

    func createReadingModeButton() -> UIBarButtonItem {
        let button = CheckboxButton(
            image: Asset.Images.pdfRawReader.image.withRenderingMode(.alwaysTemplate),
            contentInsets: NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
            cornerStyle: .capsule
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsLargeContentViewer = true
        button.accessibilityLabel = L10n.Accessibility.Speech.showReader
        button.deselectedBackgroundColor = .clear
        button.deselectedTintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        button.selectedTintColor = .white
        button.isSelected = false
        button.addAction(
            UIAction(handler: { [weak self] _ in
                self?.toggle()
            }),
            for: .touchUpInside
        )
        buttonRef = button

        let progressView = CircularProgressView(size: 20, lineWidth: 2)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isUserInteractionEnabled = false
        progressView.isHidden = true
        progressViewRef = progressView

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        container.addSubview(progressView)

        // Pad the capsule horizontally so the bar button matches the standard bar button footprint and lines up
        // evenly with the system bar buttons next to it (which have more surrounding padding than the tight capsule).
        let hPadding = navbarHorizontalPadding
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPadding),
            container.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: hPadding),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.widthAnchor.constraint(equalToConstant: navbarButtonSize),
            button.heightAnchor.constraint(equalToConstant: navbarButtonSize),
            progressView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])

        let item = UIBarButtonItem(customView: container)
        item.title = L10n.AccessibilityPopup.showReader
        item.accessibilityLabel = L10n.Accessibility.Speech.showReader
        return item
    }

    private func updateButton() {
        guard let button = buttonRef else { return }
        let isLoading = state == .loading
        button.isSelected = state == .enabled
        button.isEnabled = !isLoading
        // The progress ring takes the place of the icon while loading, as in the read aloud controls.
        button.configuration?.image = isLoading ? nil : Asset.Images.pdfRawReader.image.withRenderingMode(.alwaysTemplate)
        if isLoading {
            showProgressView()
        } else {
            hideProgressView()
        }
    }

    /// Shows the progress view, seeding it with the latest reported extraction progress (falling back to an
    /// indeterminate spinner while progress is unknown).
    private func showProgressView() {
        progressViewRef?.isHidden = false
        updateProgress(currentProgress)
    }

    private func hideProgressView() {
        guard let progressView = progressViewRef else { return }
        progressView.stopIndeterminateAnimation()
        progressView.progress = 0
        progressView.isHidden = true
        currentProgress = nil
    }

    /// Reflects the extraction progress in the progress view: a determinate arc when a value is known, an indeterminate
    /// spinner otherwise. No-op while the progress view is hidden.
    private func updateProgress(_ progress: Double?) {
        currentProgress = progress
        guard let progressView = progressViewRef, !progressView.isHidden else { return }
        if let progress {
            progressView.stopIndeterminateAnimation()
            progressView.progress = CGFloat(progress)
        } else {
            progressView.startIndeterminateAnimation()
        }
    }
}
