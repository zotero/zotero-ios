//
//  AnnotationToolbarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

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
    var rotation: AnnotationToolbarViewController.Rotation { get }
    var isCompactSize: Bool { get }
    var activeAnnotationColor: UIColor { get }
    var activeAnnotationTool: PSPDFKit.Annotation.Tool? { get }
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var maxAvailableToolbarSize: CGFloat { get }

    func toggle(tool: PSPDFKit.Annotation.Tool, options: AnnotationToolOptions)
    func showInkSettings(sender: UIView)
    func showEraserSettings(sender: UIView)
    func showColorPicker(sender: UIButton)
    func closeAnnotationToolbar()
    func performUndo()
    func performRedo()
}

class AnnotationToolbarViewController: UIViewController {
    enum Rotation {
        case horizontal, vertical
    }

    private struct Tool {
        let type: PSPDFKit.Annotation.Tool
        let title: String
        let accessibilityLabel: String
        let image: UIImage
        let isHidden: Bool

        func copy(isHidden: Bool) -> Tool {
            return Tool(type: self.type, title: self.title, accessibilityLabel: self.accessibilityLabel, image: self.image, isHidden: isHidden)
        }
    }

    static let size: CGFloat = 52
    private static let toolsToAdditionalFullOffset: CGFloat = 50
    private static let toolsToAdditionalCompactOffset: CGFloat = 50
    private let disposeBag: DisposeBag

    private weak var stackView: UIStackView!
    private weak var additionalStackView: UIStackView!
    private weak var colorPickerButton: UIButton!
    private(set) weak var undoButton: UIButton?
    private(set) weak var redoButton: UIButton?
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private var handleTop: NSLayoutConstraint!
    private var handleLeading: NSLayoutConstraint!
    private weak var additionalTrailing: NSLayoutConstraint!
    private weak var additionalBottom: NSLayoutConstraint!
    private weak var containerTop: NSLayoutConstraint!
    private weak var containerLeading: NSLayoutConstraint!
    private var containerBottom: NSLayoutConstraint!
    private var containerTrailing: NSLayoutConstraint!
    private var containerToAdditionalVertical: NSLayoutConstraint!
    private var containerToAdditionalHorizontal: NSLayoutConstraint!
    private var tools: [Tool]
    weak var delegate: AnnotationToolbarDelegate?
    private var lastGestureRecognizerTouch: UITouch?

    init() {
        self.tools = AnnotationToolbarViewController.createTools()
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func createTools() -> [Tool] {
        return [Tool(type: .highlight, title: L10n.Pdf.AnnotationToolbar.highlight, accessibilityLabel: L10n.Accessibility.Pdf.highlightAnnotationTool, image: Asset.Images.Annotations.highlighterLarge.image, isHidden: false),
                Tool(type: .note, title: L10n.Pdf.AnnotationToolbar.note, accessibilityLabel: L10n.Accessibility.Pdf.noteAnnotationTool, image: Asset.Images.Annotations.noteLarge.image, isHidden: false),
                Tool(type: .square, title: L10n.Pdf.AnnotationToolbar.image, accessibilityLabel: L10n.Accessibility.Pdf.imageAnnotationTool, image: Asset.Images.Annotations.areaLarge.image, isHidden: false),
                Tool(type: .ink, title: L10n.Pdf.AnnotationToolbar.ink, accessibilityLabel: L10n.Accessibility.Pdf.inkAnnotationTool, image: Asset.Images.Annotations.inkLarge.image, isHidden: false),
                Tool(type: .eraser, title: L10n.Pdf.AnnotationToolbar.eraser, accessibilityLabel: L10n.Accessibility.Pdf.eraserAnnotationTool, image: Asset.Images.Annotations.eraserLarge.image, isHidden: false)]
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = Asset.Colors.navbarBackground.color
        self.view.addInteraction(UILargeContentViewerInteraction())

        self.setupViews()
        if let delegate = self.delegate {
            self.set(rotation: delegate.rotation, isCompactSize: delegate.isCompactSize)
            self.view.layoutIfNeeded()
        }
    }

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
        guard self.stackView.arrangedSubviews.count == self.tools.count + 1 else {
            DDLogError("AnnotationToolbarViewController: too many views in stack view! Stack view views: \(self.stackView.arrangedSubviews.count). Tools: \(self.tools.count)")
            return
        }
        guard let button = self.stackView.arrangedSubviews.last, let maxAvailableSize = self.delegate?.maxAvailableToolbarSize, maxAvailableSize > 0 else { return }

        let isHorizontal = self.view.frame.width > self.view.frame.height
        let buttonSize = isHorizontal ? button.frame.width : button.frame.height

        guard buttonSize > 0 else { return }

        let stackViewOffset = isHorizontal ? self.containerLeading.constant : self.containerTop.constant
        let additionalSize = isHorizontal ? self.additionalStackView.frame.width : self.additionalStackView.frame.height
        let containerToAdditionalOffset = isHorizontal ? self.containerToAdditionalHorizontal.constant : self.containerToAdditionalVertical.constant
        let additionalOffset = isHorizontal ? self.additionalTrailing.constant : self.additionalBottom.constant
        let remainingSize = maxAvailableSize - stackViewOffset - containerToAdditionalOffset - additionalSize - additionalOffset
        let count = min(Int(floor(remainingSize / buttonSize)), self.tools.count)

        for idx in 0..<count {
            guard idx < (count - 1) || count == self.tools.count else { continue }
            self.stackView.arrangedSubviews[idx].alpha = 1
            self.stackView.arrangedSubviews[idx].isHidden = false
            self.tools[idx] = self.tools[idx].copy(isHidden: false)
        }

        if count < self.tools.count {
            for idx in count..<self.tools.count {
                self.tools[idx] = self.tools[idx].copy(isHidden: true)
            }
        } else {
            self.stackView.arrangedSubviews.last?.alpha = 0
            self.stackView.arrangedSubviews.last?.isHidden = true
        }

        if self.stackView.arrangedSubviews.last?.isHidden == false {
            (self.stackView.arrangedSubviews.last as? UIButton)?.menu = self.createHiddenToolsMenu()
        }
    }

