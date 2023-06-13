//
//  KeyboardResponder.swift
//  Zotero
//
//  Created by Michal Rentka on 23/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit

final class KeyboardResponder: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    private var cancellable: AnyCancellable?

    init() {
        self.cancellable = NotificationCenter.default
                                             .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
                                             .compactMap { notification in
                                                 (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height
                                             }
                                             .receive(on: DispatchQueue.main)
                                             .assign(to: \.keyboardHeight, on: self)
    }
}
