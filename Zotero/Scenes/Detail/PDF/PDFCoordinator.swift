//
//  PDFCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 06.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import UIKit
import SwiftUI

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift

protocol PdfReaderCoordinatorDelegate: ReaderCoordinatorDelegate, ReaderSidebarCoordinatorDelegate {
    func showSearch(document: Document, documentController: PDFDocumentViewController, text: String?, sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle)
    func show(error: PDFDocumentExporter.Error)
    func share(url: URL, barButton: UIBarButtonItem)
    func share(text: String, rect: CGRect, view: UIView, userInterfaceStyle: UIUserInterfaceStyle)
    func showDeletedAlertForPdf(completion: @escaping (Bool) -> Void)
    func showReader(document: Document, userInterfaceStyle: UIUserInterfaceStyle)
    func showCitation(for itemId: String, libraryId: LibraryIdentifier)
    func copyBibliography(using presenter: UIViewController, for itemId: String, libraryId: LibraryIdentifier)
    func showFontSizePicker(sender: UIView, picked: @escaping (CGFloat) -> Void)
    func showDeleteAlertForAnnotation(sender: UIView, delete: @escaping () -> Void)
    func showDocumentChangedAlert(completed: @escaping () -> Void)
    func showAccessibility<Delegate: SpeechmanagerDelegate>(
        speechManager: SpeechManager<Delegate>,
        document: Document,
        userInterfaceStyle: UIUserInterfaceStyle,
        sender: UIBarButtonItem,
        animated: Bool,
        isFormSheet: @escaping () -> Bool,
        dismissAction: @escaping () -> Void,
        voiceChangeAction: @escaping (AVSpeechSynthesisVoice) -> Void
    )
}

protocol PdfAnnotationsCoordinatorDelegate: ReaderSidebarCoordinatorDelegate {
    func createShareAnnotationMenu(state: PDFReaderState, annotation: PDFAnnotation, sender: UIButton) -> UIMenu?
}