    func set(selected: Bool, to tool: PSPDFKit.Annotation.Tool) {
        guard let idx = self.tools.firstIndex(where: { $0.type == tool }) else { return }

        (self.stackView.arrangedSubviews[idx] as? CheckboxButton)?.isSelected = selected
        (self.stackView.arrangedSubviews.last as? UIButton)?.menu = self.createHiddenToolsMenu()
    }

    func set(rotation: Rotation, isCompactSize: Bool) {
        self.view.layer.cornerRadius = 8
        self.view.layer.masksToBounds = false

        switch rotation {
        case .vertical:
            self.setVerticalLayout(isCompactSize: isCompactSize)
        case .horizontal:
            self.setHorizontalLayout(isCompactSize: isCompactSize)
        }
    }

    private func setVerticalLayout(isCompactSize: Bool) {
        self.heightConstraint.isActive = false
        self.handleTop.isActive = false
        self.containerBottom.isActive = false
        self.containerToAdditionalHorizontal.isActive = false
        self.widthConstraint.isActive = true
        self.handleLeading.isActive = true
        self.containerTrailing.isActive = true
        self.containerToAdditionalVertical.isActive = true

        self.stackView.axis = .vertical
        self.additionalStackView.axis = .vertical

        self.additionalBottom.constant = 8
        self.additionalTrailing.constant = 0
        self.containerLeading.constant = 8
        self.containerTop.constant = 15
        self.containerToAdditionalVertical.constant = isCompactSize ? AnnotationToolbarViewController.toolsToAdditionalCompactOffset : AnnotationToolbarViewController.toolsToAdditionalFullOffset

        let inset: CGFloat = isCompactSize ? 6 : 10
        let insets = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
        self.set(insets: insets, in: self.stackView)
        self.set(insets: insets, in: self.additionalStackView)
    }

    private func setHorizontalLayout(isCompactSize: Bool) {
        self.widthConstraint.isActive = false
        self.handleLeading.isActive = false
        self.containerTrailing.isActive = false
        self.containerToAdditionalVertical.isActive = false
        self.handleTop.isActive = true
        self.containerBottom.isActive = true
        self.containerToAdditionalHorizontal.isActive = true
        self.heightConstraint.isActive = true

        self.stackView.axis = .horizontal
        self.additionalStackView.axis = .horizontal

        self.additionalBottom.constant = 0
        self.additionalTrailing.constant = 15
        self.containerLeading.constant = 20
        self.containerTop.constant = 8
        self.containerToAdditionalHorizontal.constant = isCompactSize ? 20 : 50

        let inset: CGFloat = isCompactSize ? 6 : 8
        let insets = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        self.set(insets: insets, in: self.stackView)
        self.set(insets: insets, in: self.additionalStackView)
    }

