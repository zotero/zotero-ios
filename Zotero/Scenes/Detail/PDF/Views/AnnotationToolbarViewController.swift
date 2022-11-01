//
//  AnnotationToolbarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol AnnotationToolbarDelegate: AnyObject {
    func moveToolbarLeft()
    func moveToolbarRight()
    func moveToolbarTop()
}

class AnnotationToolbarViewController: UIViewController {
    enum Rotation {
        case horizontal, vertical
    }

    private let disposeBag: DisposeBag

    private var rotation: Rotation
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private weak var stackView: UIStackView!
    weak var delegate: AnnotationToolbarDelegate?

    init(rotation: Rotation) {
        self.rotation = rotation
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupConstraints()

        let button1 = UIButton(type: .custom)
        button1.setTitle("L", for: .normal)
        button1.rx.controlEvent(.touchUpInside)
                .subscribe(onNext: {
                    self.delegate?.moveToolbarLeft()
                })
                .disposed(by: self.disposeBag)

        let button2 = UIButton(type: .custom)
        button2.setTitle("R", for: .normal)
        button2.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: {
                self.delegate?.moveToolbarRight()
            })
            .disposed(by: self.disposeBag)

        let button3 = UIButton(type: .custom)
        button3.setTitle("T", for: .normal)
        button3.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: {
                self.delegate?.moveToolbarTop()
            })
            .disposed(by: self.disposeBag)

        let stackView = UIStackView(arrangedSubviews: [button1, button2, button3])
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 10),
            self.view.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 10),
            self.view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 10)
        ])

        self.view.backgroundColor = .red
        self.view.layer.cornerRadius = 8
        self.view.layer.masksToBounds = true
        self.stackView = stackView

        self.set(rotation: self.rotation)
    }

    func set(rotation: Rotation) {
        self.heightConstraint.isActive = rotation == .horizontal
        self.widthConstraint.isActive = rotation == .vertical
        self.stackView.axis = rotation == .horizontal ? .horizontal : .vertical
    }

    private func setupConstraints() {
        self.widthConstraint = self.view.widthAnchor.constraint(equalToConstant: 44)
        self.heightConstraint = self.view.heightAnchor.constraint(equalToConstant: 44)
    }
}
