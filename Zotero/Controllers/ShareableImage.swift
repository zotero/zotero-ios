//
//  ShareableImage.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 14/7/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import LinkPresentation
import UniformTypeIdentifiers

final class ShareableImage: NSObject {
    // MARK: Properties
    private let image: UIImage
    private let title: String
    private lazy var imageData: Data? = {
        // By default UIActivityViewController shares a JPEG image with 0.8 compression quality,
        // so we compute the image data as such, to keep usual expectations.
        image.jpegData(compressionQuality: 0.8)
    }()
    lazy var titleWithSize: String = {
        var titleWithSize = title
        if let imageData {
            let sizeInBytes = imageData.count
            let sizeInKB = Double(sizeInBytes) / 1024.0
            if sizeInKB < 1024.0 {
                titleWithSize += " (\(String(format: "%.0f", sizeInKB)) KB)"
            } else {
                let sizeInMB = sizeInKB / 1024.0
                titleWithSize += " (\(String(format: "%.2f", sizeInMB)) MB)"
            }
        }
        return titleWithSize
    }()

    // MARK: Object Lifecycle
    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
        super.init()
    }
}

extension ShareableImage: UIActivityItemSource {
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        imageData
    }
    
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.iconProvider = NSItemProvider(object: image)
        metadata.title = titleWithSize
        return metadata
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType.jpeg.identifier
    }
}
