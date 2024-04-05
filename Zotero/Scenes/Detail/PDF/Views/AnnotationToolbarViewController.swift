//
//  AnnotationToolbarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import RxSwift

struct AnnotationToolOptions: OptionSet {
    typealias RawValue = Int8

    let rawValue: Int8

    static let stylus = AnnotationToolOptions(rawValue: 1 << 0)
}

protocol AnnotationToolbarDelegate: AnyObject {
    var activeAnnotationTool: AnnotationTool? { get }
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var maxAvailableToolbarSize: CGFloat { get }

    func toggle(tool: AnnotationTool, options: AnnotationToolOptions)
    func showToolOptions(sender: SourceView)
    func closeAnnotationToolbar()
    func performUndo()
    func performRedo()
}

class AnnotationToolbarViewController: UIViewController {
    enum Rotation {
        case horizontal, vertical
    }

    private struct ToolButton {
        let type: AnnotationTool
        let title: String
        let accessibilityLabel: String
        let image: UIImage
        let isHidden: Bool

        func copy(isHidden: Bool) -> ToolButton {
            return ToolButton(type: type, title: title, accessibilityLabel: accessibilityLabel, image: image, isHidden: isHidden)
        }
    }

    let size: CGFloat
    static let estimatedVerticalHeight: CGFloat = 500
    private static let buttonSpacing: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 12 : 12
    private static let buttonCompactSpacing: CGFloat = 8
    private static let buttonContentInsets: NSDirectionalEdgeInsets = UIDevice.current.userInterfaceIdiom == .pad
        ? NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        : NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
    private static let toolsToAdditionalFullOffset: CGFloat = 70
    private static let toolsToAdditionalCompactOffset: CGFloat = 20
    private let disposeBag: DisposeBag
    private let undoRedoEnabled: Bool

    private var horizontalHeight: NSLayoutConstraint!
    private weak var stackView: UIStackView!
    private weak var additionalStackView: UIStackView!
    private(set) weak var colorPickerButton: UIButton!
    private var colorPickerTop: NSLayoutConstraint!
    private var colorPickerLeading: NSLayoutConstraint!
    private var colorPickerToAdditionalHorizontal: NSLayoutConstraint!
    private var colorPickerTrailing: NSLayoutConstraint!
    private var colorPickerToAdditionalVertical: NSLayoutConstraint!
    private var colorPickerBottom: NSLayoutConstraint!
    private(set) weak var undoButton: UIButton?
    private(set) weak var redoButton: UIButton?
    private var additionalTop: NSLayoutConstraint!
    private var additionalLeading: NSLayoutConstraint!
    private weak var additionalTrailing: NSLayoutConstraint!
    private weak var additionalBottom: NSLayoutConstraint!
    private weak var containerTop: NSLayoutConstraint!
    private weak var containerLeading: NSLayoutConstraint!
    private var containerBottom: NSLayoutConstraint!
    private var containerTrailing: NSLayoutConstraint!
    private var containerToPickerVertical: NSLayoutConstraint!
    private var containerToPickerHorizontal: NSLayoutConstraint!
    private var hairlineView: UIView!
    private var toolButtons: [ToolButton]
    weak var delegate: AnnotationToolbarDelegate?
    private var lastGestureRecognizerTouch: UITouch?

    init(tools: [AnnotationTool], undoRedoEnabled: Bool, size: CGFloat) {
        self.size = size
        toolButtons = tools.map({ button(from: $0) })
        self.undoRedoEnabled = undoRedoEnabled
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)

