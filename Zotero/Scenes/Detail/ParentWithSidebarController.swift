//
//  ParentWithSidebarController.swift
//  Zotero
//
//  Created by Michal Rentka on 11.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ParentWithSidebarController: UIViewController {
    func createToolbarButton() -> UIBarButtonItem
}

extension ParentWithSidebarController {
    func createToolbarButton(isSelected: Bool, deselectedTintColor: UIColor) -> UIBarButtonItem {
        var configuration = UIButton.Configuration.plain()
        let image = UIImage(systemName: "pencil.and.outline")?.applyingSymbolConfiguration(.init(scale: .large))
        let checkbox = CheckboxButton(image: image!, contentInsets: NSDirectionalEdgeInsets(top: 11, leading: 6, bottom: 9, trailing: 6))
        checkbox.scalesLargeContentImage = true
        checkbox.deselectedBackgroundColor = .clear
        checkbox.deselectedTintColor = deselectedTintColor
        checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        checkbox.selectedTintColor = .white
        checkbox.isSelected = isSelected
        checkbox.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: { [weak self, weak checkbox] _ in
                guard let self, let checkbox else { return }
                checkbox.isSelected = !checkbox.isSelected
                annotationToolbarHandler.set(hidden: !checkbox.isSelected, animated: true)
            })
            .disposed(by: disposeBag)
        let barButton = UIBarButtonItem(customView: checkbox)
        barButton.isEnabled = !viewModel.state.document.isLocked
        barButton.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.title = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.largeContentSizeImage = UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        return barButton
    }
}
