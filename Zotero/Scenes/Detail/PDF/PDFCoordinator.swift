//
//  PDFCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 06.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift

protocol PdfReaderCoordinatorDelegate: AnyObject {
    func showToolSettings(tool: PSPDFKit.Annotation.Tool, colorHex: String?, sizeValue: Float?, sender: SourceView, userInterfaceStyle: UIUserInterfaceStyle, valueChanged: @escaping (String?, Float?) -> Void)
    func showSearch(pdfController: PDFViewController, text: String?, sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle, result: @escaping (SearchResult) -> Void)
    func showAnnotationPopover(viewModel: ViewModel<PDFReaderActionHandler>, sourceRect: CGRect, popoverDelegate: UIPopoverPresentationControllerDelegate, userInterfaceStyle: UIUserInterfaceStyle)
    func show(error: PDFReaderState.Error)
    func show(error: PdfDocumentExporter.Error)
    func share(url: URL, barButton: UIBarButtonItem)
    func share(text: String, rect: CGRect, view: UIView)
    func lookup(text: String, rect: CGRect, view: UIView, userInterfaceStyle: UIUserInterfaceStyle)
    func showDeletedAlertForPdf(completion: @escaping (Bool) -> Void)
    func showSettings(with settings: PDFSettings, sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle, completion: @escaping (PDFSettings) -> Void)
    func showReader(document: Document, userInterfaceStyle: UIUserInterfaceStyle)
    func showPdfExportSettings(sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle, completed: @escaping (PDFExportSettings) -> Void)
}

protocol PdfAnnotationsCoordinatorDelegate: AnyObject {
    func createShareAnnotationMenu(state: PDFReaderState, annotation: Annotation, sender: UIButton) -> UIMenu?
    func shareAnnotationImage(state: PDFReaderState, annotation: Annotation, scale: CGFloat, sender: UIButton )
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, picked: @escaping ([Tag]) -> Void)
    func showCellOptions(for annotation: Annotation, userId: Int, library: Library, sender: UIButton, userInterfaceStyle: UIUserInterfaceStyle, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction)
    func showFilterPopup(from barButton: UIBarButtonItem, filter: AnnotationsFilter?, availableColors: [String], availableTags: [Tag], userInterfaceStyle: UIUserInterfaceStyle, completed: @escaping (AnnotationsFilter?) -> Void)
}

final class PDFCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var pdfSearchController: PDFSearchViewController?
    weak var navigationController: UINavigationController?

    private let key: String
    private let library: Library
    private let url: URL
    private let page: Int?
    private let preselectedAnnotationKey: String?
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(key: String, library: Library, url: URL, page: Int?, preselectedAnnotationKey: String?, navigationController: NavigationViewController, controllers: Controllers) {
        self.key = key
        self.library = library
        self.url = url
        self.page = page
        self.preselectedAnnotationKey = preselectedAnnotationKey
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
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let userId = self.controllers.sessionController.sessionData?.userId,
              !username.isEmpty,
              let parentNavigationController = self.parentCoordinator?.navigationController
        else { return }

        let settings = Defaults.shared.pdfSettings
        let handler = PDFReaderActionHandler(
            dbStorage: dbStorage,
            annotationPreviewController: self.controllers.annotationPreviewController,
            htmlAttributedStringConverter: self.controllers.htmlAttributedStringConverter,
            schemaController: self.controllers.schemaController,
            fileStorage: self.controllers.fileStorage,
            idleTimerController: self.controllers.idleTimerController,
            dateParser: self.controllers.dateParser
        )
        let state = PDFReaderState(
            url: self.url,
            key: self.key,
            library: self.library,
            initialPage: self.page,
            preselectedAnnotationKey: self.preselectedAnnotationKey,
            settings: settings,
            userId: userId,
            username: username,
            displayName: Defaults.shared.displayName,
            interfaceStyle: settings.appearanceMode.userInterfaceStyle(currentUserInterfaceStyle: parentNavigationController.view.traitCollection.userInterfaceStyle)
        )
        let controller = PDFReaderViewController(
            viewModel: ViewModel(initialState: state, handler: handler),
            compactSize: UIDevice.current.isCompactWidth(size: parentNavigationController.view.frame.size)
        )
        controller.coordinatorDelegate = self
        handler.delegate = controller

        self.navigationController?.setViewControllers([controller], animated: false)
    }
}