        func button(from tool: AnnotationTool) -> ToolButton {
            switch tool {
            case .highlight:
                ToolButton(
                    type: .highlight,
                    title: L10n.Pdf.AnnotationToolbar.highlight,
                    accessibilityLabel: L10n.Accessibility.Pdf.highlightAnnotationTool,
                    image: Asset.Images.Annotations.highlightLarge.image,
                    isHidden: false
                )

            case .note:
                ToolButton(
                    type: .note,
                    title: L10n.Pdf.AnnotationToolbar.note,
                    accessibilityLabel: L10n.Accessibility.Pdf.noteAnnotationTool,
                    image: Asset.Images.Annotations.noteLarge.image,
                    isHidden: false
                )

            case .image:
                ToolButton(
                    type: .image,
                    title: L10n.Pdf.AnnotationToolbar.image,
                    accessibilityLabel: L10n.Accessibility.Pdf.imageAnnotationTool,
                    image: Asset.Images.Annotations.areaLarge.image,
                    isHidden: false
                )

            case .ink:
                ToolButton(
                    type: .ink,
                    title: L10n.Pdf.AnnotationToolbar.ink,
                    accessibilityLabel: L10n.Accessibility.Pdf.inkAnnotationTool,
                    image: Asset.Images.Annotations.inkLarge.image,
                    isHidden: false
                )

            case .eraser:
                ToolButton(
                    type: .eraser,
                    title: L10n.Pdf.AnnotationToolbar.eraser,
                    accessibilityLabel: L10n.Accessibility.Pdf.eraserAnnotationTool,
                    image: Asset.Images.Annotations.eraserLarge.image,
                    isHidden: false
                )

            case .underline:
                ToolButton(
                    type: .underline,
                    title: L10n.Pdf.AnnotationToolbar.underline,
                    accessibilityLabel: L10n.Accessibility.Pdf.underlineAnnotationTool,
                    image: Asset.Images.Annotations.underlineLarge.image,
                    isHidden: false
                )

            case .freeText:
                ToolButton(
                    type: .freeText,
                    title: L10n.Pdf.AnnotationToolbar.text,
                    accessibilityLabel: L10n.Accessibility.Pdf.textAnnotationTool,
                    image: Asset.Images.Annotations.textLarge.image,
                    isHidden: false
                )
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Asset.Colors.navbarBackground.color
        view.addInteraction(UILargeContentViewerInteraction())

        setupViews()

        func setupViews() {
            view.translatesAutoresizingMaskIntoConstraints = false

            let stackView = UIStackView(arrangedSubviews: createToolButtons(from: toolButtons))
            stackView.showsLargeContentViewer = true
            stackView.axis = .vertical
            stackView.spacing = 0
            stackView.distribution = .fill
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stackView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            stackView.setContentHuggingPriority(.required, for: .vertical)
            stackView.setContentHuggingPriority(.required, for: .horizontal)
            view.addSubview(stackView)

            let picker = createColorPickerButton()
            view.addSubview(picker)
            colorPickerButton = picker

            let additionalStackView = UIStackView(arrangedSubviews: createAdditionalItems())
            additionalStackView.showsLargeContentViewer = true
            additionalStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
            additionalStackView.setContentCompressionResistancePriority(.required, for: .vertical)
            additionalStackView.setContentHuggingPriority(.required, for: .vertical)
            additionalStackView.setContentHuggingPriority(.required, for: .horizontal)
            additionalStackView.axis = .vertical
            additionalStackView.spacing = 0
            additionalStackView.distribution = .fill
            additionalStackView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(additionalStackView)

            let hairline = UIView()
            hairline.translatesAutoresizingMaskIntoConstraints = false
            hairline.backgroundColor = UIColor.separator
            view.addSubview(hairline)
            hairlineView = hairline

            horizontalHeight = view.heightAnchor.constraint(equalToConstant: size)
            horizontalHeight.priority = .required
            containerBottom = view.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 8)
            containerTrailing = view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 8)
            additionalTop = additionalStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8)
            additionalLeading = additionalStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
            containerToPickerVertical = picker.topAnchor.constraint(greaterThanOrEqualTo: stackView.bottomAnchor, constant: 0)
            containerToPickerVertical.priority = .required
            containerToPickerHorizontal = picker.leadingAnchor.constraint(equalTo: stackView.trailingAnchor)
            containerToPickerHorizontal.priority = .required
            colorPickerToAdditionalVertical = additionalStackView.topAnchor.constraint(equalTo: picker.bottomAnchor)
            colorPickerToAdditionalHorizontal = additionalStackView.leadingAnchor.constraint(greaterThanOrEqualTo: picker.trailingAnchor, constant: 0)
            colorPickerTop = picker.topAnchor.constraint(equalTo: view.topAnchor)
            colorPickerBottom = view.bottomAnchor.constraint(equalTo: picker.bottomAnchor)
            colorPickerLeading = picker.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            colorPickerTrailing = view.trailingAnchor.constraint(equalTo: picker.trailingAnchor)
            let containerTop = stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 15)
            let containerLeading = stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 15)
            let additionalBottom = view.bottomAnchor.constraint(equalTo: additionalStackView.bottomAnchor, constant: 8)
            let additionalTrailing = view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: additionalStackView.trailingAnchor, constant: 8)
            let hairlineHeight = hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
            let hairlineLeading = hairline.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let hairlineTrailing = hairline.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            let hairlineBottom = hairline.bottomAnchor.constraint(equalTo: view.bottomAnchor)

            NSLayoutConstraint.activate([
                containerTop,
                containerLeading,
                containerTrailing,
                containerToPickerVertical,
                colorPickerLeading,
                colorPickerTrailing,
                additionalBottom,
                colorPickerToAdditionalVertical,
                additionalTrailing,
                additionalLeading,
                hairlineHeight,
                hairlineLeading,
                hairlineTrailing,
                hairlineBottom
            ])

            self.containerTop = containerTop
            self.containerLeading = containerLeading
            self.additionalTrailing = additionalTrailing
            self.additionalBottom = additionalBottom
            self.stackView = stackView
            self.additionalStackView = additionalStackView

            func createToolButtons(from tools: [ToolButton]) -> [UIView] {
                var showMoreConfig = UIButton.Configuration.plain()
                showMoreConfig.contentInsets = Self.buttonContentInsets
                showMoreConfig.image = UIImage(systemName: "ellipsis")?.withRenderingMode(.alwaysTemplate)
                let showMoreButton = UIButton(type: .custom)
                showMoreButton.configuration = showMoreConfig
                showMoreButton.translatesAutoresizingMaskIntoConstraints = false
                showMoreButton.showsLargeContentViewer = true
                showMoreButton.accessibilityLabel = L10n.Accessibility.Pdf.showMoreTools
                showMoreButton.largeContentTitle = L10n.Accessibility.Pdf.showMoreTools
                showMoreButton.setContentCompressionResistancePriority(.required, for: .vertical)
                showMoreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
                showMoreButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
                showMoreButton.showsMenuAsPrimaryAction = true
                showMoreButton.widthAnchor.constraint(equalTo: showMoreButton.heightAnchor).isActive = true

                return tools.map { tool in
                    let button = CheckboxButton(image: tool.image.withRenderingMode(.alwaysTemplate), contentInsets: Self.buttonContentInsets)
                    button.translatesAutoresizingMaskIntoConstraints = false
                    button.showsLargeContentViewer = true
                    button.accessibilityLabel = tool.accessibilityLabel
                    button.largeContentTitle = tool.title
                    button.deselectedBackgroundColor = .clear
                    button.deselectedTintColor = Asset.Colors.zoteroBlueWithDarkMode.color
                    button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
                    button.selectedTintColor = .white
                    button.setContentCompressionResistancePriority(.required, for: .vertical)
                    button.setContentCompressionResistancePriority(.required, for: .horizontal)
                    button.isHidden = true
                    button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true
                    button.setNeedsUpdateConfiguration()

                    let recognizer = UITapGestureRecognizer()
                    recognizer.delegate = self
                    recognizer.rx.event
                        .subscribe(onNext: { [weak self] _ in
                            guard let self else { return }
                            delegate?.toggle(tool: tool.type, options: currentAnnotationOptions)
                        })
                        .disposed(by: disposeBag)
                    button.addGestureRecognizer(recognizer)

                    return button
                } + [showMoreButton]
            }

            func createColorPickerButton() -> UIButton {
                var pickerConfig = UIButton.Configuration.plain()
                pickerConfig.contentInsets = Self.buttonContentInsets
                pickerConfig.image = UIImage(systemName: "circle.fill")?.applyingSymbolConfiguration(.init(scale: .large))
                let picker = UIButton()
                picker.configuration = pickerConfig
                picker.showsLargeContentViewer = true
                picker.translatesAutoresizingMaskIntoConstraints = false
                picker.setContentCompressionResistancePriority(.required, for: .horizontal)
                picker.setContentCompressionResistancePriority(.required, for: .vertical)
                picker.widthAnchor.constraint(equalTo: picker.heightAnchor).isActive = true
                picker.isHidden = true
                picker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
                picker.largeContentTitle = L10n.Accessibility.Pdf.colorPicker
                picker.rx.controlEvent(.touchUpInside)
                    .subscribe(onNext: { [weak self] _ in
                        guard let self else { return }
                        delegate?.showToolOptions(sender: .view(colorPickerButton, nil))
                    })
                    .disposed(by: disposeBag)
                return picker
            }
        }
    }

    // MARK: - Undo/Redo state

    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        undoButton?.isEnabled = undoEnabled
        redoButton?.isEnabled = redoEnabled
    }

    // MARK: - Layout

    func prepareForSizeChange() {
        for (idx, view) in stackView.arrangedSubviews.enumerated() {
            if idx == stackView.arrangedSubviews.count - 1 {
                view.alpha = 1
                view.isHidden = false
            } else {
                view.alpha = 0
                view.isHidden = true
            }
        }
    }

    func sizeDidChange() {
        guard stackView.arrangedSubviews.count == toolButtons.count + 1 else {
            DDLogError("AnnotationToolbarViewController: too many views in stack view! Stack view views: \(stackView.arrangedSubviews.count). Tools: \(toolButtons.count)")
            return
        }
        guard let button = stackView.arrangedSubviews.last, let maxAvailableSize = delegate?.maxAvailableToolbarSize, maxAvailableSize > 0 else { return }

        let isHorizontal = view.frame.width > view.frame.height
        let buttonSize = isHorizontal ? button.frame.width : button.frame.height

        guard buttonSize > 0 else { return }

        let stackViewOffset = isHorizontal ? containerLeading.constant : containerTop.constant
        let additionalSize = isHorizontal ? additionalStackView.frame.width : additionalStackView.frame.height
        let containerToPickerOffset = isHorizontal ? containerToPickerHorizontal.constant : containerToPickerVertical.constant
        let pickerSize = isHorizontal ? colorPickerButton.frame.width : colorPickerButton.frame.height
        let pickerToAdditionalOffset = isHorizontal ? colorPickerToAdditionalHorizontal.constant : colorPickerToAdditionalVertical.constant
        let additionalOffset = isHorizontal ? additionalTrailing.constant : additionalBottom.constant
        let remainingSize = maxAvailableSize - stackViewOffset - containerToPickerOffset - pickerSize - pickerToAdditionalOffset - additionalSize - additionalOffset
        let count = max(0, min(Int(floor(remainingSize / buttonSize)), toolButtons.count))

        for idx in 0..<count {
            guard idx < (count - 1) || count == toolButtons.count else { continue }
            stackView.arrangedSubviews[idx].alpha = 1
            stackView.arrangedSubviews[idx].isHidden = false
            toolButtons[idx] = toolButtons[idx].copy(isHidden: false)
        }

        if count < toolButtons.count {
            for idx in count..<toolButtons.count {
                toolButtons[idx] = toolButtons[idx].copy(isHidden: true)
            }
        } else {
            stackView.arrangedSubviews.last?.alpha = 0
            stackView.arrangedSubviews.last?.isHidden = true
        }

        if stackView.arrangedSubviews.last?.isHidden == false {
            (stackView.arrangedSubviews.last as? UIButton)?.menu = createHiddenToolsMenu()
        }
    }

    func set(activeColor: UIColor) {
        colorPickerButton.tintColor = activeColor
    }

    func set(selected: Bool, to tool: AnnotationTool, color: UIColor?) {
        guard let idx = toolButtons.firstIndex(where: { $0.type == tool }) else { return }

        (stackView.arrangedSubviews[idx] as? CheckboxButton)?.isSelected = selected
        (stackView.arrangedSubviews.last as? UIButton)?.menu = createHiddenToolsMenu()

        colorPickerButton.isHidden = !selected

        if selected {
            colorPickerButton.tintColor = color ?? Asset.Colors.zoteroBlueWithDarkMode.color

            let imageName: String
            switch tool {
            case .ink, .image, .highlight, .note, .freeText, .underline:
                imageName = "circle.fill"

            default:
                imageName = "circle"
            }

            colorPickerButton.setImage(UIImage(systemName: imageName, withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        }
    }

    func set(rotation: Rotation, isCompactSize: Bool) {
        view.layer.cornerRadius = rotation == .vertical ? 8 : 0
        view.layer.masksToBounds = false

        switch rotation {
        case .vertical:
            setVerticalLayout(isCompactSize: isCompactSize)

        case .horizontal:
            setHorizontalLayout(isCompactSize: isCompactSize)
        }

        let inset: CGFloat = isCompactSize ? Self.buttonCompactSpacing : Self.buttonSpacing
        stackView.spacing = inset
        additionalStackView.spacing = inset

        func setVerticalLayout(isCompactSize: Bool) {
            horizontalHeight.isActive = false
            additionalTop.isActive = false
            containerBottom.isActive = false
            containerToPickerHorizontal.isActive = false
            colorPickerToAdditionalHorizontal.isActive = false
            colorPickerTop.isActive = false
            colorPickerBottom.isActive = false
            additionalLeading.isActive = true
            containerTrailing.isActive = true
            containerToPickerVertical.isActive = true
            colorPickerToAdditionalVertical.isActive = true
            colorPickerLeading.isActive = true
            colorPickerTrailing.isActive = true

            stackView.axis = .vertical
            additionalStackView.axis = .vertical

            additionalBottom.constant = 8
            additionalTrailing.constant = 8
            containerLeading.constant = 8
            containerTop.constant = 15
            colorPickerLeading.constant = 8
            colorPickerTrailing.constant = 8
            colorPickerToAdditionalVertical.constant = isCompactSize ? Self.toolsToAdditionalCompactOffset : Self.toolsToAdditionalFullOffset
            containerToPickerVertical.constant = isCompactSize ? 4 : 8
            hairlineView.isHidden = true
        }

        func setHorizontalLayout(isCompactSize: Bool) {
            additionalLeading.isActive = false
            containerTrailing.isActive = false
            containerToPickerVertical.isActive = false
            colorPickerToAdditionalVertical.isActive = false
            colorPickerLeading.isActive = false
            colorPickerTrailing.isActive = false
            horizontalHeight.isActive = true
            additionalTop.isActive = true
            containerBottom.isActive = true
            containerToPickerHorizontal.isActive = true
            colorPickerToAdditionalHorizontal.isActive = true
            colorPickerTop.isActive = true
            colorPickerBottom.isActive = true

            stackView.axis = .horizontal
            additionalStackView.axis = .horizontal

            additionalBottom.constant = 8
            additionalTrailing.constant = 15
            containerLeading.constant = 20
            containerTop.constant = 8
            colorPickerToAdditionalHorizontal.constant = isCompactSize ? Self.toolsToAdditionalCompactOffset : Self.toolsToAdditionalFullOffset
            containerToPickerHorizontal.constant = isCompactSize ? 4 : 8
            colorPickerBottom.constant = 8
            colorPickerTop.constant = 8
            hairlineView.isHidden = false
        }
    }

    func updateAdditionalButtons() {
        for view in additionalStackView.arrangedSubviews {
            view.removeFromSuperview()
        }
        for view in createAdditionalItems() {
            additionalStackView.addArrangedSubview(view)
        }
    }

    private var currentAnnotationOptions: AnnotationToolOptions {
        if lastGestureRecognizerTouch?.type == .stylus {
            return .stylus
        }
        return []
    }

    // MARK: - Setup

    private func createHiddenToolsMenu() -> UIMenu {
        let children = toolButtons.filter({ $0.isHidden }).map({ tool in
            let isActive = delegate?.activeAnnotationTool == tool.type
            return UIAction(
                title: tool.title,
                image: tool.image.withRenderingMode(.alwaysTemplate),
                discoverabilityTitle: tool.accessibilityLabel,
                state: (isActive ? .on : .off),
                handler: { [weak self] _ in
                    guard let self else { return }
                    delegate?.toggle(tool: tool.type, options: currentAnnotationOptions)
                }
            )
        })
        return UIMenu(children: children)
    }

    private func createAdditionalItems() -> [UIView] {
        var items: [UIView] = []

        if undoRedoEnabled {
            var undoConfig = UIButton.Configuration.plain()
            undoConfig.contentInsets = Self.buttonContentInsets
            undoConfig.image = UIImage(systemName: "arrow.uturn.left")?.applyingSymbolConfiguration(.init(scale: .large))
            let undo = UIButton(type: .custom)
            undo.configuration = undoConfig
            undo.isEnabled = delegate?.canUndo ?? false
            undo.showsLargeContentViewer = true
            undo.accessibilityLabel = L10n.Accessibility.Pdf.undo
            undo.largeContentTitle = L10n.Accessibility.Pdf.undo
            undo.rx.controlEvent(.touchUpInside)
                .subscribe(onNext: { [weak self] _ in
                    guard let self, delegate?.canUndo == true else { return }
                    delegate?.performUndo()
                })
                .disposed(by: disposeBag)
            undoButton = undo
            items.append(undo)

            var redoConfig = UIButton.Configuration.plain()
            redoConfig.contentInsets = Self.buttonContentInsets
            redoConfig.image = UIImage(systemName: "arrow.uturn.right")?.applyingSymbolConfiguration(.init(scale: .large))
            let redo = UIButton(type: .custom)
            redo.configuration = redoConfig
            redo.isEnabled = delegate?.canRedo ?? false
            redo.showsLargeContentViewer = true
            redo.accessibilityLabel = L10n.Accessibility.Pdf.redo
            redo.largeContentTitle = L10n.Accessibility.Pdf.redo
            redo.rx.controlEvent(.touchUpInside)
                .subscribe(onNext: { [weak self] _ in
                    guard let self, delegate?.canRedo == true else { return }
                    delegate?.performRedo()
                })
                .disposed(by: disposeBag)
            redoButton = redo
            items.append(redo)
        }

        var closeConfig = UIButton.Configuration.plain()
        closeConfig.contentInsets = Self.buttonContentInsets
        closeConfig.image = UIImage(systemName: "xmark.circle")?.applyingSymbolConfiguration(.init(scale: .large))
        let close = UIButton(type: .custom)
        close.configuration = closeConfig
        close.showsLargeContentViewer = true
        close.accessibilityLabel = L10n.close
        close.largeContentTitle = L10n.close
        close.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: { [weak self] _ in
                self?.delegate?.closeAnnotationToolbar()
            })
            .disposed(by: disposeBag)
        items.append(close)

        let handle = UIImageView(image: UIImage(systemName: "line.3.horizontal")?.applyingSymbolConfiguration(.init(scale: .large)))
        handle.showsLargeContentViewer = false
        handle.contentMode = .center
        items.append(handle)

        for view in items {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
            view.widthAnchor.constraint(equalTo: view.heightAnchor).isActive = true
        }

        return items
    }
}

extension AnnotationToolbarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        lastGestureRecognizerTouch = touch
        return true
    }
}
