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
    /// Leading navigation bar buttons in visual order, starting with Close.
    var navigationBarLeadingItems: [UIBarButtonItem] { get set }
    /// Primary trailing navigation bar buttons in visual order, before the optional group.
    var navigationBarTrailingFixedItems: [UIBarButtonItem] { get set }
    /// Trailing navigation bar buttons that may collapse into the system "•••" overflow menu when the bar runs out
    /// of room, in visual left-to-right order. Laid out at the trailing edge. Only menu-representable items (image/
    /// title + action or menu) belong here — custom-view buttons can't be shown in a menu.
    var navigationBarOverflowItems: [UIBarButtonItem] { get set }
    var documentController: DocumentController? { get }
    var documentControllerLeft: NSLayoutConstraint? { get }
    var sidebarController: SidebarController? { get }
    var sidebarControllerLeft: NSLayoutConstraint? { get }
    var sidebarControllerWidth: NSLayoutConstraint? { get }
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
    /// The sidebar is shown over the document in compact width readers, otherwise it is shown next to the document (moving it).
    var isSidebarOverlay: Bool {
        return ReaderLayout.isCompactWidth(size: view.bounds.size)
    }

    /// When shown over the document in compact horizontal size class, the sidebar spans the whole reader width, otherwise it has a fixed width.
    var sidebarWidth: CGFloat {
        guard isSidebarOverlay, traitCollection.horizontalSizeClass == .compact else { return ReaderLayout.fixedSidebarWidth }
        return view.bounds.width
    }

    /// Updates sidebar width and document offset for the current reader size and traits. Call when either changes.
    func updateSidebarLayout() {
        let width = sidebarWidth
        sidebarControllerWidth?.constant = width
        guard isSidebarVisible else { return }
        documentControllerLeft?.constant = isSidebarOverlay ? 0 : width
    }

    var windowSize: CGSize {
        return view.window?.bounds.size ?? navigationController?.view.frame.size ?? .zero
    }

    var isToolbarVisible: Bool {
        return toolbarState.visible
    }

    /// Groups the leading controls separately from Close. On iOS 26 and later, individual trailing groups
    /// can share a background and overflow independently.
    func applyNavigationBarButtons(windowSize: CGSize) {
        let trailingItems = navigationBarTrailingFixedItems + navigationBarOverflowItems
        if #unavailable(iOS 26.0), windowSize.width >= 385 {
            navigationItem.leadingItemGroups = []
            navigationItem.trailingItemGroups = []
            navigationItem.leftBarButtonItems = navigationBarLeadingItems
            navigationItem.rightBarButtonItems = trailingItems.reversed() + [.flexibleSpace()]
            return
        }

        navigationItem.leftBarButtonItems = nil
        var leadingGroups: [UIBarButtonItemGroup] = []
        if let closeButton = navigationBarLeadingItems.first {
            leadingGroups.append(closeButton.creatingFixedGroup())
        }
        let readerButtons = Array(navigationBarLeadingItems.dropFirst())
        if !readerButtons.isEmpty {
            leadingGroups.append(.fixedGroup(items: readerButtons))
        }
        navigationItem.leadingItemGroups = leadingGroups

        navigationItem.rightBarButtonItems = nil
        if #available(iOS 26.0, *) {
            navigationItem.trailingItemGroups = trailingItems.map { $0.creatingFixedGroup() }
        } else {
            var trailingGroups = [UIBarButtonItem.flexibleSpace().creatingFixedGroup()]
            trailingGroups += navigationBarTrailingFixedItems.map { $0.creatingFixedGroup() }
            if !navigationBarOverflowItems.isEmpty {
                trailingGroups.append(.optionalGroup(customizationIdentifier: "ParentWithSidebar.overflow", items: navigationBarOverflowItems))
            }
            navigationItem.trailingItemGroups = trailingGroups
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
            let checkbox = CheckboxButton(
                image: image?.applyingSymbolConfiguration(.init(scale: .large)),
                contentInsets: NSDirectionalEdgeInsets(top: 11, leading: 6, bottom: 9, trailing: 6)
            )
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
        updateToolbarButtonSelection(isSelected: !hidden)
        annotationToolbarHandler?.set(hidden: hidden, animated: true)
        if hidden {
            documentController?.disableAnnotationTools()
        }
    }

    func closeAnnotationToolbar() {
        setAnnotationToolbar(hidden: true)
    }

    func updateToolbarButtonSelection(isSelected: Bool) {
        if #available(iOS 26.0.0, *) {
            toolbarButton.isSelected = isSelected
            toolbarButton.tintColor = isSelected ? Asset.Colors.zoteroBlue.color : nil
        } else {
            (toolbarButton.customView as? CheckboxButton)?.isSelected = isSelected
        }
    }

    func toggleSidebar(animated: Bool, sidebarButtonTag: Int) {
        let visible = !isSidebarVisible
        if visible {
            initializeSidebarIfNeeded()
        }
        // If the sidebar is an overlay, show it above the document.
        let width = sidebarWidth
        if !isSidebarOverlay {
            documentControllerLeft?.constant = visible ? width : 0
        } else if visible && toolbarState.visible {
            closeAnnotationToolbar()
        }
        sidebarControllerLeft?.constant = visible ? 0 : -width
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
