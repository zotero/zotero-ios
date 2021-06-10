//
//  CitationStylesSearchActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct CitationStylesSearchActionHandler: ViewModelActionHandler {
    typealias Action = CitationStylesSearchAction
    typealias State = CitationStylesSearchState

    private unowned let apiClient: ApiClient
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient) {
        self.apiClient = apiClient
        self.disposeBag = DisposeBag()
    }

    func process(action: CitationStylesSearchAction, in viewModel: ViewModel<CitationStylesSearchActionHandler>) {
        switch action {
        case .load:
            self.load(in: viewModel)

        case .search(let term):
            self.filter(with: term, in: viewModel)
        }
    }

    private func load(in viewModel: ViewModel<CitationStylesSearchActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.loading = true
        }

        self.apiClient.send(request: CitationStylesRequest())
            .observe(on: MainScheduler.instance)
            .subscribe(with: viewModel, onSuccess: { (viewModel, response: (CitationStylesResponse, ResponseHeaders)) in
                           self.update(viewModel: viewModel) { state in
                               state.loading = false
                               state.styles = response.0.styles.filter({ !viewModel.state.installedIds.contains($0.id) })
                               state.error = nil
                               state.changes = [.loading, .styles]
                           }
                       }, onFailure: { viewModel, error in
                           DDLogError("CitationStylesDownloadActionHandler: can't load styles - \(error)")
                           self.update(viewModel: viewModel) { state in
                               state.error = error
                               state.loading = false
                               state.changes = .loading
                           }
                       })
                       .disposed(by: self.disposeBag)
    }

    private func filter(with string: String, in viewModel: ViewModel<CitationStylesSearchActionHandler>) {
        if string.isEmpty {
            self.update(viewModel: viewModel) { state in
                state.filtered = nil
                state.changes = .styles
            }
            return
        }

        self.update(viewModel: viewModel) { state in
            let start = CFAbsoluteTimeGetCurrent()
            state.filtered = state.styles.filter({ style in
                return style.title.localizedCaseInsensitiveContains(string) || style.category.fields.contains(where: { $0.localizedCaseInsensitiveContains(string) })
            })
            state.changes = .styles
            NSLog("TIME: \(CFAbsoluteTimeGetCurrent() - start)")
        }
    }
}
