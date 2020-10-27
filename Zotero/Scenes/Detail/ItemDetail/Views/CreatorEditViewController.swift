//
//  CreatorEditViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CreatorEditViewController: UIViewController {
    @IBOutlet private weak var typeTitle: UILabel!
    @IBOutlet private weak var typeValue: UILabel!
    @IBOutlet private weak var input1Container: UIView!
    @IBOutlet private weak var input1Title: UILabel!
    @IBOutlet private weak var input1TextField: UITextField!
    @IBOutlet private weak var input1Separator: UIView!
    @IBOutlet private weak var input2Container: UIView!
    @IBOutlet private weak var input2Title: UILabel!
    @IBOutlet private weak var input2TextField: UITextField!
    @IBOutlet private weak var input2Separator: UIView!
    @IBOutlet private weak var switchButton: UIButton!
    @IBOutlet private weak var deleteButton: UIButton!

    private unowned let viewModel: ViewModel<ItemDetailActionHandler>
    private unowned let schemaController: SchemaController
    private let disposeBag: DisposeBag

    private var creator: ItemDetailState.Creator
    weak var coordinatorDelegate: DetailCreatorEditCoordinatorDelegate?

    // MARK: - Lifecycle

    init(creator: ItemDetailState.Creator, viewModel: ViewModel<ItemDetailActionHandler>, schemaController: SchemaController) {
        self.creator = creator
        self.viewModel = viewModel
        self.schemaController = schemaController
        self.disposeBag = DisposeBag()
        super.init(nibName: "CreatorEditViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupSeparatorHeight()
        self.setupNavigationItems()
        self.setup(creator: self.creator)
    }

    // MARK: - Actions

    private func setSeparatorHeight(to height: CGFloat, in views: [UIView]) {
        for view in views {
            if view.frame.height == 1 {
                view.setHeightConstraint(to: height)
            }
            if !view.subviews.isEmpty {
                self.setSeparatorHeight(to: height, in: view.subviews)
            }
        }
    }

    // MARK: - Setups

    private func setup(creator: ItemDetailState.Creator) {
        self.typeTitle.text = creator.localizedType
        self.deleteButton.setTitle("\(L10n.delete) \(creator.localizedType)", for: .normal)

        switch creator.namePresentation {
        case .full:
            self.input1Title.text = L10n.name
            self.input1TextField.text = creator.name
            self.switchButton.setTitle(L10n.CreatorEditor.switchToDual, for: .normal)

        case .separate:
            self.input1Title.text = L10n.CreatorEditor.lastName
            self.input1TextField.text = creator.lastName
            self.input2Title.text = L10n.CreatorEditor.firstName
            self.input1TextField.text = creator.firstName
            self.switchButton.setTitle(L10n.CreatorEditor.switchToSingle, for: .normal)
        }

        self.input2Container.isHidden = creator.namePresentation == .full
        self.input2Separator.isHidden = self.input2Container.isHidden
    }

    private func setupNavigationItems() {
        let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancel.rx.tap
              .subscribe(onNext: { [weak self] in
                  self?.presentingViewController?.dismiss(animated: true, completion: nil)
              })
              .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancel

        let save = UIBarButtonItem(title: L10n.save, style: .done, target: nil, action: nil)
        save.rx.tap
              .subscribe(onNext: { [weak self] in
                  guard let `self` = self else { return }
                  self.viewModel.process(action: .saveCreator(self.creator))
                  self.presentingViewController?.dismiss(animated: true, completion: nil)
              })
              .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = save
    }

    private func setupSeparatorHeight() {
        let height = 1 / UIScreen.main.scale
        self.setSeparatorHeight(to: height, in: self.view.subviews)
    }
}

extension UIView {
    fileprivate func setHeightConstraint(to value: CGFloat) {
        guard let constraint = self.constraints.first(where: { $0.isActive && $0.firstAttribute == .height }) else { return }
        constraint.constant = value
    }
}
