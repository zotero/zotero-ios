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

    init(rawValue: Int8) {
        self.rawValue = rawValue
    }

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
            return ToolButton(type: self.type, title: self.title, accessibilityLabel: self.accessibilityLabel, image: self.image, isHidden: isHidden)
        }
    }

    let size: CGFloat
    static let estimatedVerticalHeight: CGFloat = 500
    private static let buttonSpacing: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 12 : 12
    private static let buttonCompactSpacing: CGFloat = 8
    private static let buttonContentInsets: NSDirectionalEdgeInsets = UIDevice.current.userInterfaceIdiom == .pad ? NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4) :
                                                                                                                    NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
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
        self.toolButtons = Self.createButtons(from: tools)
        self.undoRedoEnabled = undoRedoEnabled
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func createButtons(from tools: [AnnotationTool]) -> [ToolButton] {
        return tools.map({ button(from: $0) })

        func button(from tool: AnnotationTool) -> ToolButton {
            switch tool {
            case .highlight:
                ToolButton(
                    type: .highlight,
                    title: L10n.Pdf.AnnotationToolbar.highlight,
                    accessibilityLabel: L10n.Accessibility.Pdf.highlightAnnotationTool,
                    image: Asset.Images.Annotations.highlighterLarge.image,
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
                    image: UIImage(systemName: "underline")!,
                    isHidden: false
                )

            case .freeText:
                ToolButton(
                    type: .freeText,
                    title: L10n.Pdf.AnnotationToolbar.text,
                    accessibilityLabel: L10n.Accessibility.Pdf.textAnnotationTool,
                    image: UIImage(systemName: "character")!,
                    isHidden: false
                )
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = Asset.Colors.navbarBackground.color
        self.view.addInteraction(UILargeContentViewerInteraction())

        self.setupViews()
    }

    // MARK: - Undo/Redo state

    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        self.undoButton?.isEnabled = undoEnabled
        self.redoButton?.isEnabled = redoEnabled
    }

    // MARK: - Layout

    func prepareForSizeChange() {
        for (idx, view) in self.stackView.arrangedSubviews.enumerated() {
            if idx == self.stackView.arrangedSubviews.count - 1 {
                view.alpha = 1
                view.isHidden = false
            } else {
                view.alpha = 0
                view.isHidden = true
            }
        }
    }

    func sizeDidChange() {
        guard self.stackView.arrangedSubviews.count == self.toolButtons.count + 1 else {
            DDLogError("AnnotationToolbarViewController: too many views in stack view! Stack view views: \(self.stackView.arrangedSubviews.count). Tools: \(self.toolButtons.count)")
            return
        }
        guard let button = self.stackView.arrangedSubviews.last, let maxAvailableSize = self.delegate?.maxAvailableToolbarSize, maxAvailableSize > 0 else { return }

        let isHorizontal = self.view.frame.width > self.view.frame.height
        let buttonSize = isHorizontal ? button.frame.width : button.frame.height

        guard buttonSize > 0 else { return }

        let stackViewOffset = isHorizontal ? self.containerLeading.constant : self.containerTop.constant
        let additionalSize = isHorizontal ? self.additionalStackView.frame.width : self.additionalStackView.frame.height
        let containerToPickerOffset = isHorizontal ? self.containerToPickerHorizontal.constant : self.containerToPickerVertical.constant
        let pickerSize = isHorizontal ? self.colorPickerButton.frame.width : self.colorPickerButton.frame.height
        let pickerToAdditionalOffset = isHorizontal ? self.colorPickerToAdditionalHorizontal.constant : self.colorPickerToAdditionalVertical.constant
        let additionalOffset = isHorizontal ? self.additionalTrailing.constant : self.additionalBottom.constant
        let remainingSize = maxAvailableSize - stackViewOffset - containerToPickerOffset - pickerSize - pickerToAdditionalOffset - additionalSize - additionalOffset
        let count = max(0, min(Int(floor(remainingSize / buttonSize)), self.toolButtons.count))

        for idx in 0..<count {
            guard idx < (count - 1) || count == self.toolButtons.count else { continue }
            self.stackView.arrangedSubviews[idx].alpha = 1
            self.stackView.arrangedSubviews[idx].isHidden = false
            self.toolButtons[idx] = self.toolButtons[idx].copy(isHidden: false)
        }

        if count < self.toolButtons.count {
            for idx in count..<self.toolButtons.count {
                self.toolButtons[idx] = self.toolButtons[idx].copy(isHidden: true)
            }
        } else {
            self.stackView.arrangedSubviews.last?.alpha = 0
            self.stackView.arrangedSubviews.last?.isHidden = true
        }

        if self.stackView.arrangedSubviews.last?.isHidden == false {
            (self.stackView.arrangedSubviews.last as? UIButton)?.menu = self.createHiddenToolsMenu()
        }
    }

    func set(activeColor: UIColor) {
        self.colorPickerButton.tintColor = activeColor
    }

    func deselectActiveTool() {
        for view in self.stackView.arrangedSubviews {
            guard let checkbox = view as? CheckboxButton, checkbox.isSelected else { continue }
            checkbox.isSelected = false
            break
        }
        self.colorPickerButton.isHidden = true
        (self.stackView.arrangedSubviews.last as? UIButton)?.menu = self.createHiddenToolsMenu()
    }

    func set(selected: Bool, to tool: AnnotationTool, color: UIColor?) {
        guard let idx = self.toolButtons.firstIndex(where: { $0.type == tool }) else { return }

        (self.stackView.arrangedSubviews[idx] as? CheckboxButton)?.isSelected = selected
        (self.stackView.arrangedSubviews.last as? UIButton)?.menu = self.createHiddenToolsMenu()

        self.colorPickerButton.isHidden = !selected

        if selected {
            self.colorPickerButton.tintColor = color ?? Asset.Colors.zoteroBlueWithDarkMode.color

            let imageName: String
            switch tool {
            case .ink, .image, .highlight, .note:
                imageName = "circle.fill"
            default:
                imageName = "circle"
            }

            self.colorPickerButton.setImage(UIImage(systemName: imageName, withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        }
    }

    func set(rotation: Rotation, isCompactSize: Bool) {
        self.view.layer.cornerRadius = rotation == .vertical ? 8 : 0
        self.view.layer.masksToBounds = false

        switch rotation {
        case .vertical:
            self.setVerticalLayout(isCompactSize: isCompactSize)

        case .horizontal:
            self.setHorizontalLayout(isCompactSize: isCompactSize)
        }

        let inset: CGFloat = isCompactSize ? AnnotationToolbarViewController.buttonCompactSpacing : AnnotationToolbarViewController.buttonSpacing
        self.stackView.spacing = inset
        self.additionalStackView.spacing = inset
    }

    private func setVerticalLayout(isCompactSize: Bool) {
        self.horizontalHeight.isActive = false
        self.additionalTop.isActive = false
        self.containerBottom.isActive = false
        self.containerToPickerHorizontal.isActive = false
        self.colorPickerToAdditionalHorizontal.isActive = false
        self.colorPickerTop.isActive = false
        self.colorPickerBottom.isActive = false
        self.additionalLeading.isActive = true
        self.containerTrailing.isActive = true
        self.containerToPickerVertical.isActive = true
        self.colorPickerToAdditionalVertical.isActive = true
        self.colorPickerLeading.isActive = true
        self.colorPickerTrailing.isActive = true

        self.stackView.axis = .vertical
        self.additionalStackView.axis = .vertical

        self.additionalBottom.constant = 8
        self.additionalTrailing.constant = 8
        self.containerLeading.constant = 8
        self.containerTop.constant = 15
        self.colorPickerLeading.constant = 8
        self.colorPickerTrailing.constant = 8
        self.colorPickerToAdditionalVertical.constant = isCompactSize ? AnnotationToolbarViewController.toolsToAdditionalCompactOffset : AnnotationToolbarViewController.toolsToAdditionalFullOffset
        self.containerToPickerVertical.constant = isCompactSize ? 4 : 8
        self.hairlineView.isHidden = true
    }

    private func setHorizontalLayout(isCompactSize: Bool) {
        self.additionalLeading.isActive = false
        self.containerTrailing.isActive = false
        self.containerToPickerVertical.isActive = false
        self.colorPickerToAdditionalVertical.isActive = false
        self.colorPickerLeading.isActive = false
        self.colorPickerTrailing.isActive = false
        self.horizontalHeight.isActive = true
        self.additionalTop.isActive = true
        self.containerBottom.isActive = true
        self.containerToPickerHorizontal.isActive = true
        self.colorPickerToAdditionalHorizontal.isActive = true
        self.colorPickerTop.isActive = true
        self.colorPickerBottom.isActive = true

        self.stackView.axis = .horizontal
        self.additionalStackView.axis = .horizontal

        self.additionalBottom.constant = 8
        self.additionalTrailing.constant = 15
        self.containerLeading.constant = 20
        self.containerTop.constant = 8
        self.colorPickerToAdditionalHorizontal.constant = isCompactSize ? AnnotationToolbarViewController.toolsToAdditionalCompactOffset : AnnotationToolbarViewController.toolsToAdditionalFullOffset
        self.containerToPickerHorizontal.constant = isCompactSize ? 4 : 8
        self.colorPickerBottom.constant = 8
        self.colorPickerTop.constant = 8
        self.hairlineView.isHidden = false
    }

    func updateAdditionalButtons() {
        for view in self.additionalStackView.arrangedSubviews {
            view.removeFromSuperview()
        }
        for view in self.createAdditionalItems() {
            self.additionalStackView.addArrangedSubview(view)
        }
    }

    private var currentAnnotationOptions: AnnotationToolOptions {
        if self.lastGestureRecognizerTouch?.type == .stylus {
            return .stylus
        }
        return []
    }

    // MARK: - Setup

    private func createHiddenToolsMenu() -> UIMenu {
        let children = self.toolButtons.filter({ $0.isHidden }).map({ tool in
            let isActive = self.delegate?.activeAnnotationTool == tool.type
            return UIAction(title: tool.title, image: tool.image.withRenderingMode(.alwaysTemplate), discoverabilityTitle: tool.accessibilityLabel, state: (isActive ? .on : .off),
                            handler: { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.toggle(tool: tool.type, options: self.currentAnnotationOptions)
            })
        })
        return UIMenu(children: children)
    }

    private func createToolButtons(from tools: [ToolButton]) -> [UIView] {
        var showMoreConfig = UIButton.Configuration.plain()
        showMoreConfig.contentInsets = AnnotationToolbarViewController.buttonContentInsets
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
            let button = CheckboxButton(image: tool.image.withRenderingMode(.alwaysTemplate), contentInsets: AnnotationToolbarViewController.buttonContentInsets)
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
            recognizer.rx.event.subscribe(with: self, onNext: { `self`, _ in self.delegate?.toggle(tool: tool.type, options: self.currentAnnotationOptions) }).disposed(by: self.disposeBag)
            button.addGestureRecognizer(recognizer)

            return button
        } + [showMoreButton]
    }

    private func createAdditionalItems() -> [UIView] {
        var items: [UIView] = []

        if self.undoRedoEnabled {
            var undoConfig = UIButton.Configuration.plain()
            undoConfig.contentInsets = AnnotationToolbarViewController.buttonContentInsets
            undoConfig.image = UIImage(systemName: "arrow.uturn.left")?.applyingSymbolConfiguration(.init(scale: .large))
            let undo = UIButton(type: .custom)
            undo.configuration = undoConfig
            undo.isEnabled = self.delegate?.canUndo ?? false
            undo.showsLargeContentViewer = true
            undo.accessibilityLabel = L10n.Accessibility.Pdf.undo
            undo.largeContentTitle = L10n.Accessibility.Pdf.undo
            undo.rx.controlEvent(.touchUpInside)
                .subscribe(with: self, onNext: { `self`, _ in
                    guard self.delegate?.canUndo == true else { return }
                    self.delegate?.performUndo()
                })
                .disposed(by: self.disposeBag)
            self.undoButton = undo
            items.append(undo)

            var redoConfig = UIButton.Configuration.plain()
            redoConfig.contentInsets = AnnotationToolbarViewController.buttonContentInsets
            redoConfig.image = UIImage(systemName: "arrow.uturn.right")?.applyingSymbolConfiguration(.init(scale: .large))
            let redo = UIButton(type: .custom)
            redo.configuration = redoConfig
            redo.isEnabled = self.delegate?.canRedo ?? false
            redo.showsLargeContentViewer = true
            redo.accessibilityLabel = L10n.Accessibility.Pdf.redo
            redo.largeContentTitle = L10n.Accessibility.Pdf.redo
            redo.rx.controlEvent(.touchUpInside)
                .subscribe(with: self, onNext: { `self`, _ in
                    guard self.delegate?.canRedo == true else { return }
                    self.delegate?.performRedo()
                })
                .disposed(by: self.disposeBag)
            self.redoButton = redo
            items.append(redo)
        }

        var closeConfig = UIButton.Configuration.plain()
        closeConfig.contentInsets = AnnotationToolbarViewController.buttonContentInsets
        closeConfig.image = UIImage(systemName: "xmark.circle")?.applyingSymbolConfiguration(.init(scale: .large))
        let close = UIButton(type: .custom)
        close.configuration = closeConfig
        close.showsLargeContentViewer = true
        close.accessibilityLabel = L10n.close
        close.largeContentTitle = L10n.close
        close.rx.controlEvent(.touchUpInside)
             .subscribe(with: self, onNext: { `self`, _ in
                 self.delegate?.closeAnnotationToolbar()
             })
             .disposed(by: self.disposeBag)
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

    private func createColorPickerButton() -> UIButton {
        var pickerConfig = UIButton.Configuration.plain()
        pickerConfig.contentInsets = AnnotationToolbarViewController.buttonContentInsets
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
              .subscribe(with: self, onNext: { `self`, _ in
                  self.delegate?.showToolOptions(sender: .view(self.colorPickerButton, nil))
              })
              .disposed(by: self.disposeBag)
        return picker
    }

    private func setupViews() {
        self.view.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView(arrangedSubviews: self.createToolButtons(from: self.toolButtons))
        stackView.showsLargeContentViewer = true
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentHuggingPriority(.required, for: .horizontal)
        self.view.addSubview(stackView)

        let picker = self.createColorPickerButton()
        self.view.addSubview(picker)
        self.colorPickerButton = picker

        let additionalStackView = UIStackView(arrangedSubviews: self.createAdditionalItems())
        additionalStackView.showsLargeContentViewer = true
        additionalStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        additionalStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        additionalStackView.setContentHuggingPriority(.required, for: .vertical)
        additionalStackView.setContentHuggingPriority(.required, for: .horizontal)
        additionalStackView.axis = .vertical
        additionalStackView.spacing = 0
        additionalStackView.distribution = .fill
        additionalStackView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(additionalStackView)

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = UIColor.separator
        self.view.addSubview(hairline)
        self.hairlineView = hairline

        self.horizontalHeight = self.view.heightAnchor.constraint(equalToConstant: self.size)
        self.horizontalHeight.priority = .required
        self.containerBottom = self.view.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 8)
        self.containerTrailing = self.view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 8)
        self.additionalTop = additionalStackView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 8)
        self.additionalLeading = additionalStackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8)
        self.containerToPickerVertical = picker.topAnchor.constraint(greaterThanOrEqualTo: stackView.bottomAnchor, constant: 0)
        self.containerToPickerVertical.priority = .required
        self.containerToPickerHorizontal = picker.leadingAnchor.constraint(equalTo: stackView.trailingAnchor)
        self.containerToPickerHorizontal.priority = .required
        self.colorPickerToAdditionalVertical = additionalStackView.topAnchor.constraint(equalTo: picker.bottomAnchor)
        self.colorPickerToAdditionalHorizontal = additionalStackView.leadingAnchor.constraint(greaterThanOrEqualTo: picker.trailingAnchor, constant: 0)
        self.colorPickerTop = picker.topAnchor.constraint(equalTo: self.view.topAnchor)
        self.colorPickerBottom = self.view.bottomAnchor.constraint(equalTo: picker.bottomAnchor)
        self.colorPickerLeading = picker.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        self.colorPickerTrailing = self.view.trailingAnchor.constraint(equalTo: picker.trailingAnchor)
        let containerTop = stackView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 15)
        let containerLeading = stackView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 15)
        let additionalBottom = self.view.bottomAnchor.constraint(equalTo: additionalStackView.bottomAnchor, constant: 8)
        let additionalTrailing = self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: additionalStackView.trailingAnchor, constant: 8)
        let hairlineHeight = hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        let hairlineLeading = hairline.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        let hairlineTrailing = hairline.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        let hairlineBottom = hairline.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)

        NSLayoutConstraint.activate([
            containerTop,
            containerLeading,
            self.containerTrailing,
            self.containerToPickerVertical,
            self.colorPickerLeading,
            self.colorPickerTrailing,
            additionalBottom,
            self.colorPickerToAdditionalVertical,
            additionalTrailing,
            self.additionalLeading,
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
    }
}

extension AnnotationToolbarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        self.lastGestureRecognizerTouch = touch
        return true
    }
}
