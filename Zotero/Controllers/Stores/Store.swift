//
//  Store.swift
//  Zotero
//
//  Created by Michal Rentka on 20/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

protocol Store: ObservableObject {
    associatedtype Action
    associatedtype State
    
    var state: State { get }

    func handle(action: Action)
}

protocol StateUpdater: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    associatedtype State
    
    var state: State { get }
    
    func updateState(_ action: @escaping (State) -> Void)
}

extension StateUpdater {
    func updateState(_ action: @escaping (State) -> Void) {
        if Thread.isMainThread {
            self._updateState(action)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?._updateState(action)
            }
        }
    }
    
    private func _updateState(_ action: @escaping (State) -> Void) {
        self.objectWillChange.send()
        action(self.state)
    }
}