final class PDFCoordinator: ReaderCoordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var searchController: DocumentSearchViewController?
    weak var navigationController: UINavigationController?

    private let key: String
    private let parentKey: String?
    private let libraryId: LibraryIdentifier
    private let url: URL
    private let page: Int?
    private let preselectedAnnotationKey: String?
    private let previewRects: [CGRect]?
    internal unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(
        key: String,
        parentKey: String?,
        libraryId: LibraryIdentifier,
        url: URL,
        page: Int?,
        preselectedAnnotationKey: String?,
        previewRects: [CGRect]?,
        navigationController: NavigationViewController,
        controllers: Controllers
    ) {
        self.key = key
        self.parentKey = parentKey
        self.libraryId = libraryId
        self.url = url
        self.page = page
        self.preselectedAnnotationKey = preselectedAnnotationKey
        self.previewRects = previewRects
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        navigationController.dismissHandler = { [weak self] in
            guard let self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("PDFCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        let username = Defaults.shared.username
        guard let userControllers = controllers.userControllers,
              let userId = controllers.sessionController.sessionData?.userId,
              !username.isEmpty,
              let parentNavigationController = parentCoordinator?.navigationController
        else { return }

        let settings = Defaults.shared.pdfSettings
        let displayName = Defaults.shared.displayName
        if userId == 0 {
            DDLogWarn("PDFCoordinator: userId is not initialized")
        }
        if displayName.isEmpty {
            DDLogWarn("PDFCoordinator: displayName is empty")
        }
        let handler = PDFReaderActionHandler(
            dbStorage: userControllers.dbStorage,
            annotationPreviewController: controllers.annotationPreviewController,
            pdfThumbnailController: controllers.pdfThumbnailController,
            htmlAttributedStringConverter: controllers.htmlAttributedStringConverter,
            schemaController: controllers.schemaController,
            fileStorage: controllers.fileStorage,
            idleTimerController: controllers.idleTimerController,
            dateParser: controllers.dateParser
        )
        let state = PDFReaderState(
            url: url,
            key: key,
            parentKey: parentKey,
            title: try? controllers.userControllers?.dbStorage.perform(request: ReadFilenameDbRequest(libraryId: libraryId, key: key), on: .main),
            libraryId: libraryId,
            initialPage: page,
            preselectedAnnotationKey: preselectedAnnotationKey,
            previewRects: previewRects,
            settings: settings,
            userId: userId,
            username: username,
            interfaceStyle: settings.appearanceMode == .automatic ? parentNavigationController.view.traitCollection.userInterfaceStyle : settings.appearanceMode.userInterfaceStyle
        )
        let controller = PDFReaderViewController(
            viewModel: ViewModel(initialState: state, handler: handler),
            pdfWorkerController: userControllers.pdfWorkerController,
            compactSize: UIDevice.current.isCompactWidth(size: parentNavigationController.view.frame.size)
        )
        controller.coordinatorDelegate = self
        handler.delegate = controller

        navigationController?.setViewControllers([controller], animated: false)
    }
}

extension PDFCoordinator: PdfReaderCoordinatorDelegate {
    func showSearch(document: Document, documentController: PDFDocumentViewController, text: String?, sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle) {
        DDLogInfo("PDFCoordinator: show search")

        if let existing = self.searchController {
            if let controller = existing.presentingViewController {
                controller.dismiss(animated: true) { [weak self] in
                    self?.showSearch(document: document, documentController: documentController, text: text, sender: sender, userInterfaceStyle: userInterfaceStyle)
                }
                return
            }

            existing.overrideUserInterfaceStyle = userInterfaceStyle
            setupPresentation(for: existing, with: sender)
            existing.text = text

            self.navigationController?.present(existing, animated: true, completion: nil)
            return
        }

        let handler = PDFSearchHandler(document: document, documentController: documentController)
        let viewController = DocumentSearchViewController(text: text, handler: handler)
        viewController.overrideUserInterfaceStyle = userInterfaceStyle
        setupPresentation(for: viewController, with: sender)
        self.searchController = viewController
        self.navigationController?.present(viewController, animated: true, completion: nil)

        func setupPresentation(for pdfSearchController: DocumentSearchViewController, with sender: UIBarButtonItem) {
            pdfSearchController.modalPresentationStyle = .popover
            pdfSearchController.popoverPresentationController?.sourceItem = (navigationController?.isNavigationBarHidden == false) ? sender : navigationController?.view
            pdfSearchController.popoverPresentationController?.sourceRect = .zero
        }
    }

    func share(url: URL, barButton: UIBarButtonItem) {
        share(item: url, sourceItem: barButton)
    }

    func share(text: String, rect: CGRect, view: UIView, userInterfaceStyle: UIUserInterfaceStyle) {
        share(item: text, sourceView: view, sourceRect: rect, userInterfaceStyle: userInterfaceStyle)
    }

    func lookup(text: String, rect: CGRect, view: UIView, userInterfaceStyle: UIUserInterfaceStyle) {
        DDLogInfo("PDFCoordinator: show lookup")
        // When presented as a popover, UIReferenceLibraryViewController ignores overrideUserInterfaceStyle, so we wrap it in a navigation controller to force it.
        let controller = UINavigationController(rootViewController: UIReferenceLibraryViewController(term: text))
        controller.setNavigationBarHidden(true, animated: false)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = rect
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func show(error: PDFDocumentExporter.Error) {
        let message: String
        switch error {
        case .filenameMissing:
            message = "Could not find attachment item."

        case .fileError:
            // TODO: - show storage error or unknown error
            message = "Could not create PDF file."
            
        case .pdfError:
            message = "Could not export PDF file."
        }

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func showDeletedAlertForPdf(completion: @escaping (Bool) -> Void) {
        let controller = UIAlertController(title: L10n.Pdf.deletedTitle, message: L10n.Pdf.deletedMessage, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: .default, handler: { _ in
            completion(false)
        }))
        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { [weak self] _ in
            completion(true)
            self?.navigationController?.dismiss(animated: true, completion: nil)
        }))
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func showDeleteAlertForAnnotation(sender: UIView, delete: @escaping () -> Void) {
        let controller = UIAlertController(title: nil, message: L10n.Pdf.deleteAnnotation, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.sourceItem = sender
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { _ in
            delete()
        }))
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func showReader(document: Document, userInterfaceStyle: UIUserInterfaceStyle) {
        DDLogInfo("PDFCoordinator: show plain text reader")
        let controller = PDFPlainReaderViewController(document: document)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle
        navigationController.modalPresentationStyle = .fullScreen
        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showCitation(for itemId: String, libraryId: LibraryIdentifier) {
        (parentCoordinator as? DetailCoordinator)?.showCitation(using: navigationController, for: Set([itemId]), libraryId: libraryId, delegate: self)
    }

    func copyBibliography(using presenter: UIViewController, for itemId: String, libraryId: LibraryIdentifier) {
        (parentCoordinator as? DetailCoordinator)?.copyBibliography(using: presenter, for: Set([itemId]), libraryId: libraryId, delegate: self)
    }

    func showFontSizePicker(sender: UIView, picked: @escaping (CGFloat) -> Void) {
        let controller = FontSizePickerViewController(pickAction: picked)
        let presentedController: UIViewController
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            controller.modalPresentationStyle = .popover
            controller.popoverPresentationController?.sourceItem = sender
            controller.preferredContentSize = CGSize(width: 200, height: 400)
            presentedController = controller

        default:
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .formSheet
            presentedController = navigationController
        }

        self.navigationController?.present(presentedController, animated: true)
    }

    func showDocumentChangedAlert(completed: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.warning, message: L10n.Errors.Pdf.documentChanged, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in completed() }))
        navigationController?.present(controller, animated: true)
    }

    func showAccessibility<Delegate: SpeechmanagerDelegate>(
        speechManager: SpeechManager<Delegate>,
        document: Document,
        userInterfaceStyle: UIUserInterfaceStyle,
        sender: UIBarButtonItem,
        animated: Bool,
        isFormSheet: @escaping () -> Bool,
        dismissAction: @escaping () -> Void,
        voiceChangeAction: @escaping (AVSpeechSynthesisVoice) -> Void
    ) {
        guard let navigationController else { return }
        let readerAction = { [weak self] in
            guard let self else { return }
            self.navigationController?.dismiss(animated: true)
            showReader(document: document, userInterfaceStyle: userInterfaceStyle)
        }
        let controller = AccessibilityPopupViewController(
            speechManager: speechManager,
            isFormSheet: isFormSheet,
            readerAction: readerAction,
            dismissAction: dismissAction,
            voiceChangeAction: voiceChangeAction
        )
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.coordinatorDelegate = self
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.modalPresentationStyle = .popover
            controller.popoverPresentationController?.delegate = controller
            if #available(iOS 17, *) {
                controller.popoverPresentationController?.sourceItem = sender
            } else {
                controller.popoverPresentationController?.barButtonItem = sender
            }
        } else {
            controller.modalPresentationStyle = .formSheet
        }
        navigationController.present(controller, animated: animated)
    }
}