extension PDFCoordinator: PdfReaderCoordinatorDelegate {
    func showToolSettings(
        tool: PSPDFKit.Annotation.Tool,
        colorHex: String?,
        sizeValue: Float?,
        sender: SourceView,
        userInterfaceStyle: UIUserInterfaceStyle,
        valueChanged: @escaping (String?, Float?) -> Void
    ) {
        DDLogInfo("PDFCoordinator: show tool settings for \(tool)")
        let state = AnnotationToolOptionsState(tool: tool, colorHex: colorHex, size: sizeValue)
        let handler = AnnotationToolOptionsActionHandler()
        let controller = AnnotationToolOptionsViewController(viewModel: ViewModel(initialState: state, handler: handler), valueChanged: valueChanged)

        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            controller.overrideUserInterfaceStyle = userInterfaceStyle
            controller.modalPresentationStyle = .popover
            switch sender {
            case .view(let view, _):
                controller.popoverPresentationController?.sourceView = view

            case .item(let item):
                controller.popoverPresentationController?.barButtonItem = item
            }
            self.navigationController?.present(controller, animated: true, completion: nil)

        default:
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .formSheet
            navigationController.overrideUserInterfaceStyle = userInterfaceStyle
            self.navigationController?.present(navigationController, animated: true, completion: nil)
        }
    }

    func showAnnotationPopover(viewModel: ViewModel<PDFReaderActionHandler>, sourceRect: CGRect, popoverDelegate: UIPopoverPresentationControllerDelegate, userInterfaceStyle: UIUserInterfaceStyle) {
        guard let currentNavigationController = self.navigationController else { return }

        DDLogInfo("PDFCoordinator: show annotation popover")

        if let coordinator = self.childCoordinators.last, coordinator is AnnotationPopoverCoordinator {
            return
        }

        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle

        let coordinator = AnnotationPopoverCoordinator(navigationController: navigationController, controllers: self.controllers, viewModel: viewModel)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.sourceView = currentNavigationController.view
            navigationController.popoverPresentationController?.sourceRect = sourceRect
            navigationController.popoverPresentationController?.permittedArrowDirections = [.left, .right]
            navigationController.popoverPresentationController?.delegate = popoverDelegate
        }

        currentNavigationController.present(navigationController, animated: true, completion: nil)
    }

    func showSearch(pdfController: PDFViewController, text: String?, sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle, result: @escaping (SearchResult) -> Void) {
        DDLogInfo("PDFCoordinator: show search")

        if let existing = self.pdfSearchController {
            if let controller = existing.presentingViewController {
                controller.dismiss(animated: true) { [weak self] in
                    self?.showSearch(pdfController: pdfController, text: text, sender: sender, userInterfaceStyle: userInterfaceStyle, result: result)
                }
                return
            }

            existing.overrideUserInterfaceStyle = userInterfaceStyle
            existing.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
            existing.popoverPresentationController?.barButtonItem = sender
            existing.text = text

            self.navigationController?.present(existing, animated: true, completion: nil)
            return
        }

        let viewController = PDFSearchViewController(controller: pdfController, text: text, searchSelected: result)
        viewController.overrideUserInterfaceStyle = userInterfaceStyle
        viewController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        viewController.popoverPresentationController?.barButtonItem = sender
        self.pdfSearchController = viewController
        self.navigationController?.present(viewController, animated: true, completion: nil)
    }

    func share(url: URL, barButton: UIBarButtonItem) {
        self.share(item: url, sourceView: .item(barButton))
    }

    func share(text: String, rect: CGRect, view: UIView) {
        self.share(item: text, sourceView: .view(view, rect))
    }

    func lookup(text: String, rect: CGRect, view: UIView, userInterfaceStyle: UIUserInterfaceStyle) {
        DDLogInfo("PDFCoordinator: show lookup")
        let controller = UIReferenceLibraryViewController(term: text)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = rect
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func show(error: PDFReaderState.Error) {
        let title: String
        let message: String

        switch error {
        case .mergeTooBig:
            title = L10n.Errors.Pdf.mergeTooBigTitle
            message = L10n.Errors.Pdf.mergeTooBig

        case .cantAddAnnotations:
            title = L10n.error
            message = L10n.Errors.Pdf.cantAddAnnotations

        case .cantDeleteAnnotation:
            title = L10n.error
            message = L10n.Errors.Pdf.cantDeleteAnnotations

        case .cantUpdateAnnotation:
            title = L10n.error
            message = L10n.Errors.Pdf.cantUpdateAnnotation

        case .pageNotInt:
            title = L10n.error
            message = L10n.Errors.Pdf.pageIndexNotInt

        case .unknown:
            title = L10n.error
            message = L10n.Errors.unknown
        }

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .default))
        self.navigationController?.present(controller, animated: true)
    }

    func show(error: PdfDocumentExporter.Error) {
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

    func showSettings(with settings: PDFSettings, sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle, completion: @escaping (PDFSettings) -> Void) {
        DDLogInfo("PDFCoordinator: show settings")

        let state = PDFSettingsState(settings: settings)
        let viewModel = ViewModel(initialState: state, handler: PDFSettingsActionHandler())

        let controller: UIViewController

        if UIDevice.current.userInterfaceIdiom == .pad {
            let _controller = PDFSettingsViewController(viewModel: viewModel)
            _controller.changeHandler = completion
            controller = _controller
        } else {
            let _controller = PDFSettingsViewController(viewModel: viewModel)
            _controller.changeHandler = completion
            controller = UINavigationController(rootViewController: _controller)
        }

        controller.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        controller.popoverPresentationController?.barButtonItem = sender
        controller.preferredContentSize = CGSize(width: 480, height: 306)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
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

    func showPdfExportSettings(sender: UIBarButtonItem, userInterfaceStyle: UIUserInterfaceStyle, completed: @escaping (PDFExportSettings) -> Void) {
        DDLogInfo("PDFCoordinator: show PDF export")
        let view = PDFExportSettingsView(settings: PDFExportSettings(includeAnnotations: true), exportHandler: { [weak self] settings in
            self?.navigationController?.dismiss(animated: true, completion: {
                completed(settings)
            })
        })
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.preferredContentSize = CGSize(width: 400, height: 140)
        controller.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        controller.popoverPresentationController?.barButtonItem = sender
        self.navigationController?.present(controller, animated: true)
    }
}

extension PDFCoordinator: PdfAnnotationsCoordinatorDelegate {
    private func deferredShareImageMenuElement(
        state: PDFReaderState,
        annotation: Annotation,
        sender: UIButton,
        boundingBoxConverter: AnnotationBoundingBoxConverter,
        scale: CGFloat,
        title: String
    ) -> UIDeferredMenuElement {
        UIDeferredMenuElement { [weak self] elementProvider in
            guard let self else {
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
                document: state.document,
                page: pageIndex,
                rect: rect,
                imageSize: size,
                imageScale: 1.0,
                key: annotation.key,
                parentKey: state.key,
                libraryId: state.library.id
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
                    
                    if let coordinator = self.childCoordinators.last, coordinator is AnnotationPopoverCoordinator {
                        coordinator.share(item: shareableImage, sourceView: .view(sender, nil), completionWithItemsHandler: completion)
                    } else {
                        (self as Coordinator).share(item: shareableImage, sourceView: .view(sender, nil), completionWithItemsHandler: completion)
                    }
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
        
    func createShareAnnotationMenu(state: PDFReaderState, annotation: Annotation, sender: UIButton) -> UIMenu? {
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
    
    func shareAnnotationImage(state: PDFReaderState, annotation: Annotation, scale: CGFloat = 1.0, sender: UIButton) {
        guard annotation.type == .image, let pdfReaderViewController = navigationController?.viewControllers.last as? PDFReaderViewController else { return }
        let annotationPreviewController = controllers.annotationPreviewController
        let pageIndex: PageIndex = UInt(annotation.page)
        let rect = annotation.boundingBox(boundingBoxConverter: pdfReaderViewController)
        var size = rect.size
        size.width *= scale
        size.height *= scale
        annotationPreviewController.render(
            document: state.document,
            page: pageIndex,
            rect: rect,
            imageSize: size,
            imageScale: 1.0,
            key: annotation.key,
            parentKey: state.key,
            libraryId: state.library.id
        )
        .observe(on: MainScheduler.instance)
        .subscribe { [weak self] (image: UIImage) in
            guard let self else { return }
            if let coordinator = self.childCoordinators.last, coordinator is AnnotationPopoverCoordinator {
                coordinator.share(item: image, sourceView: .view(sender, nil))
            } else {
                (self as Coordinator).share(item: image, sourceView: .view(sender, nil))
            }
        } onFailure: { (error: Error) in
            DDLogError("PDFCoordinator: can't render annotation image - \(error)")
            // TODO: show error?
        }
        .disposed(by: disposeBag)
    }
    
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, picked: @escaping ([Tag]) -> Void) {
        guard let navigationController else { return }
        (self.parentCoordinator as? DetailCoordinator)?.showTagPicker(
            libraryId: libraryId,
            selected: selected,
            userInterfaceStyle: userInterfaceStyle,
            navigationController: navigationController,
            picked: picked
        )
    }

    func showFilterPopup(
        from barButton: UIBarButtonItem,
        filter: AnnotationsFilter?,
        availableColors: [String],
        availableTags: [Tag],
        userInterfaceStyle: UIUserInterfaceStyle,
        completed: @escaping (AnnotationsFilter?) -> Void
    ) {
        DDLogInfo("PDFCoordinator: show annotations filter popup")

        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle

        let coordinator = AnnotationsFilterPopoverCoordinator(
            initialFilter: filter,
            availableColors: availableColors,
            availableTags: availableTags,
            navigationController: navigationController,
            controllers: self.controllers,
            completionHandler: completed
        )
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.barButtonItem = barButton
            navigationController.popoverPresentationController?.permittedArrowDirections = .down
        }

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showCellOptions(
        for annotation: Annotation,
        userId: Int,
        library: Library,
        sender: UIButton,
        userInterfaceStyle: UIUserInterfaceStyle,
        saveAction: @escaping AnnotationEditSaveAction,
        deleteAction: @escaping AnnotationEditDeleteAction
    ) {
        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle

        let coordinator = AnnotationEditCoordinator(
            annotation: annotation,
            userId: userId,
            library: library,
            saveAction: saveAction,
            deleteAction: deleteAction,
            navigationController: navigationController,
            controllers: self.controllers
        )
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.sourceView = sender
            navigationController.popoverPresentationController?.permittedArrowDirections = .left
        }
        
        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }
}
