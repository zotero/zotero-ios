//
//  ExportLocalePickerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct ExportLocalePickerActionHandler: ViewModelActionHandler {
    typealias Action = ExportLocalePickerAction
    typealias State = ExportLocalePickerState

    private unowned let fileStorage: FileStorage
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    init(fileStorage: FileStorage) {
        self.fileStorage = fileStorage
        self.queue = DispatchQueue(label: "org.zotero.ExportLocalePickerActionHandler", qos: .userInitiated)
        self.disposeBag = DisposeBag()
    }

    func process(action: ExportLocalePickerAction, in viewModel: ViewModel<ExportLocalePickerActionHandler>) {
        switch action {
        case .load:
            self.load(in: viewModel)

        case .setLocale(let localeId):
            Defaults.shared.exportDefaultLocaleId = localeId
        }
    }

    private func load(in viewModel: ViewModel<ExportLocalePickerActionHandler>) {
        self.queue.async { [weak viewModel] in
            do {
                let locales = try ExportLocaleReader.load()

                DispatchQueue.main.async {
                    guard let viewModel = viewModel else { return }
                    self.update(viewModel: viewModel) { state in
                        state.locales = locales
                        state.loading = false
                    }
                }
            } catch let error {
                DDLogError("ExportActionHandler: can't load data - \(error)")
                DispatchQueue.main.async {
                    guard let viewModel = viewModel else { return }
                    self.update(viewModel: viewModel) { state in
                        state.loading = false
                    }
                }
            }
        }
    }
}