extension PDFCoordinator: AccessibilityPopoupCoordinatorDelegate {
    func showVoicePicker(for voice: AVSpeechSynthesisVoice, userInterfaceStyle: UIUserInterfaceStyle, selectionChanged: @escaping (AVSpeechSynthesisVoice) -> Void) {
        guard let navigationController else { return }
        let view = SpeechVoicePickerView(selectedVoice: voice, dismiss: { voice in
            selectionChanged(voice)
            if let presentedViewController = navigationController.presentedViewController as? AccessibilityPopupViewController<PDFReaderViewController> {
                presentedViewController.dismiss(animated: true)
            } else {
                navigationController.dismiss(animated: true)
            }
        })
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.modalPresentationStyle = .formSheet
        controller.isModalInPresentation = true
        if let presentedController = navigationController.presentedViewController {
            presentedController.present(controller, animated: true)
        } else {
            navigationController.present(controller, animated: true)
        }
    }
}

extension PDFCoordinator: PdfAnnotationsCoordinatorDelegate {
    private func deferredShareImageMenuElement(
        state: PDFReaderState,
        annotation: PDFAnnotation,
        sender: UIButton,
        boundingBoxConverter: AnnotationBoundingBoxConverter,
        scale: CGFloat,
        title: String
    ) -> UIDeferredMenuElement {
        let document = state.document
        let key = state.key
        let library = state.library
        return UIDeferredMenuElement { [weak self, weak boundingBoxConverter, weak document] elementProvider in
            guard let self, let boundingBoxConverter, let document else {
                elementProvider([])
                return
            }
            let annotationPreviewController = self.controllers.annotationPreviewController
            let pageIndex: PageIndex = UInt(annotation.page)
            let rect = annotation.boundingBox(boundingBoxConverter: boundingBoxConverter)
            var size = rect.size
            size.width *= scale
            size.height *= scale
            annotationPreviewController.render(
                document: document,
                page: pageIndex,
                rect: rect,
                imageSize: size,
                imageScale: 1.0,
                key: annotation.key,
                parentKey: key,
                libraryId: library.id
            )
            .observe(on: MainScheduler.instance)
            .subscribe { [weak self] image in
                let shareableImage = ShareableImage(image: image, title: title)
                let action = UIAction(title: shareableImage.titleWithSize) { [weak self] (_: UIAction) in
                    guard let self else { return }
                    DDLogInfo("PDFCoordinator: share pdf annotation image - \(title)")
                    let completion = { (activityType: UIActivity.ActivityType?, completed: Bool, _: [Any]?, error: Error?) in
                        DDLogInfo("PDFCoordinator: share pdf annotation image - activity type: \(String(describing: activityType)) completed: \(completed) error: \(String(describing: error))")
                    }
                    
                    ((childCoordinators.last as? AnnotationPopoverCoordinator) ?? (self as? Coordinator))?.share(item: shareableImage, sourceItem: sender, completionWithItemsHandler: completion)
                }
                action.accessibilityLabel = L10n.Accessibility.Pdf.shareAnnotationImage + " " + title
                action.isAccessibilityElement = true
                elementProvider([action])
            } onFailure: { (error: Error) in
                DDLogError("PDFCoordinator: can't render annotation image - \(error)")
                elementProvider([])
            }
            .disposed(by: self.disposeBag)
        }
    }

