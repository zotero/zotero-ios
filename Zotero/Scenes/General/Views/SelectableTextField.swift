//
//  SelectableTextField.swift
//  Zotero
//
//  Created by Michal Rentka on 23/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import SwiftUI

struct SelectableTextField: UIViewRepresentable {
    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFirstResponder: Bool
        @Binding var didTapDone: Bool

        init(text: Binding<String>, isFirstResponder: Binding<Bool>, didTapDone: Binding<Bool>) {
            self._text = text
            self._isFirstResponder = isFirstResponder
            self._didTapDone = didTapDone
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            self.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            self.isFirstResponder = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            self.isFirstResponder = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            self.didTapDone = true
            return true
        }
    }

    let placeholder: String
    @Binding var text: String
    let secure: Bool
    let autocapitalizationType: UITextAutocapitalizationType
    let returnKeyType: UIReturnKeyType
    @Binding var isFirstResponder: Bool
    @Binding var didTapDone: Bool

    func makeUIView(context: UIViewRepresentableContext<SelectableTextField>) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.isSecureTextEntry = self.secure
        textField.returnKeyType = self.returnKeyType
        textField.autocapitalizationType = self.autocapitalizationType
        textField.placeholder = self.placeholder
        textField.text = self.text
        textField.delegate = context.coordinator
        return textField
    }

    func makeCoordinator() -> SelectableTextField.Coordinator {
        return Coordinator(text: self.$text, isFirstResponder: self.$isFirstResponder, didTapDone: self.$didTapDone)
    }

    func updateUIView(_ uiView: UITextField, context: UIViewRepresentableContext<SelectableTextField>) {
        uiView.text = self.text
        if self.isFirstResponder {
            // TODO: - iPad crashes when it becomes first responder
            uiView.becomeFirstResponder()
        } else {
            uiView.resignFirstResponder()
        }
    }
}
