//
//  CitationBibliographyExportCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI
import WebKit

import CocoaLumberjackSwift
import RxSwift

protocol CitationBibliographyExportCoordinatorDelegate: AnyObject {
    func showStylePicker(picked: @escaping (Style) -> Void)
    func showLanguagePicker(picked: @escaping (ExportLocale) -> Void)
    func cancel()
}

final class CitationBibliographyExportCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private static let defaultSize: CGSize = CGSize(width: 600, height: 504)
    private let itemIds: Set<String>
    private let libraryId: LibraryIdentifier
    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(itemIds: Set<String>, libraryId: LibraryIdentifier, navigationController: NavigationViewController, controllers: Controllers) {
        self.itemIds = itemIds
        self.libraryId = libraryId
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        super.init()

        navigationController.delegate = self
        navigationController.dismissHandler = { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        guard let citationController = self.controllers.userControllers?.citationController else { return }

        let style: Style

        if let rStyle = try? self.controllers.bundledDataStorage.perform(request: ReadStyleDbRequest(identifier: Defaults.shared.exportStyleId)),
           let _style = Style(rStyle: rStyle) {
            style = _style
        } else {
            style = Style(identifier: "", dependencyId: nil, title: L10n.unknown, updated: Date(), href: URL(fileURLWithPath: ""),
                          filename: "", supportsBibliography: false, isNoteStyle: false, defaultLocale: nil)
        }

        let webView = WKWebView()
        webView.isHidden = true

        let localeId = style.defaultLocale ?? Defaults.shared.exportLocaleId
        let languageEnabled = style.defaultLocale == nil

        let state = CitationBibliographyExportState(itemIds: self.itemIds, libraryId: self.libraryId, selectedStyle: style, selectedLocaleId: localeId, languagePickerEnabled: languageEnabled,
                                                    selectedMode: Defaults.shared.exportOutputMode, selectedMethod: Defaults.shared.exportOutputMethod)
        var handler = CitationBibliographyExportActionHandler(citationController: citationController, fileStorage: self.controllers.fileStorage, webView: webView)
        handler.coordinatorDelegate = self
        let viewModel = ViewModel(initialState: state, handler: handler)

        viewModel.stateObservable
                 .subscribe(with: self, onNext: { `self`, state in
                     if state.changes.contains(.finished) {
                         self.cancel()
                     }

                     if let file = state.outputFile {
                         self.share(file: file)
                     }
                 })
                 .disposed(by: self.disposeBag)

        var view = CitationBibliographyExportView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = CitationBibliographyExportCoordinator.defaultSize

        self.navigationController.setViewControllers([controller], animated: animated)
        self.navigationController.view.insertSubview(webView, at: 0)
    }

    private func share(file: File) {
        let controller = UIActivityViewController(activityItems: [file.createUrl()], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        controller.popoverPresentationController?.barButtonItem = self.navigationController.navigationBar.topItem?.rightBarButtonItem
        controller.completionWithItemsHandler = { [weak self] _, finished, _, _ in
            if finished {
                self?.cancel()
            }
        }
        self.navigationController.present(controller, animated: true, completion: nil)
    }
}

extension CitationBibliographyExportCoordinator: CitationBibliographyExportCoordinatorDelegate {
    func showStylePicker(picked: @escaping (Style) -> Void) {
        let handler = StylePickerActionHandler(dbStorage: self.controllers.bundledDataStorage)
        let state = StylePickerState(selected: Defaults.shared.exportStyleId)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let view = StylePickerView(picked: picked)
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = CGSize(width: CitationBibliographyExportCoordinator.defaultSize.width, height: UIScreen.main.bounds.size.height)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showLanguagePicker(picked: @escaping (ExportLocale) -> Void) {
        let handler = ExportLocalePickerActionHandler(fileStorage: self.controllers.fileStorage)
        let state = ExportLocalePickerState(selected: Defaults.shared.exportLocaleId)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let view = ExportLocalePickerView(picked: picked)
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = CGSize(width: CitationBibliographyExportCoordinator.defaultSize.width, height: UIScreen.main.bounds.size.height)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func cancel() {
        self.navigationController.parent?.presentingViewController?.dismiss(animated: true, completion: nil)
    }
}

extension CitationBibliographyExportCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard viewController.preferredContentSize.width > 0 && viewController.preferredContentSize.height > 0 else { return }
        navigationController.preferredContentSize = viewController.preferredContentSize
    }
}
