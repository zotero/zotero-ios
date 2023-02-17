//
//  LogsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 02.02.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class LogsViewController: UIViewController {
    private let logs: BehaviorRelay<String>
    private let lines: BehaviorRelay<Int>
    private let disposeBag: DisposeBag

    private weak var scrollView: UIScrollView?
    private weak var label: UILabel?

    init(logs: BehaviorRelay<String>, lines: BehaviorRelay<Int>) {
        self.logs = logs
        self.lines = lines
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()
        self.view = UIView()
        self.view.backgroundColor = .white
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.updateTitle()
        self.setupViews(logs: self.logs.value)

        self.logs.observe(on: MainScheduler.instance)
                 .debounce(.milliseconds(500), scheduler: MainScheduler.instance)
                 .subscribe(with: self, onNext: { `self`, logs in
                     self.label?.text = logs
                     self.updateTitle()
                 })
                 .disposed(by: self.disposeBag)
    }

    private func updateTitle() {
        self.title = L10n.Settings.lines(self.lines.value)
    }

    private func setupViews(logs: String) {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scrollView)
        self.scrollView = scrollView

        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.text = logs
        label.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(label)
        self.label = label

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            label.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 15),
            scrollView.contentLayoutGuide.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: 15),
            label.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 15),
            scrollView.contentLayoutGuide.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 15),
            label.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -30)
        ])
    }
}
