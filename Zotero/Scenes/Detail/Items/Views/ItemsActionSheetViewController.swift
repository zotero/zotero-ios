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
    enum Action {
        case showSortTypePicker
        case showItemCreation
        case showNoteCreation
        case showAttachmentPicker
    }

    @IBOutlet private weak var menuView: UIView!
    @IBOutlet private weak var editingButton: UIButton!
    @IBOutlet private weak var sortTypeButton: UIButton!
    @IBOutlet private weak var sortOrderButton: UIButton!
    @IBOutlet private weak var newItemButton: UIButton!
    @IBOutlet private weak var newNoteButton: UIButton!
    @IBOutlet private weak var uploadButton: UIButton!
    @IBOutlet private weak var containerTop: NSLayoutConstraint!
    @IBOutlet private weak var containerHeight: NSLayoutConstraint!

    private let topOffset: CGFloat
    private let viewModel: ViewModel<ItemsActionHandler>
    private let disposeBag: DisposeBag
    let actionObserver: PublishSubject<Action>

    init(viewModel: ViewModel<ItemsActionHandler>, topOffset: CGFloat) {
        self.viewModel = viewModel
        self.topOffset = topOffset
        self.actionObserver = PublishSubject()
        self.disposeBag = DisposeBag()

        super.init(nibName: "ItemsActionSheetViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupBackgroundGesture()
        self.containerTop.constant = self.topOffset
        self.setupSortButtons(with: self.viewModel.state)
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
            self.setupSortButtons(with: state)
        }
    }

    private func setupSortButtons(with state: ItemsState) {
        self.sortTypeButton.setTitle("Sort By: \(state.sortType.field.title)", for: .normal)
        let sortOrderTitle = state.sortType.ascending ? "Ascending" : "Descending"
        self.sortOrderButton.setTitle("Sort Order: \(sortOrderTitle)", for: .normal)
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

    @IBAction private func startEditing() {
        self.dismiss(animated: true) {
            self.viewModel.process(action: .startEditing)
        }
    }

    @IBAction private func changeSortType() {
        self.dismiss(animated: true) {
            self.actionObserver.on(.next(.showSortTypePicker))
        }
    }

    @IBAction private func toggleSortOrder() {
        self.viewModel.process(action: .toggleSortOrder)
    }

    @IBAction private func createNewItem() {
        self.dismiss(animated: true) {
            self.actionObserver.on(.next(.showItemCreation))
        }
    }

    @IBAction private func createNewNote() {
        self.dismiss(animated: true) {
            self.actionObserver.on(.next(.showNoteCreation))
        }
    }

    @IBAction private func uploadAttachment() {
        self.dismiss(animated: true) {
            self.actionObserver.on(.next(.showAttachmentPicker))
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
}
