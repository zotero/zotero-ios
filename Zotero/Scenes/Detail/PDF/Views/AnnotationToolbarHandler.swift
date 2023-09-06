//
//  AnnotationToolbarHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol AnnotationToolbarHandlerDelegate: AnyObject {
    var statusBarVisible: Bool { get }
    var isNavigationBarHidden: Bool { get }
    var isSidebarHidden: Bool { get }

    func layoutIfNeeded()
    func isCompactSize(for rotation: AnnotationToolbarViewController.Rotation) -> Bool
    func hideSidebarIfNeeded(forPosition position: AnnotationToolbarHandler.State.Position, animated: Bool)
    func setNavigationBar(hidden: Bool, animated: Bool)
    func setNavigationBar(alpha: CGFloat)
    func topOffsets(statusBarVisible: Bool) -> (statusBarHeight: CGFloat, navigationBarHeight: CGFloat, total: CGFloat)
    func topDidChange(forToolbarState state: AnnotationToolbarHandler.State, statusBarVisible: Bool)
}

final class AnnotationToolbarHandler {
    struct State: Codable {
        enum Position: Int, Codable {
            case leading = 0
            case trailing = 1
            case top = 2
            case pinned = 3
        }

        let position: Position
        let visible: Bool
    }

    private unowned let controller: AnnotationToolbarViewController
    private unowned let delegate: AnnotationToolbarHandlerDelegate
    private static let toolbarCompactInset: CGFloat = 12
    private static let toolbarFullInsetInset: CGFloat = 20
    private static let minToolbarWidth: CGFloat = 300

    private var state: State {
        didSet {
            self.stateDidChange?(self.state)
        }
    }
    private var toolbarInitialFrame: CGRect?
    private weak var toolbarTop: NSLayoutConstraint!
    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarLeadingSafeArea: NSLayoutConstraint!
    private var toolbarTrailing: NSLayoutConstraint!
    private var toolbarTrailingSafeArea: NSLayoutConstraint!
    private weak var dragHandleLongPressRecognizer: UILongPressGestureRecognizer!

    var stateDidChange: ((State) -> Void)?
    var didHide: (() -> Void)?

    init(state: State, controller: AnnotationToolbarViewController, delegate: AnnotationToolbarHandlerDelegate) {
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.setContentHuggingPriority(.required, for: .horizontal)
        controller.view.setContentHuggingPriority(.required, for: .vertical)

        self.state = state
        self.controller = controller
        self.delegate = delegate
    }

    func viewWillAppear(documentIsLocked: Bool) {
        self.setAnnotationToolbarHandleMinimumLongPressDuration(forPosition: self.state.position)
        if self.state.visible && !documentIsLocked {
            self.showAnnotationToolbar(state: self.state, statusBarVisible: self.delegate.statusBarVisible, animated: false)
        } else {
            self.hideAnnotationToolbar(newState: self.state, statusBarVisible: self.delegate.statusBarVisible, animated: false)
        }
    }

    func set(hidden: Bool, animated: Bool) {
        self.state = State(position: self.state.position, visible: !hidden)

        if hidden {
            self.hideAnnotationToolbar(newState: self.state, statusBarVisible: self.delegate.statusBarVisible, animated: animated)
        } else {
            self.showAnnotationToolbar(state: self.state, statusBarVisible: self.delegate.statusBarVisible, animated: animated)
        }
    }

