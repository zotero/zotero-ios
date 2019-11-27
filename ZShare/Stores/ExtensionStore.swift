//
//  ExtensionStore.swift
//  ZShare
//
//  Created by Michal Rentka on 25/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation
import MobileCoreServices

import RxSwift
import RxAlamofire

class ExtensionStore {
    struct State {
        enum PickerState {
            case loading, failed
            case picked(Library, Collection?)
        }

        enum DownloadState {
            case loadingMetadata
            case progress(Float)
            case failed
        }

        var pickerState: PickerState = .loading
        var downloadState: DownloadState? = .loadingMetadata
    }

    enum Error: Swift.Error {
        case expired, cantLoadWebData, downloadFailed
    }

    @Published var state: State
    private weak var context: NSExtensionContext?

    private let syncController: SyncController
    private let apiClient: ApiClient
    private let disposeBag: DisposeBag

    init(context: NSExtensionContext, apiClient: ApiClient, syncController: SyncController) {
        self.syncController = syncController
        self.apiClient = apiClient
        self.context = context
        self.state = State()
        self.disposeBag = DisposeBag()

        self.syncController.observable
                           .observeOn(MainScheduler.instance)
                           .subscribe(onNext: { [weak self] data in
                               self?.finishSync(successful: (data == nil))
                           }, onError: { [weak self] _ in
                               self?.finishSync(successful: false)
                           })
                           .disposed(by: self.disposeBag)
    }

    func loadCollections() {
        self.syncController.start(type: .normal, libraries: .all)
    }

    private func finishSync(successful: Bool) {
        if successful {
            self.state.pickerState = .picked(Library(identifier: .custom(.myLibrary),
                                                     name: RCustomLibraryType.myLibrary.libraryName,
                                                     metadataEditable: true,
                                                     filesEditable: true),
                                             nil)
        } else {
            self.state.pickerState = .failed
        }
    }

    func loadDocument() {
        self.loadWebData().flatMap { [weak self] data -> Observable<RxProgress> in
            guard let `self` = self else { return Observable.error(Error.expired) }

            let file = Files.sharedItem(key: KeyGenerator.newKey, ext: "pdf")
            let request = FileDownloadRequest(url: data.1, downloadUrl: file.createUrl())
            return self.apiClient.download(request: request)
        }
        .observeOn(MainScheduler.instance)
        .subscribe(onNext: { [weak self] progress in
            self?.state.downloadState = .progress(progress.completed)
        }, onError: { [weak self] error in
            self?.state.downloadState = .failed
        }, onCompleted: {
            self.state.downloadState = nil
        })
        .disposed(by: self.disposeBag)
    }

    private func loadWebData() -> Observable<(String, URL)> {
        let propertyList = kUTTypePropertyList as String

        guard let extensionItem = self.context?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first,
              itemProvider.hasItemConformingToTypeIdentifier(propertyList) else {
            return Observable.error(Error.cantLoadWebData)
        }

        return Observable.create { subscriber in
            itemProvider.loadItem(forTypeIdentifier: propertyList, options: nil, completionHandler: { item, error -> Void in
                guard let scriptData = item as? [String: Any],
                      let data = scriptData[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else {
                    subscriber.onError(Error.cantLoadWebData)
                    return
                }

                let title = (data["title"] as? String) ?? ""
                let url = URL(string: "https://bitcoin.org/bitcoin.pdf")!//(data["url"] as? String) ?? ""

                subscriber.onNext((title, url))
                subscriber.onCompleted()
            })

            return Disposables.create()
        }
    }

    func set(collection: Collection, library: Library) {
        self.state.pickerState = .picked(library, (collection.type.isCustom ? nil : collection))
    }
}
