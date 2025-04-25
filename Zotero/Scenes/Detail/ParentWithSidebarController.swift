//
//  ParentWithSidebarController.swift
//  Zotero
//
//  Created by Michal Rentka on 11.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol ParentWithSidebarController: UIViewController {
    associatedtype DocumentController: UIViewController
    associatedtype SidebarController: UIViewController

    var toolbarButton: UIBarButtonItem { get }
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

    func createToolbarButton() -> UIBarButtonItem
    func closeAnnotationToolbar()
    func toggleSidebar(animated: Bool, sidebarButtonTag: Int)
    func setupAccessibility(forSidebarButton button: UIBarButtonItem)
}

extension ParentWithSidebarController {
    var isToolbarVisible: Bool {
        return toolbarState.visible
    }

    var isSidebarVisible: Bool {
        return sidebarControllerLeft?.constant == 0
    }

    func createToolbarButton() -> UIBarButtonItem {
        var configuration = UIButton.Configuration.plain()
        let image = UIImage(systemName: "pencil.and.outline")?.applyingSymbolConfiguration(.init(scale: .large))
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
                checkbox.isSelected = !checkbox.isSelected
                annotationToolbarHandler?.set(hidden: !checkbox.isSelected, animated: true)
            })
            .disposed(by: disposeBag)
        let barButton = UIBarButtonItem(customView: checkbox)
        barButton.isEnabled = !isDocumentLocked
        barButton.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.title = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.largeContentSizeImage = UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        return barButton
    }

    func closeAnnotationToolbar() {
        (toolbarButton.customView as? CheckboxButton)?.isSelected = false
        annotationToolbarHandler?.set(hidden: true, animated: true)
    }

    func toggleSidebar(animated: Bool, sidebarButtonTag: Int) {
        let visible = !isSidebarVisible
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
}
