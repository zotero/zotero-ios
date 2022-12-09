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

    static let size: CGFloat = 52
    private let disposeBag: DisposeBag

    private weak var scrollView: UIScrollView!
    private var scrollViewWidthContentConstraint: NSLayoutConstraint!
    private var scrollViewHeightContentConstraint: NSLayoutConstraint!
    private weak var stackView: UIStackView!
    private weak var noteButton: CheckboxButton!
    private weak var highlightButton: CheckboxButton!
    private weak var areaButton: CheckboxButton!
    private weak var inkButton: CheckboxButton!
    private weak var eraserButton: CheckboxButton!
    private weak var colorPickerButton: UIButton!
    private weak var additionalStackView: UIStackView!
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
    weak var delegate: AnnotationToolbarDelegate?
    private var lastGestureRecognizerTouch: UITouch?

    init() {
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = Asset.Colors.navbarBackground.color

        self.setupViews()
        if let delegate = self.delegate {
            self.set(rotation: delegate.rotation, isCompactSize: delegate.isCompactSize)
            self.view.layoutIfNeeded()
        }
    }

    func set(selected: Bool, to tool: PSPDFKit.Annotation.Tool) {
        switch tool {
        case .highlight:
            self.highlightButton.isSelected = selected
        case .note:
            self.noteButton.isSelected = selected
        case .square:
            self.areaButton.isSelected = selected
        case .ink:
            self.inkButton.isSelected = selected
        case .eraser:
            self.eraserButton.isSelected = selected
        default: break
        }
    }

    func set(rotation: Rotation, isCompactSize: Bool) {
        self.view.layer.cornerRadius = 8
        self.view.layer.masksToBounds = false

        switch rotation {
        case .vertical:
            self.heightConstraint.isActive = false
            self.handleTop.isActive = false
            self.containerBottom.isActive = false
            self.containerToAdditionalHorizontal.isActive = false
            self.scrollViewHeightContentConstraint.priority = UILayoutPriority(rawValue: 999)
            self.scrollViewWidthContentConstraint.priority = .required
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
            self.containerToAdditionalVertical.constant = isCompactSize ? 20 : 50

        case .horizontal:
            self.widthConstraint.isActive = false
            self.handleLeading.isActive = false
            self.containerTrailing.isActive = false
            self.containerToAdditionalVertical.isActive = false
            self.scrollViewWidthContentConstraint.priority = UILayoutPriority(rawValue: 999)
            self.scrollViewHeightContentConstraint.priority = .required
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

    private func createButtons() -> [UIView] {
        let symbolConfig = UIImage.SymbolConfiguration(scale: .large)

        let highlight = CheckboxButton(type: .custom)
        highlight.accessibilityLabel = L10n.Accessibility.Pdf.highlightAnnotationTool
        highlight.setImage(Asset.Images.Annotations.highlighterLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        highlight.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        highlight.rx.controlEvent(.touchDown)
                 .subscribe(with: self, onNext: { `self`, _ in
                     self.delegate?.toggle(tool: .highlight, options: self.currentAnnotationOptions)
                 })
                 .disposed(by: self.disposeBag)
        self.highlightButton = highlight

        let note = CheckboxButton(type: .custom)
        note.accessibilityLabel = L10n.Accessibility.Pdf.noteAnnotationTool
        note.setImage(Asset.Images.Annotations.noteLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        note.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        note.rx.controlEvent(.touchDown)
            .subscribe(with: self, onNext: { `self`, _ in
                self.delegate?.toggle(tool: .note, options: self.currentAnnotationOptions)
            })
            .disposed(by: self.disposeBag)
        self.noteButton = note

        let area = CheckboxButton(type: .custom)
        area.accessibilityLabel = L10n.Accessibility.Pdf.imageAnnotationTool
        area.setImage(Asset.Images.Annotations.areaLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        area.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        area.rx.controlEvent(.touchDown)
            .subscribe(with: self, onNext: { `self`, _ in
                self.delegate?.toggle(tool: .square, options: self.currentAnnotationOptions)
            })
            .disposed(by: self.disposeBag)
        self.areaButton = area

        let inkLongPress = UILongPressGestureRecognizer()
        inkLongPress.delegate = self
        inkLongPress.rx.event
                    .subscribe(with: self, onNext: { `self`, recognizer in
                        if recognizer.state == .began, let view = recognizer.view {
                            self.delegate?.showInkSettings(sender: view)
                            if self.delegate?.activeAnnotationTool != .ink {
                                self.delegate?.toggle(tool: .ink, options: self.currentAnnotationOptions)
                            }
                        }
                    })
                    .disposed(by: self.disposeBag)

        let inkTap = UITapGestureRecognizer()
        inkTap.delegate = self
        inkTap.rx.event
              .subscribe(with: self, onNext: { `self`, _ in
                  self.delegate?.toggle(tool: .ink, options: self.currentAnnotationOptions)
              })
              .disposed(by: self.disposeBag)
        inkTap.require(toFail: inkLongPress)

        let ink = CheckboxButton(type: .custom)
        ink.accessibilityLabel = L10n.Accessibility.Pdf.inkAnnotationTool
        ink.setImage(Asset.Images.Annotations.inkLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        ink.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        ink.addGestureRecognizer(inkLongPress)
        ink.addGestureRecognizer(inkTap)
        self.inkButton = ink

        let eraserLongPress = UILongPressGestureRecognizer()
        eraserLongPress.delegate = self
        eraserLongPress.rx.event
                       .subscribe(with: self, onNext: { `self`, recognizer in
                           if recognizer.state == .began, let view = recognizer.view {
                               self.delegate?.showEraserSettings(sender: view)
                               if self.delegate?.activeAnnotationTool != .eraser {
                                   self.delegate?.toggle(tool: .eraser, options: self.currentAnnotationOptions)
                               }
                           }
                       })
                       .disposed(by: self.disposeBag)

        let eraserTap = UITapGestureRecognizer()
        eraserTap.delegate = self
        eraserTap.rx.event
              .subscribe(with: self, onNext: { `self`, _ in
                  self.delegate?.toggle(tool: .eraser, options: self.currentAnnotationOptions)
              })
              .disposed(by: self.disposeBag)
        eraserTap.require(toFail: eraserLongPress)

        let eraser = CheckboxButton(type: .custom)
        eraser.accessibilityLabel = L10n.Accessibility.Pdf.eraserAnnotationTool
        eraser.setImage(Asset.Images.Annotations.eraserLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        eraser.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        eraser.addGestureRecognizer(eraserLongPress)
        eraser.addGestureRecognizer(eraserTap)
        self.eraserButton = eraser

        [highlight, note, area, ink, eraser].forEach { button in
            button.adjustsImageWhenHighlighted = false
            button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
            button.selectedTintColor = .white
            button.layer.cornerRadius = 4
            button.layer.masksToBounds = true
        }

        let picker = UIButton()
        picker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
        picker.setImage(UIImage(systemName: "circle.fill", withConfiguration: symbolConfig), for: .normal)
        picker.tintColor = self.delegate?.activeAnnotationColor
        picker.rx.controlEvent(.touchUpInside)
              .subscribe(with: self, onNext: { `self`, _ in
                  self.delegate?.showColorPicker(sender: self.colorPickerButton)
              })
              .disposed(by: self.disposeBag)
        self.colorPickerButton = picker

        NSLayoutConstraint.activate([
            highlight.widthAnchor.constraint(equalTo: highlight.heightAnchor),
            note.widthAnchor.constraint(equalTo: note.heightAnchor),
            area.widthAnchor.constraint(equalTo: area.heightAnchor),
            ink.widthAnchor.constraint(equalTo: ink.heightAnchor),
            picker.widthAnchor.constraint(equalTo: picker.heightAnchor),
            eraser.widthAnchor.constraint(equalTo: eraser.heightAnchor)
        ])

        return [highlight, note, area, ink, eraser, picker]
    }

    private func createAdditionalItems() -> [UIView] {
        let undo = UIButton(type: .custom)
        undo.setImage(UIImage(systemName: "arrow.uturn.left", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        undo.isEnabled = self.delegate?.canUndo ?? false
        undo.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        undo.setContentCompressionResistancePriority(.required, for: .horizontal)
        undo.setContentCompressionResistancePriority(.required, for: .vertical)
        undo.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                guard let `self` = self, self.delegate?.canUndo == true else { return }
                self.delegate?.performUndo()
            })
            .disposed(by: self.disposeBag)
        self.undoButton = undo

        let redo = UIButton(type: .custom)
        redo.setImage(UIImage(systemName: "arrow.uturn.right", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        redo.isEnabled = self.delegate?.canRedo ?? false
        redo.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        redo.setContentCompressionResistancePriority(.required, for: .horizontal)
        redo.setContentCompressionResistancePriority(.required, for: .vertical)
        redo.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                guard let `self` = self, self.delegate?.canRedo == true else { return }
                self.delegate?.performRedo()
            })
            .disposed(by: self.disposeBag)
        self.redoButton = redo

        let close = UIButton(type: .custom)
        close.setImage(UIImage(systemName: "xmark.circle", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        close.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        close.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        close.setContentCompressionResistancePriority(.required, for: .horizontal)
        close.setContentCompressionResistancePriority(.required, for: .vertical)
        close.rx.controlEvent(.touchUpInside)
             .subscribe(with: self, onNext: { `self`, _ in
                 self.delegate?.closeAnnotationToolbar()
             })
             .disposed(by: self.disposeBag)

        let handle = UIImageView(image: UIImage(systemName: "line.3.horizontal", withConfiguration: UIImage.SymbolConfiguration(scale: .large)))
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.contentMode = .center
        handle.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        handle.setContentCompressionResistancePriority(.required, for: .horizontal)
        handle.setContentCompressionResistancePriority(.required, for: .vertical)

        return [undo, redo, close, handle]
    }

    private func setupViews() {
        self.widthConstraint = self.view.widthAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size)
        self.heightConstraint = self.view.heightAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        self.view.addSubview(scrollView)

        let stackView = UIStackView(arrangedSubviews: self.createButtons())
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollView.addSubview(stackView)

        let additionalStackView = UIStackView(arrangedSubviews: self.createAdditionalItems())
        additionalStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        additionalStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        additionalStackView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        additionalStackView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        additionalStackView.axis = .vertical
        additionalStackView.spacing = 0
        additionalStackView.distribution = .fill
        additionalStackView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(additionalStackView)

        self.containerBottom = self.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8)
        self.containerTrailing = self.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 8)
        self.handleTop = self.view.topAnchor.constraint(equalTo: additionalStackView.topAnchor)
        self.handleLeading = self.view.leadingAnchor.constraint(equalTo: additionalStackView.leadingAnchor)
        self.containerToAdditionalVertical = additionalStackView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 50)
        self.containerToAdditionalVertical.priority = .required
        self.containerToAdditionalHorizontal = additionalStackView.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 50)
        self.containerToAdditionalHorizontal.priority = .required
        let containerTop = scrollView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 15)
        let containerLeading = scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 15)
        let additionalBottom = self.view.bottomAnchor.constraint(equalTo: additionalStackView.bottomAnchor)
        let additionalTrailing = self.view.trailingAnchor.constraint(equalTo: additionalStackView.trailingAnchor)
        self.scrollViewWidthContentConstraint = scrollView.frameLayoutGuide.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        self.scrollViewHeightContentConstraint = scrollView.frameLayoutGuide.heightAnchor.constraint(equalTo: stackView.heightAnchor)

        NSLayoutConstraint.activate([containerTop, containerLeading, self.containerTrailing, self.containerToAdditionalVertical, additionalBottom, additionalTrailing, self.handleLeading,
                                     self.scrollViewWidthContentConstraint, self.scrollViewHeightContentConstraint,
                                     scrollView.contentLayoutGuide.topAnchor.constraint(equalTo: stackView.topAnchor),
                                     scrollView.contentLayoutGuide.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                                     scrollView.contentLayoutGuide.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
                                     scrollView.contentLayoutGuide.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)])

        self.scrollView = scrollView
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
