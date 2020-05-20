//
//  ItemDetailCreatorEditingCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class ItemDetailCreatorEditingCell: RxTableViewCell {
    @IBOutlet private weak var titleButton: UIButton!
    @IBOutlet private weak var splitContainer: UIStackView!
    @IBOutlet private weak var firstNameTextField: UITextField!
    @IBOutlet private weak var lastNameTextField: UITextField!
    @IBOutlet private weak var fullTextField: UITextField!
    @IBOutlet private weak var namePresentationButton: UIButton!

    private var namePresentation: ItemDetailState.Creator.NamePresentation = .full

    var typeObservable: ControlEvent<()> {
        return self.titleButton.rx.controlEvent(.touchUpInside)
    }
    var namePresentationObservable: Observable<ItemDetailState.Creator.NamePresentation> {
        return self.namePresentationButton.rx.controlEvent(.touchUpInside)
                             .flatMap { _ -> Observable<ItemDetailState.Creator.NamePresentation> in
                                 return Observable.just(self.namePresentation == .full ? .separate : .full)
                             }
    }
    var firstNameObservable: ControlProperty<String> {
        return self.firstNameTextField.rx.text.orEmpty
    }
    var lastNameObservable: ControlProperty<String> {
        return self.lastNameTextField.rx.text.orEmpty
    }
    var fullNameObservable: ControlProperty<String> {
        return self.fullTextField.rx.text.orEmpty
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleButton.titleLabel?.font = UIFont.preferredFont(for: .headline, weight: .regular)
    }

    func setup(with creator: ItemDetailState.Creator) {
        let isSplit = creator.namePresentation == .separate
        self.namePresentation = creator.namePresentation
        self.titleButton.setTitle(creator.localizedType, for: .normal)
        self.splitContainer.isHidden = !isSplit
        self.fullTextField.isHidden = isSplit
        self.firstNameTextField.text = creator.firstName
        self.lastNameTextField.text = creator.lastName
        self.fullTextField.text = creator.fullName
        self.namePresentationButton.setTitle((isSplit ? L10n.ItemDetail.mergeName : L10n.ItemDetail.splitName), for: .normal)
    }
}
