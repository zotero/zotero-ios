//
//  ParentWithSidebarController.swift
//  Zotero
//
//  Created by Michal Rentka on 11.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol ParentWithSidebarDocumentController: UIViewController {
    func disableAnnotationTools()
}

protocol ParentWithSidebarController: UIViewController {
    associatedtype DocumentController: ParentWithSidebarDocumentController
    associatedtype SidebarController: UIViewController

    var toolbarButton: UIBarButtonItem { get }
    /// Fixed leading navigation bar buttons (never overflow), in visual left-to-right order.
    var navigationBarLeadingItems: [UIBarButtonItem] { get set }
    /// Fixed trailing navigation bar buttons (never overflow), in visual left-to-right order. Laid out inboard of
    /// (to the left of) the overflow group.
    var navigationBarTrailingFixedItems: [UIBarButtonItem] { get set }
    /// Trailing navigation bar buttons that may collapse into the system "•••" overflow menu when the bar runs out
    /// of room, in visual left-to-right order. Laid out at the trailing edge. Only menu-representable items (image/
    /// title + action or menu) belong here — custom-view buttons can't be shown in a menu.
    var navigationBarOverflowItems: [UIBarButtonItem] { get set }
    var documentController: DocumentController? { get }
    var documentControllerLeft: NSLayoutConstraint? { get }
    var sidebarController: SidebarController? { get }
    var sidebarControllerLeft: NSLayoutConstraint? { get }
    var annotationToolbarController: AnnotationToolbarViewController? { get }
    var annotationToolbarHandler: AnnotationToolbarHandler? { get }
    var toolbarState: AnnotationToolbarHandler.State { get }
    var isSidebarVisible: Bool { get }
    var isToolbarVisible: Bool { get }
    var isCompactWidth: Bool { get }
    var isDocumentLocked: Bool { get }
    var disposeBag: DisposeBag { get }
    var windowSize: CGSize { get }

    func createToolbarButton() -> UIBarButtonItem
    func closeAnnotationToolbar()
    func initializeSidebarIfNeeded()
    func toggleSidebar(animated: Bool, sidebarButtonTag: Int)
    func setupAccessibility(forSidebarButton button: UIBarButtonItem)
    func add(controller: UIViewController)
}

extension ParentWithSidebarController {
    var windowSize: CGSize {
        return view.window?.bounds.size ?? navigationController?.view.frame.size ?? .zero
    }

    var isToolbarVisible: Bool {
        return toolbarState.visible
    }

    /// Builds the navigation bar from item groups so that, when the bar runs out of room, the overflow items collapse
    /// into the system "•••" menu instead of being squashed/clipped (which is what happens with the classic
    /// `left/rightBarButtonItems` arrays).
    ///
    /// - Each fixed item gets its own `fixedGroup` so they keep the standard discrete inter-item spacing (items inside
    ///   a single group are clustered tightly together).
    /// - On iPad the overflow items share one `optionalGroup`; the system moves them into a "•••" menu together when
    ///   space is tight (e.g. minimum split-view width). Only menu-representable items belong there — custom-view
    ///   buttons stay fixed.
    /// - On iPhone the overflow items are kept fixed as well — everything fits and having all buttons visible looks
    ///   better than collapsing some into a "•••" menu.
    /// - `trailingItemGroups` are laid out leading→trailing in array order, so the fixed groups come first (inboard)
    ///   and the overflow group sits at the trailing edge.
    func applyNavigationBarButtons(windowSize: CGSize) {
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace, primaryAction: nil, menu: nil)

