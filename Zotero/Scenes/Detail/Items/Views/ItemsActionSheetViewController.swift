//
//  ItemsActionSheetViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 03/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemsActionSheetViewController: UIViewController {
    @IBOutlet private weak var menuView: UIView!
    @IBOutlet private weak var stackView: UIStackView!
    @IBOutlet private weak var containerTop: NSLayoutConstraint!
    @IBOutlet private weak var containerHeight: NSLayoutConstraint!
    private weak var sortFieldButton: UIButton!
    private weak var sortOrderButton: UIButton!

    private let topOffset: CGFloat
    private let viewModel: ViewModel<ItemsActionHandler>
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: DetailItemActionSheetCoordinatorDelegate?

    init(viewModel: ViewModel<ItemsActionHandler>, topOffset: CGFloat) {
        self.viewModel = viewModel
        self.topOffset = topOffset
        self.disposeBag = DisposeBag()

        super.init(nibName: "ItemsActionSheetViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.menuView.backgroundColor = self.traitCollection.userInterfaceStyle == .light ? .white : UIColor.black.withAlphaComponent(0.6)
        self.setupBackgroundGesture()
        self.setupActions(metadataEditable: self.viewModel.state.library.metadataEditable,
                          filesEditable: self.viewModel.state.library.filesEditable,
                          sortType: self.viewModel.state.sortType)
        self.containerTop.constant = self.topOffset
        self.view.layoutIfNeeded()

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.main.async {
            self.rollMenuDown()
        }
    }

    // MARK: - UI State

    private func update(state: ItemsState) {
        if state.changes.contains(.sortType) {
            let (fieldTitle, orderTitle) = self.sortButtonTitles(for: state.sortType)
            self.sortFieldButton.setTitle(fieldTitle, for: .normal)
            self.sortOrderButton.setTitle(orderTitle, for: .normal)
        }
    }

    private func sortButtonTitles(for sortType: ItemsSortType) -> (field: String, order: String) {
        let sortOrderTitle = sortType.ascending ? "Ascending" : "Descending"
        return ("Sort By: \(sortType.field.title)",
                "Sort Order: \(sortOrderTitle)")
    }

    // MARK: - Actions

    private func rollMenuDown() {
        self.containerHeight.constant = self.menuView.frame.height
        UIView.animate(withDuration: 0.35,
                       delay: 0,
                       usingSpringWithDamping: 1,
                       initialSpringVelocity: 5,
                       options: [.curveEaseOut],
                       animations: {
                           self.view.layoutIfNeeded()
                       },
                       completion: nil)
    }

    @objc private func startEditing() {
        self.dismiss(animated: true) {
            self.viewModel.process(action: .startEditing)
        }
    }

    @objc private func changeSortField() {
        self.dismiss(animated: true) {
            let binding = self.viewModel.binding(keyPath: \.sortType.field, action: { .setSortField($0) })
            self.coordinatorDelegate?.showSortTypePicker(sortBy: binding)
        }
    }

    @objc private func changeSortOrder() {
        self.viewModel.process(action: .toggleSortOrder)
    }

    @objc private func createNewItem() {
        self.dismiss(animated: true) {
            self.coordinatorDelegate?.showItemCreation(library: self.viewModel.state.library,
                                                       collectionKey: self.viewModel.state.type.collectionKey)
        }
    }

    @objc private func createNewNote() {
        let viewModel = self.viewModel
        self.dismiss(animated: true) {
            self.coordinatorDelegate?.showNoteCreation(save: { text in
                viewModel.process(action: .saveNote(nil, text))
            })
        }
    }

    @objc private func uploadAttachment() {
        let viewModel = self.viewModel
        self.dismiss(animated: true) {
            self.coordinatorDelegate?.showAttachmentPicker(save: { urls in
                viewModel.process(action: .addAttachments(urls))
            })
        }
    }

    // MARK: - Setups

    private func setupBackgroundGesture() {
        let tapRecognizer = UITapGestureRecognizer()
        tapRecognizer.rx
                     .event
                     .observeOn(MainScheduler.instance)
                     .subscribe(onNext: { [weak self] _ in
                         self?.dismiss(animated: true, completion: nil)
                     })
                     .disposed(by: self.disposeBag)
        self.view.addGestureRecognizer(tapRecognizer)
    }

    private func setupActions(metadataEditable: Bool, filesEditable: Bool, sortType: ItemsSortType) {
        var subviews: [UIView] = []

        if metadataEditable {
            subviews.append(self.createButton(with: "Select Items", selector: #selector(ItemsActionSheetViewController.startEditing)))
            subviews.append(self.createSeparatorLine())
        }

        let (sortFieldTitle, sortOrderTitle) = self.sortButtonTitles(for: sortType)
        let sortFieldButton = self.createButton(with: sortFieldTitle, selector: #selector(ItemsActionSheetViewController.changeSortField))
        let sortOrderButton = self.createButton(with: sortOrderTitle, selector: #selector(ItemsActionSheetViewController.changeSortOrder))
        subviews.append(sortFieldButton)
        subviews.append(sortOrderButton)
        self.sortFieldButton = sortFieldButton
        self.sortOrderButton = sortOrderButton

        if metadataEditable {
            subviews.append(self.createSeparatorLine())
            subviews.append(self.createButton(with: "New Item", selector: #selector(ItemsActionSheetViewController.createNewItem)))
            subviews.append(self.createButton(with: "New Standalone Note", selector: #selector(ItemsActionSheetViewController.createNewNote)))
        }

        if filesEditable {
            if !metadataEditable {
                subviews.append(self.createSeparatorLine())
            }
            subviews.append(self.createButton(with: "Upload File", selector: #selector(ItemsActionSheetViewController.uploadAttachment)))
        }

        subviews.forEach({ self.stackView.addArrangedSubview($0) })
    }

    private func createButton(with title: String, selector: Selector) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    private func createSeparatorLine() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }
}
