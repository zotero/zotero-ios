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

class ShareViewController: UIViewController {
    @IBOutlet private weak var label: UILabel!

    private let apiClient: ApiClient

    required init?(coder: NSCoder) {
        self.apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString,
                                         headers: ["Zotero-API-Version": ApiConstants.version.description])
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.loadWebData { [weak self] url, title in
            self?.label.text = "\(title) - \(url)"
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
            let url = (data["url"] as? String) ?? ""

            DispatchQueue.main.async {
                completion(url, title)
            }
        })
    }
}