        if windowSize.width < 385 {
            navigationItem.leftBarButtonItems = nil
            navigationItem.rightBarButtonItems = nil

            navigationItem.leadingItemGroups = navigationBarLeadingItems.map { $0.creatingFixedGroup() }

            var trailingGroups = [spacer.creatingFixedGroup()] + navigationBarTrailingFixedItems.map { $0.creatingFixedGroup() }
            if !navigationBarOverflowItems.isEmpty {
                trailingGroups.append(.optionalGroup(customizationIdentifier: "ParentWithSidebar.overflow", items: navigationBarOverflowItems))
            }
            navigationItem.trailingItemGroups = trailingGroups
        } else {
            navigationItem.leadingItemGroups = []
            navigationItem.trailingItemGroups = []

            navigationItem.leftBarButtonItems = navigationBarLeadingItems
            navigationItem.rightBarButtonItems = (navigationBarTrailingFixedItems + navigationBarOverflowItems).reversed() + [spacer]
        }
    }

    var isSidebarVisible: Bool {
        return sidebarControllerLeft?.constant == 0
    }

    func createToolbarButton() -> UIBarButtonItem {
        let barButton: UIBarButtonItem
        let imageSystemName = "pencil.and.outline"
        let image = UIImage(systemName: imageSystemName)
        if #available(iOS 26.0.0, *) {
            barButton = UIBarButtonItem(image: image)
            barButton.changesSelectionAsPrimaryAction = true
            barButton.isSelected = !isDocumentLocked && isToolbarVisible
            barButton.tintColor = barButton.isSelected ? Asset.Colors.zoteroBlue.color : nil
            barButton.primaryAction = UIAction(title: "", image: image) { [weak self] _ in
                guard let self else { return }
                setAnnotationToolbar(hidden: toolbarButton.isSelected)
            }
        } else {
            image?.applyingSymbolConfiguration(.init(scale: .large))
            let checkbox = CheckboxButton(image: image!, contentInsets: NSDirectionalEdgeInsets(top: 11, leading: 6, bottom: 9, trailing: 6))
            checkbox.scalesLargeContentImage = true
            checkbox.deselectedBackgroundColor = .clear
            checkbox.deselectedTintColor = isDocumentLocked ? .gray : Asset.Colors.zoteroBlueWithDarkMode.color
            checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
            checkbox.selectedTintColor = .white
            checkbox.isSelected = !isDocumentLocked && isToolbarVisible
            checkbox.rx.controlEvent(.touchUpInside)
                .subscribe(onNext: { [weak self, weak checkbox] _ in
                    guard let self, let checkbox else { return }
                    setAnnotationToolbar(hidden: checkbox.isSelected)
                })
                .disposed(by: disposeBag)
            barButton = UIBarButtonItem(customView: checkbox)
        }
        barButton.isEnabled = !isDocumentLocked
        barButton.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.title = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.largeContentSizeImage = UIImage(systemName: imageSystemName, withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        return barButton
    }

    private func setAnnotationToolbar(hidden: Bool) {
        if #available(iOS 26.0.0, *) {
            toolbarButton.isSelected = !hidden
            toolbarButton.tintColor = toolbarButton.isSelected ? Asset.Colors.zoteroBlue.color : nil
        } else {
            (toolbarButton.customView as? CheckboxButton)?.isSelected = !hidden
        }
        annotationToolbarHandler?.set(hidden: hidden, animated: true)
        if hidden {
            documentController?.disableAnnotationTools()
        }
    }

    func closeAnnotationToolbar() {
        setAnnotationToolbar(hidden: true)
    }

    func toggleSidebar(animated: Bool, sidebarButtonTag: Int) {
        let visible = !isSidebarVisible
        if visible {
            initializeSidebarIfNeeded()
        }
        // If the layout is compact, show annotation sidebar above pdf document.
        if !isCompactWidth {
            documentControllerLeft?.constant = visible ? PDFReaderLayout.sidebarWidth : 0
        } else if visible && toolbarState.visible {
            closeAnnotationToolbar()
        }
        sidebarControllerLeft?.constant = visible ? 0 : -PDFReaderLayout.sidebarWidth
        if toolbarState.visible {
            annotationToolbarHandler?.recalculateConstraints()
        }

        if let button = navigationItem.leftBarButtonItems?.first(where: { $0.tag == sidebarButtonTag }) {
            setupAccessibility(forSidebarButton: button)
        }

        if !animated {
            sidebarController?.view.isHidden = !visible
            annotationToolbarController?.prepareForSizeChange()
            view.layoutIfNeeded()
            annotationToolbarController?.sizeDidChange()

            if !visible {
                view.endEditing(true)
            }
            return
        }

        if visible {
            sidebarController?.view.isHidden = false
        } else {
            view.endEditing(true)
        }

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 5, options: [.curveEaseOut], animations: { [weak self] in
            guard let self else { return }
            annotationToolbarController?.prepareForSizeChange()
            view.layoutIfNeeded()
            annotationToolbarController?.sizeDidChange()
        }, completion: { [weak self] finished in
            guard let self, finished else { return }
            if !visible {
                sidebarController?.view.isHidden = true
            }
        })
    }

    func setupAccessibility(forSidebarButton button: UIBarButtonItem) {
        button.accessibilityLabel = isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        button.title = isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
    }

    func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        addChild(controller)
        controller.didMove(toParent: self)
    }
}
