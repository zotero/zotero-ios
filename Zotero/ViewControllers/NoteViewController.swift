//
//  NoteViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 16/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

typealias NoteChangeAction = (String) -> Void

class NoteViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var textView: UITextView!
    // Constants
    private let initialText: String
    private let changeAction: NoteChangeAction
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(text: String, change: @escaping NoteChangeAction) {
        self.initialText = text
        self.changeAction = change
        self.disposeBag = DisposeBag()
        super.init(nibName: "NoteViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupNavigationItems()
        self.textView.text = self.initialText
    }

    // MARK: - Actions

    private func save() {
        if self.initialText != self.textView.text {
            self.changeAction(self.textView.text)
        }
        self.cancel()
    }

    private func cancel() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupNavigationItems() {
        let cancelItem = UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil)
        cancelItem.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.cancel()
                         })
                         .disposed(by: self.disposeBag)
        let saveItem = UIBarButtonItem(title: "Save", style: .plain, target: nil, action: nil)
        saveItem.rx.tap.subscribe(onNext: { [weak self] _ in
                           self?.save()
                       })
                       .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancelItem
        self.navigationItem.rightBarButtonItem = saveItem
    }

}