    private func set(insets: UIEdgeInsets, in stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            if let button = view as? UIButton {
                button.contentEdgeInsets = insets
            } else if let imageView = view as? UIImageView {
                imageView.constraints.forEach({ $0.isActive = false })

                guard let image = imageView.image else { continue }

                if insets.left == 0 {
                    imageView.heightAnchor.constraint(equalToConstant: (image.size.height + insets.top + insets.bottom)).isActive = true
                } else {
                    imageView.widthAnchor.constraint(equalToConstant: (image.size.width + insets.left + insets.right)).isActive = true
                }
            }
        }
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

    private func process(longPressToolAction action: PSPDFKit.Annotation.Tool, recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let view = recognizer.view else { return }

        switch action {
        case .ink:
            self.delegate?.showInkSettings(sender: view)
            if self.delegate?.activeAnnotationTool != .ink {
                self.delegate?.toggle(tool: .ink, options: self.currentAnnotationOptions)
            }

        case .eraser:
            self.delegate?.showEraserSettings(sender: view)
            if self.delegate?.activeAnnotationTool != .eraser {
                self.delegate?.toggle(tool: .eraser, options: self.currentAnnotationOptions)
            }

        default: break
        }
    }

    private func createHiddenToolsMenu() -> UIMenu {
        let children = self.tools.filter({ $0.isHidden }).map({ tool in
            let isActive = self.delegate?.activeAnnotationTool == tool.type
            return UIAction(title: tool.title, image: tool.image.withRenderingMode(.alwaysTemplate), discoverabilityTitle: tool.accessibilityLabel, state: (isActive ? .on : .off),
                            handler: { [weak self] _ in
                guard let `self` = self else { return }
                self.delegate?.toggle(tool: tool.type, options: self.currentAnnotationOptions)
            })
        })
        return UIMenu(children: children)
    }

    private func createToolButtons(from tools: [Tool]) -> [UIView] {
        let showMoreButton = UIButton(type: .custom)
        showMoreButton.showsLargeContentViewer = true
        showMoreButton.accessibilityLabel = L10n.Accessibility.Pdf.showMoreTools
        showMoreButton.largeContentTitle = L10n.Accessibility.Pdf.showMoreTools
        showMoreButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        showMoreButton.setContentHuggingPriority(.defaultHigh, for: .vertical)
        showMoreButton.setContentCompressionResistancePriority(.required, for: .vertical)
        showMoreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        showMoreButton.setImage(UIImage(systemName: "ellipsis")?.withRenderingMode(.alwaysTemplate), for: .normal)
        showMoreButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        showMoreButton.showsMenuAsPrimaryAction = true

        return tools.map { tool in
            let button = CheckboxButton(type: .custom)
            button.showsLargeContentViewer = true
            button.accessibilityLabel = tool.accessibilityLabel
            button.largeContentTitle = tool.title
            button.setImage(tool.image.withRenderingMode(.alwaysTemplate), for: .normal)
            button.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
            button.adjustsImageWhenHighlighted = false
            button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
            button.selectedTintColor = .white
            button.layer.cornerRadius = 4
            button.layer.masksToBounds = true
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            button.setContentHuggingPriority(.defaultHigh, for: .vertical)
            button.setContentCompressionResistancePriority(.required, for: .vertical)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.isHidden = true
            button.rx.controlEvent(.touchUpInside).subscribe(with: self, onNext: { `self`, _ in self.delegate?.toggle(tool: tool.type, options: self.currentAnnotationOptions) }).disposed(by: self.disposeBag)
            return button
        } + [showMoreButton]
    }

