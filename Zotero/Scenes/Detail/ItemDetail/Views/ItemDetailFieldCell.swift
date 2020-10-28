//
//  ItemDetailFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class ItemDetailFieldCell: RxTableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleTop: NSLayoutConstraint!
    @IBOutlet private weak var titleBottom: NSLayoutConstraint!
    @IBOutlet private weak var titleWidth: NSLayoutConstraint!
    @IBOutlet private weak var valueTextField: UITextField!
    @IBOutlet private weak var valueLabel: UILabel!
    @IBOutlet private weak var additionalInfoLabel: UILabel!
    @IBOutlet private weak var additionalInfoOffset: NSLayoutConstraint!

    private static let horizontalOffset: CGFloat = 16
    private static let verticalInset: CGFloat = 10
    private static let editingVerticalInset: CGFloat = 15

    var textObservable: Observable<String> {
        return self.valueTextField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.valueTextField.text ?? "") })
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
    }

    func setup(with field: ItemDetailState.Field, titleWidth: CGFloat, isEditing: Bool) {
        self.titleLabel.text = field.name
        self.valueTextField.text = field.value
        self.valueTextField.isHidden = !isEditing
        self.titleWidth.constant = titleWidth
        self.setAdditionalInfo(value: field.additionalInfo?[.dateOrder])

        self.valueLabel.text = field.value
        if !isEditing {
            if field.isTappable {
                self.valueLabel.textColor = Asset.Colors.zoteroBlue.color
            } else {
                self.valueLabel.textColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? .white : .black })
            }
        }
        self.valueLabel.isHidden = isEditing
        self.setupInsets(isEditing: isEditing)
    }

    func setup(with creator: ItemDetailState.Creator, titleWidth: CGFloat, isEditing: Bool) {
        self.titleLabel.text = creator.localizedType
        self.valueLabel.text = creator.name
        self.valueLabel.textColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? .white : .black })
        self.valueLabel.isHidden = false
        self.valueTextField.isHidden = true
        self.titleWidth.constant = titleWidth
        self.setAdditionalInfo(value: nil)
        self.setupInsets(isEditing: isEditing)
    }

    func setup(with date: String, title: String, titleWidth: CGFloat, isEditing: Bool) {
        self.titleLabel.text = title
        self.valueLabel.text = date
        self.valueLabel.textColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? .white : .black })
        self.valueLabel.isHidden = false
        self.valueTextField.isHidden = true
        self.titleWidth.constant = titleWidth
        self.setAdditionalInfo(value: nil)
        self.setupInsets(isEditing: isEditing)
    }

    private func setAdditionalInfo(value: String?) {
        if let value = value {
            self.additionalInfoLabel.text = value
        } else {
            self.additionalInfoLabel.text = nil
        }
        self.additionalInfoOffset.constant = value == nil ? 0 : ItemDetailFieldCell.horizontalOffset
    }

    private func setupInsets(isEditing: Bool) {
        let font = self.titleLabel.font!
        let separatorHeight = 1 / UIScreen.main.scale
        let inset = isEditing ? ItemDetailFieldCell.editingVerticalInset :
                                ItemDetailFieldCell.verticalInset
        self.titleTop.constant = inset - (font.ascender - font.capHeight) + (isEditing ? -separatorHeight : 0)
        self.titleBottom.constant = inset + (isEditing ? 1 : 0) - separatorHeight
    }
}
