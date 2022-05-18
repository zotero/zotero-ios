//
//  LookupActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

final class LookupActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias State = LookupState
    typealias Action = LookupAction

    unowned let dbStorage: DbStorage
    private let translatorsController: TranslatorsAndStylesController
    private let schemaController: SchemaController
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag

    private var lookupWebViewHandler: LookupWebViewHandler?

    init(dbStorage: DbStorage, translatorsController: TranslatorsAndStylesController, schemaController: SchemaController) {
        self.backgroundQueue = DispatchQueue(label: "org.zotero.ItemsActionHandler.backgroundProcessing", qos: .userInitiated)
        self.dbStorage = dbStorage
        self.translatorsController = translatorsController
        self.schemaController = schemaController
        self.disposeBag = DisposeBag()
    }

    func process(action: LookupAction, in viewModel: ViewModel<LookupActionHandler>) {
        switch action {
        case .initialize(let webView):
            let handler = LookupWebViewHandler(webView: webView, translatorsController: self.translatorsController, schemaController: self.schemaController)
            self.lookupWebViewHandler = handler

            handler.observable
                   .subscribe(onNext: { [weak self, weak viewModel] data in
                       guard let `self` = self, let viewModel = viewModel else { return }
                       self.process(data: data, in: viewModel)
                   }, onError: { [weak self, weak viewModel] error in
                       guard let `self` = self, let viewModel = viewModel else { return }
                       self.showError(in: viewModel)
                   })
                   .disposed(by: self.disposeBag)

        case .lookUp(let identifier):
            self.lookupWebViewHandler?.lookUp(identifier: identifier)
        }
    }

    private func process(data: [LookupWebViewHandler.LookupData], in viewModel: ViewModel<LookupActionHandler>) {

    }

    private func showError(in viewModel: ViewModel<LookupActionHandler>) {

    }
}
