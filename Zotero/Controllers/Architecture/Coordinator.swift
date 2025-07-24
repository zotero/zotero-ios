//
//  Coordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 10/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

private enum Source {
    case view(UIView, CGRect)
    case item(UIPopoverPresentationControllerSourceItem)
}

protocol Coordinator: AnyObject {
    var parentCoordinator: Coordinator? { get set }
    var childCoordinators: [Coordinator] { get set }
    var navigationController: UINavigationController? { get }

    func start(animated: Bool)
    func childDidFinish(_ child: Coordinator)
    func share(
        item: Any,
        sourceItem: UIPopoverPresentationControllerSourceItem,
        presenter: UIViewController?,
        userInterfaceStyle: UIUserInterfaceStyle?,
        completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler?
    )
    func share(
        item: Any,
        sourceView: UIView,
        sourceRect: CGRect,
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

    private func share(
        item: Any,
        source: Source,
        presenter: UIViewController?,
        userInterfaceStyle: UIUserInterfaceStyle?,
        completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler?
    ) {
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        if let userInterfaceStyle {
            controller.overrideUserInterfaceStyle = userInterfaceStyle
        }
        controller.modalPresentationStyle = .pageSheet
        controller.completionWithItemsHandler = completionWithItemsHandler

        switch source {
        case .item(let item):
            controller.popoverPresentationController?.sourceItem = item

        case .view(let sourceView, let sourceRect):
            controller.popoverPresentationController?.sourceView = sourceView
            controller.popoverPresentationController?.sourceRect = sourceRect
        }

        (presenter ?? navigationController)?.present(controller, animated: true, completion: nil)
    }

    func share(
        item: Any,
        sourceItem: UIPopoverPresentationControllerSourceItem,
        presenter: UIViewController? = nil,
        userInterfaceStyle: UIUserInterfaceStyle? = nil,
        completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler? = nil
    ) {
        share(item: item, source: .item(sourceItem), presenter: presenter, userInterfaceStyle: userInterfaceStyle, completionWithItemsHandler: completionWithItemsHandler)
    }

    func share(
        item: Any,
        sourceView: UIView,
        sourceRect: CGRect,
        presenter: UIViewController? = nil,
        userInterfaceStyle: UIUserInterfaceStyle? = nil,
        completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler? = nil
    ) {
        share(item: item, source: .view(sourceView, sourceRect), presenter: presenter, userInterfaceStyle: userInterfaceStyle, completionWithItemsHandler: completionWithItemsHandler)
    }
}