    private func showAnnotationToolbar(state: State, statusBarVisible: Bool, animated: Bool) {
        self.controller.prepareForSizeChange()
        self.setConstraints(for: state.position, statusBarVisible: statusBarVisible)
        self.controller.view.isHidden = false
        self.delegate.layoutIfNeeded()
        self.controller.sizeDidChange()
        self.delegate.layoutIfNeeded()
        self.delegate.topDidChange(forToolbarState: state, statusBarVisible: statusBarVisible)

        self.delegate.hideSidebarIfNeeded(forPosition: state.position, animated: animated)

        let navigationBarHidden = !statusBarVisible || state.position == .pinned

        if !animated {
            self.controller.view.alpha = 1
            self.delegate.setNavigationBar(hidden: navigationBarHidden, animated: false)
            self.delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
            self.delegate.layoutIfNeeded()
            return
        }

        if !navigationBarHidden && self.delegate.isNavigationBarHidden {
            self.delegate.setNavigationBar(hidden: false, animated: false)
            self.delegate.setNavigationBar(alpha: 0)
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.controller.view.alpha = 1
            self.delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
            self.delegate.layoutIfNeeded()
        }, completion: { finished in
            guard finished && navigationBarHidden else { return }
            self.delegate.setNavigationBar(hidden: true, animated: false)
        })
    }

    private func hideAnnotationToolbar(newState: State, statusBarVisible: Bool, animated: Bool) {
        self.delegate.topDidChange(forToolbarState: newState, statusBarVisible: statusBarVisible)

        if !animated {
            self.delegate.layoutIfNeeded()
            self.controller.view.alpha = 0
            self.controller.view.isHidden = true
            self.delegate.setNavigationBar(alpha: statusBarVisible ? 1 : 0)
            self.delegate.setNavigationBar(hidden: !statusBarVisible, animated: false)
            return
        }

        if statusBarVisible && self.delegate.isNavigationBarHidden {
            self.delegate.setNavigationBar(hidden: false, animated: false)
            self.delegate.setNavigationBar(alpha: 0)
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.delegate.layoutIfNeeded()
            self.controller.view.alpha = 0
            self.delegate.setNavigationBar(alpha: statusBarVisible ? 1 : 0)
        }, completion: { finished in
            guard finished else { return }
            self.controller.view.isHidden = true
            self.didHide?()
            if !statusBarVisible {
                self.delegate.setNavigationBar(hidden: true, animated: false)
            }
        })
    }

    private func setConstraints(for position: State.Position, statusBarVisible: Bool) {
        let rotation: AnnotationToolbarViewController.Rotation = (position == .top || position == .pinned) ? .horizontal : .vertical
        if self.delegate.isCompactSize(for: rotation) {
            self.setCompactConstraints(for: position, statusBarVisible: statusBarVisible)
        } else {
            self.setFullConstraints(for: position, statusBarVisible: statusBarVisible)
        }
    }

    private func setFullConstraints(for position: State.Position, statusBarVisible: Bool) {
        switch position {
        case .leading:
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = false
            if !self.delegate.isSidebarHidden {
                self.toolbarLeadingSafeArea.isActive = false
                self.toolbarLeading.isActive = true
                self.toolbarLeading.constant = Self.toolbarFullInsetInset
            } else {
                self.toolbarLeading.isActive = false
                self.toolbarLeadingSafeArea.isActive = true
                self.toolbarLeadingSafeArea.constant = Self.toolbarFullInsetInset
            }
            self.toolbarTop.constant = Self.toolbarFullInsetInset + self.delegate.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: false)

        case .trailing:
            self.toolbarLeading.isActive = false
            self.toolbarLeadingSafeArea.isActive = false
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = true
            self.toolbarTrailingSafeArea.constant = Self.toolbarFullInsetInset
            self.toolbarTop.constant = Self.toolbarFullInsetInset + self.delegate.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: false)

        case .top:
            self.setupTopConstraints(isCompact: false, isPinned: false, statusBarVisible: statusBarVisible)

        case .pinned:
            self.setupTopConstraints(isCompact: false, isPinned: true, statusBarVisible: statusBarVisible)
        }
    }

    private func setCompactConstraints(for position: State.Position, statusBarVisible: Bool) {
        switch position {
        case .leading:
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = false
            if !self.delegate.isSidebarHidden {
                self.toolbarLeadingSafeArea.isActive = false
                self.toolbarLeading.isActive = true
                self.toolbarLeading.constant = Self.toolbarCompactInset
            } else {
                self.toolbarLeading.isActive = false
                self.toolbarLeadingSafeArea.isActive = true
                self.toolbarLeadingSafeArea.constant = Self.toolbarCompactInset
            }
            self.toolbarTop.constant = Self.toolbarCompactInset + self.delegate.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: true)

        case .trailing:
            self.toolbarLeading.isActive = false
            self.toolbarLeadingSafeArea.isActive = false
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = true
            self.toolbarTrailingSafeArea.constant = Self.toolbarCompactInset
            self.toolbarTop.constant = Self.toolbarCompactInset + self.delegate.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: true)

        case .top:
            self.setupTopConstraints(isCompact: true, isPinned: false, statusBarVisible: statusBarVisible)

        case .pinned:
            self.setupTopConstraints(isCompact: true, isPinned: true, statusBarVisible: statusBarVisible)
        }
    }

    private func setupTopConstraints(isCompact: Bool, isPinned: Bool, statusBarVisible: Bool) {
        self.toolbarLeadingSafeArea.isActive = false
        self.toolbarTrailingSafeArea.isActive = false
        self.toolbarTrailing.isActive = true
        self.toolbarTrailing.constant = 0
        self.toolbarLeading.isActive = true
        self.toolbarLeading.constant = 0
        self.toolbarTop.constant = isPinned ? self.delegate.topOffsets(statusBarVisible: statusBarVisible).statusBarHeight : self.delegate.topOffsets(statusBarVisible: statusBarVisible).total
        self.controller.set(rotation: .horizontal, isCompactSize: isCompact)
    }

    private func setAnnotationToolbarHandleMinimumLongPressDuration(forPosition position: State.Position) {
        switch position {
        case .leading, .trailing:
            self.dragHandleLongPressRecognizer.minimumPressDuration = 0.3

        case .top, .pinned:
            self.dragHandleLongPressRecognizer.minimumPressDuration = 0
        }
    }
}
