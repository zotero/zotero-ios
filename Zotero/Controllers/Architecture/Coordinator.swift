//
//  Coordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 10/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum SourceView {
    case view(UIView, CGRect?)
    case item(UIBarButtonItem)
}

protocol Coordinator: AnyObject {
    var parentCoordinator: Coordinator? { get }
    var childCoordinators: [Coordinator] { get set }
    var navigationController: UINavigationController? { get }

    func start(animated: Bool)
    func childDidFinish(_ child: Coordinator)
    func share(
        item: Any,
        sourceView: SourceView,
        presenter: UIViewController?,
        userInterfaceStyle: UIUserInterfaceStyle?,
        completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler?
    )
}

extension Coordinator {
    func childDidFinish(_ child: Coordinator) {
        if let index = self.childCoordinators.firstIndex(where: { $0 === child }) {
            self.childCoordinators.remove(at: index)
        }

        // Take navigation controller delegate back from child if needed
        if self.navigationController?.delegate === child,
           let delegate = self as? UINavigationControllerDelegate {
            self.navigationController?.delegate = delegate
        }
    }

    func share(
        item: Any,
        sourceView: SourceView,
        presenter: UIViewController? = nil,
        userInterfaceStyle: UIUserInterfaceStyle? = nil,
        completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler? = nil
    ) {
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        if let userInterfaceStyle {
            controller.overrideUserInterfaceStyle = userInterfaceStyle
        }
        controller.modalPresentationStyle = .pageSheet
        controller.completionWithItemsHandler = completionWithItemsHandler

        switch sourceView {
        case .item(let item):
            controller.popoverPresentationController?.barButtonItem = item

        case .view(let sourceView, let sourceRect):
            controller.popoverPresentationController?.sourceView = sourceView
            if let rect = sourceRect {
                controller.popoverPresentationController?.sourceRect = rect
            }
        }

        (presenter ?? navigationController)?.present(controller, animated: true, completion: nil)
    }
}
