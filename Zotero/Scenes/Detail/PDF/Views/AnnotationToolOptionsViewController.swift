//
//  AnnotationToolOptionsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 07.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import RxSwift

class AnnotationToolOptionsViewController: UIViewController {
    private static let width: CGFloat = 230
    private static let circleSize: CGFloat = 44
    private static let circleOffset: CGFloat = 8
    private static let verticalInset: CGFloat = 15
    private static let horizontalInset: CGFloat = 15
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
        view.backgroundColor = Asset.Colors.annotationPopoverBackground.color
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
        self.valueChanged(self.viewModel.state.colorHex, self.viewModel.state.size)
    }

    // MARK: - Actions

    private func update(state: AnnotationToolOptionsState) {
        if state.changes.contains(.color) {
            self.presentingViewController?.dismiss(animated: true)
        }
    }

    private func updateContentSizeIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              var size = self.container?.systemLayoutSizeFitting(CGSize(width: AnnotationToolOptionsViewController.width, height: .greatestFiniteMagnitude)) else { return }
        size.height += 2 * AnnotationToolOptionsViewController.verticalInset
        self.preferredContentSize = CGSize(width: AnnotationToolOptionsViewController.width, height: size.height)
    }

    // MARK: - Setup

    private var idealNumberOfColumns: Int {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return 4
        default:
            // Calculate number of circles which fit in whole screen width
            return Int((UIScreen.main.bounds.width - (2 * AnnotationToolOptionsViewController.horizontalInset)) / (AnnotationToolOptionsViewController.circleSize + AnnotationToolOptionsViewController.circleOffset))
        }
    }

    private func colors(for tool: PSPDFKit.Annotation.Tool) -> [String] {
        switch tool {
        case .ink: return AnnotationsConfig.colors(for: .ink)
        case .note: return AnnotationsConfig.colors(for: .note)
        case .highlight: return AnnotationsConfig.colors(for: .highlight)
        case .square: return AnnotationsConfig.colors(for: .image)
        default: return []
        }
    }

    private func setupView() {
        var subviews: [UIView] = []

        if let color = self.viewModel.state.colorHex {
            let columns = self.idealNumberOfColumns
            let colors = self.colors(for: self.viewModel.state.tool)
            let rows = Int(ceil(Float(colors.count) / Float(columns)))
            var colorRows: [UIStackView] = []

            for idx in 0..<rows {
                let offset = idx * columns
                var colorViews: [UIView] = []

                for idy in 0..<columns {
                    let id = offset + idy
                    if id >= colors.count {
                        break
                    }

                    let hexColor = colors[id]
                    let circleView = ColorPickerCircleView(hexColor: hexColor)
                    circleView.backgroundColor = .clear
                    circleView.circleSize = CGSize(width: AnnotationToolOptionsViewController.circleSize, height: AnnotationToolOptionsViewController.circleSize)
                    circleView.selectionLineWidth = 3
                    circleView.selectionInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
                    circleView.isSelected = hexColor == color
                    circleView.backgroundColor = Asset.Colors.defaultCellBackground.color
                    circleView.isAccessibilityElement = true
                    circleView.tap.subscribe(with: self, onNext: { `self`, hex in self.viewModel.process(action: .setColorHex(hex)) }).disposed(by: self.disposeBag)
                    colorViews.append(circleView)
                }

                if UIDevice.current.userInterfaceIdiom == .phone {
                    // Add spacer
                    colorViews.append(UIView())
                }

                let stackView = UIStackView(arrangedSubviews: colorViews)
                stackView.spacing = AnnotationToolOptionsViewController.circleOffset
                stackView.axis = .horizontal
                colorRows.append(stackView)
            }

            let colorPicker = UIStackView(arrangedSubviews: colorRows)
            colorPicker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
            colorPicker.spacing = AnnotationToolOptionsViewController.circleOffset
            colorPicker.axis = .vertical
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
        container.spacing = 20
        container.axis = .vertical
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(container)
        self.container = container

        let verticalConstraint: NSLayoutConstraint

        if UIDevice.current.userInterfaceIdiom == .pad {
            // Slider needs some offset from center, because visually the slider is a bit off when paired with other elements, because the offset applies to handle and not the line, so there's too much free space below title text.
            verticalConstraint = self.view.safeAreaLayoutGuide.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: subviews.count == 1 ? 0 : -3)
        } else {
            verticalConstraint = container.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: AnnotationToolOptionsViewController.verticalInset)
        }

        NSLayoutConstraint.activate([
            verticalConstraint,
            container.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: AnnotationToolOptionsViewController.horizontalInset),
            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: AnnotationToolOptionsViewController.horizontalInset)
        ])
    }

    private func setupNavigationBar() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Asset.Colors.navbarBackground.color
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
