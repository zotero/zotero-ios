//
//  PickerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

typealias PickerAction = (Int) -> Void

class PickerViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var pickerView: UIPickerView!
    // Constants
    private let values: [String]
    private let pickerAction: PickerAction
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(values: [String], pickAction: @escaping PickerAction) {
        self.values = values
        self.pickerAction = pickAction
        self.disposeBag = DisposeBag()
        super.init(nibName: "PickerViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupNavigationBar()
    }

    // MARK: - Actions

    private func cancel() {
        self.dismiss(animated: true, completion: nil)
    }

    private func done() {
        let row = self.pickerView.selectedRow(inComponent: 0)
        self.pickerAction(row)
        self.cancel()
    }

    // MARK: - Setups

    private func setupNavigationBar() {
        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)

        cancelButton.rx.tap.subscribe(onNext: { [weak self] _ in
                               self?.cancel()
                           })
                           .disposed(by: self.disposeBag)
        doneButton.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.done()
                         })
                         .disposed(by: self.disposeBag)

        self.navigationItem.leftBarButtonItem = cancelButton
        self.navigationItem.rightBarButtonItem = doneButton
    }
}

extension PickerViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return self.values.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return self.values[row]
    }
}
