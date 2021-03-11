//
//  CreatorEditViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

typealias CreatorEditSaveAction = (ItemDetailState.Creator) -> Void
typealias CreatorEditDeleteAction = (UUID) -> Void

final class CreatorEditViewController: UIViewController {
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
    @IBOutlet private weak var deleteContainer: UIView!
    @IBOutlet private weak var deleteButton: UIButton!

    private static let width: CGFloat = 400

    private let viewModel: ViewModel<CreatorEditActionHandler>
    private let saveAction: CreatorEditSaveAction
    private let deleteAction: CreatorEditDeleteAction?
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: DetailCreatorEditCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<CreatorEditActionHandler>, saved: @escaping CreatorEditSaveAction, deleted: CreatorEditDeleteAction?) {
        self.viewModel = viewModel
        self.saveAction = saved
        self.deleteAction = deleted
        self.disposeBag = DisposeBag()
        super.init(nibName: "CreatorEditViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.typeValue.textColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        })
        self.setupSeparatorHeight()
        self.setupNavigationItems()
        self.setup(creator: self.viewModel.state.creator)
        self.setupObservers()
        self.navigationItem.title = self.viewModel.state.creator.localizedType
        self.setupConstraints()

        self.viewModel.stateObservable
            .subscribeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.update(preferredContentSize: self.calculateSize(for: self.viewModel.state.creator.namePresentation))
    }

    // MARK: - Actions

    private func update(to state: CreatorEditState) {
        if state.changes.contains(.namePresentation) {
            self.updateLayout(for: state.creator)
        }
        if state.changes.contains(.type) {
            self.typeValue.text = state.creator.localizedType
            self.navigationItem.title = state.creator.localizedType
        }
    }

    private func updateLayout(for creator: ItemDetailState.Creator) {
        switch creator.namePresentation {
        case .full:
            self.input1Title.text = L10n.name
            self.input1TextField.text = creator.fullName
            self.switchButton.setTitle(L10n.CreatorEditor.switchToDual, for: .normal)

        case .separate:
            self.input1Title.text = L10n.CreatorEditor.lastName
            self.input1TextField.text = creator.lastName
            self.input2Title.text = L10n.CreatorEditor.firstName
            self.input2TextField.text = creator.firstName
            self.switchButton.setTitle(L10n.CreatorEditor.switchToSingle, for: .normal)
        }

        self.input2Container.isHidden = creator.namePresentation == .full
        self.input2Separator.isHidden = self.input2Container.isHidden

        self.update(preferredContentSize: self.calculateSize(for: creator.namePresentation))
    }

    private func update(preferredContentSize contentSize: CGSize) {
        self.preferredContentSize = contentSize
        self.navigationController?.preferredContentSize = contentSize
    }

    private func calculateSize(for namePresentation: ItemDetailState.Creator.NamePresentation) -> CGSize {
        let separatorHeight = 1 / UIScreen.main.scale
        var height = 194 + (3 * separatorHeight)
        if namePresentation == .separate {
            height += separatorHeight + 43
        }
        if self.deleteAction != nil {
            height += 64
        }
        return CGSize(width: CreatorEditViewController.width, height: height)
    }

    @IBAction private func toggleNamePresentation() {
        var namePresentation = self.viewModel.state.creator.namePresentation
        namePresentation.toggle()
        self.viewModel.process(action: .setNamePresentation(namePresentation))
    }

    @IBAction private func showTypePicker() {
        self.coordinatorDelegate?.showCreatorTypePicker(itemType: self.viewModel.state.itemType, selected: self.viewModel.state.creator.type, picked: { [weak self] newType in
            self?.viewModel.process(action: .setType(newType))
        })
    }

    @IBAction private func delete() {
        let controller = UIAlertController(title: L10n.warning, message: L10n.CreatorEditor.deleteConfirmation, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { [weak self] _ in
            guard let `self` = self else { return }
            self.deleteAction?(self.viewModel.state.creator.id)
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }))
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        self.present(controller, animated: true, completion: nil)
    }

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
        self.typeTitle.text = L10n.CreatorEditor.creator
        self.typeValue.text = creator.localizedType

        self.deleteContainer.isHidden = self.deleteAction == nil
        if !self.deleteContainer.isHidden {
            self.deleteButton.setTitle("\(L10n.delete) \(creator.localizedType)", for: .normal)
        }

        self.updateLayout(for: creator)
    }

    private func setupObservers() {
        self.input1TextField.rx
            .controlEvent(.editingChanged)
            .flatMap({ Observable.just(self.input1TextField.text ?? "") })
            .subscribe(onNext: { [weak self] value in
                guard let `self` = self else { return }
                switch self.viewModel.state.creator.namePresentation {
                case .full:
                    self.viewModel.process(action: .setFullName(value))
                case .separate:
                    self.viewModel.process(action: .setLastName(value))
                }
            })
            .disposed(by: self.disposeBag)

        self.input2TextField.rx
            .controlEvent(.editingChanged)
            .flatMap({ Observable.just(self.input2TextField.text ?? "") })
            .subscribe(onNext: { [weak self] value in
                self?.viewModel.process(action: .setFirstName(value))
            })
            .disposed(by: self.disposeBag)
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
                  self.saveAction(self.viewModel.state.creator)
                  self.presentingViewController?.dismiss(animated: true, completion: nil)
              })
              .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = save
    }

    private func setupSeparatorHeight() {
        let height = 1 / UIScreen.main.scale
        self.setSeparatorHeight(to: height, in: self.view.subviews)
    }

    private func setupConstraints() {
        self.view.widthAnchor.constraint(equalToConstant: CreatorEditViewController.width).isActive = true
    }
}

extension UIView {
    fileprivate func setHeightConstraint(to value: CGFloat) {
        guard let constraint = self.constraints.first(where: { $0.isActive && $0.firstAttribute == .height }) else { return }
        constraint.constant = value
    }
}
