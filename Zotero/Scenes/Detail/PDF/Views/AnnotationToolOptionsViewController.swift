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
    private weak var colorPicker: ColorPickerStackView?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<AnnotationToolOptionsActionHandler>, valueChanged: @escaping (String?, Float?) -> Void) {
        self.viewModel = viewModel
        self.valueChanged = valueChanged
        disposeBag = DisposeBag()
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

        setupView()
        setupNavigationBar()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)

        func setupView() {
            var subviews: [UIView] = []

            if let color = viewModel.state.colorHex {
                let colorPicker = ColorPickerStackView(
                    hexColors: colors(for: viewModel.state.tool),
                    columnsDistribution: UIDevice.current.userInterfaceIdiom == .pad ? .fixed(numberOfColumns: 4) : .fitInWidth(width: UIScreen.main.bounds.width - (2 * Self.horizontalInset)),
                    allowsMultipleSelection: false,
                    circleBackgroundColor: Asset.Colors.annotationPopoverBackground.color,
                    circleSize: Self.circleSize,
                    circleOffset: Self.circleOffset,
                    circleSelectionLineWidth: 3,
                    circleSelectionInset: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4),
                    trailingSpacerViewProvider: {
                        guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }
                        let spacerView = UIView()
                        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
                        return spacerView
                    },
                    hexColorToggled: { [weak self] hexColor in
                        self?.viewModel.process(action: .setColorHex(hexColor))
                    }
                )
                colorPicker.setSelected(hexColor: color)
                colorPicker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
                subviews.append(colorPicker)
                self.colorPicker = colorPicker
            }

            if let size = viewModel.state.size {
                let settings: LineWidthView.Settings
                switch self.viewModel.state.tool {
                case .freeText:
                    settings = .fontSize

                default:
                    settings = .lineWidth
                }
                let sizePicker = LineWidthView(title: L10n.size, settings: settings, contentInsets: UIEdgeInsets())
                sizePicker.value = size
                sizePicker.valueObservable
                    .subscribe(with: self, onNext: { `self`, value in
                        self.viewModel.process(action: .setSize(value))
                    })
                    .disposed(by: disposeBag)
                subviews.append(sizePicker)
            }

            let container = UIStackView(arrangedSubviews: subviews)
            container.setContentHuggingPriority(.required, for: .vertical)
            container.spacing = 20
            container.axis = .vertical
            container.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(container)
            self.container = container

            let verticalConstraint: NSLayoutConstraint

            if UIDevice.current.userInterfaceIdiom == .pad {
                // Slider needs some offset from center, because visually the slider is a bit off when paired with other elements, 
                // because the offset applies to handle and not the line, so there's too much free space below title text.
                verticalConstraint = view.safeAreaLayoutGuide.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: subviews.count == 1 ? 0 : -3)
            } else {
                verticalConstraint = container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Self.verticalInset)
            }

            NSLayoutConstraint.activate([
                verticalConstraint,
                container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Self.horizontalInset),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: Self.horizontalInset)
            ])

            func colors(for tool: AnnotationTool) -> [String] {
                switch tool {
                case .ink: return AnnotationsConfig.colors(for: .ink)
                case .note: return AnnotationsConfig.colors(for: .note)
                case .highlight: return AnnotationsConfig.colors(for: .highlight)
                case .image: return AnnotationsConfig.colors(for: .image)
                case .freeText: return AnnotationsConfig.colors(for: .freeText)
                case .underline: return AnnotationsConfig.colors(for: .underline)
                default: return []
                }
            }
        }

        func setupNavigationBar() {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return }

            if #unavailable(iOS 26.0.0) {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = Asset.Colors.navbarBackground.color
                navigationController?.navigationBar.standardAppearance = appearance
                navigationController?.navigationBar.scrollEdgeAppearance = appearance
            }

            let primaryAction = UIAction(title: L10n.lookUp) { [weak self] _ in
                self?.navigationController?.presentingViewController?.dismiss(animated: true)
            }
            let doneButton = UIBarButtonItem(systemItem: .done, primaryAction: primaryAction)
            if #available(iOS 26.0.0, *) {
                doneButton.tintColor = Asset.Colors.zoteroBlue.color
            }
            navigationItem.rightBarButtonItem = doneButton
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateContentSizeIfNeeded()

        func updateContentSizeIfNeeded() {
            guard UIDevice.current.userInterfaceIdiom == .pad, var size = container?.systemLayoutSizeFitting(CGSize(width: Self.width, height: .greatestFiniteMagnitude)) else { return }
            size.height += 2 * Self.verticalInset
            preferredContentSize = CGSize(width: Self.width, height: size.height)
        }
    }

    private func update(state: AnnotationToolOptionsState) {
        valueChanged(state.colorHex, state.size)
        if state.changes.contains(.color) {
            presentingViewController?.dismiss(animated: true)
        }
    }
}
