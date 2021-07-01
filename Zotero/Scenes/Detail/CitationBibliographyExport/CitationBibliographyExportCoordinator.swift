//
//  CitationBibliographyExportCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import CocoaLumberjackSwift

protocol CitationBibliographyExportCoordinatorDelegate: AnyObject {
    func showStylePicker(picked: @escaping (Style) -> Void)
    func showLanguagePicker(picked: @escaping (ExportLocale) -> Void)
    func cancel()
}

final class CitationBibliographyExportCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private static let defaultSize: CGSize = CGSize(width: 600, height: 456)

    init(navigationController: NavigationViewController, controllers: Controllers) {
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []

        super.init()

        navigationController.delegate = self
        navigationController.dismissHandler = { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        do {
            let styleId = Defaults.shared.quickCopyStyleId
            let rStyle = try self.controllers.bundledDataStorage.createCoordinator().perform(request: ReadStyleDbRequest(identifier: styleId))
            guard let style = Style(rStyle: rStyle) else { return }

            let state = CitationBibliographyExportState(selectedStyle: style, selectedLocaleId: Defaults.shared.quickCopyLocaleId)
            let handler = CitationBibliographyExportActionHandler(citationController: self.controllers.citationController)
            let viewModel = ViewModel(initialState: state, handler: handler)

            var view = CitationBibliographyExportView()
            view.coordinatorDelegate = self

            let controller = UIHostingController(rootView: view.environmentObject(viewModel))
            controller.preferredContentSize = CitationBibliographyExportCoordinator.defaultSize

            self.navigationController.setViewControllers([controller], animated: animated)
        } catch let error {
            DDLogError("DetailCoordinator: can't open citeexport - \(error)")
        }
    }
}

extension CitationBibliographyExportCoordinator: CitationBibliographyExportCoordinatorDelegate {
    func showStylePicker(picked: @escaping (Style) -> Void) {
        let handler = StylePickerActionHandler(dbStorage: self.controllers.bundledDataStorage)
        let state = StylePickerState(selected: Defaults.shared.quickCopyStyleId)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let view = StylePickerView(picked: picked)
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = CGSize(width: CitationBibliographyExportCoordinator.defaultSize.width, height: UIScreen.main.bounds.size.height)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showLanguagePicker(picked: @escaping (ExportLocale) -> Void) {
        let handler = ExportLocalePickerActionHandler(fileStorage: self.controllers.fileStorage)
        let state = ExportLocalePickerState(selected: Defaults.shared.quickCopyLocaleId)
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
