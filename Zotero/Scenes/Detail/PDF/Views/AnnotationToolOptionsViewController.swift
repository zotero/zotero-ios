//
//  AnnotationToolOptionsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 07.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

#if PDFENABLED

class AnnotationToolOptionsViewController: UIViewController {
    private static let width: CGFloat = 312
    private static let verticalInsets: CGFloat = 15
    private let viewModel: ViewModel<AnnotationToolOptionsActionHandler>
    private let valueChanged: (String?, Float?) -> Void
    private let disposeBag: DisposeBag

    private weak var container: UIStackView?
    private weak var colorPicker: UIStackView?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<AnnotationToolOptionsActionHandler>, valueChanged: @escaping (String?, Float?) -> Void) {
        self.viewModel = viewModel
        self.valueChanged = valueChanged
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .white
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupView()
        self.setupNavigationBar()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updateContentSizeIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if UIDevice.current.userInterfaceIdiom == .phone {
            self.valueChanged(self.viewModel.state.colorHex, self.viewModel.state.size)
        }
    }

    // MARK: - Actions

    private func update(state: AnnotationToolOptionsState) {
        if state.changes.contains(.size), UIDevice.current.userInterfaceIdiom == .pad {
            self.valueChanged(nil, state.size)
        }

        if state.changes.contains(.color) {
            if let colorPicker = self.colorPicker {
                for view in colorPicker.arrangedSubviews {
                    guard let circleView = view as? ColorPickerCircleView else { continue }
                    circleView.isSelected = circleView.hexColor == state.colorHex
                }
            }
            if UIDevice.current.userInterfaceIdiom == .pad {
                self.valueChanged(state.colorHex, nil)
            }
        }
    }

    private func updateContentSizeIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              var size = self.container?.systemLayoutSizeFitting(CGSize(width: AnnotationToolOptionsViewController.width, height: .greatestFiniteMagnitude)) else { return }
        size.height += 2 * AnnotationToolOptionsViewController.verticalInsets
        self.preferredContentSize = CGSize(width: AnnotationToolOptionsViewController.width, height: size.height)
    }

    // MARK: - Setup

    private func setupView() {
        var subviews: [UIView] = []

        if let color = self.viewModel.state.colorHex {
            var colorViews: [UIView] = AnnotationsConfig.colors.enumerated().map { idx, hexColor in
                let circleView = ColorPickerCircleView(hexColor: hexColor)
                circleView.backgroundColor = .clear
                circleView.circleSize = CGSize(width: 40, height: 40)
                circleView.selectionLineWidth = 3
                circleView.selectionInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
                circleView.contentInsets = idx == (AnnotationsConfig.colors.count - 1) ? UIEdgeInsets() : UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
                circleView.isSelected = hexColor == color
                circleView.backgroundColor = Asset.Colors.defaultCellBackground.color
                circleView.isAccessibilityElement = true
                circleView.tap.subscribe(with: self, onNext: { `self`, hex in self.viewModel.process(action: .setColorHex(hex)) }).disposed(by: self.disposeBag)
                return circleView
            }

            // Add spacer
            colorViews.append(UIView())

            let colorPicker = UIStackView(arrangedSubviews: colorViews)
            colorPicker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
            colorPicker.axis = .horizontal
            colorPicker.heightAnchor.constraint(equalToConstant: 50).isActive = true
            subviews.append(colorPicker)
            self.colorPicker = colorPicker
        }

        if let size = self.viewModel.state.size {
            let sizePicker = LineWidthView(title: L10n.size, settings: .lineWidth, contentInsets: UIEdgeInsets())
            sizePicker.value = size
            sizePicker.valueObservable
                .subscribe(with: self, onNext: { `self`, value in
                    self.viewModel.process(action: .setSize(value))
                })
                .disposed(by: self.disposeBag)
            subviews.append(sizePicker)
        }

        let container = UIStackView(arrangedSubviews: subviews)
        container.setContentHuggingPriority(.required, for: .vertical)
        container.spacing = 12
        container.axis = .vertical
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(container)
        self.container = container

        let verticalConstraint: NSLayoutConstraint

        if UIDevice.current.userInterfaceIdiom == .pad {
            verticalConstraint = self.view.safeAreaLayoutGuide.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        } else {
            verticalConstraint = container.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 15)
        }

        NSLayoutConstraint.activate([
            verticalConstraint,
            container.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 15),
            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 15)
        ])
    }

    private func setupNavigationBar() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        self.navigationController?.navigationBar.standardAppearance = appearance
        self.navigationController?.navigationBar.scrollEdgeAppearance = appearance

        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: nil, action: nil)
        doneButton.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.navigationController?.presentingViewController?.dismiss(animated: true)
        })
        .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = doneButton
    }
}

#endif