    private func createAdditionalItems() -> [UIView] {
        let picker = UIButton()
        picker.showsLargeContentViewer = true
        picker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
        picker.largeContentTitle = L10n.Accessibility.Pdf.colorPicker
        picker.setImage(UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        picker.rx.controlEvent(.touchUpInside)
              .subscribe(with: self, onNext: { `self`, _ in
                  self.delegate?.showColorPicker(sender: self.colorPickerButton)
              })
              .disposed(by: self.disposeBag)
        self.colorPickerButton = picker

        let undo = UIButton(type: .custom)
        undo.showsLargeContentViewer = true
        undo.accessibilityLabel = L10n.Accessibility.Pdf.undo
        undo.largeContentTitle = L10n.Accessibility.Pdf.undo
        undo.setImage(UIImage(systemName: "arrow.uturn.left", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        undo.rx.controlEvent(.touchUpInside)
            .subscribe(with: self, onNext: { `self`, _ in
                guard self.delegate?.canUndo == true else { return }
                self.delegate?.performUndo()
            })
            .disposed(by: self.disposeBag)
        self.undoButton = undo

        let redo = UIButton(type: .custom)
        redo.showsLargeContentViewer = true
        redo.accessibilityLabel = L10n.Accessibility.Pdf.redo
        redo.largeContentTitle = L10n.Accessibility.Pdf.redo
        redo.setImage(UIImage(systemName: "arrow.uturn.right", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        redo.rx.controlEvent(.touchUpInside)
            .subscribe(with: self, onNext: { `self`, _ in
                guard self.delegate?.canRedo == true else { return }
                self.delegate?.performRedo()
            })
            .disposed(by: self.disposeBag)
        self.redoButton = redo

        let close = UIButton(type: .custom)
        close.showsLargeContentViewer = true
        close.accessibilityLabel = L10n.close
        close.largeContentTitle = L10n.close
        close.setImage(UIImage(systemName: "xmark.circle", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        close.rx.controlEvent(.touchUpInside)
             .subscribe(with: self, onNext: { `self`, _ in
                 self.delegate?.closeAnnotationToolbar()
             })
             .disposed(by: self.disposeBag)

        let handle = UIImageView(image: UIImage(systemName: "line.3.horizontal", withConfiguration: UIImage.SymbolConfiguration(scale: .large)))
        handle.showsLargeContentViewer = false
        handle.contentMode = .center

        for (idx, view) in [picker, undo, redo, close, handle].enumerated() {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.tintColor = idx == 0 ? self.delegate?.activeAnnotationColor : Asset.Colors.zoteroBlueWithDarkMode.color
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentHuggingPriority(.required, for: .vertical)
        }

        return [picker, undo, redo, close, handle]
    }

    private func setupViews() {
        self.view.translatesAutoresizingMaskIntoConstraints = false
        self.widthConstraint = self.view.widthAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size)
        self.heightConstraint = self.view.heightAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size)

        let stackView = UIStackView(arrangedSubviews: self.createToolButtons(from: self.tools))
        stackView.showsLargeContentViewer = true
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentHuggingPriority(.required, for: .horizontal)
        self.view.addSubview(stackView)

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

        self.containerBottom = self.view.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 8)
        self.containerTrailing = self.view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 8)
        self.handleTop = self.view.topAnchor.constraint(equalTo: additionalStackView.topAnchor)
        self.handleLeading = self.view.leadingAnchor.constraint(equalTo: additionalStackView.leadingAnchor)
        self.containerToAdditionalVertical = additionalStackView.topAnchor.constraint(greaterThanOrEqualTo: stackView.bottomAnchor, constant: AnnotationToolbarViewController.toolsToAdditionalFullOffset)
        self.containerToAdditionalVertical.priority = .required
        self.containerToAdditionalHorizontal = additionalStackView.leadingAnchor.constraint(greaterThanOrEqualTo: stackView.trailingAnchor, constant: AnnotationToolbarViewController.toolsToAdditionalFullOffset)
        self.containerToAdditionalHorizontal.priority = .required
        let containerTop = stackView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 15)
        let containerLeading = stackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 15)
        let additionalBottom = self.view.bottomAnchor.constraint(equalTo: additionalStackView.bottomAnchor)
        let additionalTrailing = self.view.trailingAnchor.constraint(equalTo: additionalStackView.trailingAnchor)

        NSLayoutConstraint.activate([containerTop, containerLeading, self.containerTrailing, self.containerToAdditionalVertical, additionalBottom, additionalTrailing, self.handleLeading])

        self.stackView = stackView
        self.containerTop = containerTop
        self.containerLeading = containerLeading
        self.additionalTrailing = additionalTrailing
        self.additionalBottom = additionalBottom
        self.additionalStackView = additionalStackView
    }
}

extension AnnotationToolbarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        self.lastGestureRecognizerTouch = touch
        return true
    }
}

#endif
