//
//  DocumentKeyCommandsHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

/// Single @objc method that view controllers implement to receive document key commands.
/// The view controller forwards the sender to `DocumentKeyCommandsHandler.handle(_:)`.
@objc protocol DocumentKeyCommandResponder {
    func handleDocumentKeyCommand(_ sender: UIKeyCommand)
}

final class DocumentKeyCommandsHandler {
    enum Action {
        case search
        case navigateBack
        case navigateForward
        // Speech
        case speechForwardByParagraph
        case speechBackwardByParagraph
        case speechForwardBySentence
        case speechBackwardBySentence
        // Highlighter
        case highlighterMoveForward
        case highlighterMoveBackward
        case highlighterExtendForward
        case highlighterExtendBackward
        case highlighterConfirm
        case highlighterCancel
        case highlighterSelectHighlight
        case highlighterSelectUnderline
        case highlighterSelectColor(Int)
    }

    struct Parameters {
        let isHighlighterOverlayVisible: Bool
        let isSpeechActive: Bool
        let hasBackActions: Bool
        let hasForwardActions: Bool
    }

    static let actionSelector = #selector(DocumentKeyCommandResponder.handleDocumentKeyCommand(_:))

    var onAction: ((Action) -> Void)?

    func createKeyCommands(parameters: Parameters) -> [UIKeyCommand] {
        var commands: [UIKeyCommand] = [
            command(.search, title: L10n.Pdf.Search.title, input: "f", modifierFlags: .command)
        ]
        if parameters.hasBackActions {
            commands.append(command(.navigateBack, title: L10n.back, input: "[", modifierFlags: .command))
            if !parameters.isHighlighterOverlayVisible {
                commands.append(command(.navigateBack, title: L10n.back, input: UIKeyCommand.inputLeftArrow, modifierFlags: .command))
            }
        }
        if parameters.hasForwardActions {
            commands.append(command(.navigateForward, title: L10n.forward, input: "]", modifierFlags: .command))
            if !parameters.isHighlighterOverlayVisible {
                commands.append(command(.navigateForward, title: L10n.forward, input: UIKeyCommand.inputRightArrow, modifierFlags: .command))
            }
        }
        if parameters.isHighlighterOverlayVisible {
            commands += highlighterKeyCommands()
        } else if parameters.isSpeechActive {
            commands += speechKeyCommands()
        }
        return commands
    }

    func handle(_ sender: UIKeyCommand) {
        guard let identifier = sender.propertyList as? String, let action = Self.action(from: identifier) else { return }
        onAction?(action)
    }

    // MARK: - Private

    private func command(_ action: Action, title: String = "", input: String, modifierFlags: UIKeyModifierFlags = []) -> UIKeyCommand {
        UIKeyCommand(title: title, action: Self.actionSelector, input: input, modifierFlags: modifierFlags, propertyList: Self.identifier(for: action))
    }

    private func speechKeyCommands() -> [UIKeyCommand] {
        [
            command(.speechForwardByParagraph, title: L10n.Accessibility.Speech.forward, input: UIKeyCommand.inputRightArrow),
            command(.speechBackwardByParagraph, title: L10n.Accessibility.Speech.backward, input: UIKeyCommand.inputLeftArrow),
            command(.speechForwardBySentence, title: L10n.Accessibility.Speech.forward, input: UIKeyCommand.inputRightArrow, modifierFlags: .alternate),
            command(.speechBackwardBySentence, title: L10n.Accessibility.Speech.backward, input: UIKeyCommand.inputLeftArrow, modifierFlags: .alternate)
        ]
    }

    private func highlighterKeyCommands() -> [UIKeyCommand] {
        var commands: [UIKeyCommand] = [
            command(.highlighterMoveForward, title: L10n.Accessibility.Speech.forward, input: UIKeyCommand.inputRightArrow),
            command(.highlighterMoveBackward, title: L10n.Accessibility.Speech.backward, input: UIKeyCommand.inputLeftArrow),
            command(.highlighterExtendForward, input: UIKeyCommand.inputRightArrow, modifierFlags: .command),
            command(.highlighterExtendBackward, input: UIKeyCommand.inputLeftArrow, modifierFlags: .command),
            command(.highlighterConfirm, input: "\r"),
            command(.highlighterCancel, input: UIKeyCommand.inputEscape),
            command(.highlighterSelectHighlight, input: "h"),
            command(.highlighterSelectUnderline, input: "u")
        ]
        for index in 0..<8 {
            commands.append(command(.highlighterSelectColor(index), input: "\(index + 1)"))
        }
        return commands
    }

    // MARK: - Action ↔ Identifier Mapping

    private static let colorPrefix = "highlighterSelectColor."

    private static func identifier(for action: Action) -> String {
        switch action {
        case .search: return "search"
        case .navigateBack: return "navigateBack"
        case .navigateForward: return "navigateForward"
        case .speechForwardByParagraph: return "speechForwardByParagraph"
        case .speechBackwardByParagraph: return "speechBackwardByParagraph"
        case .speechForwardBySentence: return "speechForwardBySentence"
        case .speechBackwardBySentence: return "speechBackwardBySentence"
        case .highlighterMoveForward: return "highlighterMoveForward"
        case .highlighterMoveBackward: return "highlighterMoveBackward"
        case .highlighterExtendForward: return "highlighterExtendForward"
        case .highlighterExtendBackward: return "highlighterExtendBackward"
        case .highlighterConfirm: return "highlighterConfirm"
        case .highlighterCancel: return "highlighterCancel"
        case .highlighterSelectHighlight: return "highlighterSelectHighlight"
        case .highlighterSelectUnderline: return "highlighterSelectUnderline"
        case .highlighterSelectColor(let index): return "\(colorPrefix)\(index)"
        }
    }

    private static func action(from identifier: String) -> Action? {
        if identifier.hasPrefix(colorPrefix), let index = Int(identifier.dropFirst(colorPrefix.count)) {
            return .highlighterSelectColor(index)
        }
        switch identifier {
        case "search": return .search
        case "navigateBack": return .navigateBack
        case "navigateForward": return .navigateForward
        case "speechForwardByParagraph": return .speechForwardByParagraph
        case "speechBackwardByParagraph": return .speechBackwardByParagraph
        case "speechForwardBySentence": return .speechForwardBySentence
        case "speechBackwardBySentence": return .speechBackwardBySentence
        case "highlighterMoveForward": return .highlighterMoveForward
        case "highlighterMoveBackward": return .highlighterMoveBackward
        case "highlighterExtendForward": return .highlighterExtendForward
        case "highlighterExtendBackward": return .highlighterExtendBackward
        case "highlighterConfirm": return .highlighterConfirm
        case "highlighterCancel": return .highlighterCancel
        case "highlighterSelectHighlight": return .highlighterSelectHighlight
        case "highlighterSelectUnderline": return .highlighterSelectUnderline
        default: return nil
        }
    }
}
