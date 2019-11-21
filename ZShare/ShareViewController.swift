//
//  ShareViewController.swift
//  ZShare
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import MobileCoreServices
import Social
import UIKit

import RxSwift

class ShareViewController: UIViewController {
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var progressBar: UIProgressView!

    private let apiClient: ApiClient
    private let disposeBag: DisposeBag

    required init?(coder: NSCoder) {
        self.apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString,
                                         headers: ["Zotero-API-Version": ApiConstants.version.description])
        self.disposeBag = DisposeBag()

        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.loadWebData { [weak self] url, title in
            guard let `self` = self,
                  let url = URL(string: url) else { return }

            self.label.text = "\(title) - \(url.absoluteString)"

            let file = Files.sharedItem(key: KeyGenerator.newKey, ext: "pdf")
            let request = FileDownloadRequest(url: url, downloadUrl: file.createUrl())
            self.apiClient.download(request: request)
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] progress in
                              self?.progressBar.progress = progress.completed
                          }, onError: { error in
                              // TODO: - Show error
                          }, onCompleted: {
                              self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                          })
                          .disposed(by: self.disposeBag)
        }
    }

    private func loadWebData(completion: @escaping (String, String) -> Void) {
        guard let extensionItem = self.extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else { return }

        let propertyList = String(kUTTypePropertyList)

        guard itemProvider.hasItemConformingToTypeIdentifier(propertyList) else { return }

        itemProvider.loadItem(forTypeIdentifier: propertyList, options: nil, completionHandler: { item, error -> Void in
            guard let scriptData = item as? [String: Any],
                  let data = scriptData[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else { return }
            let title = (data["title"] as? String) ?? ""
            let url = "https://bitcoin.org/bitcoin.pdf"//(data["url"] as? String) ?? ""

            DispatchQueue.main.async {
                completion(url, title)
            }
        })
    }
}
