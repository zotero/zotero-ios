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

protocol AnnotationToolbarLeadingView: UIView {
    func update(toRotation rotation: AnnotationToolbarViewController.Rotation)
}

protocol AnnotationToolbarDelegate: AnyObject {
    var activeAnnotationTool: AnnotationTool? { get }
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var maxAvailableToolbarSize: CGFloat { get }

    func isCompactSize(for rotation: AnnotationToolbarViewController.Rotation) -> Bool
    func toggle(tool: AnnotationTool, options: AnnotationToolOptions)
    func showToolOptions(sourceItem: UIPopoverPresentationControllerSourceItem)
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
        var isHidden: Bool
    }

    // MARK: - Constants

    static let estimatedVerticalHeight: CGFloat = 500
    private static let buttonSpacing: CGFloat = 12
    private static let buttonCompactSpacing: CGFloat = 8
    private static let pickerToToolsGap: CGFloat = 8
    private static let pickerToToolsCompactGap: CGFloat = 4
    private static let toolsToAdditionalOffset: CGFloat = 20
    private static let buttonContentInsets: NSDirectionalEdgeInsets = UIDevice.current.userInterfaceIdiom == .pad
        ? NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        : NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)

    /// Horizontal layout: top/bottom padding of all items inside the toolbar.
    private static let horizontalCrossAxisInset: CGFloat = 8
    /// Horizontal layout: left inset of the tools stack from safe area when no leading view.
    private static let horizontalToolsLeadingInset: CGFloat = 20
    /// Horizontal layout: right inset of the additional buttons stack from safe area.
    private static let horizontalAdditionalTrailingInset: CGFloat = 15
    /// Horizontal layout: left inset of the leading view from the view's left edge.
    private static let horizontalLeadingViewInset: CGFloat = 15
    /// Horizontal layout: minimum gap between the leading view and the tools stack.
    private static let horizontalLeadingViewToToolsGap: CGFloat = 8

    /// Vertical layout: left/right padding of all items inside the toolbar.
    private static let verticalCrossAxisInset: CGFloat = 8
    /// Vertical layout: top inset of the tools stack (or leading view) from the view's top edge.
    private static let verticalToolsTopInset: CGFloat = 15
    /// Vertical layout: bottom inset of the additional buttons stack from the view's bottom edge.
    private static let verticalAdditionalBottomInset: CGFloat = 8
    /// Vertical layout: minimum gap between the leading view and the tools stack.
    private static let verticalLeadingViewToToolsGap: CGFloat = 20

    // MARK: - Public

    let size: CGFloat
    weak var delegate: AnnotationToolbarDelegate?
    private(set) weak var colorPickerButton: UIButton!
    private(set) weak var undoButton: UIButton?
    private(set) weak var redoButton: UIButton?

    // MARK: - Private state

    private let undoRedoEnabled: Bool
    private let disposeBag: DisposeBag
    private var toolButtons: [ToolButton]
    private var rotation: Rotation = .horizontal
    private var lastAppliedIsCompactSize: Bool?
    private var lastLaidOutVariableDimension: CGFloat = 0
    private var lastSeenMaxAvailableSize: CGFloat = 0
    private var lastGestureRecognizerTouch: UITouch?

    private var isCompactSize: Bool {
        return delegate?.isCompactSize(for: rotation) ?? false
    }

    // MARK: - Subviews

    private weak var leadingView: AnnotationToolbarLeadingView?
    private weak var toolsStackView: UIStackView!
    private weak var additionalStackView: UIStackView!
    private weak var hairlineView: UIView!

    // MARK: - Constraints

    private var fixedDimensionConstraint: NSLayoutConstraint!
    private var layoutConstraints: [NSLayoutConstraint] = []
    private weak var pickerToToolsGapConstraint: NSLayoutConstraint?
    private weak var toolsToAdditionalSeparatorConstraint: NSLayoutConstraint?

    // MARK: - Init

    init(tools: [AnnotationTool], undoRedoEnabled: Bool, size: CGFloat) {
        self.size = size
        self.toolButtons = tools.map({ ToolButton(type: $0, title: $0.name, accessibilityLabel: $0.accessibilityLabel, image: $0.image, isHidden: false) })
        self.undoRedoEnabled = undoRedoEnabled
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Asset.Colors.navbarBackground.color
        view.addInteraction(UILargeContentViewerInteraction())
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)

        setupSubviews()

        fixedDimensionConstraint = view.heightAnchor.constraint(equalToConstant: size)
        fixedDimensionConstraint.priority = .required
        fixedDimensionConstraint.isActive = true

        applyLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        var shouldRecalculate = false

        // Re-evaluate compact-size state from the delegate. Window/container resizes (e.g. iPad Stage Manager drag)
        // can change the threshold without any explicit notification, leaving spacings stale.
        if isCompactSize != lastAppliedIsCompactSize {
            applyCompactSizeStyling()
            shouldRecalculate = true
        }

        // The toolbar's own bounds may not change even when the available space does — e.g. in vertical mode the
        // toolbar's height is intrinsic, so when the navigation bar hides/shows or the scrubber appears, the
        // document controller's frame moves but our bounds stay the same. Re-run the button-count calculation
        // whenever the delegate's reported maximum changes.
        let currentMax = delegate?.maxAvailableToolbarSize ?? 0
        if abs(currentMax - lastSeenMaxAvailableSize) > 0.5 {
            lastSeenMaxAvailableSize = currentMax
            shouldRecalculate = true
        }

        // Also catch direct changes to our own bounds (covers any case the delegate's max doesn't reflect, e.g.
        // explicit external sizing).
        let currentDim = (rotation == .horizontal) ? view.bounds.width : view.bounds.height
        if abs(currentDim - lastLaidOutVariableDimension) > 0.5 {
            lastLaidOutVariableDimension = currentDim
            shouldRecalculate = true
        }

        if shouldRecalculate {
            sizeDidChange()
        }
    }

    // MARK: - Public API

    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        undoButton?.isEnabled = undoEnabled
        redoButton?.isEnabled = redoEnabled
    }

    func set(activeColor: UIColor) {
        colorPickerButton.tintColor = activeColor
    }

    func set(selected: Bool, to tool: AnnotationTool, color: UIColor?) {
        guard let idx = toolButtons.firstIndex(where: { $0.type == tool }) else { return }

        (toolsStackView.arrangedSubviews[idx] as? CheckboxButton)?.isSelected = selected
        (toolsStackView.arrangedSubviews.last as? UIButton)?.menu = createHiddenToolsMenu()

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

    func set(rotation: Rotation) {
        // Only rebuild constraints when the rotation actually changes. The handler calls this on every
        // interface-visibility change (which doesn't affect rotation), and tearing down + reactivating
        // the whole constraint set mid-animation leaves UIStackView with stale layout state.
        guard self.rotation != rotation else { return }
        self.rotation = rotation
        applyLayout()
    }

    func setLeadingView(view: AnnotationToolbarLeadingView?) {
        if let oldView = leadingView {
            oldView.removeFromSuperview()
            leadingView = nil
        }
        if let view {
            self.view.addSubview(view)
            self.leadingView = view
        }
        applyLayout()
    }

    func updateAdditionalButtons() {
        for view in additionalStackView.arrangedSubviews {
            view.removeFromSuperview()
        }
        for view in createAdditionalItems() {
            additionalStackView.addArrangedSubview(view)
        }
    }

    func prepareForSizeChange() {
        for (idx, view) in toolsStackView.arrangedSubviews.enumerated() {
            let isMoreButton = idx == toolsStackView.arrangedSubviews.count - 1
            view.alpha = isMoreButton ? 1 : 0
            view.isHidden = !isMoreButton
        }
    }

    func sizeDidChange() {
        guard toolsStackView.arrangedSubviews.count == toolButtons.count + 1 else {
            DDLogError("AnnotationToolbarViewController: too many views in stack view! Stack view views: \(toolsStackView.arrangedSubviews.count). Tools: \(toolButtons.count)")
            return
        }
        guard let maxAvailableSize = delegate?.maxAvailableToolbarSize, maxAvailableSize > 0 else { return }

        let referenceButton = toolsStackView.arrangedSubviews.last!
        let buttonSize = (rotation == .horizontal) ? referenceButton.frame.width : referenceButton.frame.height
        guard buttonSize > 0 else { return }

        let remainingSize = availableToolsSize(maxAvailableSize: maxAvailableSize)
        if remainingSize < 0 {
            DDLogWarn("AnnotationToolbarViewController: not enough \(rotation == .horizontal ? "horizontal" : "vertical") minimum size")
        }
        let spacing = toolsStackView.spacing
        let count = max(0, min(Int(floor((remainingSize + spacing) / (buttonSize + spacing))), toolButtons.count))
        let hasOverflow = count < toolButtons.count
        // When there's overflow the last visible slot is taken by the "more" button, so only (count - 1) tool buttons fit.
        let visibleToolCount = hasOverflow ? max(0, count - 1) : toolButtons.count

        var didChangeVisibility = false

        for idx in 0..<toolButtons.count {
            let shouldShow = idx < visibleToolCount
            toolButtons[idx].isHidden = !shouldShow
            let view = toolsStackView.arrangedSubviews[idx]
            // Only mutate isHidden when it actually changes — UIStackView can leave arranged subviews
            // (including ones whose visibility isn't changing) at stale frames if isHidden is re-set
            // to its current value during the same pass.
            if view.isHidden != !shouldShow {
                view.isHidden = !shouldShow
                didChangeVisibility = true
            }
            view.alpha = shouldShow ? 1 : 0
        }

        let moreButton = toolsStackView.arrangedSubviews.last
        if let moreButton, moreButton.isHidden != !hasOverflow {
            moreButton.isHidden = !hasOverflow
            didChangeVisibility = true
        }
        moreButton?.alpha = hasOverflow ? 1 : 0

        if hasOverflow {
            (moreButton as? UIButton)?.menu = createHiddenToolsMenu()
        }

        if didChangeVisibility {
            // UIStackView doesn't always re-propagate its intrinsic content size when arranged subview
            // visibility changes. Invalidate explicitly so the toolbar's height (vertical mode) or width
            // (horizontal mode) is recomputed, and the "more" button ends up below the newly-revealed
            // tool buttons instead of overlapping them.
            toolsStackView.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }
    }

    // MARK: - Layout

    private func applyLayout() {
        view.layer.cornerRadius = rotation == .vertical ? 8 : 0
        view.layer.masksToBounds = false
        hairlineView.isHidden = rotation == .vertical

        let stackAxis: NSLayoutConstraint.Axis = (rotation == .horizontal) ? .horizontal : .vertical
        toolsStackView.axis = stackAxis
        additionalStackView.axis = stackAxis

        fixedDimensionConstraint.isActive = false
        switch rotation {
        case .horizontal:
            fixedDimensionConstraint = view.heightAnchor.constraint(equalToConstant: size)

        case .vertical:
            fixedDimensionConstraint = view.widthAnchor.constraint(equalToConstant: size)
        }
        fixedDimensionConstraint.priority = .required
        fixedDimensionConstraint.isActive = true

        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints.removeAll(keepingCapacity: true)

        switch rotation {
        case .horizontal:
            buildHorizontalConstraints()

        case .vertical:
            buildVerticalConstraints()
        }

        leadingView?.update(toRotation: rotation)

        NSLayoutConstraint.activate(layoutConstraints)
        applyCompactSizeStyling()
        view.setNeedsLayout()
    }

    private func applyCompactSizeStyling() {
        let compact = isCompactSize
        lastAppliedIsCompactSize = compact
        let spacing: CGFloat = compact ? Self.buttonCompactSpacing : Self.buttonSpacing
        toolsStackView.spacing = spacing
        additionalStackView.spacing = spacing
        pickerToToolsGapConstraint?.constant = compact ? Self.pickerToToolsCompactGap : Self.pickerToToolsGap
        toolsToAdditionalSeparatorConstraint?.constant = Self.toolsToAdditionalOffset
    }

    private func buildHorizontalConstraints() {
        let cross = Self.horizontalCrossAxisInset
        let pickerGap = colorPickerButton.leadingAnchor.constraint(equalTo: toolsStackView.trailingAnchor)
        let separator = additionalStackView.leadingAnchor.constraint(greaterThanOrEqualTo: colorPickerButton.trailingAnchor)
        pickerToToolsGapConstraint = pickerGap
        toolsToAdditionalSeparatorConstraint = separator

        layoutConstraints.append(contentsOf: [
            // Vertically center all main items between top/bottom inset.
            toolsStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: cross),
            view.bottomAnchor.constraint(equalTo: toolsStackView.bottomAnchor, constant: cross),
            colorPickerButton.topAnchor.constraint(equalTo: view.topAnchor, constant: cross),
            view.bottomAnchor.constraint(equalTo: colorPickerButton.bottomAnchor, constant: cross),
            additionalStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: cross),
            view.bottomAnchor.constraint(equalTo: additionalStackView.bottomAnchor, constant: cross),
            // Picker is anchored to the right of tools; additional buttons are anchored to the right side
            // with a minimum gap from the picker (this is the visual separator).
            pickerGap,
            separator,
            view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: additionalStackView.trailingAnchor, constant: Self.horizontalAdditionalTrailingInset)
        ])

        if let leadingView {
            // Leading view pinned to the left; tools are centered horizontally (matching legacy visual behavior).
            layoutConstraints.append(contentsOf: [
                leadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.horizontalLeadingViewInset),
                leadingView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
                view.bottomAnchor.constraint(greaterThanOrEqualTo: leadingView.bottomAnchor),
                leadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                toolsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingView.trailingAnchor, constant: Self.horizontalLeadingViewToToolsGap),
                toolsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            ])
        } else {
            layoutConstraints.append(toolsStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Self.horizontalToolsLeadingInset))
        }
    }

    private func buildVerticalConstraints() {
        let cross = Self.verticalCrossAxisInset
        let pickerGap = colorPickerButton.topAnchor.constraint(equalTo: toolsStackView.bottomAnchor)
        // Vertical mode: toolbar height is intrinsic to content, so the separator must be an exact distance —
        // a `>=` leaves the height under-constrained and Auto Layout can keep it at its previous (larger) value
        // when content shrinks, leaving the "more" button floating in unused space instead of moving up.
        // Horizontal mode keeps `>=` because the toolbar's width is variable and the spacer must be allowed to grow.
        let separator = additionalStackView.topAnchor.constraint(equalTo: colorPickerButton.bottomAnchor)
        pickerToToolsGapConstraint = pickerGap
        toolsToAdditionalSeparatorConstraint = separator

        layoutConstraints.append(contentsOf: [
            // Horizontally center all main items between left/right inset.
            toolsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: cross),
            view.trailingAnchor.constraint(equalTo: toolsStackView.trailingAnchor, constant: cross),
            colorPickerButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: cross),
            view.trailingAnchor.constraint(equalTo: colorPickerButton.trailingAnchor, constant: cross),
            additionalStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: cross),
            view.trailingAnchor.constraint(equalTo: additionalStackView.trailingAnchor, constant: cross),
            // Picker is below tools; additional buttons are below the picker with a minimum gap (visual separator).
            pickerGap,
            separator,
            view.bottomAnchor.constraint(equalTo: additionalStackView.bottomAnchor, constant: Self.verticalAdditionalBottomInset)
        ])

        if let leadingView {
            layoutConstraints.append(contentsOf: [
                leadingView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
                view.trailingAnchor.constraint(greaterThanOrEqualTo: leadingView.trailingAnchor),
                leadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                leadingView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.verticalToolsTopInset),
                toolsStackView.topAnchor.constraint(greaterThanOrEqualTo: leadingView.bottomAnchor, constant: Self.verticalLeadingViewToToolsGap)
            ])
        } else {
            layoutConstraints.append(toolsStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.verticalToolsTopInset))
        }
    }

    // Computes the size budget available for the tools stack (along the variable axis) after subtracting everything else.
    private func availableToolsSize(maxAvailableSize: CGFloat) -> CGFloat {
        let pickerGap: CGFloat = isCompactSize ? Self.pickerToToolsCompactGap : Self.pickerToToolsGap

        switch rotation {
        case .horizontal:
            let pickerSize = colorPickerButton.frame.width
            let additionalSize = additionalStackView.frame.width
            let rightSide = pickerGap + pickerSize + Self.toolsToAdditionalOffset + additionalSize + Self.horizontalAdditionalTrailingInset

            if let leadingView {
                // Tools are centered, so each side of the center must accommodate the larger of leadingSide / rightSide.
                let leadingSide = Self.horizontalLeadingViewInset + leadingView.frame.width + Self.horizontalLeadingViewToToolsGap
                return maxAvailableSize - 2 * max(leadingSide, rightSide)
            }
            return maxAvailableSize - Self.horizontalToolsLeadingInset - rightSide

        case .vertical:
            let pickerSize = colorPickerButton.frame.height
            let additionalSize = additionalStackView.frame.height
            let bottomSide = pickerGap + pickerSize + Self.toolsToAdditionalOffset + additionalSize + Self.verticalAdditionalBottomInset

            if let leadingView {
                let topSide = Self.verticalToolsTopInset + leadingView.frame.height + Self.verticalLeadingViewToToolsGap
                return maxAvailableSize - topSide - bottomSide
            }
            return maxAvailableSize - Self.verticalToolsTopInset - bottomSide
        }
    }

    // MARK: - Setup

    private func setupSubviews() {
        let tools = makeToolsStackView()
        view.addSubview(tools)
        toolsStackView = tools

        let picker = makeColorPickerButton()
        view.addSubview(picker)
        colorPickerButton = picker

        let additional = makeAdditionalStackView()
        view.addSubview(additional)
        additionalStackView = additional

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = .separator
        view.addSubview(hairline)
        hairlineView = hairline

        NSLayoutConstraint.activate([
            hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            hairline.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeToolsStackView() -> UIStackView {
        let buttons: [UIView] = toolButtons.map(makeToolButton(for:)) + [makeMoreButton()]
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.showsLargeContentViewer = true
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentHuggingPriority(.required, for: .vertical)
        return stack
    }

    private func makeToolButton(for tool: ToolButton) -> CheckboxButton {
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
    }

    private func makeMoreButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.contentInsets = Self.buttonContentInsets
        config.image = UIImage(systemName: "ellipsis")?.withRenderingMode(.alwaysTemplate)
        let button = UIButton(type: .custom)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsLargeContentViewer = true
        button.accessibilityLabel = L10n.Accessibility.Pdf.showMoreTools
        button.largeContentTitle = L10n.Accessibility.Pdf.showMoreTools
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        button.showsMenuAsPrimaryAction = true
        button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true
        return button
    }

    private func makeColorPickerButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.contentInsets = Self.buttonContentInsets
        config.image = UIImage(systemName: "circle.fill")?.applyingSymbolConfiguration(.init(scale: .large))
        let button = UIButton()
        button.configuration = config
        button.showsLargeContentViewer = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true
        button.isHidden = true
        button.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
        button.largeContentTitle = L10n.Accessibility.Pdf.colorPicker
        button.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: { [weak self] _ in
                guard let self else { return }
                delegate?.showToolOptions(sourceItem: colorPickerButton)
            })
            .disposed(by: disposeBag)
        return button
    }

    private func makeAdditionalStackView() -> UIStackView {
        let stack = UIStackView(arrangedSubviews: createAdditionalItems())
        stack.showsLargeContentViewer = true
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentHuggingPriority(.required, for: .vertical)
        return stack
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

    // MARK: - Helpers

    private var currentAnnotationOptions: AnnotationToolOptions {
        if lastGestureRecognizerTouch?.type == .stylus {
            return .stylus
        }
        return []
    }

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
}

extension AnnotationToolbarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        lastGestureRecognizerTouch = touch
        return true
    }
}
