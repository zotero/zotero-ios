//
//  AnnotationEditCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 07.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import CocoaLumberjackSwift
import RxSwift

final class AnnotationEditCoordinator: Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private let annotation: Annotation
    private let userId: Int
    private let library: Library
    private let previewCache: AnnotationsPreviewCache
    private let saveAction: AnnotationEditSaveAction
    private let deleteAction: AnnotationEditDeleteAction
    private unowned let controllers: Controllers
    unowned let navigationController: UINavigationController
    private let disposeBag: DisposeBag

    init(annotation: Annotation, userId: Int, library: Library, previewCache: AnnotationsPreviewCache, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction, navigationController: NavigationViewController, controllers: Controllers) {
        self.annotation = annotation
        self.userId = userId
        self.library = library
        self.previewCache = previewCache
        self.saveAction = saveAction
        self.deleteAction = deleteAction
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        navigationController.dismissHandler = {
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("AnnotationEditCoordinator: deinitialized")
    }

    private func share(image: UIImage) {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        controller.popoverPresentationController?.sourceView = self.navigationController.viewControllers.first?.view
        controller.completionWithItemsHandler = { [weak self] _, finished, _, _ in
            if finished {
                self?.cancel()
            }
        }
        self.navigationController.present(controller, animated: true)
    }

    func cancel() {
        self.navigationController.parent?.presentingViewController?.dismiss(animated: true, completion: nil)
    }


    func start(animated: Bool) {
        let state = AnnotationEditState(annotation: self.annotation, userId: self.userId, library: self.library)
        let handler = AnnotationEditActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationEditViewController(viewModel: viewModel, includeColorPicker: true, saveAction: self.saveAction, deleteAction: self.deleteAction)
        controller.coordinatorDelegate = self
        self.navigationController.setViewControllers([controller], animated: false)
    }
}

extension AnnotationEditCoordinator: AnnotationEditCoordinatorDelegate {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction) {
        let state = AnnotationPageLabelState(label: label, updateSubsequentPages: updateSubsequentPages)
        let handler = AnnotationPageLabelActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationPageLabelViewController(viewModel: viewModel, saveAction: saveAction)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showShare(key: PDFReaderState.AnnotationKey) {
        let nsKey = key.key as NSString
        guard let image = previewCache.object(forKey: nsKey) else { return }
        self.share(image: image)
    }
}

#endif
