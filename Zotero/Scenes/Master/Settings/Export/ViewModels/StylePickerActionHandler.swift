//
//  StylePickerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct StylePickerActionHandler: ViewModelActionHandler {
    typealias Action = StylePickerAction
    typealias State = StylePickerState

    private unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: StylePickerAction, in viewModel: ViewModel<StylePickerActionHandler>) {
        switch action {
        case .load:
            self.load(in: viewModel)
        }
    }

    private func load(in viewModel: ViewModel<StylePickerActionHandler>) {
        do {
            let styles = try self.dbStorage.createCoordinator().perform(request: ReadInstalledStylesDbRequest())
            self.update(viewModel: viewModel) { state in
                state.results = styles
            }
        } catch let error {
            DDLogError("StylePickerActionHandler: can't read styles - \(error)")
        }
    }
}
