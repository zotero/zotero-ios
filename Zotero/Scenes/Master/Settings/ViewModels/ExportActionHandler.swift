//
//  ExportActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 11.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct ExportActionHandler: ViewModelActionHandler {
    typealias Action = ExportAction
    typealias State = ExportState

    private unowned let bundledDataStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    init(bundledDataStorage: DbStorage, fileStorage: FileStorage) {
        self.bundledDataStorage = bundledDataStorage
        self.fileStorage = fileStorage
        self.queue = DispatchQueue(label: "org.zotero.ExportActionHandler", qos: .userInitiated)
        self.disposeBag = DisposeBag()
    }

    func process(action: ExportAction, in viewModel: ViewModel<ExportActionHandler>) {
        switch action {
        case .setCopyAsHtml(let value):
            self.update(viewModel: viewModel) { state in
                state.copyAsHtml = value
            }
            Defaults.shared.exportCopyAsHtml = value
        }
    }

//    private func load(in viewModel: ViewModel<ExportActionHandler>) {
//        self.queue.async { [weak viewModel] in
//            guard let viewModel = viewModel else { return }
//
//            guard let localesUrl = Bundle.main.url(forResource: "locales", withExtension: "json", subdirectory: "Bundled/locales") else { return }
//
//            do {
//                let localesData = try Data(contentsOf: localesUrl)
//                let localesJson = try JSONSerialization.jsonObject(with: localesData, options: [.allowFragments])
//                let localeIds = self.loadSupportedLocales(from: localesJson)
//
//                DispatchQueue.main.async {
//                    let styles = try? self.bundledDataStorage.createCoordinator().perform(request: ReadInstalledStylesDbRequest())
//
//                    self.update(viewModel: viewModel) { state in
//                        state.styles = styles
//                        state.localeIds = localeIds
//                        state.locales = locales
//                    }
//                }
//            } catch let error {
//                DDLogError("ExportActionHandler: can't load data - \(error)")
//                DispatchQueue.main.async {
//                    self.update(viewModel: viewModel) { state in
//                        state.loading = false
//                    }
//                }
//            }
//        }
//    }

    private func loadSupportedLocales(from json: Any) -> [String] {
        guard let dictionary = json as? [String: Any],
              let codes = dictionary["primary-dialects"] as? [String: String] else { return [] }
        return Array(codes.values)
    }
}
