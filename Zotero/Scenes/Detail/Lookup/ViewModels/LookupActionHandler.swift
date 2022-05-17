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
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag

    private var lookupWebViewHandler: LookupWebViewHandler?

    init(dbStorage: DbStorage, translatorsController: TranslatorsAndStylesController) {
        self.backgroundQueue = DispatchQueue(label: "org.zotero.ItemsActionHandler.backgroundProcessing", qos: .userInitiated)
        self.dbStorage = dbStorage
        self.translatorsController = translatorsController
        self.disposeBag = DisposeBag()
    }

    func process(action: LookupAction, in viewModel: ViewModel<LookupActionHandler>) {
        switch action {
        case .initialize(let webView):
            let handler = LookupWebViewHandler(webView: webView, translatorsController: self.translatorsController)
            self.lookupWebViewHandler = handler
            handler.observable

        case .lookUp(let identifier):
            self.lookupWebViewHandler?.lookUp(identifier: identifier)
        }
    }
}