    func createShareAnnotationMenuForSelectedAnnotation(sender: UIButton) -> UIMenu? {
        guard let pdfController = self.navigationController?.viewControllers.first as? PDFReaderViewController, let annotation = pdfController.state.selectedAnnotation else { return nil }
        return createShareAnnotationMenu(state: pdfController.state, annotation: annotation, sender: sender)
    }

    func createShareAnnotationMenu(state: PDFReaderState, annotation: PDFAnnotation, sender: UIButton) -> UIMenu? {
        guard annotation.type == .image, let boundingBoxConverter = self.navigationController?.viewControllers.last as? AnnotationBoundingBoxConverter else { return nil }
        var children: [UIMenuElement] = []
        var shareImageMenuChildren: [UIMenuElement] = []
        for (scale, title) in [
            (300.0 / 72.0, L10n.Pdf.AnnotationShare.Image.medium),
            (600.0 / 72.0, L10n.Pdf.AnnotationShare.Image.large)
        ] {
            let menuElement = deferredShareImageMenuElement(state: state, annotation: annotation, sender: sender, boundingBoxConverter: boundingBoxConverter, scale: scale, title: title)
            shareImageMenuChildren.append(menuElement)
        }
        let shareImageMenu = UIMenu(title: L10n.Pdf.AnnotationShare.Image.share, options: [.displayInline], children: shareImageMenuChildren)
        children.append(shareImageMenu)
        return UIMenu(children: children)
    }
}

extension PDFCoordinator: DetailCitationCoordinatorDelegate {
    func showCitationPreviewError(using presenter: UINavigationController, errorMessage: String) {
        guard let coordinator = parentCoordinator as? DetailCoordinator else { return }
        coordinator.showCitationPreviewError(using: presenter, errorMessage: errorMessage)
    }
    
    func showMissingStyleError(using presenter: UINavigationController?) {
        guard let coordinator = parentCoordinator as? DetailCoordinator else { return }
        coordinator.showMissingStyleError(using: navigationController)
    }
}

extension PDFCoordinator: DetailCopyBibliographyCoordinatorDelegate { }
